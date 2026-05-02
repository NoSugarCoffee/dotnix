# Re-exports each NixOS module so other flakes can import a curated subset:
#
#   imports = [ inputs.starter.nixosModules.base inputs.starter.nixosModules.networking ];
#
# `all` is a convenience that imports every module in this directory.
{
  base = ./base.nix;
  networking = ./networking.nix;
  users = ./users.nix;
  desktop = ./desktop.nix;

  all = {
    imports = [
      ./base.nix
      ./networking.nix
      ./users.nix
      ./desktop.nix
    ];
  };
}
