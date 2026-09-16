#!/usr/bin/env bash
# Run the selected Autoloop program's evaluation on the Actions runner
# (Nix + gh available) and write JSON to /tmp/gh-aw/autoloop-eval.json for
# the sandboxed agent. The sandbox historically cannot see `nix` or reach
# the gh CLI proxy, so this is the authoritative metric for the iteration.
set -euo pipefail

CONFIG="${AUTOLOOP_JSON:-/tmp/gh-aw/autoloop.json}"
OUT="${AUTOLOOP_EVAL_JSON:-/tmp/gh-aw/autoloop-eval.json}"
mkdir -p "$(dirname "$OUT")"

if [ ! -f "$CONFIG" ]; then
  echo "autoloop.json not found at $CONFIG" >&2
  exit 1
fi

selected=$(jq -r '.selected // empty' "$CONFIG")
if [ -z "$selected" ]; then
  jq -n '{selected: null}' > "$OUT"
  echo "No program selected; wrote $OUT"
  exit 0
fi

case "$selected" in
  darwin-packages-freshness)
    script=".github/workflows/scripts/eval_darwin_packages_freshness.sh"
    ;;
  nixpkgs-freshness)
    script=".github/workflows/scripts/eval_nixpkgs_freshness.sh"
    ;;
  *)
    jq -n --arg selected "$selected" \
      '{selected: $selected, error: "no runner-side evaluator for this program"}' > "$OUT"
    echo "No evaluator for $selected; wrote $OUT"
    exit 0
    ;;
esac

# Measure the branch the iteration will land on, not the default ref: bumps
# accepted by earlier iterations live only on that branch, and evaluating main
# would re-propose them -- for nixpkgs-freshness that means handing the agent a
# flake.lock derived from main, reverting every bump already on the branch.
head_branch=$(jq -r '.head_branch // empty' "$CONFIG")
existing_pr=$(jq -r '.existing_pr // empty' "$CONFIG")
if [ -n "$head_branch" ] && [ -n "$existing_pr" ] &&
  git rev-parse --verify --quiet "refs/remotes/origin/$head_branch" >/dev/null; then
  git checkout -B "$head_branch" "refs/remotes/origin/$head_branch"
fi

if [ ! -f "$script" ]; then
  jq -n --arg selected "$selected" --arg script "$script" \
    '{selected: $selected, error: "evaluator \($script) is absent from the evaluated tree"}' > "$OUT"
  echo "Evaluator $script is absent from the evaluated tree; wrote $OUT" >&2
  exit 0
fi

result=$(bash "$script")
jq -n --arg selected "$selected" --argjson result "$result" \
  '$result + {selected: $selected}' > "$OUT"
echo "Wrote evaluation for $selected to $OUT"
cat "$OUT"
