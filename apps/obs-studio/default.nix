{ lib, pkgs, ... }:
{
  home.packages = lib.filter (lib.meta.availableOn pkgs.stdenv.hostPlatform) [
    pkgs.obs-studio
    pkgs.obs-studio-darwin
  ];
}
