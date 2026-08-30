---
name: Code Quality Monitoring

on:
  schedule: weekly on monday
  workflow_dispatch: {}
  # A weekly agent with nothing new to say would otherwise reopen the same
  # findings forever; hold off while any of its issues is still unaddressed.
  skip-if-match: 'is:issue is:open in:title "[quality] "'

permissions:
  contents: read
  issues: read

# OpenRouter has no first-class engine; it is reached by pointing an engine's
# base URL at it. codex rather than claude because the model is a GPT -- the
# claude engine drives the Claude Code CLI, which cannot run one. gh-aw sees a
# custom endpoint and stops rewriting the model slug, so the provider-prefixed
# name passes through intact.
engine:
  id: codex
  env:
    OPENAI_BASE_URL: "https://openrouter.ai/api/v1"
    OPENAI_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}

model: openai/gpt-5.6-luna

# The agent runs behind the AWF egress firewall, so the provider host has to be
# allowlisted explicitly.
network:
  allowed:
    - defaults
    - openrouter.ai

# Luna's OpenRouter rate. The AWF proxy rejects models missing from its
# built-in pricing table with HTTP 400, and a provider-prefixed slug is not
# in it.
models:
  default-ai-credits-pricing:
    input: 0.20
    output: 1.20

timeout-minutes: 20

# Both checks below read files straight out of the checkout, so this needs no
# setup steps and no Nix -- unlike the linters, which moved to ci.yml.
tools:
  bash: ["*"]

safe-outputs:
  create-issue:
    title-prefix: "[quality] "
    labels: [code-quality, automation]
    max: 3
---

# Weekly Repository Review

This repository is a Home Manager flake that configures macOS (aarch64) and
Linux workstations.

`statix`, `deadnix`, `nixfmt`, `ruff` and `shellcheck` all run in CI on every
pull request (`.github/workflows/ci.yml`, the `lint` job) and block the merge.
**Do not re-report anything a linter would catch** — if it were there, the
build would already be red. Your job is the two checks no linter can express.

## 1. README drift

`CLAUDE.md` requires the "Managed packages" section of `README.md` to stay in
sync with the packages installed by `home/home.nix`. Compare the two and
report:

- packages installed in `home/home.nix` but absent from the README table
- packages listed in the README but no longer installed
- `macOS` / `Linux` tags that no longer match the platform conditionals in
  `home/home.nix` (`lib.optionals pkgs.stdenv.isDarwin` and friends)

Note that some entries are deliberately annotated rather than bare names —
local packages describe what they do, and some carry a fork note. A wording
difference is not drift; a missing or wrongly-tagged package is.

## 2. Flake input staleness

Read the `lastModified` timestamps in `flake.lock` and report inputs not
updated in more than 90 days, naming each input and its age in days.

Distinguish the root inputs this repo controls from transitive nodes pulled in
by another flake — the two need different fixes, and saying which is which is
most of the value. Do not propose a specific version bump; the point is to
surface age, not to plan the upgrade.

## What to Create

At most one issue per check, and only when there is something to say. If both
checks come back clean, create no issues at all — that is a normal outcome for
a repository this small, not a reason to lower the bar.

Each issue should:

- Reference files as **repository-relative paths** — `home/home.nix:118`, not
  the absolute path of the runner's checkout. Absolute paths render as dead
  links on GitHub.
- Explain why the finding matters for this repository specifically.
- Suggest a concrete first step.
- Carry a severity: High for anything that can break activation on a fresh
  machine, Medium for maintainability, Low for cosmetics.

## What to Skip

- Anything the `lint` job in `.github/workflows/ci.yml` already blocks.
- Anything the build already catches: `ci.yml` runs `nix flake check`, builds
  the activation package on both platforms, and smoke-tests activation and the
  interactive-zsh PATH.
- Pinned version and hash literals in `pkgs/*-darwin/default.nix`. Those track
  upstream DMG releases and are expected to lag; bumping them is a separate,
  manual job.
- Suggestions to add tooling the repository has deliberately rejected — check
  `README.md` "Notes" and the git history before proposing a new dependency.
