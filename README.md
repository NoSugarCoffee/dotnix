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

Cross-platform unless tagged. Codex config is written to `~/.codex/config.toml`
(model `gpt-5-codex`, approval policy `on-request`).

**AI tooling** &nbsp; [codex](https://github.com/openai/codex) &middot;
[claude-code](https://github.com/anthropics/claude-code) &middot;
[claude-desktop](https://claude.ai/download) &middot;
[ping-island](https://github.com/NoSugarCoffee/ping-island) `macOS` (personal fork with zellij support)

**Terminals & shells** &nbsp; [kitty](https://sw.kovidgoyal.net/kitty/) &middot;
[zellij](https://zellij.dev/) &middot;
[zoxide](https://github.com/ajeetdsouza/zoxide) &middot;
[nix-zsh-completions](https://github.com/nix-community/nix-zsh-completions)

**Editors & IDEs** &nbsp; [intellij-idea-ultimate](https://www.jetbrains.com/idea/) &middot;
[pulsar](https://pulsar-edit.dev/) `macOS`

**Version control** &nbsp; [git](https://git-scm.com/) &middot;
[gh](https://cli.github.com/) &middot;
[glab](https://gitlab.com/gitlab-org/cli)

**Runtimes** &nbsp; [asdf](https://asdf-vm.com/) &middot;
go &middot; nodejs &middot; java (Temurin JDK & JRE) &middot; maven &middot;
[python3](https://www.python.org/) &middot;
[ipython](https://ipython.org/)

**Browsers** &nbsp; [google-chrome](https://www.google.com/chrome/) `macOS`

**Launchers** &nbsp; [albert](https://albertlauncher.github.io/) `macOS`

**Clipboard** &nbsp; [maccy](https://maccy.app/) `macOS` &middot;
[copyq](https://hluk.github.io/CopyQ/) `Linux`

**Screenshots** &nbsp; [macshot](https://github.com/sw33tLie/macshot) `macOS`

**Input** &nbsp; [scroll-reverser](https://pilotmoon.com/scrollreverser/) `macOS`

**Networking** &nbsp; [clash-verge-rev](https://www.clashverge.dev/)

**Utilities** &nbsp; [just](https://just.systems/) &middot;
[lark-cli](https://www.npmjs.com/package/@larksuite/cli)

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
repo and change just that string, then update the git identity in
`home/home.nix` (`programs.git.settings.user.name` / `.email`) — that's
the whole rebranding step.

## 📝 Notes

- **zsh is managed** (`programs.zsh.enable`) so `home.sessionPath` (which puts `~/.asdf/shims` on `PATH`) reaches an interactive shell. Move any hand-written `~/.zshrc` aside before the first switch — home-manager refuses to overwrite it.
- **asdf owns Go / Node / Java / Maven**, tracking latest on every switch (best-effort — network hiccups warn, don't abort). Java is pinned to a specific Temurin build; asdf-java uses vendor-prefixed versions rather than plain semver. Per-project pinning via `.tool-versions`.
- **Python is from nixpkgs, not asdf**: asdf compiles CPython from source (needs Xcode CLT on macOS) and picks the experimental free-threaded variant as "latest".
- **Mainland-China mirrors**: `scripts/bootstrap-macos.sh` writes SJTU/TUNA/USTC substituters to `/etc/nix/nix.custom.conf` and restarts the daemon before running the switch. `cache.nixos.org` stays as the fallback. Verify with `nix config show | grep substitut`.

## 📄 License

MIT — see [LICENSE](LICENSE).
