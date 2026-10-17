#!/usr/bin/env bash
# Routes the Nix daemon's own downloads through the local proxy declared in
# lib/proxy.nix (Clash Verge's mixed port).
#
# Packages no binary cache has -- unfree ones like the Android SDK, and the
# GitHub release assets nur-packages repacks when its cache misses -- are fetched by builders
# the daemon spawns, and those never see the shell's http(s)_proxy. From
# mainland China that means timeouts on dl.google.com, downloads.claude.ai and
# GitHub. `impure-env` hands the proxy to exactly those fetches; binary-cache
# downloads (the China mirrors) are made by the daemon itself and stay direct.
# Client-side `--option impure-env` is ignored by the daemon, so this has to
# live in the system-level /etc/nix/nix.custom.conf, hence sudo.
#
# Trade-off: once set, those fetches fail fast while the proxy is down
# instead of trying a direct connection. Keep Clash Verge running.
# DOTNIX_DIRECT=1 skips the write, and if a proxy-routing impure-env line
# is already there, removes it and restarts the daemon so uncached fetches
# go direct (no proxy, a TUN / system VPN, or Clash is down).
#
# Usage:
#   nix-daemon-proxy.sh [<repo root>]          enable it (idempotent)
#   nix-daemon-proxy.sh --check [<repo root>]  exit 0 iff the proxy is listening
#   DOTNIX_DIRECT=1 nix-daemon-proxy.sh        skip / clear the proxy routing
#
# Sourced (by bootstrap-macos.sh and tests): defines the helpers below and
# returns without touching the daemon or the network.
set -euo pipefail

: "${DOTNIX_NIX_DAEMON_LABEL:=systems.determinate.nix-daemon}"
: "${DOTNIX_NIX_CUSTOM_CONF:=/etc/nix/nix.custom.conf}"
: "${DOTNIX_NIX_DAEMON_PLIST:=/Library/LaunchDaemons/${DOTNIX_NIX_DAEMON_LABEL}.plist}"

dotnix_direct() {
  [[ "${DOTNIX_DIRECT:-}" == 1 ]]
}

# Proxy-routing only (https_proxy=). A user's `impure-env = FOO=bar` is not
# "configured". Matches extra-impure-env too (StringMap extra- appends).
# Missing file: 1. Unreadable file: 2 and a message (do not hide with grep -s).
dotnix_conf_has_proxy_impure_env() {
  local conf="${1:-$DOTNIX_NIX_CUSTOM_CONF}"
  local line
  [[ -e "$conf" ]] || return 1
  if [[ ! -r "$conf" ]]; then
    echo "error: cannot read ${conf}; it must be world-readable (0644)" >&2
    return 2
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    if [[ "$line" =~ ^[[:space:]]*(extra-)?impure-env[[:space:]]*=.*https_proxy= ]]; then
      return 0
    fi
  done <"$conf"
  return 1
}

dotnix_conf_has_impure_env() {
  dotnix_conf_has_proxy_impure_env "$@"
}

# noop: nothing to strip. clear: a proxy-routing impure-env line is present.
dotnix_direct_action() {
  local conf="${1:-$DOTNIX_NIX_CUSTOM_CONF}"
  local st=0
  dotnix_conf_has_proxy_impure_env "$conf" || st=$?
  if [[ "$st" -eq 0 ]]; then
    printf '%s\n' clear
    return 0
  fi
  if [[ "$st" -eq 1 ]]; then
    printf '%s\n' noop
    return 0
  fi
  return "$st"
}

