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
| [browser-use](https://browser-use.com/) | yes | yes |
| [copyq](https://hluk.github.io/CopyQ/) | yes | — |

Codex config is written to `~/.codex/config.toml` (model `gpt-5-codex`, approval policy `on-request`).

`browser-use` is exposed as a normal command in your profile. During `home-manager switch`,
a pinned upstream installer script is executed automatically and idempotently to provision
`~/.browser-use-env` on first setup (or when the pinned installer hash changes).

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
