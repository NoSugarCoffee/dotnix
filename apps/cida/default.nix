{ lib, pkgs, ... }:
{
  home.packages = lib.optional (pkgs.nosugarcoffee ? cida) pkgs.nosugarcoffee.cida;
}
