---
schedule: weekly
# Open-ended: upstream never stops moving, so there's no metric value at
# which this program is "done" -- matches the cadence of the existing
# read-only staleness check in .github/workflows/code-quality.md.
---

# Nixpkgs and Flake Input Freshness

## Goal

Keep this flake's **root** inputs pinned to the newest commit available on
their locked ref. One iteration = bump one stale root input via
`nix flake update <input-name>` and let CI prove the new pin still builds.

Root inputs (from `flake.nix`, five total): `nixpkgs`, `nixpkgs-unstable`,
`home-manager`, `flake-utils`, `claude-desktop`.

**Do not bump `claude-desktop`'s own `nixpkgs` follow.** That input is
deliberately *not* set to follow this repo's `nixpkgs` -- its build recipe
still calls `nodePackages.asar`, which nixpkgs removed on 2026-03-03, and
letting it use its own older pinned nixpkgs is what keeps the Linux build
working. `nix flake update claude-desktop` will re-lock claude-desktop's own
transitive graph as *its* flake.nix dictates; that's expected and outside
this program's control. Only the five root inputs above are yours to bump.

If many small bumps have been exhausted and one root input's evaluation
still reports itself stale, prefer bumping that one over re-checking inputs
already at HEAD.

The metric is `up_to_date_fraction`. **Higher is better.**

## Target

Only modify:
- `flake.lock`

Do NOT modify:
- `flake.nix` (input URLs, `follows` overrides -- those are structural
  decisions, not freshness bumps)
- `pkgs/**` (covered by the separate `darwin-packages-freshness` program)
- `home/home.nix`, `README.md`, any file under `.github/workflows/`

## Evaluation

```bash
set -euo pipefail

total=0
current=0
stale='[]'

for name in $(jq -r '.nodes.root.inputs | keys[]' flake.lock); do
  node=$(jq -r --arg n "$name" '.nodes.root.inputs[$n]' flake.lock)
  owner=$(jq -r --arg n "$node" '.nodes[$n].original.owner' flake.lock)
  repo=$(jq -r --arg n "$node" '.nodes[$n].original.repo' flake.lock)
  ref=$(jq -r --arg n "$node" '.nodes[$n].original.ref // empty' flake.lock)
  locked_rev=$(jq -r --arg n "$node" '.nodes[$n].locked.rev' flake.lock)

  if [ -n "$ref" ]; then
    latest_rev=$(gh api "repos/${owner}/${repo}/commits?sha=${ref}&per_page=1" --jq '.[0].sha')
  else
    latest_rev=$(gh api "repos/${owner}/${repo}/commits?per_page=1" --jq '.[0].sha')
  fi

  total=$((total + 1))
  # Compare full 40-char revs -- abbreviating either side turns every input
  # into a false mismatch (the same trap code-quality.md's check documents).
  if [ "$locked_rev" = "$latest_rev" ]; then
    current=$((current + 1))
  else
    stale=$(echo "$stale" | jq --arg n "$name" --arg latest "$latest_rev" '. + [{name: $n, latest: $latest}]')
  fi
done

fraction=$(awk -v c="$current" -v t="$total" 'BEGIN { printf "%.4f", c/t }')
jq -n --argjson fraction "$fraction" --argjson stale "$stale" \
  '{up_to_date_fraction: $fraction, stale_inputs: $stale}'
```

The metric is `up_to_date_fraction` from the JSON output (`current_count /
total_root_inputs`). **Higher is better.** `nix flake check` and this repo's
own `ci.yml` build jobs are the real safety net -- this script only measures
staleness, it does not build anything.
