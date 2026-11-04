{ pkgs, ... }:
{
  # Not pkgs.agent-browser: the pins stop at 0.27.0 / 0.41.1, short of v0.41.2.
  home.packages = [ (pkgs.callPackage ./package.nix { }) ];
}
