# Common tasks — run `just` to list them.
# Override HOST / USER for non-default targets:
#   just rebuild HOST=laptop
#   just hm USER=bob HOST=laptop

set shell := ["bash", "-cu"]

HOST := env_var_or_default("HOST", "example-host")
USER := env_var_or_default("USER", "alice")

default:
    @just --list

# Update all flake inputs to their latest versions.
update:
    nix flake update

# Update one input only, e.g. `just update-input nixpkgs`.
update-input INPUT:
    nix flake update {{INPUT}}

# Build (but don't switch) the configured NixOS host.
build:
    nixos-rebuild build --flake .#{{HOST}}

# Switch the running NixOS host. Requires sudo.
rebuild:
    sudo nixos-rebuild switch --flake .#{{HOST}}

# Standalone home-manager switch (non-NixOS or per-user).
hm:
    home-manager switch --flake .#{{USER}}@{{HOST}}

# Run all flake checks (formatting, statix, deadnix).
check:
    nix flake check

# Auto-format the whole tree.
fmt:
    nix fmt

# Show the dependency graph of the system closure.
tree:
    nix-tree --derivation .#nixosConfigurations.{{HOST}}.config.system.build.toplevel

# Diff the current and previous system generations.
diff:
    nvd diff /run/current-system result || nvd diff /run/current-system /nix/var/nix/profiles/system

# Garbage-collect everything older than 14 days.
gc:
    sudo nix-collect-garbage --delete-older-than 14d
    nix-collect-garbage --delete-older-than 14d

# Drop into a devshell explicitly (for tooling outside direnv).
shell:
    nix develop
