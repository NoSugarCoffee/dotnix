set shell := ["bash", "-cu"]

USER := env_var_or_default("USER", `nix eval --raw .#username`)
SYSTEM := arch() + "-" + (if os() == "macos" { "darwin" } else { "linux" })
CONFIG := USER + "-" + SYSTEM

default:
    @just --list

# Apply the Home Manager configuration for the current platform, as $USER.
switch:
    flake=$(scripts/local-flake.sh) && nix run "$flake#home-manager" -- switch --flake "$flake#{{CONFIG}}"

# Show all Home Manager generations.
generations:
    nix run .#home-manager -- generations

# Build the Home Manager activation package without switching, as $USER.
build:
    flake=$(scripts/local-flake.sh) && nix build "$flake#homeConfigurations.{{CONFIG}}.activationPackage"

# Show flake outputs.
show:
    nix flake show

# Update flake inputs.
update:
    nix flake update
