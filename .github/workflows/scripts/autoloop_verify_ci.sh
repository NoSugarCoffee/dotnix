#!/usr/bin/env bash
# Report the CI verdict for the selected program's branch head, so the agent
# starts each iteration knowing whether the previous one actually builds.
#
# The verdict is necessarily one run behind: gh-aw wipes git credentials before
# the agent starts and pushes its commit from the safe_outputs job after it
# exits, so no agent can watch CI for the commit it just wrote.
set -euo pipefail

CONFIG="${AUTOLOOP_JSON:-/tmp/gh-aw/autoloop.json}"
OUT="${AUTOLOOP_CI_JSON:-/tmp/gh-aw/autoloop-ci.json}"
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
mkdir -p "$(dirname "$OUT")"

write() {
  jq -n --arg state "$1" --arg branch "${2-}" --arg head_sha "${3-}" --arg run_url "${4-}" \
    '{state: $state,
      branch: (if $branch == "" then null else $branch end),
      head_sha: (if $head_sha == "" then null else $head_sha end),
      run_url: (if $run_url == "" then null else $run_url end)}' > "$OUT"
  cat "$OUT"
}

branch=$(jq -r '.head_branch // empty' "$CONFIG")
if [ -z "$branch" ]; then
  write none
  exit 0
fi

# Asked of the API rather than the checkout: a fetched ref goes stale the moment
# another run pushes the branch, and ratifying a stale sha would bless a commit
# that no longer is the head.
head_sha=$(gh api "repos/$repo/branches/$branch" 2>/dev/null | jq -r '.commit.sha // empty')
if [ -z "$head_sha" ]; then
  write none "$branch"
  exit 0
fi

default_branch="${DEFAULT_BRANCH:-main}"
default_sha=$(gh api "repos/$repo/commits/$default_branch" | jq -r '.sha')
if [ "$head_sha" = "$default_sha" ]; then
  write none "$branch" "$head_sha"
  exit 0
fi

# head_sha as a query parameter rather than a page of recent branch runs: no
# pagination cap can hide the run that matters.
run=$(gh api "repos/$repo/actions/workflows/ci.yml/runs?head_sha=$head_sha&per_page=20" |
  jq '.workflow_runs[0] // empty')
if [ -z "$run" ]; then
  write pending "$branch" "$head_sha"
  exit 0
fi

run_url=$(jq -r '.html_url' <<<"$run")
if [ "$(jq -r '.status' <<<"$run")" != "completed" ]; then
  write pending "$branch" "$head_sha" "$run_url"
  exit 0
fi

# Only a real build failure may start a repair iteration. cancelled, skipped,
# neutral and action_required say nothing about the commit, so treating them as
# failures would burn the repair budget on a build that never ran.
case "$(jq -r '.conclusion' <<<"$run")" in
  success)
    write verified "$branch" "$head_sha" "$run_url"
    ;;
  failure | timed_out | startup_failure)
    write failed "$branch" "$head_sha" "$run_url"
    ;;
  *)
    write pending "$branch" "$head_sha" "$run_url"
    ;;
esac
