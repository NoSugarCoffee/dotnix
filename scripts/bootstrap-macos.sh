#!/usr/bin/env bash
# One-shot bootstrap for a brand-new Mac: installs Nix if needed, then applies
# this flake's Home Manager configuration for the current architecture.
# No local clone or `git` CLI required — the flake is fetched straight from
# GitHub by Nix's own tarball fetcher.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/NoSugarCoffee/dotnix/main/scripts/bootstrap-macos.sh | bash
set -euo pipefail

flake_repo="github:NoSugarCoffee/dotnix"

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

flake_target="liangliangdai-${system}"

if ! command -v nix >/dev/null 2>&1; then
  echo "==> Nix not found, installing via the Determinate Systems installer..."
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
  cat <<EOF

Nix has been installed. Open a new terminal (so PATH picks up nix), then
re-run this to apply the Home Manager configuration:

  curl -fsSL https://raw.githubusercontent.com/NoSugarCoffee/dotnix/main/scripts/bootstrap-macos.sh | bash
EOF
  exit 0
fi

# home.nix's extra-substituters only take effect for a trusted Nix user
# (Determinate Nix's default trusted-users is just `root`). Determinate Nix
# specifically supports /etc/nix/nix.custom.conf for this kind of
# customization -- editing /etc/nix/nix.conf directly gets reverted, since
# Determinate's tooling manages that file itself. Idempotent: only appends
# if this user isn't already listed.
custom_conf="/etc/nix/nix.custom.conf"
current_user="$(id -un)"
if ! sudo grep -qsE "(^|[[:space:]])extra-trusted-users(.*[[:space:]])?${current_user}([[:space:]]|$)" "$custom_conf" 2>/dev/null; then
  echo "==> Adding ${current_user} to Nix's trusted-users (via ${custom_conf}) so extra-substituters take effect..."
  printf 'extra-trusted-users = %s\n' "$current_user" | sudo tee -a "$custom_conf" >/dev/null
  sudo pkill -x nix-daemon 2>/dev/null || true
else
  echo "==> ${current_user} is already a trusted Nix user."
fi

echo "==> Applying Home Manager configuration for ${flake_target} from ${flake_repo}..."
nix run "${flake_repo}#home-manager" -- switch --flake "${flake_repo}#${flake_target}"

echo "==> Done. Re-run this script (or 'nix run ${flake_repo}#home-manager -- switch --flake ${flake_repo}#${flake_target}') to pick up future updates."
