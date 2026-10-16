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
# instead of trying a direct connection. Keep Clash Verge running.
#
# Usage:
#   nix-daemon-proxy.sh [<repo root>]          enable it (idempotent)
#   nix-daemon-proxy.sh --check [<repo root>]  exit 0 iff the proxy is listening
set -euo pipefail

check_only=0
if [[ "${1:-}" == "--check" ]]; then
  check_only=1
  shift
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
EOF
  exit 1
fi
[[ "$check_only" == 1 ]] && exit 0

daemon_label="systems.determinate.nix-daemon"
if [[ ! -e "/Library/LaunchDaemons/${daemon_label}.plist" ]]; then
  echo "error: not a Determinate Nix install on macOS; configure the daemon proxy by hand" >&2
  exit 1
fi

custom_conf="/etc/nix/nix.custom.conf"
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
  # Drop a stale value (e.g. lib/proxy.nix changed) rather than stacking a
  # second impure-env line after it.
  if [[ -e "$custom_conf" ]]; then
    sudo sed -i '' '/^impure-env[[:space:]]*=/d' "$custom_conf"
  fi
  printf '%s\n' "$env_line" | sudo tee -a "$custom_conf" >/dev/null
  changed=1
fi

if [[ "$changed" == 1 ]]; then
  sudo launchctl kickstart -k "system/${daemon_label}"
else
  echo "==> Daemon proxy already configured."
fi
