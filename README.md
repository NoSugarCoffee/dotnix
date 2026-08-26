<div align="center">
  <img src="logo.png" alt="dotnix" width="512"/>

  [![nixpkgs](https://img.shields.io/badge/nixpkgs-26.05-5277C3?logo=nixos&logoColor=white)](https://github.com/NixOS/nixpkgs/tree/nixos-26.05)
  [![home-manager](https://img.shields.io/badge/home--manager-26.05-5277C3?logo=nixos&logoColor=white)](https://github.com/nix-community/home-manager/tree/release-26.05)
  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

  **Personal Home Manager dotfiles for Linux + macOS — reproducible, declarative, zero drift.**
</div>

---

## 📦 Managed packages

Cross-platform unless noted. Codex config is written to `~/.codex/config.toml`
(model `gpt-5-codex`, approval policy `on-request`).

**AI tooling** &nbsp; [codex](https://github.com/openai/codex) &middot;
[claude-code](https://github.com/anthropics/claude-code) &middot;
[claude-desktop](https://claude.ai/download)

**Shells & terminals** &nbsp; [kitty](https://sw.kovidgoyal.net/kitty/) &middot;
[zellij](https://zellij.dev/) &middot;
[zoxide](https://github.com/ajeetdsouza/zoxide) &middot;
[nix-zsh-completions](https://github.com/nix-community/nix-zsh-completions)

**Version control** &nbsp; [git](https://git-scm.com/) &middot;
[gh](https://cli.github.com/) &middot;
[glab](https://gitlab.com/gitlab-org/cli)

**Runtimes via asdf** &nbsp; go &middot; nodejs &middot; java (Temurin JDK & JRE) &middot; maven

**Other** &nbsp; [asdf](https://asdf-vm.com/) &middot;
[just](https://just.systems/) &middot;
[python3](https://www.python.org/) &middot;
[ipython](https://ipython.org/) &middot;
[lark-cli](https://www.npmjs.com/package/@larksuite/cli) &middot;
[intellij-idea-ultimate](https://www.jetbrains.com/idea/) &middot;
[clash-verge-rev](https://www.clashverge.dev/)

**macOS only** &nbsp; [google-chrome](https://www.google.com/chrome/) &middot;
[maccy](https://maccy.app/) &middot;
[macshot](https://github.com/sw33tLie/macshot) &middot;
[pulsar](https://pulsar-edit.dev/) &middot;
[albert](https://albertlauncher.github.io/) &middot;
[scroll-reverser](https://pilotmoon.com/scrollreverser/)

**Linux only** &nbsp; [copyq](https://hluk.github.io/CopyQ/)

## 🚀 Quick start

```sh
just switch
```

First time on a machine — bootstrap without an existing `home-manager`:

```sh
# Linux
nix run .#home-manager -- switch --flake .#liangliangdai

# macOS
nix run .#home-manager -- switch --flake .#liangliangdai-aarch64-darwin
```

### 🍎 New Mac, zero Nix installed

One-liner that installs Nix (via the [Determinate installer](https://install.determinate.systems/)) if missing and applies this flake — no local clone or `git` needed:

```sh
curl -fsSL https://raw.githubusercontent.com/NoSugarCoffee/dotnix/main/scripts/bootstrap-macos.sh | bash
```

If Nix wasn't installed yet, open a new terminal after the installer finishes and re-run.

## 🔧 Commands

| Command | Description |
|---------|-------------|
| `just switch` | Apply the configuration |
| `just build` | Build without switching |
| `just generations` | Show Home Manager generations |
| `just update` | Update flake inputs |
| `just show` | Show flake outputs |

## 📝 Notes

- **zsh is managed** (`programs.zsh.enable`) so `home.sessionPath` (which puts `~/.asdf/shims` on `PATH`) reaches an interactive shell. Move any hand-written `~/.zshrc` aside before the first switch — home-manager refuses to overwrite it.
- **asdf owns Go / Node / Java / Maven**, tracking latest on every switch (best-effort — network hiccups warn, don't abort). Java is pinned to a specific Temurin build; asdf-java uses vendor-prefixed versions rather than plain semver. Per-project pinning via `.tool-versions`.
- **Python is from nixpkgs, not asdf**: asdf compiles CPython from source (needs Xcode CLT on macOS) and picks the experimental free-threaded variant as "latest".
- **Mainland-China mirrors**: `scripts/bootstrap-macos.sh` writes SJTU/TUNA/USTC substituters to `/etc/nix/nix.custom.conf` and restarts the daemon before running the switch. `cache.nixos.org` stays as the fallback. Verify with `nix config show | grep substitut`.

## 🐚 Dev shell

`just` is available without Home Manager:

```sh
nix develop
```

## 📄 License

MIT — see [LICENSE](LICENSE).
