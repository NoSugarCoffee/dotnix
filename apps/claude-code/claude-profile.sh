#!/bin/sh
# Run Claude Code under a separate account while sharing every other piece of
# configuration with ~/.claude and ~/.claude.json.
#
# The account lives in the Keychain entry keyed by CLAUDE_CONFIG_DIR, plus the
# account fields of the profile's own .claude.json. Everything else in ~/.claude
# is symlinked in; mcpServers and projects are synced through ~/.claude.json
# around each run, because .claude.json mixes account state with config and
# cannot be shared as a whole.
set -eu

if [ "$#" -eq 0 ]; then
  printf 'Usage: claude-profile NAME [claude arguments...]\n' >&2
  exit 2
fi

profile=$1
shift
case "$profile" in
  ''|.|..|.*|*[!A-Za-z0-9._-]*)
    printf 'Invalid profile name: %s\n' "$profile" >&2
    exit 2
    ;;
esac

shared_dir="$HOME/.claude"
shared_json="$HOME/.claude.json"
config_dir="$HOME/.claude-profiles/$profile"
migrated_root="$HOME/.claude-profiles/.migrated/$profile"
migrated_dir=
# Present once the profile has been linked; from then on a real file where a
# symlink was means Claude Code replaced the link (write-temp-then-rename), so
# the profile's copy is the newer one.
linked_marker="$config_dir/.linked-to-shared"
mkdir -p "$config_dir"
chmod 700 "$config_dir"

# Account- or org-bound state that must stay per profile.
is_account_bound() {
  case "$1" in
    .credentials.json|.oauth_refresh.lock.owner|backups|daemon|daemon-auth-*|daemon.log \
      |mcp-needs-auth-cache.json|policy-limits.json*|remote-settings.json*) return 0 ;;
    *) return 1 ;;
  esac
}

is_profile_bookkeeping() {
  case "$1" in
    .claude.json|.claude.json.*|.linked-to-shared|.config.json) return 0 ;;
    *) return 1 ;;
  esac
}

# One backup directory per linking pass, so a pass never overwrites the
# backups of an earlier one.
ensure_migrated_dir() {
  [ -n "$migrated_dir" ] && return 0
  mkdir -p "$migrated_root"
  migrated_dir=$(mktemp -d "$migrated_root/$(date +%Y%m%d%H%M%S).XXXXXX")
}

# First migration: the shared copy wins and the profile's entry is merged in
# where that is lossless. The original is kept under .migrated either way.
absorb_into_shared() {
  local_path=$1
  shared_path=$2
  name=$(basename "$local_path")
  if [ -d "$local_path" ] && [ -d "$shared_path" ]; then
    rsync -a --ignore-existing "$local_path/" "$shared_path/"
  elif [ "$name" = history.jsonl ]; then
    cat "$local_path" >>"$shared_path"
  fi
  ensure_migrated_dir
  mv "$local_path" "$migrated_dir/$name"
}

