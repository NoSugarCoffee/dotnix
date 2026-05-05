{ lib, pkgs, ... }:
let
  homeDirectory = if pkgs.stdenv.isDarwin then "/Users/liangliangdai" else "/home/liangliangdai";
in
{
  home = {
    username = "liangliangdai";
    inherit homeDirectory;
    stateVersion = "25.11";
    packages = [ pkgs.codex ] ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.copyq ];
    file.".codex/config.toml" = {
      force = true;
      text = ''
        # Managed by home-manager. Authentication is created by `codex login`.

        model = "gpt-5-codex"
        approval_policy = "on-request"
        sandbox_mode = "workspace-write"
        file_opener = "cursor"

        [sandbox_workspace_write]
        network_access = true

        [tui]
        notifications = true

        [history]
        persistence = "save-all"

        [shell_environment_policy]
        inherit = "all"
      '';
    };
  };
  home.activation.codexHomeDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p $HOME/.codex
    $DRY_RUN_CMD chmod 700 $HOME/.codex
  '';
  programs.home-manager.enable = true;
}
