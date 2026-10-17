# AGENTS.md

Guidance for AI coding agents (Claude Code, Cursor, Codex, and others) working in this
repository. `CLAUDE.md` is a symlink to this file, kept only because Claude Code looks for
that filename specifically — there is a single source of truth here, so the two can't drift.

See `README.md` for what the repo is, supported systems, managed packages, commands, and the
rationale for asdf / mirrors / kitty / zellij. This file only covers things that aren't in the
README.

## Layout

One directory per app under `apps/<name>/`: `default.nix` is its home-manager module (packages,
config, launchd, activation), and its config files sit beside it. `home.nix` imports every
`apps/*` directory automatically, so adding an app is adding a directory. This repo holds no
package definitions (see "Packages nixpkgs lacks" below). Shared bits live in `lib/` (proxy
values, `managed_settings.py`).

## macOS app placement

`home.activation.copyApps` in `home.nix` copies every `home.packages` app bundle into
`~/Applications/Home Manager Apps`, except bundles containing `Contents/Library/SystemExtensions`
(VPN, virtual camera, driver), which go to `/Applications`. macOS only activates a system
extension from there; elsewhere it fails, and Tailscale's standalone app even aborts at launch.
Routing is keyed on the bundle, so a new app with a system extension needs no opt-in. Don't add
per-app symlinks or activation steps to work around placement. Ownership of an `/Applications`
copy is an xattr (`home-manager.copied`) on the `.app` directory, written before rsync and
again after as a defensive restamp (the copy does not pass `-X`/`-A`).
`~/.local/state/home-manager/copied-system-apps` is only an index for cleanup; a sweep of
`/Applications` also removes sentinel-owned bundles whose sidecar was lost. A bundle without
that xattr is left alone, except a one-time adopt of a sidecar-only copy from before this
sentinel whose `CFBundleIdentifier` matches the store app (so Tailscale/OBS installed from
`main` keep updating). A hand-replace with a different id drops the stale sidecar. Same-id
hand-replace is indistinguishable from that adopt and is overwritten. The store copy stays in
`~/Applications/Home Manager Apps` when we skip. Replacing a running app that already has an
active system extension may need a reboot or relaunch before macOS loads the new bundle.

## Packages nixpkgs lacks

Never add a `package.nix` here. A package nixpkgs doesn't have (or ships Linux-only) comes
from one of two flake inputs, prebuilt and cached for the systems they ship (not Intel macOS):

- **AI agents → `llm-agents`** (`github:numtide/llm-agents.nix`), below.
- **Everything else → `nur-packages`** ([NoSugarCoffee/nur-packages](https://github.com/NoSugarCoffee/nur-packages),
  ours): add `pkgs/<name>/package.nix` (+ `pin.json` for a release download) there; it is
  updated 4× daily and cached on `nosugarcoffee.cachix.org`. Here it appears as
  `pkgs.nosugarcoffee.<name>`, holding only what the system supports, so modules take it with
  `lib.optional (pkgs.nosugarcoffee ? <name>) pkgs.nosugarcoffee.<name>`. On x86_64-darwin,
  which nixpkgs-unstable dropped, that set comes from its overlay against our 26.05 and builds
  locally. A new package reaches dotnix once the lock moves: `flake-update.yml`'s daily PR
  merges after CI, or run `nix flake update nur-packages` yourself.

### AI agent packages

Prefer prebuilt packages from the `llm-agents` flake input over vendoring our own derivations.

Wire new agents by adding their attribute name to the `llmAgentsPackages` list in `flake.nix`.
Names missing on a system are skipped automatically — do not cover a platform gap that
`llm-agents` does not ship yet with a derivation of our own, here or in `nur-packages`.

Currently taken from `llm-agents`: `apm`, `ccstatusline`, `claude-code`, `claude-desktop`,
`grok-bot`, `orca`, `paperclip`. Keep the README managed-packages table in sync when that set changes.

## Public repo

No work-internal hostnames, tokens, or identities in commits or PR bodies. Work-specific git
identity lives in an untracked `~/.gitconfig-local` that home-manager includes conditionally.

## Constraints on the assistant's shell

- **`git add` new files before `nix build`.** The flake source is the git tree; untracked
  `apps/*/` files are invisible to the build until staged.
- **`sudo` can't prompt for a password here — not even via `!`.** A `!` command has no
  terminal either, so `! sudo …` fails the same way. Anything needing sudo (bootstrap,
  `just nix-proxy`, some fixes) must be run by the user in their own terminal; give them the
  exact command and ask them to report back.
- **`home-manager switch` needs macOS "App Management" permission** for the terminal it runs
  in, which the assistant's shell lacks. When activation is needed, ask the user to run
  `! just switch` themselves.

## Workflow

- **Feature branch → PR → squash-merge → local reset.** `gh pr merge N --squash --delete-branch`,
  then `git reset --hard origin/main` locally.
- **Use a git worktree, not `git switch`, when opening a second PR while the current branch has
  in-flight work.** `git worktree add ../dotnix-<slug> -b feat/<slug> main` keeps the two
  checkouts physically separate and avoids stash/pop churn.
- **Commits and PRs only on explicit request.** Draft the change, show the diff, wait for
  "commit" / "open a PR".
- **Keep the README managed-packages table in sync with `apps/`.** A PR-reviewer bot flags
  drift on every PR — if a package is added or removed in an app module, update the table in
  the same commit.

## Agent skills and workflows

### Issue tracker

Issues live in GitHub Issues on NoSugarCoffee/dotnix, via the `gh` CLI. See
`docs/agents/issue-tracker.md`.

### Triage labels

The five default triage labels are used as-is (`needs-triage`, `needs-info`, `ready-for-agent`,
`ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` plus `docs/adr/` at the repo root, both created when first
needed. See `docs/agents/domain.md`.
