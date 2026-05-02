# Sensible defaults for any NixOS host: locale, timezone, Nix settings,
# basic CLI tools. Imported by every host.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # --- Nix daemon settings -------------------------------------------------
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      trusted-users = [
        "root"
        "@wheel"
      ];
      # Use a few public binary caches by default.
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };

    optimise.automatic = true;
  };

  # --- System basics -------------------------------------------------------
  time.timeZone = lib.mkDefault "Asia/Shanghai";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
  i18n.supportedLocales = lib.mkDefault [
    "en_US.UTF-8/UTF-8"
    "zh_CN.UTF-8/UTF-8"
  ];

  console.keyMap = lib.mkDefault "us";

  # --- Baseline packages ---------------------------------------------------
  environment.systemPackages = with pkgs; [
    bat
    curl
    fd
    git
    htop
    jq
    ripgrep
    tmux
    tree
    unzip
    vim
    wget
  ];

  # --- Programs ------------------------------------------------------------
  programs = {
    zsh.enable = true;
    git.enable = true;
    nix-ld.enable = true; # run dynamically-linked binaries on NixOS
  };

  # --- State version -------------------------------------------------------
  # Pin the NixOS state version. NEVER bump this casually — read the release
  # notes first; it controls migration of stateful services.
  system.stateVersion = lib.mkDefault "25.11";
}
