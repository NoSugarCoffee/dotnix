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
bash .github/workflows/scripts/eval_nixpkgs_freshness.sh
```

The metric is `up_to_date_fraction` from the JSON output (`current_count /
total_root_inputs`). **Higher is better.** Prefer
`/tmp/gh-aw/autoloop-eval.json` when present (written on the runner before
the sandbox starts). `nix flake check` and this repo's own `ci.yml` build
jobs are the real safety net -- this script only measures staleness, it does
not build anything.
