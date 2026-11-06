{ lib, pkgs, ... }:
{
  home.packages = lib.optional (pkgs.nosugarcoffee ? heyclicky) pkgs.nosugarcoffee.heyclicky;
}
