# dotnix

Minimal Home Manager flake for installing and configuring Codex CLI for `liangliangdai`.

## What remains

- `flake.nix` defines one Home Manager output: `homeConfigurations.liangliangdai`.
- `home/liangliangdai/home.nix` installs `pkgs.codex` and writes `~/.codex/config.toml`.
- `justfile` provides small wrappers for build, switch, show, and update.

## Apply

First run, or any time `home-manager` is not installed yet:

```sh
nix run .#home-manager -- switch --flake .#liangliangdai
```

After activation, this config enables the `home-manager` command, so later runs can use:

```sh
home-manager switch --flake .#liangliangdai
```

Or with `just`:

```sh
just switch
```

## Build without switching

```sh
nix build .#homeConfigurations.liangliangdai.activationPackage
```

Or with `just`:

```sh
just build
```

## After activation

Authenticate Codex once:

```sh
codex login
```

Authentication files are intentionally not managed by this repository.
