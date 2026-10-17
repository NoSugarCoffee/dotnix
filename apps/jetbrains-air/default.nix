{ lib, pkgs, ... }:
{
  home.packages = lib.optional (pkgs.nosugarcoffee ? jetbrains-air) pkgs.nosugarcoffee.jetbrains-air;
}
