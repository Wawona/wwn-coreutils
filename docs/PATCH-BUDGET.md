# Patch budget (Apple-mobile Mode A)

uutils / zsh / libssh2 / fastfetch patches are expensive. Prefer less surface.

## Rules

1. **Pin upstream hard.** Bump versions rarely. One pin file owns the rev
   (`coreutils-src.nix`, zsh recipe, libssh2 versions).
2. **Prefer configure / env / `#ifdef` over new patch files.**
3. **Every Apple-mobile patch needs an anchor verifier** in that repo's CI
   (`verify-*-ios-patches.py` or equivalent). No silent `sed` in recipes.
4. **Refuse a second Apple-mobile fork** of the same tool (no parallel
   "ios13" vs "ios26" trees). Floor is iOS 13.0; SDK is latest.
5. **New patch = same PR updates** this budget note if the reason is durable,
   plus the verifier anchors.

## This repo

| Artifact | Role |
|----------|------|
| `coreutils-src.nix` | Upstream uutils pin |
| `patch-coreutils-source.sh` | Staticlib + `wawona_coreutils_main` only |
| `safe-subset.txt` | Which utils Mode A may call in-process |

Do not grow `patch-coreutils-source.sh` for product policy. Product tool lists
live in `safe-subset.txt` and consumer sync checks.
