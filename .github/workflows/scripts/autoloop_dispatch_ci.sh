#!/usr/bin/env bash
# Dispatch ci.yml on every autoloop branch whose head commit has no CI run yet.
# Autoloop pushes its commits with GITHUB_TOKEN, and GitHub suppresses the push
# and pull_request events that token creates; workflow_dispatch is the documented
# exception, so this is what gets the loop's commits built at all.
set -euo pipefail

repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
default_branch=$(gh api "repos/$repo" | jq -r '.default_branch')
default_sha=$(gh api "repos/$repo/commits/$default_branch" | jq -r '.sha')

status=0
for branch in $(gh api "repos/$repo/branches?per_page=100" |
  jq -r '.[] | select(.name | startswith("autoloop/")) | .name'); do
  head_sha=$(gh api "repos/$repo/branches/$branch" | jq -r '.commit.sha')

  # A branch sitting exactly at the default branch carries no iteration to verify.
  if [ "$head_sha" = "$default_sha" ]; then
    echo "$branch: at $default_branch, nothing to build"
    continue
  fi

  runs=$(gh run list --workflow ci.yml --branch "$branch" --limit 20 --json headSha |
    jq --arg sha "$head_sha" '[.[] | select(.headSha == $sha)] | length')
  if [ "$runs" -gt 0 ]; then
    echo "$branch: $head_sha already built"
    continue
  fi

  echo "$branch: dispatching ci.yml for $head_sha"
  # One branch failing to dispatch must not hide the others; the exit code still
  # reports it.
  gh workflow run ci.yml --ref "$branch" || status=1
done

exit "$status"
