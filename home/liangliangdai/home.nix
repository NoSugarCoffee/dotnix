{ claudeDesktopPackage, browserUsePackage, lib, pkgs, ... }:
let
  homeDirectory = if pkgs.stdenv.isDarwin then "/Users/liangliangdai" else "/home/liangliangdai";
in
{
  home = {
    username = "liangliangdai";
    inherit homeDirectory;
    stateVersion = "25.11";
    packages =
      [ pkgs.codex pkgs.claude-code pkgs.asdf-vm pkgs.git browserUsePackage ]
      ++ lib.optionals (claudeDesktopPackage != null) [ claudeDesktopPackage ]
      ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.copyq ]
      ++ lib.optionals pkgs.stdenv.isDarwin [ pkgs.google-chrome ];
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
  # Mirrors are 1:1 mirrors of cache.nixos.org (same signing key, so no
  # extra-trusted-public-keys needed) that are much faster to reach from
  # mainland China. `extra-substituters` only appends to the daemon's list --
  # cache.nixos.org stays as the fallback for anything a mirror doesn't have.
  # Only takes effect if this user is a trusted-user in /etc/nix/nix.conf
  # (the Determinate Systems installer adds the installing user by default);
  # otherwise the daemon silently ignores user-supplied substituters.
  xdg.configFile."nix/nix.conf".text = ''
    extra-substituters = https://mirror.sjtu.edu.cn/nix-channels/store https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store
  '';
  home.activation.codexHomeDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p $HOME/.codex
    $DRY_RUN_CMD chmod 700 $HOME/.codex
  '';
  programs.home-manager.enable = true;
}
