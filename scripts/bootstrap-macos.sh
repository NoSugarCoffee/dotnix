#!/usr/bin/env bash
# One-shot bootstrap for a brand-new Mac: installs Nix if needed, then applies
# this flake's Home Manager configuration for the current architecture.
#
# No local clone, no `git` CLI, and nothing to edit: the source is downloaded
# as a tarball with curl and the current account is injected into that
# throwaway copy, so $USER alone decides which homeConfiguration is applied.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/NoSugarCoffee/dotnix/main/scripts/bootstrap-macos.sh | bash
#   env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
#     curl -fsSL ... | env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
#     -u all_proxy -u ALL_PROXY DOTNIX_DIRECT=1 bash
set -euo pipefail

# Home Manager session vars (apps/clash-verge-rev) point curl at 127.0.0.1:7890.
# DOTNIX_DIRECT=1 is the Clash-down recovery path, so drop those before any fetch.
# Keep this list in sync with the README one-liner.
dotnix_direct_clear_shell_proxy() {
  if [[ "${DOTNIX_DIRECT:-}" == 1 ]]; then
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
  fi
}

# Prefer the copy next to this script so a local checkout of a PR is used
# even though the flake tarball still tracks `branch`.
# curl | bash leaves BASH_SOURCE unbound (set -u) or empty; never fall
# back to cwd, or a nix-daemon-proxy.sh there would get sourced.
# $1 = srcdir (downloaded tarball). $2 = this script's BASH_SOURCE (may be empty).
dotnix_resolve_proxy_script() {
  local srcdir="$1"
  local src="${2:-}"
  local here=""
  if [[ -n "$src" ]]; then
    here="$(cd "$(dirname "$src")" && pwd)"
  fi
  if [[ -n "$here" && -f "${here}/nix-daemon-proxy.sh" ]]; then
    printf '%s\n' "${here}/nix-daemon-proxy.sh"
  else
    printf '%s\n' "${srcdir}/scripts/nix-daemon-proxy.sh"
  fi
}

# Sourced by tests: helpers only. curl | bash has empty BASH_SOURCE, so do
# not treat a missing BASH_SOURCE as "sourced" or the one-liner would no-op.
if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "${0}" ]]; then
  return 0
fi

dotnix_direct_clear_shell_proxy

# This repo as GitHub `owner/name`, and the branch to fetch. A fork changes
# these two lines (and the Usage URL above); nothing else here is repo-specific.
repo="NoSugarCoffee/dotnix"
branch="main"

# `nix-command`/`flakes` are still gated behind experimental features, and
# whether they are enabled depends on config this script may not be able to
# read (e.g. a nix that isn't the Determinate install). Ask for them
# explicitly via `extra-experimental-features`, appended *after* any existing
# NIX_CONFIG: Nix config lines apply top to bottom, and a caller's own plain
# (non-"extra-") `experimental-features = nix-command` would otherwise come
# after ours and overwrite the whole setting, dropping flakes again.
export NIX_CONFIG="${NIX_CONFIG:+${NIX_CONFIG}$'\n'}extra-experimental-features = nix-command flakes"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: this script is for macOS only" >&2
  exit 1
fi

case "$(uname -m)" in
  arm64) system="aarch64-darwin" ;;
  x86_64) system="x86_64-darwin" ;;
  *)
    echo "error: unsupported architecture $(uname -m)" >&2
    exit 1
    ;;
esac

if ! command -v nix >/dev/null 2>&1; then
  echo "==> Nix not found, installing via the Determinate Systems installer..."
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
  cat <<EOF

Nix has been installed. Open a new terminal (so PATH picks up nix), then
re-run this to apply the Home Manager configuration:

  curl -fsSL https://raw.githubusercontent.com/${repo}/${branch}/scripts/bootstrap-macos.sh | bash
EOF
  exit 0
fi

daemon_label="systems.determinate.nix-daemon"
if [[ ! -e "/Library/LaunchDaemons/${daemon_label}.plist" ]]; then
  cat >&2 <<EOF
