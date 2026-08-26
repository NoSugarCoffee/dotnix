# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

See `README.md` for what the repo is, supported systems, managed packages, commands, and the rationale for asdf / mirrors / kitty / zellij. This file only covers things that aren't in the README.

## Public repo

No work-internal hostnames, tokens, or identities in commits or PR bodies. Work-specific git identity lives in an untracked `~/.gitconfig-local` that home-manager includes conditionally.

## Constraints on the assistant's shell

- **`git add` new files before `nix build`.** The flake source is the git tree; untracked `pkgs/*/default.nix` or new modules are invisible to the build until staged.
- **`sudo` is non-interactive-hostile here.** Anything needing it (bootstrap, some fixes) must be run by the user with `! sudo …` in the prompt — don't try to script it.
- **`home-manager switch` needs macOS "App Management" permission** for the terminal it runs in, which the assistant's shell lacks. When activation is needed, ask the user to run `! just switch` themselves.

## Workflow

- **Feature branch → PR → squash-merge → local reset.** `gh pr merge N --squash --delete-branch`, then `git reset --hard origin/main` locally.
- **Use a git worktree, not `git switch`, when opening a second PR while the current branch has in-flight work.** `git worktree add ../dotnix-<slug> -b feat/<slug> main` keeps the two checkouts physically separate and avoids stash/pop churn.
- **Commits and PRs only on explicit request.** Draft the change, show the diff, wait for "commit" / "open a PR".
- **Keep the README managed-packages table in sync with `home.nix`.** A PR-reviewer bot flags drift on every PR — if a package is added or removed in `home.nix`, update the table in the same commit.
