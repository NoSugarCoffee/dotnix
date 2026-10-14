#!/usr/bin/env bash
# Prints a flake reference for this checkout with flake.nix rewritten to the
# local $USER/$HOME, so `just switch` / `just build` apply the config to the
# account running them -- the same rewrite bootstrap-macos.sh does to its
# downloaded copy. Without it, a checkout only builds for the account named
# in flake.nix (the repo's default), and every other machine gets "does not
# provide attribute 'homeConfigurations.<user>-<system>'".
#
# Only git-tracked files are copied (staged new files included), matching
# what Nix itself sees when it evaluates the checkout as a git flake.
#
# Usage: local-flake.sh [<repo root>]
set -euo pipefail

root=$(cd "${1:-.}" && pwd)

# Already this account (CI, the repo owner): use the checkout as-is.
home_default="/Users/${USER}"
[[ $(uname -s) == Darwin ]] || home_default="/home/${USER}"
if [[ $(nix eval --raw "${root}#username" 2>/dev/null) == "$USER" && "$HOME" == "$home_default" ]]; then
  printf '%s\n' "$root"
  exit 0
fi

# One fixed per-user copy, rebuilt from scratch every run, so a file removed
# from the checkout can't linger in it and nothing piles up in $TMPDIR.
# Tracked files deleted in the worktree but not yet staged are skipped, as
# Nix does. tar, not rsync: macOS ships rsync 2.6.9, which lacks the flags
# a filtered copy needs.
copy="${XDG_CACHE_HOME:-$HOME/.cache}/dotnix/local-flake"
rm -rf "$copy"
mkdir -p "$copy"
(
  cd "$root"
  git ls-files -z --cached | while IFS= read -r -d '' file; do
    if [[ -e "$file" || -L "$file" ]]; then
      printf '%s\0' "$file"
    fi
  done | tar -cf - --null -T -
) | tar -xf - -C "$copy"
bash "${copy}/scripts/inject-account.sh" "$copy" "$USER" "$HOME" >&2
printf 'path:%s\n' "$copy"
