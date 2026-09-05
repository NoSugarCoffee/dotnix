#!/usr/bin/env bash
# Runner-side (and in-sandbox) evaluation for darwin-packages-freshness.
# Prints a JSON object with packages_current plus optional proposed bumps
# when nix is available and a pin is stale. Higher packages_current is better.
set -euo pipefail

cv_pinned=$(grep -oP '(?<=version = ")[^"]+' pkgs/clash-verge-rev-darwin/default.nix | head -1)
cv_latest_tag=$(gh api repos/clash-verge-rev/clash-verge-rev/releases/latest --jq '.tag_name')
cv_latest="${cv_latest_tag#v}"
cv_current=0
[ "$cv_pinned" = "$cv_latest" ] && cv_current=1

cd_pinned_hash=$(grep -oP '(?<=hash = ")[^"]+' pkgs/claude-desktop-darwin/default.nix | head -1)
cd_url=$(grep -oP '(?<=url = ")[^"]+' pkgs/claude-desktop-darwin/default.nix | head -1)
cd_fresh_hash=$(nix store prefetch-file --json "$cd_url" | jq -r '.hash')
cd_current=0
[ "$cd_pinned_hash" = "$cd_fresh_hash" ] && cd_current=1

packages_current=$((cv_current + cd_current))

proposed='{}'
if [ "$cv_current" -eq 0 ]; then
  cv_aarch_url="https://github.com/clash-verge-rev/clash-verge-rev/releases/download/v${cv_latest}/Clash.Verge_${cv_latest}_aarch64.dmg"
  cv_x64_url="https://github.com/clash-verge-rev/clash-verge-rev/releases/download/v${cv_latest}/Clash.Verge_${cv_latest}_x64.dmg"
  cv_aarch_hash=$(nix store prefetch-file --json "$cv_aarch_url" | jq -r '.hash')
  cv_x64_hash=$(nix store prefetch-file --json "$cv_x64_url" | jq -r '.hash')
  proposed=$(jq -n \
    --arg version "$cv_latest" \
    --arg aarch "$cv_aarch_hash" \
    --arg x64 "$cv_x64_hash" \
    '{ "clash-verge-rev": { version: $version, archHash: { "aarch64-darwin": $aarch, "x86_64-darwin": $x64 } } }')
fi
if [ "$cd_current" -eq 0 ]; then
  proposed=$(echo "$proposed" | jq --arg hash "$cd_fresh_hash" '. + { "claude-desktop": { hash: $hash } }')
fi

jq -n \
  --argjson packages_current "$packages_current" \
  --arg cv_pinned "$cv_pinned" --arg cv_latest "$cv_latest" --argjson cv_current "$cv_current" \
  --argjson cd_current "$cd_current" \
  --argjson proposed "$proposed" \
  '{packages_current: $packages_current,
    "clash-verge-rev": {pinned: $cv_pinned, latest: $cv_latest, current: ($cv_current == 1)},
    "claude-desktop": {current: ($cd_current == 1)},
    proposed: $proposed}'
