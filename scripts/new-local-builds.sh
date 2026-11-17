#!/usr/bin/env bash
# Fails when <candidate> would compile a package locally that <base> did not.
#
# Gates the daily flake.lock bump: nixos-26.05 advances once the NixOS (Linux)
# tests pass, without waiting for Hydra's darwin builds, so a bump can land on
# a revision whose darwin packages aren't in any binary cache yet. Every Mac
# then builds them from source on `just switch`, test suites included (gh
# 2.104.0's flaky git tests broke switch that way). Failing here keeps the
# bump unmerged until the caches catch up; the next day's run retries.
#
# Derivations both sides build anyway (home-manager's own files, unfree
# repacks no cache serves) are compared by name with version segments
# dropped, so a version bump of one of those doesn't count as new.
#
# Run it before any CI-local cache (magic-nix-cache) is configured, or that
# cache hides the misses.
#
# Usage: new-local-builds.sh <base flake ref> <candidate flake ref> <attribute>
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <base flake ref> <candidate flake ref> <attribute>" >&2
  exit 2
fi
base=$1
candidate=$2
attribute=$3

local_builds() {
  local dry_run status=0
  # Called from a command substitution, where set -e does not abort a failed
  # assignment. Return the dry-run status so a fetch or cache error is not
  # parsed as an empty build list.
  dry_run=$(nix build --dry-run "$1#$attribute" 2>&1 >/dev/null) || status=$?
  if [[ $status -ne 0 ]]; then
    echo "nix build --dry-run failed for $1#$attribute" >&2
    printf '%s\n' "$dry_run" >&2
    return "$status"
  fi
  awk '/will be built/ { building = 1; next }
       /will be fetched/ { building = 0; next }
       building && $1 ~ "^/nix/store/" { print $1 }' <<<"$dry_run" |
    sed -E 's|^/nix/store/[a-z0-9]{32}-||; s|\.drv$||; s/-v?[0-9][^-]*//g' |
    sort -u
}

# Capture both lists before comm. A process substitution drops the producer's
# status, and comm then treats a failed dry-run as "built nothing".
base_builds=$(local_builds "$base") || exit $?
candidate_builds=$(local_builds "$candidate") || exit $?
new=$(comm -13 <(printf '%s\n' "$base_builds") <(printf '%s\n' "$candidate_builds")) || exit $?
if [[ -n $new ]]; then
  echo "::error::$candidate builds these locally, but $base does not:"
  echo "$new"
  echo "Their binaries aren't cached yet; the next flake update retries."
  exit 1
fi
echo "No new local builds."
