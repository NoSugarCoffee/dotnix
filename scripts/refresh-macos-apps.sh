#!/usr/bin/env bash
# Remove Nix store bundles from Open With without deleting rollback generations.
# Usage: bash scripts/refresh-macos-apps.sh [copied-apps-directory]
set -euo pipefail

lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
copiedApps=${1:-"$HOME/Applications/Home Manager Apps"}
systemApps=/Applications

if [[ ! -x "$lsregister" ]]; then
  echo "LaunchServices is unavailable; skipping app registration refresh." >&2
  exit 0
fi

# Snapshot first: a failed dump must not be mistaken for an empty database.
dump=$(mktemp)
trap 'rm -f "$dump"' EXIT
"$lsregister" -dump > "$dump"

status=0
# Register real copies first. Do not follow symlinks back into the store or
# recursively scan bundles (which would register their internal helper apps).
for directory in "$copiedApps" "$systemApps"; do
  for app in "$directory"/*.app; do
    [[ -d "$app" && ! -L "$app" ]] || continue
    if ! "$lsregister" -f "$app"; then
      echo "warning: could not register $app" >&2
      status=1
    fi
  done
done

# Dump paths end in an optional database address, e.g. " (0x938c)".
# Include missing bundles: GC can delete a path without removing its record.
# Keep spaces/parentheses intact and never feed unrelated paths to -u.
while IFS= read -r app; do
  [[ "$app" == /nix/store/*.app ]] || continue
  echo "unregistering $app"
  if ! "$lsregister" -u "$app"; then
    echo "warning: could not unregister $app" >&2
    status=1
  fi
done < <(sed -nE 's/^path:[[:space:]]+(\/nix\/store\/.*)/\1/p' "$dump" \
  | sed -E 's/ \(0x[[:xdigit:]]+\)$//' | sort -u)

exit "$status"
