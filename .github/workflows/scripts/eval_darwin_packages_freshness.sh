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

ego_file="pkgs/ego-lite-darwin/default.nix"
ego_url_template=$(grep -oP '(?<=url = ")[^"]+' "$ego_file" | head -1)
ego_current=1
ego_proposed='{}'
for arch in aarch64:arm64 x86_64:x64; do
  nix_arch="${arch%%:*}-darwin"
  url_arch="${arch##*:}"
  pinned=$(grep -oP "(?<=^    ${nix_arch} = \")sha256-[^\"]+" "$ego_file" | head -1)
  url=${ego_url_template//\$\{archName.\$\{system\}\}/$url_arch}
  fresh=$(nix store prefetch-file --json "$url" | jq -r '.hash')
  if [ "$pinned" != "$fresh" ]; then
    ego_current=0
    ego_proposed=$(jq --arg a "$nix_arch" --arg h "$fresh" '. + {($a): $h}' <<<"$ego_proposed")
  fi
done

cida_file="pkgs/cida-darwin/default.nix"
cida_pinned=$(grep -oP '(?<=version = ")[^"]+' "$cida_file" | head -1)
cida_pinned_build=$(grep -oP '(?<=build = ")[^"]+' "$cida_file" | head -1)
cida_release=$(gh api repos/Xuanwo/cida/releases/latest)
cida_latest_tag=$(jq -er '.tag_name' <<<"$cida_release")
cida_latest="${cida_latest_tag#v}"
cida_asset=$(jq -er --arg version "$cida_latest" \
  '[.assets[].name | select(test("^Cida-" + $version + "-[0-9]+[.]dmg$"))] |
   if length == 1 then .[0] else error("expected one Cida DMG asset") end' <<<"$cida_release")
cida_latest_build="${cida_asset#Cida-"${cida_latest}"-}"
cida_latest_build="${cida_latest_build%.dmg}"
cida_current=0
[ "$cida_pinned" = "$cida_latest" ] && [ "$cida_pinned_build" = "$cida_latest_build" ] && cida_current=1

packages_current=$((cv_current + ego_current + cida_current))

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
if [ "$ego_current" -eq 0 ]; then
  proposed=$(echo "$proposed" | jq --argjson archHash "$ego_proposed" '. + { "ego-lite": { archHash: $archHash } }')
fi
if [ "$cida_current" -eq 0 ]; then
  cida_url="https://github.com/Xuanwo/cida/releases/download/${cida_latest_tag}/${cida_asset}"
  cida_hash=$(nix store prefetch-file --json "$cida_url" | jq -er '.hash')
  proposed=$(jq --arg version "$cida_latest" --arg build "$cida_latest_build" --arg hash "$cida_hash" \
    '. + { cida: { version: $version, build: $build, hash: $hash } }' <<<"$proposed")
fi

jq -n \
  --argjson packages_current "$packages_current" \
  --arg cv_pinned "$cv_pinned" --arg cv_latest "$cv_latest" --argjson cv_current "$cv_current" \
  --argjson ego_current "$ego_current" \
  --arg cida_pinned "$cida_pinned" --arg cida_latest "$cida_latest" --argjson cida_current "$cida_current" \
  --argjson proposed "$proposed" \
  '{packages_current: $packages_current,
    "clash-verge-rev": {pinned: $cv_pinned, latest: $cv_latest, current: ($cv_current == 1)},
    "ego-lite": {current: ($ego_current == 1)},
    cida: {pinned: $cida_pinned, latest: $cida_latest, current: ($cida_current == 1)},
    proposed: $proposed}'
