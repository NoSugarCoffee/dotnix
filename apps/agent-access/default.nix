{ lib, pkgs, ... }:
{
  home.packages = lib.optional (pkgs.nosugarcoffee ? agent-access) pkgs.nosugarcoffee.agent-access;
}
