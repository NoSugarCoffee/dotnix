---
schedule: weekly
# Open-ended: same reasoning as nixpkgs-freshness -- upstream releases never
# stop, so there's no metric value at which this program is "done".
---

# Darwin DMG-Repack Package Freshness

## Goal

Keep the two hand-pinned macOS packages current with their upstream release:

- `pkgs/clash-verge-rev-darwin` -- versioned GitHub releases. Stale when the
  pinned `version` is behind the latest release tag.
- `pkgs/claude-desktop-darwin` -- an **unversioned** "latest" URL (Anthropic
  publishes no version tag for it). Stale when a fresh download of that URL
  no longer matches the pinned `hash` -- i.e. upstream shipped a new build.
  This means the evaluation genuinely re-downloads that DMG every run; there
  is no cheaper staleness signal available for an unversioned URL.

One iteration = bump one package (prefer whichever the evaluation reports
stale; if both are stale, fix one now and let next week's run catch the
other). For clash-verge-rev-darwin, bumping means updating `version` and
re-deriving **both** `archHash` entries (`aarch64-darwin` and `x86_64-darwin`)
from the new version's release URLs via `nix store prefetch-file --json
<url>` -- do not guess a hash. For claude-desktop-darwin, bumping means
updating `hash` to the freshly observed value; `version` there is an
informational label with no authoritative upstream source, so a best-effort
bump (or leaving it unchanged) is acceptable as long as `hash` is correct.

The metric is `packages_current` (0, 1, or 2 -- how many of the two packages
are currently pinned to their upstream-latest). **Higher is better.**

## Target

Only modify:
- `pkgs/clash-verge-rev-darwin/default.nix`
- `pkgs/claude-desktop-darwin/default.nix`

Do NOT modify:
- Any other file under `pkgs/**`
- `flake.lock` / `flake.nix` (covered by the separate `nixpkgs-freshness`
  program)
- `home/home.nix`, `README.md`, any file under `.github/workflows/`

## Evaluation

```bash
set -euo pipefail

# --- clash-verge-rev-darwin: compare pinned version to the latest GitHub release tag ---
cv_pinned=$(grep -oP '(?<=version = ")[^"]+' pkgs/clash-verge-rev-darwin/default.nix | head -1)
cv_latest_tag=$(gh api repos/clash-verge-rev/clash-verge-rev/releases/latest --jq '.tag_name')
cv_latest="${cv_latest_tag#v}"
cv_current=0
[ "$cv_pinned" = "$cv_latest" ] && cv_current=1

# --- claude-desktop-darwin: compare pinned hash to a fresh prefetch of the same URL ---
cd_pinned_hash=$(grep -oP '(?<=hash = ")[^"]+' pkgs/claude-desktop-darwin/default.nix | head -1)
cd_url=$(grep -oP '(?<=url = ")[^"]+' pkgs/claude-desktop-darwin/default.nix | head -1)
cd_fresh_hash=$(nix store prefetch-file --json "$cd_url" | jq -r '.hash')
cd_current=0
[ "$cd_pinned_hash" = "$cd_fresh_hash" ] && cd_current=1

packages_current=$((cv_current + cd_current))

jq -n \
  --argjson packages_current "$packages_current" \
  --arg cv_pinned "$cv_pinned" --arg cv_latest "$cv_latest" --argjson cv_current "$cv_current" \
  --argjson cd_current "$cd_current" \
  '{packages_current: $packages_current,
    "clash-verge-rev": {pinned: $cv_pinned, latest: $cv_latest, current: ($cv_current == 1)},
    "claude-desktop": {current: ($cd_current == 1)}}'
```

The metric is `packages_current` from the JSON output. **Higher is better.**
CI's macOS build job (`ci.yml` `build-macos`) actually fetches and unpacks
both DMGs, so a wrong hash or a broken app-bundle assumption fails loudly
there rather than silently passing this script.
