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

# Python is built from source by the asdf step and needs a C toolchain;
# without CLT that build fails late with a confusing openssl error, so
# check up front. The switch itself continues fine either way (the python
# install is best-effort), so this only warns and triggers the installer.
if ! xcode-select -p >/dev/null 2>&1; then
  echo "==> Xcode Command Line Tools not found; requesting install (needed for the Python build)..."
  xcode-select --install || true
  echo "==> Continuing -- if the Python install fails below, re-run this script after the CLT install finishes."
fi

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
if ! sudo grep -qsF "$mirrors" "$custom_conf" 2>/dev/null; then
  echo "==> Adding mainland China binary cache mirrors to ${custom_conf}..."
  printf 'extra-substituters = %s\n' "$mirrors" | sudo tee -a "$custom_conf" >/dev/null
  sudo pkill -x nix-daemon 2>/dev/null || true
else
  echo "==> Binary cache mirrors already configured."
fi

echo "==> Applying Home Manager configuration for ${flake_target} from ${flake_repo}..."
nix run "${flake_repo}#home-manager" -- switch --flake "${flake_repo}#${flake_target}"

echo "==> Done. Re-run this script (or 'nix run ${flake_repo}#home-manager -- switch --flake ${flake_repo}#${flake_target}') to pick up future updates."
