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
set -euo pipefail

# This repo as GitHub `owner/name`, and the branch to fetch. A fork changes
# these two lines (and the Usage URL above); nothing else here is repo-specific.
repo="NoSugarCoffee/dotnix"
branch="main"

# `nix-command`/`flakes` are still gated behind experimental features, and
# whether they are enabled depends on config this script may not be able to
# read (e.g. a nix that isn't the Determinate install). Ask for them explicitly
# so the script works regardless of the ambient nix.conf.
export NIX_CONFIG="extra-experimental-features = nix-command flakes${NIX_CONFIG:+$'\n'${NIX_CONFIG}}"

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

# Which account this machine manages is decided by $USER alone, so a fresh
# machine never has to edit anything: download the source as a tarball and
# rewrite the single `username` line in the private copy. A directory with no
# `.git` in it is a perfectly good flake source, which is how the clone and the
# git CLI are both avoided; the copy is deleted on exit, so nothing on disk
# goes stale.
workdir="$(mktemp -d)"
srcdir="${workdir}/dotnix"
trap 'rm -rf "${workdir}"' EXIT
mkdir -p "${srcdir}"
echo "==> Downloading ${repo}@${branch}..."
curl -fsSL "https://github.com/${repo}/archive/refs/heads/${branch}.tar.gz" |
  tar -xz -C "${srcdir}" --strip-components=1

# Deliberately not `sed -i`: its flags differ between BSD and GNU, and this
# form is identical on both. The rewrite is line-level, so flake.nix keeps
# `username` on one line, and a renamed or reformatted line fails loudly below
# rather than silently deploying the repo's default account instead of the
# local one.
sed -e "s|^ *username = .*;|      username = \"${USER}\";|" \
  "${srcdir}/flake.nix" > "${srcdir}/flake.nix.new"
mv "${srcdir}/flake.nix.new" "${srcdir}/flake.nix"
if ! grep -qF "username = \"${USER}\";" "${srcdir}/flake.nix"; then
  echo "error: could not set the account to '${USER}' in the downloaded flake.nix" >&2
  exit 1
fi
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

if [[ "$restart_daemon" == 1 ]]; then
  sudo pkill -x nix-daemon 2>/dev/null || true
fi

echo "==> Applying Home Manager configuration for ${flake_target} (account ${USER})..."
nix run "${srcdir}#home-manager" -- switch --flake "${srcdir}#${flake_target}"

echo "==> Done. Re-run this to pick up future updates:"
echo "    curl -fsSL https://raw.githubusercontent.com/${repo}/${branch}/scripts/bootstrap-macos.sh | bash"
