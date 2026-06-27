#!/usr/bin/env bash
# Patch the vendored uutils "coreutils" umbrella crate so it builds as a static
# library exposing a single C entry point, wawona_coreutils_main(), that
# dispatches by argv[0] basename through the umbrella's generated util_map.
#
# This mirrors dependencies/libs/waypipe/patch-waypipe-source.sh:
#   * crate-type = ["rlib", "staticlib"]   (was a [[bin]] multicall)
#   * append a #[no_mangle] extern "C" entry point
#
# The umbrella keeps its own build.rs (which writes $OUT_DIR/uutils_map.rs with
# util_map<T>()) and its own [workspace], so all the uu_* sub-crates and their
# `workspace = true` field inheritance keep resolving. We only remove the bin
# target and bolt a library + C shim onto the existing src/bin/coreutils.rs.
set -euo pipefail

UMBRELLA_MAIN="src/bin/coreutils.rs"

if [ ! -f "Cargo.toml" ]; then
  echo "ERROR: patch-coreutils-source.sh must run inside the coreutils crate root" >&2
  exit 1
fi
if [ ! -f "$UMBRELLA_MAIN" ]; then
  echo "ERROR: $UMBRELLA_MAIN not found — uutils layout changed; update patch-coreutils-source.sh" >&2
  exit 1
fi

# === Phase 1: Cargo.toml — drop the bin, add a staticlib lib target ===
python3 - <<'PY'
import re
from pathlib import Path

p = Path("Cargo.toml")
s = p.read_text()

# Remove every [[bin]] section (the multicall binary). Stop at the next table.
def strip_table(content, header):
    out = []
    skip = False
    for line in content.split("\n"):
        st = line.strip()
        if st == header:
            skip = True
            continue
        if skip and st.startswith("[") and st != header:
            skip = False
        if not skip:
            out.append(line)
    return "\n".join(out)

s = strip_table(s, "[[bin]]")

# default-run points at the removed bin; drop it.
s = re.sub(r'^\s*default-run\s*=.*$', '', s, flags=re.MULTILINE)

# Ensure a [lib] target rooted at the umbrella source so util_map() and the
# generated $OUT_DIR/uutils_map.rs are reachable from the C shim.
lib_block = (
    '[lib]\n'
    'name = "coreutils"\n'
    'path = "src/bin/coreutils.rs"\n'
    'crate-type = ["rlib", "staticlib"]\n'
)
if "[lib]" in s:
    # Replace the existing [lib] table wholesale.
    s = strip_table(s, "[lib]")

# Insert [lib] after the [package] table (including [package.metadata.*] subtables).
# Do NOT use a [^\[]* regex — package fields like authors = ["…"] contain '['.
lines = s.split("\n")
insert_at = None
in_package = False
for i, line in enumerate(lines):
    st = line.strip()
    if st == "[package]":
        in_package = True
        continue
    if in_package and st.startswith("[") and not st.startswith("[package"):
        insert_at = i
        break
if insert_at is None:
    # Fallback: append after the file header / before first top-level table.
    for i, line in enumerate(lines):
        if line.strip().startswith("[") and line.strip() != "[package]":
            insert_at = i
            break
if insert_at is None:
    insert_at = len(lines)
lines = lines[:insert_at] + ["", lib_block.rstrip(), ""] + lines[insert_at:]
s = "\n".join(lines)

p.write_text(s)
print("✓ Cargo.toml: removed [[bin]], added staticlib [lib] (coreutils)")
PY

# === Phase 2: append the C entry point to the umbrella source ===
python3 - "$UMBRELLA_MAIN" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
content = path.read_text()

if "fn wawona_coreutils_main" in content:
    print("✓ wawona_coreutils_main already present (idempotent)")
    sys.exit(0)

