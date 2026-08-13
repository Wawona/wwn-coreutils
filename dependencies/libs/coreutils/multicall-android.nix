# uutils multicall PIE for Android (fork/exec on PATH).
#
# Same safe subset as multicall.nix / in-process Cargo features. Shipped in the
# APK as libcoreutils_bin.so; android_jni.c symlinks usr/bin/{ls,whoami,…} → it
# (exec follows the jniLibs target — app-private copies are not executable).
{
  lib,
  pkgs,
  coreutils-src,
  androidToolchain,
  utils ? [
    "ls" "cat" "cp" "mv" "rm" "mkdir" "rmdir" "ln" "touch" "echo"
    "pwd" "head" "tail" "wc" "sort" "cut" "tr" "seq" "basename"
    "dirname" "stat" "du" "df" "date" "env" "printenv" "uname"
    "whoami" "yes" "tee" "nl" "tac" "fold" "expand" "unexpand"
    "truncate"
  ],
  ...
}:

let
  rustToolchain = pkgs.rust-bin.stable.latest.default.override {
    targets = [ "aarch64-linux-android" ];
  };
  rustPlatform = pkgs.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };

  androidLinkerWrapper = pkgs.writeShellScript "android-linker-wrapper" ''
    exec ${androidToolchain.androidCC} "$@"
  '';
in
rustPlatform.buildRustPackage {
  pname = "wawona-coreutils-multicall-android";
  version = "0.0.30";
  src = coreutils-src;

  cargoLock = {
    lockFile = "${coreutils-src}/Cargo.lock";
  };

  buildNoDefaultFeatures = true;
  buildFeatures = utils;

  CARGO_BUILD_TARGET = "aarch64-linux-android";
  CC_aarch64_linux_android = "${androidLinkerWrapper}";
  CXX_aarch64_linux_android = androidToolchain.androidCXX;
  AR_aarch64_linux_android = androidToolchain.androidAR;
  CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = "${androidLinkerWrapper}";

  cargoBuildFlags = [
    "--bin" "coreutils"
    "--target" "aarch64-linux-android"
  ];
  doCheck = false;
  dontFixup = true;

  preConfigure = ''
    export RUSTFLAGS="-A warnings $RUSTFLAGS"
  '';

  postInstall = ''
    mkdir -p $out/bin
    search_roots="''${CARGO_TARGET_DIR:-target} target"
    binf=$(find $search_roots -type f -name "coreutils" -perm -u+x 2>/dev/null | head -1)
    if [ -z "$binf" ]; then
      echo "ERROR: coreutils multicall binary not found" >&2
      find $search_roots -maxdepth 6 -type f -name "coreutils*" 2>/dev/null >&2 || true
      exit 1
    fi
    cp "$binf" $out/bin/coreutils
    cd $out/bin
    for u in ${lib.concatStringsSep " " utils}; do
      ln -sf coreutils "$u"
    done
  '';

  meta = {
    description = "uutils coreutils multicall (Android aarch64, Wawona safe subset)";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
