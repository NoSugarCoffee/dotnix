set shell := ["bash", "-cu"]

USER := env_var_or_default("USER", "liangliangdai")

default:
    @just --list

# Apply the Codex-only Home Manager configuration.
switch:
    nix run .#home-manager -- switch --flake .#{{USER}}

# Build the Home Manager activation package without switching.
build:
    nix build .#homeConfigurations.{{USER}}.activationPackage

# Show flake outputs.
show:
    nix flake show

# Update flake inputs.
update:
    nix flake update
