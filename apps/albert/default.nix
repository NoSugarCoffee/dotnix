{ lib, pkgs, ... }:
{
  home.packages = lib.filter (lib.meta.availableOn pkgs.stdenv.hostPlatform) [ pkgs.albert-darwin ];
  # Auto-launch Albert at login. macOS user LaunchAgents fire once the user's
  # Aqua session comes up -- the earliest legitimate hook for a GUI app.
  launchd.agents.albert = {
    enable = pkgs.stdenv.isDarwin;
    config = {
      ProgramArguments = [
        "${pkgs.albert-darwin}/Applications/Albert.app/Contents/MacOS/Albert"
      ];
      RunAtLoad = true;
      KeepAlive = false;
      ProcessType = "Interactive";
    };
  };
}
