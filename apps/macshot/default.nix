{ lib, pkgs, ... }:
let
  # Null on x86_64-darwin: 26.05 has no macshot, and nixpkgs-unstable does
  # not evaluate on that system. Elsewhere, keep the platform filter so a
  # Linux build of the attribute is not installed.
  macshot = pkgs.macshot or null;
in
{
  home.packages = lib.optional (
    macshot != null && lib.meta.availableOn pkgs.stdenv.hostPlatform macshot
  ) macshot;
}
