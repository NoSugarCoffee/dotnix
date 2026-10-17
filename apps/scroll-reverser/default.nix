{ lib, pkgs, ... }:
let
  scroll-reverser = pkgs.nosugarcoffee.scroll-reverser or null;
in
{
  home.packages = lib.optional (scroll-reverser != null) scroll-reverser;
  # Scroll Reverser only reverses scroll direction while its process is
  # running, so it has to come up with the login session.
  launchd.agents.scroll-reverser = lib.mkIf (scroll-reverser != null) {
    enable = true;
    config = {
      ProgramArguments = [
        "${scroll-reverser}/Applications/Scroll Reverser.app/Contents/MacOS/Scroll Reverser"
      ];
      RunAtLoad = true;
      KeepAlive = false;
      ProcessType = "Interactive";
    };
  };
}
