# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A standalone Home Manager flake that declares one user's environment (`liangliangdai`) across `x86_64-linux`, `aarch64-darwin`, `x86_64-darwin`. There is no NixOS module and no nix-darwin: `home-manager switch` alone owns everything under `~`. This is a **public** repo — no work-internal hostnames, tokens, or identities belong in it.

## Common commands

```sh
just switch         # apply the configuration for the current platform
just build          # build the activation package without switching
just generations    # list Home Manager generations
just update         # bump flake inputs
nix develop         # dev shell with just on PATH
```

Direct build (what CI runs, and what to use when scripting a check):

```sh
nix build ".#homeConfigurations.liangliangdai-aarch64-darwin.activationPackage" --no-link --print-out-paths
```

Then `<path>/activate` runs the activation scripts. The build proves the derivation evaluates and fetches; only running `activate` exercises the activation blocks in `home.nix`.

There are no unit tests. CI (`.github/workflows/ci.yml`) is the test surface: `nix flake check` + build on Linux, and on macOS it additionally runs `activate` against a throwaway `/Users/liangliangdai` and smoke-tests that `codex`, `browser-use`, `Google Chrome.app`, and the asdf shims (`npm`, `lark-cli`) are resolvable through an **interactive** `/bin/zsh -i -c ...`. If a change might affect shell PATH, mirror that interactive-zsh check locally — a non-interactive shell will lie about it.

## Constraints on the working shell

- **New files must be `git add`ed before `nix build`** — the flake source is the git tree, so untracked `pkgs/*/default.nix` or added modules are invisible until staged.
- **`sudo` is non-interactive-hostile here.** Anything that needs it (bootstrap, activation on a fresh Mac) must be run by the user with `! sudo …` in the Claude Code prompt; don't try to script it.
- **`home-manager switch` needs macOS "App Management" permission** for the terminal it runs in, which the assistant's shell lacks. When the user needs to activate, ask them to run `! just switch` themselves.
- **First switch on a machine with a hand-written `~/.zshrc`** fails: move it aside (`mv ~/.zshrc ~/.zshrc.backup`) and fold anything worth keeping into `programs.zsh.initContent`.

## Architecture

### Flake shape (`flake.nix`)

