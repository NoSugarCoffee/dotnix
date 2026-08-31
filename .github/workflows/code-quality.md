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

# No setup steps and no Nix -- unlike the linters, which moved to ci.yml. The
# README check reads the checkout; the flake check also needs to ask GitHub for
# each input's newest commit, which gh-proxy mode provides as a pre-authenticated
# `gh` in bash rather than a separate MCP server.
tools:
  github:
    mode: gh-proxy
    # Narrowed from the default set: the only GitHub call either check makes is
    # reading commits, so pull_requests and issues access would be unused
    # permissions.
    toolsets: [repos]
  bash: ["*"]

safe-outputs:
  create-issue:
    title-prefix: "[quality] "
    labels: [code-quality, automation]
    # Two checks, at most one issue each.
    max: 2
---

# Weekly Repository Review

This repository is a Home Manager flake that configures macOS (aarch64) and
Linux workstations.

`statix`, `deadnix`, `nixfmt`, `ruff` and `shellcheck` run in CI and block the
merge (`.github/workflows/ci.yml`, the `lint` job) on every pull request that
touches Nix, Python or shell code — `ci.yml` skips documentation-only PRs,
which cannot introduce those findings anyway. **Do not re-report anything a
linter would catch**; if it were there, the build would already be red. Your
job is the two checks no linter can express.

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

## 2. Flake inputs behind upstream

**Age is not staleness.** Several inputs here are pinned to repositories that
are finished — `numtide/flake-utils` and `nix-systems/default` have not had a
commit in years, so a pin that looks ancient is simply current. Reporting age
alone produces false positives; the first version of this check did exactly
that and filed an issue about three inputs that were all already at HEAD.

So compare, don't date. For each input in `flake.lock`, take its `owner`,
`repo` and `ref`, ask GitHub for the newest commit on that ref, and report only
inputs whose locked `rev` is **not** that commit:

```bash
gh api "repos/<owner>/<repo>/commits?sha=<ref>&per_page=1" \
  --jq '.[0] | .sha[0:7] + "  " + .commit.committer.date[0:10]'
```

Report how far behind each one is — commits, or dates if that is easier to
establish — and name the newest available rev. An input already at HEAD is not
a finding no matter how old the commit is.

Two things to get right:

- **Separate root inputs from transitive ones.** Root inputs are yours to bump.
  A transitive node belongs to whichever flake pulled it in and usually cannot
  be moved without updating that flake.
- **Read `flake.nix` before reporting a transitive nixpkgs.** The
  `claude-desktop` input deliberately does not follow this repo's nixpkgs,
  because its build recipe still calls `nodePackages.asar`, which nixpkgs
  removed on 2026-03-03. That node being old is what keeps the Linux build
  working. Do not report a pin whose comment explains why it is pinned.

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
