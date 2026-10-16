#!/usr/bin/env bash
# Routes the Nix daemon's own downloads through the local proxy declared in
# lib/proxy.nix (Clash Verge's mixed port).
#
# Packages no binary cache has -- unfree ones like the Android SDK, and the
# GitHub release assets apps/*/pin.json point at -- are fetched by builders
# the daemon spawns, and those never see the shell's http(s)_proxy. From
# mainland China that means timeouts on dl.google.com, downloads.claude.ai and
# GitHub. `impure-env` hands the proxy to exactly those fetches; binary-cache
# downloads (the China mirrors) are made by the daemon itself and stay direct.
# Client-side `--option impure-env` is ignored by the daemon, so this has to
# live in the system-level /etc/nix/nix.custom.conf, hence sudo.
#
# Trade-off: once set, those fetches fail fast while the proxy is down
# instead of trying a direct connection. Keep Clash Verge running. Skip the
# write entirely with DOTNIX_DIRECT=1 (no proxy, or a TUN / different port).
#
# Usage:
#   nix-daemon-proxy.sh [<repo root>]          enable it (idempotent)
#   nix-daemon-proxy.sh --check [<repo root>]  exit 0 iff the proxy is listening
#   DOTNIX_DIRECT=1 nix-daemon-proxy.sh        no-op (leave nix.custom.conf)
#
# Sourced (by bootstrap-macos.sh and tests): defines the helpers below and
# returns without touching the daemon or the network.
set -euo pipefail

DOTNIX_NIX_DAEMON_LABEL="systems.determinate.nix-daemon"
DOTNIX_NIX_CUSTOM_CONF="/etc/nix/nix.custom.conf"

dotnix_direct() {
  [[ "${DOTNIX_DIRECT:-}" == 1 ]]
}

dotnix_conf_has_impure_env() {
  local conf="${1:-$DOTNIX_NIX_CUSTOM_CONF}"
  [[ -e "$conf" ]] && grep -qsE '^impure-env[[:space:]]*=' "$conf"
}

# Drop only a proxy-routing impure-env line (so a user's other impure-env
# stays). stdin -> stdout; callers write the result back.
dotnix_strip_proxy_impure_env() {
  sed '/^impure-env[[:space:]]*=.*https_proxy=/d'
}

dotnix_find_app_bundle() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  find "$dir" -maxdepth 1 -name "*.app" -print -quit
}

dotnix_find_clash_app() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  find "$dir" -maxdepth 1 -iname '*clash*.app' -print -quit
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
  if dotnix_conf_has_impure_env "$conf"; then
    if [[ -n "$(dotnix_find_clash_app "$hm_apps")" ]]; then
      printf '%s\n' start-existing
    else
      printf '%s\n' tell-user
    fi
    return 0
  fi
  printf '%s\n' install-clash
}

# Sourced by bootstrap / tests: helpers only.
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  return 0
fi

check_only=0
if [[ "${1:-}" == "--check" ]]; then
  check_only=1
  shift
fi

if [[ "$check_only" != 1 ]] && dotnix_direct; then
  echo "==> DOTNIX_DIRECT=1: not writing impure-env; daemon downloads stay direct."
  exit 0
fi

# Enable (just nix-proxy) is macOS / Determinate only. Probe after that so
# Linux never hits macOS `nc -G` and reports a false "nothing is listening".
if [[ "$check_only" != 1 && ! -e "/Library/LaunchDaemons/${DOTNIX_NIX_DAEMON_LABEL}.plist" ]]; then
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
env_line="impure-env = http_proxy=${proxy_url} https_proxy=${proxy_url} no_proxy=${no_proxy}"

# Authenticate once up front: a sudo that can't prompt (no terminal) would
# otherwise fail half-way through. The file itself is world-readable, so
# the checks below need no sudo and can't mistake "unreadable" for "absent".
if ! sudo -v; then
  echo "error: sudo needs a password prompt; run this from a regular terminal" >&2
  exit 1
fi

changed=0
if ! grep -qsxF "$features_line" "$custom_conf"; then
  echo "==> Enabling configurable-impure-env in ${custom_conf}..."
  printf '%s\n' "$features_line" | sudo tee -a "$custom_conf" >/dev/null
  changed=1
fi
if ! grep -qsxF "$env_line" "$custom_conf"; then
  echo "==> Routing daemon downloads through ${proxy_url} in ${custom_conf}..."
  # Replace a stale proxy-routing line (lib/proxy.nix changed). Leave any
  # other impure-env the user added.
  if [[ -e "$custom_conf" ]]; then
    stripped=$(dotnix_strip_proxy_impure_env <"$custom_conf")
    printf '%s\n' "$stripped" | sudo tee "$custom_conf" >/dev/null
  fi
  printf '%s\n' "$env_line" | sudo tee -a "$custom_conf" >/dev/null
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
