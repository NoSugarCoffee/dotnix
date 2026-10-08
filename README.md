<div align="center">
  <img src="logo.png" alt="dotnix" width="512"/>

  [![nixpkgs](https://img.shields.io/badge/nixpkgs-26.05-5277C3?logo=nixos&logoColor=white)](https://github.com/NixOS/nixpkgs/tree/nixos-26.05)
  [![home-manager](https://img.shields.io/badge/home--manager-26.05-5277C3?logo=nixos&logoColor=white)](https://github.com/nix-community/home-manager/tree/release-26.05)
  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

  **Personal Home Manager dotfiles for Linux + macOS — reproducible, declarative, zero drift.**
</div>

---

## 📖 Overview

Keeping a home environment consistent across machines usually means scattered configs, manual
installs, and "works on my machine" drift. This flake declares the entire home environment as
code — packages, dotfiles, and tool configs all version-controlled in one place — so one
command applies a fully reproducible setup on any supported machine.

## 🚀 Quick start

**New machine, no Nix installed** — one-liner that installs Nix (via the
[Determinate installer](https://install.determinate.systems/)) if missing and applies this flake.
No local clone or `git` needed:

```sh
curl -fsSL https://raw.githubusercontent.com/NoSugarCoffee/dotnix/main/scripts/bootstrap-macos.sh | bash
```

If Nix wasn't installed yet, open a new terminal after the installer finishes and re-run.

**Already have Nix, no home-manager yet** — bootstrap the first switch:

```sh
# Linux
nix run .#home-manager -- switch --flake .#liangliangdai

# macOS
nix run .#home-manager -- switch --flake .#liangliangdai-aarch64-darwin
```

**Day to day** — once `just` is on PATH:

```sh
just switch
```

## 📦 Managed packages

Cross-platform unless tagged.

**AI tooling** &nbsp; [codex](https://github.com/openai/codex) &middot;
[claude-code](https://github.com/anthropics/claude-code) &middot;
[ChatGPT](https://learn.chatgpt.com/docs/app) `macOS` &middot;
[claude-desktop](https://claude.ai/download) &middot;
[pi](https://pi.dev/) &middot;
[apm](https://microsoft.github.io/apm/) &middot;
[ccstatusline](https://github.com/sirmalloc/ccstatusline) &middot;
[paperclip](https://paperclip.ing) &middot;
[orca](https://github.com/stablyai/orca) &middot;
[agent-access](https://github.com/bitwarden/agent-access) &middot;
[bitwarden-cli](https://bitwarden.com/help/cli/) &middot;
claude-session-registry (local; reopens Claude Code sessions in zellij)

**Terminal** &nbsp; [kitty](https://sw.kovidgoyal.net/kitty/) &middot;
[zellij](https://zellij.dev/) &middot;
[zoxide](https://github.com/ajeetdsouza/zoxide) &middot;
[yazi](https://github.com/sxyazi/yazi) &middot;
[nix-zsh-completions](https://github.com/nix-community/nix-zsh-completions)

**Editors** &nbsp; [intellij-idea-ultimate](https://www.jetbrains.com/idea/) &middot;
[cursor](https://cursor.com/) &middot;
[jetbrains-air](https://air.dev/) `macOS` &middot;
[pulsar](https://pulsar-edit.dev/) `macOS`

**Dev** &nbsp; [git](https://git-scm.com/) &middot;
[git-open](https://github.com/paulirish/git-open) &middot;
[gh](https://cli.github.com/) &middot;
[glab](https://gitlab.com/gitlab-org/cli) &middot;
[docker](https://www.docker.com/) (client) &middot;
[docker-compose](https://docs.docker.com/compose/) &middot;
[colima](https://github.com/abiosoft/colima) `macOS` &middot;
[asdf](https://asdf-vm.com/) (go, nodejs, java, maven) &middot;
[pnpm](https://pnpm.io/) &middot;
[python3](https://www.python.org/) (ipython, pip) &middot;
[just](https://just.systems/) &middot;
[lark-cli](https://www.npmjs.com/package/@larksuite/cli)

**Desktop** &nbsp; [google-chrome](https://www.google.com/chrome/) `macOS` &middot;
[ego-lite](https://github.com/citrolabs/ego-lite) `macOS` &middot;
[albert](https://albertlauncher.github.io/) `macOS` &middot;
[maccy](https://maccy.app/) `macOS` &middot;
[copyq](https://hluk.github.io/CopyQ/) `Linux` &middot;
[macshot](https://github.com/sw33tLie/macshot) `macOS` &middot;
[obs-studio](https://obsproject.com/) &middot;
[scroll-reverser](https://pilotmoon.com/scrollreverser/) `macOS` &middot;
[clash-verge-rev](https://www.clashverge.dev/) &middot;
[cida](https://github.com/Xuanwo/cida) `macOS`

## 🔧 Commands

| Command | Description |
|---------|-------------|
| `just switch` | Apply the configuration |
| `just build` | Build without switching |
| `just generations` | Show Home Manager generations |
| `just update` | Update flake inputs |
| `just show` | Show flake outputs |

## 🍴 Fork

The username is a single source of truth in `flake.nix`:

```nix
let
  username = "liangliangdai";
```

Everything else (`homeConfigurations` attribute names, `home.username`,
`homeDirectory`, CI `USERNAME`, the bootstrap script's flake target)
reads from there directly or via `nix eval --raw .#username`. Fork the
repo and change just that string — that's the whole rebranding step.

## 📝 Notes

- **zsh is managed.** Move an existing `~/.zshrc` aside before the first switch; machine-local config goes in an untracked `~/.zshrc-local`.
- **git config is not.** Per-checkout identity needs `includeIf` paths, so `~/.gitconfig` is hand-written.
- **Codex and Claude Code settings stay writable.** A switch seeds them if missing and resets only the keys declared under `home/codex/` and in `home/claude/settings.nix`.
- **asdf pins Go / Node / Java / Maven** to explicit versions in `home/home.nix`. Python comes from nixpkgs instead, since asdf compiles it from source.
- **Docker on macOS is colima.** A launchd agent starts the VM at login; resize it with `colima stop && colima start --cpu 4 --memory 8`. On Linux the daemon is a system service, out of scope here.
- **China mirrors.** `scripts/bootstrap-macos.sh` adds SJTU/TUNA/USTC substituters; check with `nix config show | grep substitut`.

## 📄 License

MIT — see [LICENSE](LICENSE).
