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
bash .github/workflows/scripts/eval_darwin_packages_freshness.sh
```

The metric is `packages_current` from the JSON output. **Higher is better.**
When a pin is stale the JSON also includes a `proposed` object with
prefetch-derived hashes — apply those rather than guessing. Prefer
`/tmp/gh-aw/autoloop-eval.json` when present (written on the runner before
the sandbox starts). CI's macOS build job (`ci.yml` `build-macos`) actually
fetches and unpacks both DMGs, so a wrong hash or a broken app-bundle
assumption fails loudly there rather than silently passing this script.
