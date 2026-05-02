# Git + delta. Replace userName / userEmail before you deploy.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.git = {
    enable = true;
    userName = lib.mkDefault "Your Name";
    userEmail = lib.mkDefault "you@example.com";

    delta = {
      enable = true;
      options = {
        navigate = true;
        line-numbers = true;
        side-by-side = true;
      };
    };

    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      rebase.autoStash = true;
      merge.conflictStyle = "zdiff3";
      diff.colorMoved = "default";
    };

    ignores = [
      ".direnv/"
      "result"
      "result-*"
      ".DS_Store"
      "*.swp"
    ];
  };

  programs.gh = {
    enable = true;
    settings.git_protocol = "ssh";
  };

  programs.lazygit.enable = true;
}