# The umbrella already imports std::path::Path / std::collections::HashMap and
# `include!`s util_map<T>() from OUT_DIR. We only add the FFI shim; keep imports
# local to avoid clashing with the file's existing `use` set.
shim = r'''

// ---- Wawona in-process dispatch shim (App Store compliant: no fork/exec) ----
//
// wawona_dispatch_inprocess() in libwwn-pty.a forwards external commands here
// instead of fork()/exec() on the Apple sandbox. We look up argv[0]'s basename
// in the umbrella util_map and run the util in-process. A util panic is caught
// so the host app survives; utils that call process::exit are kept out of the
// in-process safe subset (see dependencies/libs/wawona-pty/src/wawona-dispatch.c).
use std::ffi::CStr;
use std::os::raw::{c_char, c_int};
use std::os::unix::ffi::OsStringExt as _;

/// Returned when argv[0] is not a known utility, so the caller (zsh exec hook)
/// can fall through to its normal not-found handling. Kept in sync with the
/// WWN_DISPATCH_NOT_HANDLED macro in wwn_pty.h.
pub const WWN_DISPATCH_NOT_HANDLED: c_int = -1;

#[no_mangle]
pub extern "C" fn wawona_coreutils_main(argc: c_int, argv: *const *const c_char) -> c_int {
    if argc <= 0 || argv.is_null() {
        return WWN_DISPATCH_NOT_HANDLED;
    }

    let mut args: Vec<OsString> = Vec::with_capacity(argc as usize);
    for i in 0..argc as isize {
        let ptr = unsafe { *argv.offset(i) };
        if ptr.is_null() {
            continue;
        }
        let bytes = unsafe { CStr::from_ptr(ptr) }.to_bytes().to_vec();
        args.push(OsString::from_vec(bytes));
    }
    if args.is_empty() {
        return WWN_DISPATCH_NOT_HANDLED;
    }

    let util = match std::path::Path::new(&args[0]).file_name().and_then(|s| s.to_str()) {
        Some(name) => name.to_string(),
        None => return WWN_DISPATCH_NOT_HANDLED,
    };

    // util_map<T>() is the generated dispatch table; T must implement
    // uucore::Args (blanket-impl'd for Iterator<Item = OsString>).
    let utils = util_map::<std::vec::IntoIter<OsString>>();
    let entry = match utils.get(util.as_str()) {
        Some(entry) => entry,
        None => return WWN_DISPATCH_NOT_HANDLED,
    };
    let uumain = entry.0;

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(move || {
        uumain(args.into_iter())
    }));
    match result {
        Ok(code) => code,
        Err(_) => 1,
    }
}
'''

content = content.rstrip() + "\n" + shim
path.write_text(content)
print("✓ appended wawona_coreutils_main to", path)
PY

echo "✓ coreutils patched for in-process dispatch"

# === Phase 3: Apple-mobile uu_cp mode_t fix ===================================
# On iOS (and other Apple-mobile targets) libc mode constants are u16, like
# macOS. Upstream uu/cp only special-cases macOS/android/freebsd/redox; iOS
# falls into the Linux u32 branch and fails to cross-compile.
python3 - <<'PY'
from pathlib import Path

path = Path("src/uu/cp/src/cp.rs")
if not path.is_file():
    print("SKIP uu_cp Apple-mobile patch (layout changed)")
    raise SystemExit(0)

text = path.read_text()
needle = '            target_os = "macos",\n            target_os = "freebsd",'
insert = '            target_os = "macos",\n            target_os = "ios",\n            target_os = "freebsd",'
if needle not in text:
    if 'target_os = "ios",' in text:
        print("✓ uu_cp Apple-mobile patch already applied (idempotent)")
    else:
        print("WARNING: uu_cp mode_t anchors missing — uutils layout may have changed", flush=True)
else:
    text = text.replace(needle, insert, 2)  # both cfg(not(any(...))) and cfg(any(...))
    path.write_text(text)
    print("✓ uu_cp: treat iOS like macOS for mode_t constants")
PY

# === Phase 4: Apple-mobile uu_date clock_settime fix ========================
# iOS libc does not expose clock_settime (sandbox cannot set system time).
# Upstream excludes macOS/redox but not iOS, so the Linux set-time path fails
# to cross-compile. Treat iOS like macOS: display-only, no --set.
python3 - <<'PY'
from pathlib import Path

path = Path("src/uu/date/src/date.rs")
if not path.is_file():
    print("SKIP uu_date Apple-mobile patch (layout changed)")
    raise SystemExit(0)

text = path.read_text()
if 'target_os = "ios"' in text:
    print("✓ uu_date Apple-mobile patch already applied (idempotent)")
    raise SystemExit(0)

text = text.replace(
    'not(target_os = "macos"), not(target_os = "redox")',
    'not(any(target_os = "macos", target_os = "ios")), not(target_os = "redox")',
)
text = text.replace(
    'not(any(target_os = "macos", target_os = "redox"))',
    'not(any(target_os = "macos", target_os = "ios", target_os = "redox"))',
)
text = text.replace(
    '#[cfg(target_os = "macos")]\nstatic OPT_SET_HELP_STRING',
    '#[cfg(any(target_os = "macos", target_os = "ios"))]\nstatic OPT_SET_HELP_STRING',
)
text = text.replace(
    '#[cfg(target_os = "macos")]\nfn set_system_datetime',
    '#[cfg(any(target_os = "macos", target_os = "ios"))]\nfn set_system_datetime',
)
text = text.replace(
    "setting the date is not supported by macOS",
    "setting the date is not supported on this platform",
)
path.write_text(text)
print("✓ uu_date: treat iOS like macOS (no clock_settime / --set)")
PY
