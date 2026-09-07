#!/usr/bin/env bash
# Dispatch ci.yml on every autoloop branch whose head commit has no CI run yet.
# Autoloop pushes its commits with GITHUB_TOKEN, and GitHub suppresses the push
# and pull_request events that token creates; workflow_dispatch is the documented
# exception, so this is what gets the loop's commits built at all.
set -euo pipefail

repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
default_branch=$(gh api "repos/$repo" | jq -r '.default_branch')
default_sha=$(gh api "repos/$repo/commits/$default_branch" | jq -r '.sha')

# Name and head sha come from the same paginated listing: a per-branch lookup
# would need the ref URL-encoded, and would miss branches past the first page.
branches=$(gh api --paginate "repos/$repo/branches?per_page=100" |
  jq -r '.[] | select(.name | startswith("autoloop/")) | "\(.name) \(.commit.sha)"')

status=0
while read -r branch head_sha; do
  [ -n "$branch" ] || continue

  # A branch sitting exactly at the default branch carries no iteration to build.
  if [ "$head_sha" = "$default_sha" ]; then
    echo "$branch: at $default_branch, nothing to build"
    continue
  fi

  # Scoped to ci.yml, not the repository's runs: any other workflow having run
  # for this sha would otherwise read as "built" and the gate would wait forever.
  # One branch's transient API error must not cost the others their build.
  runs=$(gh api "repos/$repo/actions/workflows/ci.yml/runs?head_sha=$head_sha&per_page=1" |
    jq -r '.total_count') || {
    echo "$branch: could not read runs for $head_sha" >&2
    status=1
    continue
  }
  if [ "$runs" -gt 0 ]; then
    echo "$branch: $head_sha already built"
    continue
  fi

  echo "$branch: dispatching ci.yml for $head_sha"
  gh workflow run ci.yml --ref "$branch" || status=1
done <<<"$branches"

exit "$status"