# A shared entry removed from ~/.claude leaves its profile symlink behind.
# Claude then cannot recreate it: mkdir fails with "File exists" on the
# dangling link. Only links that point into the shared dir are removed.
prune_stale_shared_links() {
  for local_path in "$config_dir"/* "$config_dir"/.[!.]*; do
    [ -L "$local_path" ] || continue
    target=$(readlink "$local_path") || continue
    case "$target" in
      "$shared_dir"/*)
        [ -e "$target" ] || rm -f "$local_path"
        ;;
    esac
  done
}

# After migration: the profile's entry replaced our symlink, so it wins. The
# shared copy it overwrites is kept under .migrated.
adopt_into_shared() {
  local_path=$1
  shared_path=$2
  name=$(basename "$local_path")
  ensure_migrated_dir
  cp -Rp "$shared_path" "$migrated_dir/$name"
  if [ -d "$local_path" ] && [ -d "$shared_path" ]; then
    rsync -a "$local_path/" "$shared_path/"
    rm -rf "$local_path"
  else
    rm -rf "$shared_path"
    mv "$local_path" "$shared_path"
  fi
  printf 'claude-profile: kept %s changes to %s in %s (previous copy in %s)\n' \
    "$profile" "$name" "$shared_dir" "$migrated_dir" >&2
}

link_shared_entries() {
  migrated_dir=
  for shared_path in "$shared_dir"/* "$shared_dir"/.[!.]*; do
    [ -e "$shared_path" ] || continue
    name=$(basename "$shared_path")
    if is_account_bound "$name" || is_profile_bookkeeping "$name"; then
      continue
    fi
    local_path="$config_dir/$name"
    if [ -e "$local_path" ] && [ ! -L "$local_path" ]; then
      if [ -e "$linked_marker" ]; then
        adopt_into_shared "$local_path" "$shared_path"
      else
        absorb_into_shared "$local_path" "$shared_path"
      fi
    fi
    ln -sfn "$shared_path" "$local_path"
  done
  prune_stale_shared_links
  : >"$linked_marker"
}

# Entries Claude Code created only in the profile are not shared automatically,
# because a new one may be account-bound; name them so they are not missed.
warn_unshared_entries() {
  for local_path in "$config_dir"/* "$config_dir"/.[!.]*; do
    if [ ! -e "$local_path" ] || [ -L "$local_path" ]; then
      continue
    fi
    name=$(basename "$local_path")
    if is_account_bound "$name" || is_profile_bookkeeping "$name" || [ -e "$shared_dir/$name" ]; then
      continue
    fi
    printf 'claude-profile: %s exists only in %s; move it to %s to share it\n' \
      "$name" "$config_dir" "$shared_dir" >&2
  done
}

# Usage: sync_json SOURCE TARGET [BASE]
# Copies the shared keys from SOURCE into TARGET, leaving TARGET's account
# fields untouched. With BASE (the shared file at launch), apply only SOURCE's
# delta so a concurrent claude's new servers and project entries are kept.
sync_json() {
  python3 -I - "$1" "$2" "${3:-}" <<'EOF'
import json, os, sys

SHARED_KEYS = ("mcpServers", "projects")
source_path, target_path, base_path = sys.argv[1], sys.argv[2], sys.argv[3]


def load(path):
    if not path or not os.path.exists(path):
        return None
    try:
        with open(path) as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None


def merge_dicts(base, ours, theirs):
    result = {}
    for key in set(base) | set(ours) | set(theirs):
        in_base, in_ours, in_theirs = key in base, key in ours, key in theirs
        b, o, t = base.get(key), ours.get(key), theirs.get(key)
        if in_ours and in_theirs:
            if o == t:
                result[key] = o
            elif in_base and o == b:
                result[key] = t
            elif in_base and t == b:
                result[key] = o
            elif isinstance(o, dict) and isinstance(t, dict):
                result[key] = merge_dicts(b if isinstance(b, dict) else {}, o, t)
            else:
                result[key] = o
        elif in_ours and not in_theirs:
            if not in_base or o != b:
                result[key] = o
        elif in_theirs and not in_ours:
            if not in_base or t != b:
                result[key] = t
    return result


source = load(source_path)
if source is None:
    # Missing source: nothing to copy. Unreadable source: fail so the caller
    # can report it instead of keeping a stale target.
    sys.exit(0 if not source_path or not os.path.exists(source_path) else 1)
target = load(target_path)
if target is None:
    if os.path.exists(target_path):
        sys.exit(1)
    target = {}

def as_dict(doc, key):
    value = doc.get(key)
    return value if isinstance(value, dict) else {}

if base_path:
    base = load(base_path)
    if base is None:
        base = {}
    for key in SHARED_KEYS:
        # A key the source omits is a deletion. Merge against an empty "ours"
        # so a concurrent session can still keep entries this run did not touch,
        # and drop the key entirely when nothing remains.
        if key not in source:
            merged = merge_dicts(as_dict(base, key), {}, as_dict(target, key))
            if merged:
                target[key] = merged
            else:
                target.pop(key, None)
        else:
            target[key] = merge_dicts(as_dict(base, key), as_dict(source, key), as_dict(target, key))
else:
    for key in SHARED_KEYS:
        if key in source:
            target[key] = source[key]
        else:
            target.pop(key, None)

# 0600 from the start. open() then chmod leaves mcpServers readable under the
# umask until chmod runs.
tmp_path = f"{target_path}.tmp.{os.getpid()}"
fd = os.open(tmp_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    json.dump(target, f, indent=2)
os.replace(tmp_path, target_path)
EOF
}

link_shared_entries
sync_json "$shared_json" "$config_dir/.claude.json"
launch_snapshot="$config_dir/.claude.json.launch"
if [ -f "$shared_json" ]; then
  cp "$shared_json" "$launch_snapshot"
else
  printf '%s\n' '{}' >"$launch_snapshot"
fi

export CLAUDE_CONFIG_DIR="$config_dir"
status=0
after_ran=0
claude_pid=

after_run() {
  [ "${after_ran:-0}" -eq 1 ] && return 0
  after_ran=1
  # set -e is off while these run so a failure is reported and does not
  # replace Claude's exit status. The subshell turns it back on so a command
  # in the middle of a function still fails the step.
  set +e
  (set -e; link_shared_entries)
  link_status=$?
  (set -e; warn_unshared_entries)
  warn_status=$?
  sync_json "$config_dir/.claude.json" "$shared_json" "$launch_snapshot"
  sync_status=$?
  rm -f "$launch_snapshot"
  set -e
  [ "$link_status" -eq 0 ] ||
    printf 'claude-profile: failed to link shared entries\n' >&2
  [ "$warn_status" -eq 0 ] ||
    printf 'claude-profile: failed to check for unshared entries\n' >&2
  [ "$sync_status" -eq 0 ] ||
    printf 'claude-profile: failed to write shared config back to %s\n' "$shared_json" >&2
  return 0
}

# Signal traps are the only callers; shellcheck does not see those as calls.
# shellcheck disable=SC2317,SC2329
stop_claude() {
  if [ -n "${claude_pid:-}" ]; then
    kill -s "$1" "$claude_pid" 2>/dev/null || :
    wait "$claude_pid" 2>/dev/null || :
    claude_pid=
  fi
}

trap after_run EXIT
trap 'stop_claude HUP; exit 129' HUP
trap 'stop_claude INT; exit 130' INT
trap 'stop_claude TERM; exit 143' TERM

claude "$@" &
claude_pid=$!
wait "$claude_pid" || status=$?
claude_pid=
after_run
exit "$status"
