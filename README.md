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
[apm](https://microsoft.github.io/apm/) (agent package manager; official prebuilt release, not in nixpkgs) &middot;
[agent-access](https://github.com/bitwarden/agent-access) (Bitwarden credential broker for agents; official prebuilt release, not in nixpkgs) &middot;
[bitwarden-cli](https://bitwarden.com/help/cli/) (vault backing agent-access) &middot;
[claude-desktop](https://claude.ai/download) &middot;
[ping-island](https://github.com/NoSugarCoffee/ping-island) `macOS` (personal fork with zellij support) &middot;
claude-session-registry (local: records live Claude Code conversations, replays them into zellij tabs and attaches each session in a kitty tab) &middot;
[ccstatusline](https://github.com/sirmalloc/ccstatusline) (Claude Code status line formatter; prebuilt npm release, not in nixpkgs) &middot;
[pi](https://pi.dev/) (minimal coding agent harness; prebuilt npm release, not in nixpkgs) &middot;
[pi-desktop](https://github.com/vastsa/PI-Desktop) `macOS` (local-first desktop workspace for coding agents; official prebuilt DMG, not in nixpkgs)

**Terminals & shells** &nbsp; [kitty](https://sw.kovidgoyal.net/kitty/) &middot;
[zellij](https://zellij.dev/) &middot;
[zoxide](https://github.com/ajeetdsouza/zoxide) &middot;
[yazi](https://github.com/sxyazi/yazi) (terminal file manager; `y` cds the shell to wherever you left it) &middot;
[nix-zsh-completions](https://github.com/nix-community/nix-zsh-completions)

**Editors & IDEs** &nbsp; [intellij-idea-ultimate](https://www.jetbrains.com/idea/) &middot;
[jetbrains-air](https://air.dev/) `macOS` &middot;
[cursor](https://cursor.com/) &middot;
[pulsar](https://pulsar-edit.dev/) `macOS`

**Version control** &nbsp; [git](https://git-scm.com/) &middot;
[gh](https://cli.github.com/) &middot;
[glab](https://gitlab.com/gitlab-org/cli)

**Containers** &nbsp; [docker](https://www.docker.com/) (client only) &middot;
[docker-compose](https://docs.docker.com/compose/) &middot;
[colima](https://github.com/abiosoft/colima) `macOS` (runs the Linux VM the daemon lives in — see Notes)

**Runtimes** &nbsp; [asdf](https://asdf-vm.com/) &middot;
go &middot; nodejs &middot;
[pnpm](https://pnpm.io/) &middot;
java (Temurin JDK & JRE) &middot; maven &middot;
[python3](https://www.python.org/) &middot;
[ipython](https://ipython.org/) &middot;
[pip](https://pip.pypa.io/)

**Browsers** &nbsp; [google-chrome](https://www.google.com/chrome/) `macOS` &middot;
[ego-lite](https://github.com/citrolabs/ego-lite) `macOS` (browser that shares your logged-in state with AI agents; provides the `ego-browser` automation CLI, official prebuilt DMG, not in nixpkgs)

**Launchers** &nbsp; [albert](https://albertlauncher.github.io/) `macOS`

**Clipboard** &nbsp; [maccy](https://maccy.app/) `macOS` &middot;
[copyq](https://hluk.github.io/CopyQ/) `Linux`

**Screenshots & recording** &nbsp; [macshot](https://github.com/sw33tLie/macshot) `macOS` &middot;
[obs-studio](https://obsproject.com/)

**Input** &nbsp; [scroll-reverser](https://pilotmoon.com/scrollreverser/) `macOS`

**Networking** &nbsp; [clash-verge-rev](https://www.clashverge.dev/)

**Utilities** &nbsp; [just](https://just.systems/) &middot;
[lark-cli](https://www.npmjs.com/package/@larksuite/cli) &middot;
translate-selection (local: translates the terminal selection via [translate-shell](https://github.com/soimort/translate-shell), bound to a kitty hotkey — see Notes)

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

- **zsh is managed** (`programs.zsh.enable`) so `home.sessionPath` (which puts `~/.asdf/shims` on `PATH`) reaches an interactive shell. Move any hand-written `~/.zshrc` aside before the first switch — home-manager refuses to overwrite it. Since the generated `~/.zshrc` is a store symlink and can't be edited, an untracked `~/.zshrc-local` is sourced last if it exists: put machine-specific or non-public shell config there rather than in this repo.
- **git config is deliberately unmanaged.** git is installed, but `~/.gitconfig` is hand-maintained. Identity has to switch per checkout (personal vs employer), and git expresses that only through `includeIf`, which takes a *path* — so a second machine-local file is unavoidable. Generating half the chain from the store while the other half stayed hand-written was worse than owning none of it, not least because a store symlink means a rebuild to fix a typo in an email address.
- **asdf owns Go / Node / Java / Maven**, each pinned to an explicit version in `home/home.nix` (best-effort — network hiccups warn, don't abort). Nothing tracks "latest": a switch with the pinned versions already installed makes no network calls, and moving a version is a one-line bump. asdf-java uses vendor-prefixed versions rather than plain semver. Per-project pinning via `.tool-versions`.
- **Python is from nixpkgs, not asdf**: asdf compiles CPython from source (needs Xcode CLT on macOS) and picks the experimental free-threaded variant as "latest".
- **Docker on macOS runs on colima, not Docker Desktop.** Only the `docker` client and `docker-compose` are installed; the daemon lives inside a Linux VM that colima boots through Apple's Virtualization framework, entirely in user space — no privileged helper, no `sudo`, nothing outside the nix store (standalone home-manager cannot install a system LaunchDaemon anyway). A `launchd` agent runs `colima start` at login and colima points `docker`'s default context at the VM's socket, so `docker` just works; check with `colima status`. Compose is installed both ways — as `docker-compose` and, via a `~/.docker/cli-plugins` symlink, as the `docker compose` subcommand (the docker client only looks for plugins there, never in the nix profile). The VM's size is colima's own state, not nix's — change it with `colima stop && colima start --cpu 4 --memory 8`. The first start downloads a VM image, so it is slow once; the agent inherits the Clash proxy env for that. On Linux the daemon is a *system* service and out of scope here (NixOS: `virtualisation.docker.enable`) — the client still works against a remote `DOCKER_HOST`.
- **Translate the selection** with `Cmd+Shift+T` (macOS) / `Ctrl+Shift+Alt+T` (Linux): the selected text is translated in a kitty overlay window, Chinese ↔ English with the direction auto-detected. Because zellij grabs the mouse there are two ways to select — `Shift`+drag makes the selection kitty's own, a plain drag makes it zellij's and copy-on-select puts it in the system clipboard; the hotkey reads whichever is present.
- **Mainland-China mirrors**: `scripts/bootstrap-macos.sh` writes SJTU/TUNA/USTC substituters to `/etc/nix/nix.custom.conf` and restarts the daemon before running the switch. `cache.nixos.org` stays as the fallback. Verify with `nix config show | grep substitut`.

## 📄 License

MIT — see [LICENSE](LICENSE).
