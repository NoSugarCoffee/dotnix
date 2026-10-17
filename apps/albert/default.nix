{
  homeDirectory,
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = lib.optional (pkgs.nosugarcoffee ? albert) pkgs.nosugarcoffee.albert;
  # Auto-launch Albert at login. macOS user LaunchAgents fire once the user's
  # Aqua session comes up -- the earliest legitimate hook for a GUI app.
  launchd.agents.albert = {
    enable = pkgs.stdenv.isDarwin;
    config = {
      ProgramArguments = [
        "${homeDirectory}/${config.targets.darwin.copyApps.directory}/Albert.app/Contents/MacOS/Albert"
      ];
      RunAtLoad = true;
      KeepAlive = false;
      ProcessType = "Interactive";
    };
  };
}
