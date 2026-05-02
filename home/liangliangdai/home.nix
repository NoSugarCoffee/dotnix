# Example home-manager user. Reuse from inside a NixOS host or use standalone:
#   home-manager switch --flake .#liangliangdai@example-host
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ../../modules/home-manager/shell.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/packages.nix
    ../../modules/home-manager/development.nix
    ../../modules/home-manager/codex.nix
  ];

  home = {
    username = "liangliangdai";
    homeDirectory = "/home/liangliangdai";

    # Pin to the home-manager release you initially installed; do not bump
    # without reading the release notes.
    stateVersion = "25.11";
  };

  # Feature toggles from the development module.
  modules.development = {
    enable = true;
    languages = {
      go = true;
      python = true;
      node = false;
    };
  };

  # OpenAI Codex CLI. Run `codex login` once after activation.
  modules.codex = {
    enable = true;
    model = "gpt-5-codex";
    approvalPolicy = "on-request";
    sandboxMode = "workspace-write";
    networkAccess = true;
    fileOpener = "cursor";
  };

  # Override the placeholder identity from modules/home-manager/git.nix.
  # TODO: replace with your real git identity.
  programs.git.userName = "liangliangdai";
  programs.git.userEmail = "1353025854@qq.com";

  # Let home-manager manage itself.
  programs.home-manager.enable = true;
}
