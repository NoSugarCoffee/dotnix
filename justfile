set shell := ["bash", "-cu"]

USER := env_var_or_default("USER", `nix eval --raw .#username`)
SYSTEM := arch() + "-" + (if os() == "macos" { "darwin" } else { "linux" })
CONFIG := USER + "-" + SYSTEM

default:
    @just --list

# Apply the Home Manager configuration for the current platform.
# Refuses when an untracked `.overlay` file is present: this checkout is then
# an input to a private overlay flake (see "Fork or extend" in the README),
# and switching from here builds the same modules *without* that flake's,
# silently removing everything it manages. The dependency is one-way, so this
# marker is the only thing that can notice.
switch:
    @if [ -f .overlay ]; then echo "This checkout is an input to the overlay flake at $(cat .overlay) -- run 'just switch' there instead." >&2; exit 1; fi
    nix run .#home-manager -- switch --flake .#{{CONFIG}}

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
