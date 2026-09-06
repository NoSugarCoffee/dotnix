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
if [ -z "$branch" ] || ! git rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null; then
  write none
  exit 0
fi

head_sha=$(git rev-parse "refs/remotes/origin/$branch")
default_branch="${DEFAULT_BRANCH:-main}"
if [ "$head_sha" = "$(git rev-parse "refs/remotes/origin/$default_branch")" ]; then
  write none "$branch" "$head_sha"
  exit 0
fi

runs=$(gh run list --workflow ci.yml --branch "$branch" --limit 20 \
  --json headSha,status,conclusion,url)
run=$(jq --arg sha "$head_sha" '[.[] | select(.headSha == $sha)] | first // empty' <<<"$runs")

if [ -z "$run" ]; then
  write pending "$branch" "$head_sha"
  exit 0
fi

run_url=$(jq -r '.url' <<<"$run")
if [ "$(jq -r '.status' <<<"$run")" != "completed" ]; then
  write pending "$branch" "$head_sha" "$run_url"
elif [ "$(jq -r '.conclusion' <<<"$run")" = "success" ]; then
  write verified "$branch" "$head_sha" "$run_url"
else
  write failed "$branch" "$head_sha" "$run_url"
fi
