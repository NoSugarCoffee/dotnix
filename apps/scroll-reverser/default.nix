{ lib, pkgs, ... }:
{
  home.packages = lib.filter (lib.meta.availableOn pkgs.stdenv.hostPlatform) [ pkgs.scroll-reverser ];
  # Scroll Reverser only reverses scroll direction while its process is
  # running, so it has to come up with the login session.
  launchd.agents.scroll-reverser = {
    enable = pkgs.stdenv.isDarwin;
    config = {
      ProgramArguments = [
        "${pkgs.scroll-reverser}/Applications/Scroll Reverser.app/Contents/MacOS/Scroll Reverser"
      ];
      RunAtLoad = true;
      KeepAlive = false;
      ProcessType = "Interactive";
    };
  };
}
