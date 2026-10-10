See `CLAUDE.md` for repository conventions. It applies to every agent working in this repo, not just Claude Code -- kept as a single file rather than duplicated here so the two can't drift.

## AI agent packages

Prefer prebuilt packages from the `llm-agents` flake input (`github:numtide/llm-agents.nix`) over vendoring our own derivations.

Wire new agents by adding their attribute name to the `llmAgentsPackages` list in `flake.nix`. Names missing on a system are skipped automatically — do not add a local `pkgs/*` package (or release-pin / DMG repack) to cover a platform gap that `llm-agents` does not ship yet.

Currently taken from `llm-agents`: `apm`, `ccstatusline`, `claude-desktop`, `grok-bot`, `orca`, `paperclip`. Keep the README managed-packages table in sync when that set changes.
