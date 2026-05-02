# Per-user packages installed via home-manager.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    # CLI essentials
    bat
    eza
    fd
    ripgrep
    jq
    yq-go
    tree
    htop
    btop
    tmux
    tldr

    # Network / cloud
    curl
    wget
    httpie
    dig
    nmap

    # Archives
    unzip
    p7zip

    # Nix tooling
    nix-tree
    nix-output-monitor
    nvd
  ];
}
