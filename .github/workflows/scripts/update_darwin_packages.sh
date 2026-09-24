#!/usr/bin/env bash
set -euo pipefail

eval_script="${DARWIN_EVAL_SCRIPT:-.github/workflows/scripts/eval_darwin_packages_freshness.sh}"
eval_file="${DARWIN_EVAL_JSON:-}"

if [ -n "$eval_file" ]; then
  eval_json=$(cat "$eval_file")
else
  eval_json=$(bash "$eval_script")
fi

rewrite() {
  local file=$1
  local what=$2
  shift 2
  local tmp
  tmp=$(mktemp)
  sed "$@" "$file" >"$tmp"
  if cmp -s "$file" "$tmp"; then
    rm -f "$tmp"
    echo "${what}: the evaluation proposed a bump but no line in ${file} matched" >&2
    exit 1
  fi
  mv "$tmp" "$file"
}

proposed=$(jq -c '.proposed' <<<"$eval_json")
summary=""
changed=false

clash=$(jq -c '.["clash-verge-rev"] // empty' <<<"$proposed")
if [ -n "$clash" ]; then
  pinned=$(jq -r '.["clash-verge-rev"].pinned' <<<"$eval_json")
  version=$(jq -r '.version' <<<"$clash")
  aarch64=$(jq -r '.archHash["aarch64-darwin"]' <<<"$clash")
  x86_64=$(jq -r '.archHash["x86_64-darwin"]' <<<"$clash")

  rewrite pkgs/clash-verge-rev-darwin/default.nix clash-verge-rev \
    -e "s|^\(  version = \)\"[^\"]*\";|\1\"${version}\";|" \
    -e "s|^\(    aarch64-darwin = \)\"sha256-[^\"]*\";|\1\"${aarch64}\";|" \
    -e "s|^\(    x86_64-darwin = \)\"sha256-[^\"]*\";|\1\"${x86_64}\";|"

  changed=true
  summary+="- \`clash-verge-rev-darwin\`: ${pinned} -> ${version}"$'\n'
fi

desktop=$(jq -c '.["claude-desktop"] // empty' <<<"$proposed")
if [ -n "$desktop" ]; then
  file="pkgs/claude-desktop-darwin/default.nix"
  hash=$(jq -r '.hash' <<<"$desktop")
  label=$(sed -n 's|^  version = "\([^"]*\)";|\1|p' "$file")

  rewrite "$file" claude-desktop \
    -e "s|^\(    hash = \)\"sha256-[^\"]*\";|\1\"${hash}\";|"

  changed=true
  summary+="- \`claude-desktop-darwin\`: upstream shipped a new build at the unversioned URL; hash bumped to \`${hash}\`."$'\n'
  summary+="  The \`version = \"${label}\"\` label has no authoritative upstream source and was left as is."$'\n'
fi

ego=$(jq -c '.["ego-lite"] // empty' <<<"$proposed")
if [ -n "$ego" ]; then
  file="pkgs/ego-lite-darwin/default.nix"
  label=$(sed -n 's|^    aarch64-darwin = "\([0-9][^"]*\)";|\1|p' "$file")
  args=()
  for nix_arch in aarch64-darwin x86_64-darwin; do
    hash=$(jq -r --arg a "$nix_arch" '.archHash[$a] // empty' <<<"$ego")
    [ -n "$hash" ] || continue
    args+=(-e "s|^\(    ${nix_arch} = \)\"sha256-[^\"]*\";|\1\"${hash}\";|")
    summary+="- \`ego-lite-darwin\` (${nix_arch}): new build at the unversioned URL, hash bumped to \`${hash}\`."$'\n'
  done

  rewrite "$file" ego-lite "${args[@]}"

  changed=true
  summary+="  The \`archVersion\` labels still read \`${label}\`; read CFBundleShortVersionString out of the DMG to correct them."$'\n'
fi

{
  echo "changed=${changed}"
  echo "summary<<SUMMARY_EOF"
  printf '%s' "$summary"
  echo "SUMMARY_EOF"
} >>"${GITHUB_OUTPUT:-/dev/stdout}"

if [ "$changed" = false ]; then
  echo "Both darwin DMG pins are current."
fi
