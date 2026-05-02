# Example NixOS host configuration — tweak hostname, hardware import, and
# user. Build with:
#   sudo nixos-rebuild switch --flake .#example-host
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    # Generated when you ran `nixos-generate-config`. Copy yours here.
    ./hardware-configuration.nix

    # Shared modules from this flake.
    ../../modules/nixos/base.nix
    ../../modules/nixos/networking.nix
    ../../modules/nixos/users.nix
    ../../modules/nixos/desktop.nix
  ];

  # --- Identity ------------------------------------------------------------
  networking.hostName = "example-host";

  # --- Bootloader ----------------------------------------------------------
  # Defaults to systemd-boot on UEFI. Switch to GRUB if you're on BIOS.
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # --- Feature toggles -----------------------------------------------------
  modules.desktop.enable = true;

  # --- Host-specific packages ---------------------------------------------
  environment.systemPackages = with pkgs; [
    firefox
  ];

  # --- Virtualisation ------------------------------------------------------
  virtualisation.docker.enable = true;
}