# stdin -> stdout. A later plain `impure-env =` replaces the whole
# StringMap, so custom keys on an earlier line are lost unless we merge.
# extra-impure-env appends but does not override existing keys (std::map
# insert). Collect every (extra-)impure-env pair, drop the three proxy
# keys, then emit one impure-env line. $1 is clear or set; set takes
# proxy URL and no_proxy as $2 $3.
dotnix_apply_proxy_impure_env() {
  local mode="$1"
  local proxy_url="${2:-}"
  local no_proxy="${3:-}"
  local kept=()
  local line orig rest tok key toks
  while IFS= read -r line || [[ -n "$line" ]]; do
    orig="$line"
    line="${line%%#*}"
    if [[ "$line" =~ ^[[:space:]]*(extra-)?impure-env[[:space:]]*= ]]; then
      rest="${line#*=}"
      rest="${rest#"${rest%%[![:space:]]*}"}"
      toks=()
      set -f
      read -ra toks <<<"$rest"
      set +f
      # bash 3.2 + set -u: empty "${toks[@]}" is an unbound error.
      if ((${#toks[@]})); then
        for tok in "${toks[@]}"; do
          key="${tok%%=*}"
          case "$key" in
            http_proxy | https_proxy | no_proxy) ;;
            *) kept+=("$tok") ;;
          esac
        done
      fi
    else
      printf '%s\n' "$orig"
    fi
  done
  local merged=()
  if ((${#kept[@]})); then
    merged+=("${kept[@]}")
  fi
  if [[ "$mode" == set ]]; then
    merged+=("http_proxy=${proxy_url}" "https_proxy=${proxy_url}" "no_proxy=${no_proxy}")
  fi
  if ((${#merged[@]})); then
    printf 'impure-env = %s\n' "${merged[*]}"
  fi
}

# stdin -> $1, via a sibling temp so an interrupt cannot truncate dest.
# 0644: nix.custom.conf is world-readable (Determinate and this script read it).
dotnix_replace_file() {
  local dest="$1"
  local dir tmp
  dir=$(dirname -- "$dest")
  tmp=$(mktemp "${dir}/.dotnix.XXXXXX")
  # shellcheck disable=SC2064
  trap "rm -f -- $(printf '%q' "$tmp")" RETURN
  cat >"$tmp"
  chmod 0644 "$tmp"
  mv -f "$tmp" "$dest"
  trap - RETURN
}

# Same, as root, staging next to dest (mv is atomic on one filesystem).
# mktemp is 0600; install must reset mode/owner or the dest becomes root-only
# and every later non-sudo read fails.
dotnix_sudo_replace_file() {
  local dest="$1"
  local tmp stage
  tmp=$(mktemp)
  stage="${dest}.dotnix-new"
  # shellcheck disable=SC2064
  trap "rm -f -- $(printf '%q' "$tmp"); sudo rm -f -- $(printf '%q' "$stage")" RETURN
  cat >"$tmp"
  sudo install -m 0644 -o root -g wheel "$tmp" "$stage"
  sudo mv -f "$stage" "$dest"
  rm -f "$tmp"
  trap - RETURN
}

# Top-level "$dir"/*.app only. Darwin find accepts -maxdepth but not GNU
# -quit; a glob works on bash 3.2 without either.
dotnix_find_app_bundle() {
  local dir="$1"
  local app
  [[ -d "$dir" ]] || return 0
  for app in "$dir"/*.app; do
    [[ -d "$app" ]] || continue
    printf '%s\n' "$app"
    return 0
  done
}

dotnix_find_clash_app() {
  local dir="$1"
  local app base lower
  [[ -d "$dir" ]] || return 0
  for app in "$dir"/*.app; do
    [[ -d "$app" ]] || continue
    base="${app##*/}"
    lower=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')
    if [[ "$lower" == *clash*.app ]]; then
      printf '%s\n' "$app"
      return 0
    fi
  done
}

dotnix_wait_for_nix_daemon() {
  local attempts="${1:-20}"
  local delay="${2:-0.5}"
  local i
  for ((i = 1; i <= attempts; i++)); do
    if nix store info --store daemon >/dev/null 2>&1; then
      return 0
    fi
    sleep "$delay"
  done
  return 1
}

dotnix_print_daemon_unreachable() {
  cat >&2 <<EOF
error: the Nix daemon is not reachable. Restart it and re-run this:
       sudo launchctl kickstart -k system/${DOTNIX_NIX_DAEMON_LABEL}
       Its log is /var/log/determinate-nix-daemon.log.
EOF
}

# What bootstrap should do about the daemon proxy.
# $1 = nix.custom.conf, $2 = Home Manager Apps dir, $3 = 1 if the proxy is up.
# Prints one of: direct | enable | start-existing | tell-user | install-clash
dotnix_bootstrap_proxy_plan() {
  local conf="$1"
  local hm_apps="$2"
  local proxy_up="$3"
  if dotnix_direct; then
    printf '%s\n' direct
    return 0
  fi
  if [[ "$proxy_up" == 1 ]]; then
    printf '%s\n' enable
    return 0
  fi
  local st=0
  dotnix_conf_has_proxy_impure_env "$conf" || st=$?
  if [[ "$st" -eq 0 ]]; then
    if [[ -n "$(dotnix_find_clash_app "$hm_apps")" ]]; then
      printf '%s\n' start-existing
    else
      printf '%s\n' tell-user
    fi
    return 0
  fi
  [[ "$st" -eq 1 ]] || return "$st"
  printf '%s\n' install-clash
}

# Sourced by bootstrap / tests: helpers only.
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  return 0
fi

_dotnix_main_tmps=()
dotnix_cleanup_main_tmps() {
  local f
  if ((${#_dotnix_main_tmps[@]})); then
    for f in "${_dotnix_main_tmps[@]}"; do
      rm -f -- "$f"
    done
  fi
}
trap dotnix_cleanup_main_tmps EXIT

check_only=0
if [[ "${1:-}" == "--check" ]]; then
  check_only=1
  shift
fi

if [[ "$check_only" != 1 ]] && dotnix_direct; then
  # `[[ "$(cmd)" == noop ]]` discards cmd's status, so unreadability
  # (2) would fall through to the clear path and wipe dest from EOF.
  action=$(dotnix_direct_action) || exit $?
  if [[ "$action" == noop ]]; then
    echo "==> DOTNIX_DIRECT=1: no proxy impure-env; daemon downloads stay direct."
    exit 0
  fi
  if [[ ! -e "$DOTNIX_NIX_DAEMON_PLIST" ]]; then
    echo "error: not a Determinate Nix install on macOS; configure the daemon proxy by hand" >&2
    exit 1
  fi
  if ! sudo -v; then
    echo "error: sudo needs a password prompt; run this from a regular terminal" >&2
    exit 1
  fi
  echo "==> DOTNIX_DIRECT=1: removing the proxy impure-env from ${DOTNIX_NIX_CUSTOM_CONF}..."
  wanted=$(mktemp)
  _dotnix_main_tmps+=("$wanted")
  if [[ -e "$DOTNIX_NIX_CUSTOM_CONF" ]]; then
    dotnix_apply_proxy_impure_env clear <"$DOTNIX_NIX_CUSTOM_CONF" >"$wanted"
  fi
  dotnix_sudo_replace_file "$DOTNIX_NIX_CUSTOM_CONF" <"$wanted"
  sudo launchctl kickstart -k "system/${DOTNIX_NIX_DAEMON_LABEL}"
  if ! dotnix_wait_for_nix_daemon; then
    dotnix_print_daemon_unreachable
    exit 1
  fi
  echo "==> Uncached daemon downloads now go direct."
  exit 0
fi

# Enable (just nix-proxy) is macOS / Determinate only. Probe after that so
# Linux never hits macOS `nc -G` and reports a false "nothing is listening".
if [[ "$check_only" != 1 && ! -e "$DOTNIX_NIX_DAEMON_PLIST" ]]; then
  echo "error: not a Determinate Nix install on macOS; configure the daemon proxy by hand" >&2
  exit 1
fi

root=$(cd "${1:-$(dirname "$0")/..}" && pwd)

proxy_url=$(nix eval --raw --file "${root}/lib/proxy.nix" proxyUrl)
no_proxy=$(nix eval --raw --file "${root}/lib/proxy.nix" noProxy)
hostport=${proxy_url#*://}
hostport=${hostport%%/*}
host=${hostport%:*}
port=${hostport##*:}

if ! nc -z -G 2 "$host" "$port" >/dev/null 2>&1; then
  [[ "$check_only" == 1 ]] && exit 1
  cat >&2 <<EOF
error: nothing is listening on ${proxy_url}.
       Start Clash Verge (with a subscription imported) and re-run this;
       enabling the daemon proxy now would break every uncached download.
       Skip the proxy with DOTNIX_DIRECT=1 if you don't need one.
EOF
  exit 1
fi
[[ "$check_only" == 1 ]] && exit 0

custom_conf="$DOTNIX_NIX_CUSTOM_CONF"
features_line="extra-experimental-features = configurable-impure-env"

# Authenticate once up front: a sudo that can't prompt (no terminal) would
# otherwise fail half-way through. The file itself is world-readable, so
# the checks below need no sudo and can't mistake "unreadable" for "absent".
if ! sudo -v; then
  echo "error: sudo needs a password prompt; run this from a regular terminal" >&2
  exit 1
fi

wanted=$(mktemp)
_dotnix_main_tmps+=("$wanted")
if [[ -e "$custom_conf" ]]; then
  dotnix_apply_proxy_impure_env set "$proxy_url" "$no_proxy" <"$custom_conf" >"$wanted"
else
  dotnix_apply_proxy_impure_env set "$proxy_url" "$no_proxy" </dev/null >"$wanted"
fi
if ! grep -qsxF "$features_line" "$wanted"; then
  printf '%s\n' "$features_line" >>"$wanted"
fi

changed=0
if [[ ! -e "$custom_conf" ]] || ! cmp -s "$wanted" "$custom_conf"; then
  echo "==> Routing daemon downloads through ${proxy_url} in ${custom_conf}..."
  dotnix_sudo_replace_file "$custom_conf" <"$wanted"
  changed=1
fi

if [[ "$changed" == 1 ]]; then
  sudo launchctl kickstart -k "system/${DOTNIX_NIX_DAEMON_LABEL}"
  if ! dotnix_wait_for_nix_daemon; then
    dotnix_print_daemon_unreachable
    exit 1
  fi
else
  echo "==> Daemon proxy already configured."
fi