error: found nix at $(command -v nix), but not a Determinate Nix install
       (/Library/LaunchDaemons/${daemon_label}.plist is missing).
       This script configures the daemon through /etc/nix/nix.custom.conf, which
       only Determinate Nix reads. Uninstall the existing Nix (see
       https://nix.dev/manual/nix/latest/installation/uninstall), then re-run this.
EOF
  exit 1
fi

# Which account this machine manages is decided by $USER (and its real home
# directory, which is not always /Users/$USER -- a directory-service account
# can have a different one) alone, so a fresh machine never has to edit
# anything: download the source as a tarball and rewrite the `username`/
# `homeDirectory` lines in the private copy. A directory with no `.git` in it
# is a perfectly good flake source, which is how the clone and the git CLI are
# both avoided; the copy is deleted on exit, so nothing on disk goes stale.
workdir="$(mktemp -d)"
srcdir="${workdir}/dotnix"
trap 'rm -rf "${workdir}"' EXIT
mkdir -p "${srcdir}"
echo "==> Downloading ${repo}@${branch}..."
curl -fsSL "https://github.com/${repo}/archive/refs/heads/${branch}.tar.gz" |
  tar -xz -C "${srcdir}" --strip-components=1

# The downloaded copy already carries scripts/inject-account.sh, so this runs
# the very same rewrite CI exercises rather than a copy of it that could
# silently diverge.
bash "${srcdir}/scripts/inject-account.sh" "${srcdir}" "${USER}" "${HOME}"
flake_target="${USER}-${system}"

# Mirrors of cache.nixos.org that are much faster to reach from mainland
# China (1:1 mirrors, same signing key, so no extra-trusted-public-keys
# needed; extra-substituters only appends, cache.nixos.org stays as the
# fallback). This must be system-level daemon config so it takes effect for
# the very first switch's downloads -- per-user ~/.config/nix/nix.conf is
# both written too late (only after a switch completes) and ignored for
# non-trusted users. Determinate Nix supports /etc/nix/nix.custom.conf for
# exactly this kind of customization; editing /etc/nix/nix.conf directly
# gets reverted, since Determinate's tooling manages that file itself.
# Idempotent: only appends if not already present.
custom_conf="/etc/nix/nix.custom.conf"
mirrors="https://mirror.sjtu.edu.cn/nix-channels/store https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store"
restart_daemon=0
if ! sudo grep -qsF "$mirrors" "$custom_conf" 2>/dev/null; then
  echo "==> Adding mainland China binary cache mirrors to ${custom_conf}..."
  printf 'extra-substituters = %s\n' "$mirrors" | sudo tee -a "$custom_conf" >/dev/null
  restart_daemon=1
else
  echo "==> Binary cache mirrors already configured."
fi

# The Home Manager config manages per-user substituter *ordering* (mirrors
# before cache.nixos.org) via ~/.config/nix/nix.conf, which the daemon
# silently ignores unless the user is in trusted-users. The Determinate
# installer only adds that when asked at install time, so ensure it here.
# Idempotent: only appends if not already present.
if ! sudo grep -qsE "^(extra-)?trusted-users( )*=.*\b${USER}\b" "$custom_conf" 2>/dev/null; then
  echo "==> Adding ${USER} to extra-trusted-users in ${custom_conf}..."
  printf 'extra-trusted-users = %s\n' "$USER" | sudo tee -a "$custom_conf" >/dev/null
  restart_daemon=1
else
  echo "==> ${USER} already a trusted user."
fi

# Helpers live in nix-daemon-proxy.sh (sourced: no sudo / no network).
proxy_script=$(dotnix_resolve_proxy_script "$srcdir" "${BASH_SOURCE[0]:-}")
# Path is a variable (sibling checkout vs downloaded tarball).
# shellcheck disable=SC1090,SC1091
. "$proxy_script"

if [[ "$restart_daemon" == 1 ]]; then
  sudo launchctl kickstart -k "system/${daemon_label}"
fi

if ! dotnix_wait_for_nix_daemon; then
  dotnix_print_daemon_unreachable
  exit 1
fi

bootstrap_url="https://raw.githubusercontent.com/${repo}/${branch}/scripts/bootstrap-macos.sh"

# Clash Verge first, the rest only through it. Many uncached downloads (GitHub
# release assets, the Android SDK, Claude Code) time out from mainland China
# unless the daemon goes through the proxy -- but the proxy is itself one of
# those packages. So without a proxy listening, install just Clash Verge (the
# one download that must go direct, retryable on its own), open it, and stop;
# the re-run finds the proxy up, points the daemon at it, and switches.
#
# DOTNIX_DIRECT=1 skips that gate and the impure-env write. If a proxy-routing
# line is already in nix.custom.conf, the proxy script removes it and restarts
# the daemon so uncached fetches actually go direct. A machine that already
# has that line (and no DOTNIX_DIRECT) must not try to fetch Clash.
proxy_up=0
if ! dotnix_direct && bash "${proxy_script}" --check "${srcdir}"; then
  proxy_up=1
fi
hm_apps="${HOME}/Applications/Home Manager Apps"
plan=$(dotnix_bootstrap_proxy_plan "$custom_conf" "$hm_apps" "$proxy_up")

if [[ "$plan" == direct ]]; then
  bash "${proxy_script}" "${srcdir}"
elif [[ "$plan" == enable ]]; then
  bash "${proxy_script}" "${srcdir}"
elif [[ "$plan" == start-existing ]]; then
  clash_app=$(dotnix_find_clash_app "$hm_apps")
  open "$clash_app"
  cat <<EOF

The daemon already routes uncached downloads through the proxy, but nothing
is listening. Opened the Clash Verge in ~/Applications/Home Manager Apps.
Start a node, then re-run:

  curl -fsSL ${bootstrap_url} | bash

If you don't need a proxy, re-run with DOTNIX_DIRECT=1 instead:

  env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
    curl -fsSL ${bootstrap_url} \
    | env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY DOTNIX_DIRECT=1 bash
EOF
  exit 1
elif [[ "$plan" == tell-user ]]; then
  cat >&2 <<EOF
error: the daemon already routes uncached downloads through the proxy, but
       nothing is listening. Start the Clash Verge you already have
       (subscription imported, a node selected, mixed port matching
       lib/proxy.nix), then re-run:

  curl -fsSL ${bootstrap_url} | bash

       If you don't need a proxy, re-run with DOTNIX_DIRECT=1:

  env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
    curl -fsSL ${bootstrap_url} \
    | env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY DOTNIX_DIRECT=1 bash
EOF
  exit 1
elif [[ "$plan" == install-clash ]]; then
  echo "==> No proxy listening yet; installing Clash Verge on its own first..."
  clash=$(nix build --no-link --print-out-paths \
    "${srcdir}#homeConfigurations.${flake_target}.pkgs.clash-verge-rev-darwin")
  clash_app=$(dotnix_find_app_bundle "${clash}/Applications")
  if [[ -z "$clash_app" ]]; then
    echo "error: nix build produced no .app under ${clash}/Applications" >&2
    exit 1
  fi
  open "$clash_app"
  cat <<EOF

Clash Verge is open (run from the Nix store for now). Import a subscription,
select a node, and check the mixed port matches lib/proxy.nix, then re-run:

  curl -fsSL ${bootstrap_url} | bash

After that switch, quit this copy and use the one in
~/Applications/Home Manager Apps instead.
EOF
  exit 0
else
  echo "error: unknown proxy plan '${plan}'" >&2
  exit 1
fi

echo "==> Applying Home Manager configuration for ${flake_target} (account ${USER})..."
nix run "${srcdir}#home-manager" -- switch --flake "${srcdir}#${flake_target}"

echo "==> Done. Re-run this to pick up future updates:"
echo "    curl -fsSL ${bootstrap_url} | bash"
