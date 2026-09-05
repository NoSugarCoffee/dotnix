#!/usr/bin/env bash
# Runner-side (and in-sandbox) evaluation for nixpkgs-freshness.
# Prints JSON with up_to_date_fraction and stale_inputs. Higher is better.
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
