# wwn-coreutils

Wawona's vendored [uutils/coreutils](https://github.com/uutils/coreutils): the
in-process `ls`/`cat`/`cp`/... multicall used by the App-Store-compliant build
(no `fork`/`exec`), kept in sync with the `coreutils` Cargo feature subset and
`wwn_safe_subset[]` in `wawona-dispatch.c`.

Patch-overlay model: pristine uutils-coreutils `0.0.30` is pinned in
`coreutils-src.nix` and patched at build time (`patch-coreutils-source.sh`).

## Use

```nix
inputs.wwn-coreutils.url = "github:Wawona/wwn-coreutils";

# Patched source tree for the Rust backend Cargo path-dep:
patched   = wwn-coreutils.lib.mkPatchedSrc { inherit pkgs; platform = "macos"; };
# macOS/Android multicall binary (fork/exec-allowed platforms):
multicall = wwn-coreutils.lib.mkMulticall { inherit pkgs; };
```

## Standalone build

```sh
nix build .#coreutils-multicall
nix build .#coreutils-patched-src-ios
```

## License

MIT for the Wawona Nix packaging / patches (see `LICENSE`). uutils-coreutils is MIT;
its source is fetched from upstream at build time.
