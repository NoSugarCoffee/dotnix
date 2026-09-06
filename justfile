set shell := ["bash", "-cu"]

USER := env_var_or_default("USER", `nix eval --raw .#username`)
SYSTEM := arch() + "-" + (if os() == "macos" { "darwin" } else { "linux" })
CONFIG := USER + "-" + SYSTEM

default:
    @just --list

# Apply the Home Manager configuration for the current platform.
# -b backup: standalone home-manager aborts at checkLinkTargets when a newly
# managed path already exists as a regular file (ccstatusline's TUI writes
# ~/.config/ccstatusline/settings.json before the first switch).
switch:
    nix run .#home-manager -- switch --flake .#{{CONFIG}} -b backup

# Show all Home Manager generations.
generations:
    nix run .#home-manager -- generations

# Build the Home Manager activation package without switching.
build:
    nix build .#homeConfigurations.{{CONFIG}}.activationPackage

# Show flake outputs.
show:
    nix flake show

# Update flake inputs.
update:
    nix flake update
