# Pristine upstream uutils/coreutils source pin (patch-overlay model). Vendored
# as the in-process ls/cat/cp/... multicall for the App-Store-compliant build
# (no fork/exec). Patched at build time by patch-coreutils-source.sh.
{ pkgs }:
pkgs.fetchFromGitHub {
  owner = "uutils";
  repo = "coreutils";
  rev = "0.0.30";
  sha256 = "sha256-OZ9AsCJmQmn271OzEmqSZtt1OPn7zHTScQiiqvPhqB0=";
}
