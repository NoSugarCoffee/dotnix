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

# Route the Nix daemon's uncached downloads through the proxy in lib/proxy.nix (macOS, sudo).
nix-proxy:
    scripts/nix-daemon-proxy.sh

# Run the Python test suite with the same bash, rsync and GNU coreutils as CI
# (activation blocks call GNU-only flags like `readlink -m`).
test:
    nix shell --inputs-from . nixpkgs#bash nixpkgs#rsync nixpkgs#coreutils --command python3 -m unittest discover -s tests -t tests
