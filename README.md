<div align="center">
  <img src="logo.png" alt="dotnix" width="512"/>

  [![nixpkgs](https://img.shields.io/badge/nixpkgs-25.11-5277C3?logo=nixos&logoColor=white)](https://github.com/NixOS/nixpkgs/tree/nixos-25.11)
  [![home-manager](https://img.shields.io/badge/home--manager-25.11-5277C3?logo=nixos&logoColor=white)](https://github.com/nix-community/home-manager/tree/release-25.11)
  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

  **❄️ Personal Home Manager dotfiles for Linux + macOS — reproducible, declarative, zero drift 🏠**
</div>

---

## Overview

**The Pain:** Keeping your home environment consistent across machines means scattered configs, manual installs, and "works on my machine" drift.

**The Solution:** A Home Manager flake that declares your entire home environment as code — packages, dotfiles, and tool configs all version-controlled in one place.

**The Result:** One command to apply a fully reproducible home setup on Linux and macOS.

## 🖥️ Supported systems

- `x86_64-linux`
- `aarch64-darwin`
- `x86_64-darwin`

`copyq` is enabled on Linux only. `codex` is enabled on all configured systems.

## 📦 What's included

- **`flake.nix`** — defines Home Manager outputs under `homeConfigurations`
- **`home/<user>/home.nix`** — per-user package list and dotfile configuration
- **`justfile`** — `switch`, `build`, `show`, and `update` shortcuts

### Currently managed: Codex CLI and CopyQ

`home/liangliangdai/home.nix` installs `pkgs.codex` and `pkgs.copyq`, and writes `~/.codex/config.toml`:

| Setting | Value |
|---------|-------|
| `model` | `gpt-5-codex` |
| `approval_policy` | `on-request` |
| `sandbox_mode` | `workspace-write` |
| `file_opener` | `cursor` |
| `history.persistence` | `save-all` |

## 🚀 Quick Start

**First run** (or when `home-manager` is not yet installed):

```sh
nix run .#home-manager -- switch --flake .#liangliangdai
```

For Darwin targets, use:

```sh
nix run .#home-manager -- switch --flake .#liangliangdai-aarch64-darwin
```

or

```sh
nix run .#home-manager -- switch --flake .#liangliangdai-x86_64-darwin
```

**Subsequent runs** (after activation enables the `home-manager` command):

```sh
home-manager switch --flake .#liangliangdai
```

For Darwin targets, use the same command with the matching target name.

**Or with `just`:**

```sh
just switch
```

## 🔧 Commands

| Command | Description |
|---------|-------------|
| `just switch` | Apply the configuration |
| `just build` | Build the activation package without switching |
| `just show` | Show flake outputs |
| `just update` | Update flake inputs |

**Build without switching:**

```sh
nix build .#homeConfigurations.liangliangdai.activationPackage
```

For Darwin targets, build `homeConfigurations.liangliangdai-aarch64-darwin.activationPackage` or `homeConfigurations.liangliangdai-x86_64-darwin.activationPackage`.

## 📄 License

MIT — see [LICENSE](LICENSE).
