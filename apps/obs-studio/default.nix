{ lib, pkgs, ... }:
{
  # nixpkgs' build on Linux, nur-packages' repack on macOS.
  home.packages =
    lib.filter (lib.meta.availableOn pkgs.stdenv.hostPlatform) [ pkgs.obs-studio ]
    ++ lib.optional (pkgs.nosugarcoffee ? obs-studio) pkgs.nosugarcoffee.obs-studio;
}
