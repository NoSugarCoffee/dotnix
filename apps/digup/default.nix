{ lib, pkgs, ... }:
{
  home.packages = lib.optional (pkgs.nosugarcoffee ? digup) pkgs.nosugarcoffee.digup;
}
