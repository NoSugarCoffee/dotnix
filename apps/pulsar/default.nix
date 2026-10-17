{ lib, pkgs, ... }:
{
  home.packages = lib.optional (pkgs.nosugarcoffee ? pulsar) pkgs.nosugarcoffee.pulsar;
}
