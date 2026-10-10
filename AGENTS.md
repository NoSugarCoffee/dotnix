See `CLAUDE.md` for repository conventions. It applies to every agent working in this repo, not just Claude Code -- kept as a single file rather than duplicated here so the two can't drift.

## Cursor Cloud specific instructions

- Nix is single-user (`--no-daemon`): this image has no systemd, so the multi-user daemon cannot run. Flakes are enabled in `~/.config/nix/nix.conf`. `nix` and `just` are on the default PATH.
- Unit tests do not need Nix: `python3 -m unittest discover -s tests -t tests -v`.
- `nix flake check` evaluates this machine's outputs. Darwin outputs are omitted unless `--all-systems` is passed.
- `just build` names the Home Manager configuration from `$USER`. On Cloud Agents `$USER` is `ubuntu`, so run `USER=$(nix eval --raw .#username) just build` to build `homeConfigurations.<username>-x86_64-linux.activationPackage`.
- Do not run `just switch` here. Activation writes to `/home/<username>` from the flake and installs asdf language runtimes.
- `git add` new Nix files before `nix build`; the flake only sees the git tree. See `CLAUDE.md`.
