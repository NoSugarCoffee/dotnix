#!/usr/bin/env bash
# Remove managed Nix app duplicates without deleting rollback generations.
# Usage: bash scripts/refresh-macos-apps.sh [copied-apps-directory]
set -euo pipefail

lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
copiedApps=${1:-"$HOME/Applications/Home Manager Apps"}
systemApps=/Applications
plistBuddy=/usr/libexec/PlistBuddy
xattr=/usr/bin/xattr

if [[ ! -x "$lsregister" ]]; then
  echo "LaunchServices is unavailable; skipping app registration refresh." >&2
  exit 0
fi

# Snapshot first: a failed dump must not be mistaken for an empty database.
workDir=$(mktemp -d)
trap 'rm -rf "$workDir"' EXIT
dump=$workDir/dump
identifiers=$workDir/identifiers
: > "$identifiers"
"$lsregister" -dump > "$dump"

status=0
# Register real copies first. Do not follow symlinks back into the store or
# recursively scan bundles (which would register their internal helper apps).
for directory in "$copiedApps" "$systemApps"; do
  for app in "$directory"/*.app; do
    [[ -d "$app" && ! -L "$app" ]] || continue
    # /Applications is shared with manually installed apps and other profiles.
    # Match copyApps ownership: a stale sidecar alone does not claim a bundle.
    if [[ "$directory" == "$systemApps" ]] \
      && ! "$xattr" -p home-manager.copied "$app" >/dev/null 2>&1; then
      continue
    fi
    if ! identifier=$("$plistBuddy" -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist") \
      || [[ -z "$identifier" ]]; then
      echo "warning: could not read bundle identifier for $app" >&2
      status=1
      continue
    fi
    if ! "$lsregister" -f "$app"; then
      echo "warning: could not register $app" >&2
      status=1
      continue
    fi
    # Only remove alternatives once their managed replacement is registered.
    printf '%s\n' "$identifier" >> "$identifiers"
  done
done

# Dump paths end in an optional database address, e.g. " (0x938c)".
# Read identifiers from the dump, not the store: GC may have deleted the bundle.
# Match identifiers, not filenames, so renamed versions are cleaned up while
# unrelated apps with the same filename retain their sole registration.
awk '
  function emit() {
    if (path != "" && identifier != "") print identifier "\t" path
    path = identifier = ""
  }
  /^bundle id:/ { emit() }
  /^path:/ {
    path = $0
    sub(/^path:[[:space:]]+/, "", path)
    sub(/ \(0x[[:xdigit:]]+\)$/, "", path)
  }
  /^identifier:/ {
    identifier = $0
    sub(/^identifier:[[:space:]]+/, "", identifier)
  }
  END { emit() }
' "$dump" | sort -u > "$workDir/bundles"
while IFS=$'\t' read -r identifier app; do
  [[ "$app" == /nix/store/*.app ]] || continue
  grep -Fxq -- "$identifier" "$identifiers" || continue
  echo "unregistering $app"
  if ! "$lsregister" -u "$app"; then
    echo "warning: could not unregister $app" >&2
    status=1
  fi
done < "$workDir/bundles"

exit "$status"
