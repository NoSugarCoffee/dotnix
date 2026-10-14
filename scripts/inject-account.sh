#!/usr/bin/env bash
# Rewrites the `username` and `homeDirectory` lines in <srcdir>/flake.nix to
# the given account and home directory, in place.
#
# Shared by bootstrap-macos.sh (real $USER/$HOME) and the CI step that proves
# the injection still works (a throwaway account), so CI exercises this exact
# rewrite instead of a reimplementation that could silently diverge from it.
#
# Usage: inject-account.sh <srcdir> <user> <home>
set -euo pipefail

srcdir=$1
user=$2
home=$3

# Escape a literal string for embedding inside a double-quoted Nix string:
# backslash and `"` both need their own backslash there. Needed because some
# login setups (e.g. a namespace-enabled Active Directory Mac) put the
# account in `$USER` as `DOMAIN\shortname`.
nix_string_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g; s/"/\\"/g'
}

# Escape a literal (already Nix-escaped) string for the replacement half of a
# sed `s|||` command: backslash, `&` ("the whole match") and the `|`
# delimiter all need their own escaping there, or the backslashes just added
# by nix_string_escape would be dropped instead of reaching the output file.
sed_replacement_escape() {
  printf '%s' "$1" | sed -e 's/[\&|]/\\&/g'
}

user_nix=$(nix_string_escape "$user")
home_nix=$(nix_string_escape "$home")

# Deliberately not `sed -i`: its flags differ between BSD and GNU, and this
# form is identical on both. The rewrite is line-level, so flake.nix keeps
# `username`/`homeDirectory` on one line each, and a renamed or reformatted
# line fails loudly below rather than silently deploying the repo's default
# account/home instead of the local one.
sed \
  -e "s|^ *username = .*;|      username = \"$(sed_replacement_escape "$user_nix")\";|" \
  -e "s|^ *homeDirectory = .*;|      homeDirectory = \"$(sed_replacement_escape "$home_nix")\";|" \
  "${srcdir}/flake.nix" >"${srcdir}/flake.nix.new"
mv "${srcdir}/flake.nix.new" "${srcdir}/flake.nix"

if ! grep -qF "username = \"${user_nix}\";" "${srcdir}/flake.nix"; then
  echo "error: could not set the account to '${user}' in the downloaded flake.nix" >&2
  exit 1
fi
if ! grep -qF "homeDirectory = \"${home_nix}\";" "${srcdir}/flake.nix"; then
  echo "error: could not set the home directory to '${home}' in the downloaded flake.nix" >&2
  exit 1
fi
