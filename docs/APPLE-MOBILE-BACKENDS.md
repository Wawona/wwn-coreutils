# Apple-mobile Mode A backends (no Swift)

For iOS / iPadOS / tvOS / watchOS / visionOS App Store Mode A shell tools:

| Need | Backend | Repo |
|------|---------|------|
| coreutils (`ls`…) | Rust uutils → `wawona_coreutils_main` | **wwn-coreutils** (this repo) |
| SSH / scp / keygen | libssh2 CLI (`ssh_main`…) | `wwn-ssh` |
| zsh | In-process `wawona_zsh_main` | `wwn-zsh` |
| `system()` stand-in | `wawona_dispatch_inprocess` | `wwn-toolchain` `wawona-pty` |

## Hard rejects

- **Swift backends** for SSH, zsh, coreutils, or dispatch (no NIOSSH, no
  Swift `Process`, no ios_system Swift wrappers as the product path)
- OpenSSH / `posix_spawn("ssh")` on Apple-mobile store builds
- Real POSIX `system()` / fork-exec of unsigned Mach-O
- ios_system dylib + `dlopen` command table

SwiftUI / UIKit host the app UI only. Policy and CLI stay Rust (+ thin C ABI).

Floor: deployment target **13.0**, latest SDK. See Wawona `wawona-ios-min-os`.
