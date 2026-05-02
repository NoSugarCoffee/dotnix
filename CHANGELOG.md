# Changelog

All notable changes to this template will be documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `modules/home-manager/codex.nix` — declarative OpenAI Codex CLI install
  (via `pkgs.codex`) with typed options for model, approval policy,
  sandbox mode, network access, and file opener. Wired into the example
  user.

## [0.1.0] — Initial release

### Added

- Flake pinned to `nixos-25.11` and `home-manager release-25.11`.
- NixOS modules: `base`, `networking`, `users`, `desktop` (opt-in).
- Home-manager modules: `shell`, `git`, `packages`, `development` (opt-in).
- Example host (`example-host`) and example user (`alice`).
- `devShells.default` containing niv, nixpkgs-fmt, nixfmt, nil, statix,
  deadnix, nix-tree, nvd, home-manager, just.
- treefmt-based `nix fmt` and `nix flake check`.
- `justfile`, `.envrc`, `.gitignore`, MIT license, README.