- `mkPkgs system` produces the pkgset with `config.allowUnfree = true` and the repo-local `localPackagesOverlay` applied.
- `localPackagesOverlay` adds macOS-only DMG-repack derivations (`clash-verge-rev-darwin`, `claude-desktop-darwin`, `pulsar-darwin`, `albert-darwin`), exposes `macshot` from unstable, and patches nixpkgs' `scroll-reverser` to delete AppleDouble sidecars that break Gatekeeper's Developer ID seal.
- `nixpkgs` is pinned to stable `nixos-25.11`. `nixpkgs-unstable` is a second input used only where stable is too old (currently `macshot` and `albert-darwin`, whose upstream source layout moved past what stable's package expects).
- `mkBrowserUsePackage` wraps `pkgs/browser-use/` (a `pyproject.toml` + lockfile) into a nix-built venv via `uv2nix` + `pyproject.nix` and exposes it as a normal binary. To bump `browser-use`, update `pkgs/browser-use/uv.lock` — don't chase the version elsewhere.
- `homeConfigurations` exposes four attrs; `liangliangdai` is the linux alias, and `just switch` picks the right one via `arch()`/`os()` in the `justfile`.

### home.nix conventions (`home/liangliangdai/home.nix`)

- Packages are conditional per-platform via `lib.optionals pkgs.stdenv.isDarwin` / `isLinux`. Adding a package means editing the correct list, not the union — check where similar packages live.
- **`home.activation.*` blocks are where the imperative work happens.** Ordering matters:
  - `asdfLanguages` runs after `linkGeneration` on purpose — slow downloads must not block `~/.config/**` symlinks from being created.
  - `claudeCodeSettings` merges a managed JSON subset into `~/.claude/settings.json` with `jq -s '.[0] * .[1]'` rather than symlinking, because Claude Code writes back to that file (`/config`, plugin toggles) and a read-only store symlink would break it.
  - `disableCmdQ` writes `NSUserKeyEquivalents` via `defaults write -g -dict-add` to preserve any other entries.
- **`launchd.agents.*`** blocks (Darwin only) start GUI apps at login by pointing `ProgramArguments` at the app's `Contents/MacOS/<Name>` binary inside the nix store path (see `albert`, `scroll-reverser`). If an app requires "run at login", prefer this over the app's own auto-launch checkbox — the checkbox writes to a per-user plist nix can't own.
- The **`asdf` step** is best-effort: a plugin install failure logs a warning, not an error. Go/Node track "latest" (silent forward drift by design); Java is pinned to specific Temurin builds because the JVM ecosystem breaks on major-version drift and asdf-java uses vendor-prefixed version strings, not semver.
- **Mainland-China networking** is baked in: `nix.settings.substituters` puts SJTU/TUNA/USTC mirrors ahead of `cache.nixos.org` at the user level, but the daemon **silently ignores** user-level substituters unless the user is in `trusted-users`. `scripts/bootstrap-macos.sh` ensures that. Direct GitHub tarball fetches (new flake inputs) go around substituters entirely and often stall — set `https_proxy`/`http_proxy`/`all_proxy` to `http://127.0.0.1:7890` for those specific `nix` commands.

### DMG-repack pattern (`pkgs/*-darwin/`)

macOS GUI apps not in nixpkgs are repackaged from the official DMG using `undmg` + `dontFixup = true` (nix's fixup phase corrupts Mach-O signatures). Two recurring failure modes when something goes wrong:

- **"App is damaged"** — extra `._Foo` AppleDouble sidecars inside the `.app` bundle break Gatekeeper's Developer ID seal. Fix by `find … -name '._*' -delete` in `postFixup` (see how `scroll-reverser` is patched in `flake.nix`).
- **`SIGKILL (Code Signature Invalid)`** — the extraction broke the Mach-O signature (typical for ad-hoc / linker-signed apps like CopyQ). Fix by re-signing with `/usr/bin/codesign --force --deep --sign -` in `installPhase`. Must be `/usr/bin/codesign`, not a nix-provided one — the Apple-shipped binary is required and isn't in the sandbox.
- Diagnose which mode you're in with `codesign -vv <app>` before "fixing" — the wrong fix throws away the app's real notarization.
- Claude Desktop's upstream URL is unversioned ("latest") — a hash mismatch on rebuild means upstream released; bump `version` **and** `sha256` in the same edit.

### Zellij + kitty keys

- Kitty is the terminal because Terminal.app translates Option+arrows into `Esc f`/`Esc b` that collide with zellij's Alt bindings, and its settings live in a plist nix can't own.
- `macos_option_as_alt = "yes"` makes Option send Alt so zellij's Alt bindings work.
- `kitty.settings.shell` is set to `zellij` so every kitty window/tab boots directly into a fresh session.
- Alt+Left/Right are freed from zellij so zsh gets word-jump; Super+Alt+Left/Right (via the kitty keyboard protocol) switches zellij tabs. If touching keybindings, check `zellij/config.kdl` and remember that Cmd only reaches zellij *because* kitty is negotiating the extended keyboard protocol.

## Workflow

- **Feature branch → PR → squash-merge → local reset.** The user prefers `gh pr merge N --squash --delete-branch` then `git reset --hard origin/main` locally.
- **Use a git worktree, not `git switch`, when opening a second PR while the current branch has in-flight work.** `git worktree add ../dotnix-<slug> -b feat/<slug> main` keeps the two checkouts physically separate and avoids stash/pop churn on the original branch.
- **Do not commit or push without an explicit ask.** Draft the change, show the diff, wait for "commit" / "open a PR".
- **Keep the README managed-packages table in sync with `home.nix`.** A PR-reviewer bot flags drift on every PR — if a package is added or removed in `home.nix`, update the table in the same commit.
- **Never introduce work-internal identifiers** (hostnames, `.corp` domains, work email addresses). Work-specific git identity lives in an untracked `~/.gitconfig-local` that home-manager includes conditionally; nothing here should reference it by content.
