{ lib, pkgs, ... }:
{
  home.packages = lib.optional (pkgs.nosugarcoffee ? ego-lite) pkgs.nosugarcoffee.ego-lite;
}
