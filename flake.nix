{
  description = "wwn-coreutils: Wawona's vendored uutils-coreutils, providing the in-process ls/cat/cp/... multicall for the App-Store-compliant (no fork/exec) build, plus the patched-source builder for the Rust backend.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    wwn-toolchain.url = "github:Wawona/wwn-toolchain";
    wwn-toolchain.inputs.nixpkgs.follows = "nixpkgs";
    wwn-toolchain.inputs.rust-overlay.follows = "rust-overlay";
  };

  outputs = { self, nixpkgs, rust-overlay, wwn-toolchain, ... }:
    let
      darwinSystems = [ "x86_64-darwin" "aarch64-darwin" ];
      linuxSystems = [ "x86_64-linux" "aarch64-linux" ];
      allSystems = darwinSystems ++ linuxSystems;
      forAll = nixpkgs.lib.genAttrs allSystems;

      pkgsFor = system: import nixpkgs {
        inherit system;
        overlays = [ (import rust-overlay) ];
        config = { allowUnfree = true; allowUnsupportedSystem = true; };
      };

      cuDir = ./dependencies/libs/coreutils;
    in
    {
      # coreutils is not a registry module; it is consumed via these lib helpers
      # (patched source tree for the Rust backend Cargo dep + macOS/Android multicall).
      lib = {
        coreutilsSrc = pkgs: import (cuDir + "/coreutils-src.nix") { inherit pkgs; };
        patchScript = cuDir + "/patch-coreutils-source.sh";
        patchedSrcRecipe = cuDir + "/coreutils-patched-src.nix";
        multicallRecipe = cuDir + "/multicall.nix";
        mkPatchedSrc = { pkgs, platform }:
          pkgs.callPackage (cuDir + "/coreutils-patched-src.nix") {
            coreutils-src = import (cuDir + "/coreutils-src.nix") { inherit pkgs; };
            patchScript = cuDir + "/patch-coreutils-source.sh";
            inherit platform;
          };
        mkMulticall = { pkgs }:
          pkgs.callPackage (cuDir + "/multicall.nix") {
            coreutils-src = import (cuDir + "/coreutils-src.nix") { inherit pkgs; };
          };
      };

      packages = forAll (system:
        let pkgs = pkgsFor system; in {
          coreutils-multicall = self.lib.mkMulticall { inherit pkgs; };
          coreutils-patched-src-ios = self.lib.mkPatchedSrc { inherit pkgs; platform = "ios"; };
        });

      formatter = forAll (system: (pkgsFor system).nixfmt-rfc-style);
    };
}
