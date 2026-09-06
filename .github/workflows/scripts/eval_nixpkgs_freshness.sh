#!/usr/bin/env bash
# Runner-side (and in-sandbox) evaluation for nixpkgs-freshness.
# Prints JSON with up_to_date_fraction and stale_inputs, plus a proposed
# flake.lock bumping one stale input when nix is available. Higher is better.
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

# The agent sandbox has no nix, so the lock rewrite -- rev, narHash and
# lastModified, none of which can be derived by hand -- happens here and is
# handed over as a file for the agent to copy into place.
proposed='null'
proposed_error='null'
if [ "$(jq 'length' <<<"$stale")" -gt 0 ]; then
  if ! command -v nix >/dev/null 2>&1; then
    proposed_error=$(jq -n '"nix is unavailable here; the rewrite only happens on the runner"')
  else
    input=$(jq -r '.[0].name' <<<"$stale")
    scratch=$(mktemp -d)
    trap 'rm -rf "$scratch"' EXIT
    cp flake.nix flake.lock "$scratch/"

    # A failed update must not sink the whole iteration: the metric above is
    # already valid, and reporting it with proposed: null lets the agent record
    # honest state instead of the run erroring out with nothing.
    if nix flake update "$input" --flake "$scratch" >&2; then
      proposed_dir="${AUTOLOOP_PROPOSED_DIR:-/tmp/gh-aw/autoloop-proposed}"
      mkdir -p "$proposed_dir"
      cp "$scratch/flake.lock" "$proposed_dir/flake.lock"

      proposed=$(jq -n \
        --arg input "$input" \
        --arg flake_lock "$proposed_dir/flake.lock" \
        --arg base_blob "$(git hash-object flake.lock)" \
        --arg rev "$(jq -r --arg i "$input" '.nodes[.nodes.root.inputs[$i]].locked.rev' "$scratch/flake.lock")" \
        '{input: $input, flake_lock: $flake_lock, base_flake_lock_blob: $base_blob, rev: $rev}')
    else
      proposed_error=$(jq -n --arg input "$input" '"nix flake update \($input) failed; see the runner log"')
    fi
  fi
fi

fraction=$(awk -v c="$current" -v t="$total" 'BEGIN { printf "%.4f", c/t }')
jq -n --argjson fraction "$fraction" --argjson stale "$stale" \
  --argjson proposed "$proposed" --argjson proposed_error "$proposed_error" \
  '{up_to_date_fraction: $fraction, stale_inputs: $stale,
    proposed: $proposed, proposed_error: $proposed_error}'
