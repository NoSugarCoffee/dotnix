<div align="center">
  <img src="logo.png" alt="dotnix" width="512"/>

  [![nixpkgs](https://img.shields.io/badge/nixpkgs-25.11-5277C3?logo=nixos&logoColor=white)](https://github.com/NixOS/nixpkgs/tree/nixos-25.11)
  [![home-manager](https://img.shields.io/badge/home--manager-25.11-5277C3?logo=nixos&logoColor=white)](https://github.com/nix-community/home-manager/tree/release-25.11)
  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

  **Personal Home Manager dotfiles for Linux + macOS — reproducible, declarative, zero drift.**
</div>

---

## 📖 Overview

Keeping a home environment consistent across machines means scattered configs, manual installs,
and "works on my machine" drift. This flake declares the entire home environment as code —
packages, dotfiles, and tool configs all version-controlled in one place — so one command
applies a fully reproducible setup on any supported machine.

## 🖥️ Supported systems

- `x86_64-linux`
- `aarch64-darwin`
- `x86_64-darwin`

## 📦 Managed packages

| Package | Linux | macOS |
|---------|-------|-------|
| [codex](https://github.com/openai/codex) | yes | yes |
| [claude-code](https://github.com/anthropics/claude-code) | yes | yes |
| [asdf](https://asdf-vm.com/) | yes | yes |
| [git](https://git-scm.com/) | yes | yes |
| [browser-use](https://browser-use.com/) | yes | yes |
| [google-chrome](https://www.google.com/chrome/) | — | yes |
| [copyq](https://hluk.github.io/CopyQ/) | yes | — |

Codex config is written to `~/.codex/config.toml` (model `gpt-5-codex`, approval policy `on-request`).

`browser-use` is exposed as a normal command in your profile. During `home-manager switch`,
a pinned upstream installer script is executed automatically and idempotently to provision
`~/.browser-use-env` on first setup (or when the pinned installer hash changes).

### 🌐 Faster downloads from mainland China

`~/.config/nix/nix.conf` is written with `extra-substituters` pointing at the SJTU, TUNA, and
USTC mirrors of `cache.nixos.org` — all 1:1 mirrors of the official cache (same signing key), so
they're only ever an addition: `cache.nixos.org` stays as the automatic fallback for anything a
mirror doesn't have.

This only takes effect if your user is listed as a `trusted-user` in `/etc/nix/nix.conf` (the
Determinate Systems installer adds the installing user by default) — otherwise the Nix daemon
silently ignores user-supplied substituters and downloads still go straight to the official
cache. If switches still feel slow, check `trusted-users` in `/etc/nix/nix.conf`.

### 🧰 Go / Node / Python / Java via asdf

Rather than pinning these to whatever version nixpkgs currently ships, `home-manager switch`
installs `asdf` itself, then runs its own activation step
(`home.activation.asdfLanguages` in `home.nix`) that plugs in `golang`, `nodejs`, `python`, and
`java` (pinned to the [Temurin](https://adoptium.net/) build, since asdf-java's versions are
vendor-prefixed rather than plain semver) and sets each to whatever asdf resolves as latest.

This re-checks on every switch, so the active toolchain can move forward silently as upstream
releases land — that's the tradeoff for tracking "latest" instead of a version pinned in this
repo. Each install is best-effort: a network hiccup, or (on a bare Mac without Xcode Command
Line Tools) a failed Python source build, logs a warning instead of failing the whole switch.

To pin a specific project to an older version instead of whatever's currently global, add a
`.tool-versions` file in that project (standard asdf behavior, e.g. `python 3.11.9`) — asdf's
shims (already on `PATH` via `home.sessionPath`) pick it up automatically per-directory.

On a brand-new Mac, install Xcode Command Line Tools first (`xcode-select --install`) so the
Python build succeeds on first activation.

## 🚀 Quick start

```sh
just switch
```

First time (before `home-manager` is on your PATH), bootstrap with:

```sh
# Linux
nix run .#home-manager -- switch --flake .#liangliangdai

# macOS (pick your arch)
nix run .#home-manager -- switch --flake .#liangliangdai-aarch64-darwin
nix run .#home-manager -- switch --flake .#liangliangdai-x86_64-darwin
```

### 🍎 New Mac, zero Nix (or even git) installed

No local clone needed — Nix fetches flakes straight from GitHub via its own
tarball fetcher, `git` CLI not required. `scripts/bootstrap-macos.sh` chains
the two steps: installs Nix (via the
[Determinate Systems installer](https://install.determinate.systems/)) if
it's missing, then applies this flake's Home Manager configuration for your
Mac's architecture directly from `github:NoSugarCoffee/dotnix`.

```sh
curl -fsSL https://raw.githubusercontent.com/NoSugarCoffee/dotnix/main/scripts/bootstrap-macos.sh | bash
```

If Nix wasn't already installed, open a new terminal after the installer
finishes (so `PATH` picks up `nix`) and re-run the same command to apply the
configuration.

Equivalent manual command, if you'd rather not pipe a script into `bash`:

```sh
nix run github:NoSugarCoffee/dotnix#home-manager -- switch --flake github:NoSugarCoffee/dotnix#liangliangdai-aarch64-darwin
```

## 🔧 Commands

| Command | Description |
|---------|-------------|
| `just switch` | Apply the configuration |
| `just generations` | Show all Home Manager generations |
| `just build` | Build without switching |
| `just show` | Show flake outputs |
| `just update` | Update flake inputs |

## 🐚 Dev shell

`just` is available in a repo-local dev shell — no Home Manager needed:

```sh
nix develop
```

## 📄 License

MIT — see [LICENSE](LICENSE).
