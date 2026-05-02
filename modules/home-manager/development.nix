# Dev tooling tailored to a Go / Python / Shell workflow. Enable selectively.
{
  config,
  lib,
  pkgs,
  unstable ? pkgs,
  ...
}:
let
  cfg = config.modules.development;
in
{
  options.modules.development = {
    enable = lib.mkEnableOption "developer toolchain (Go, Python, Node, containers)";

    languages = {
      go = lib.mkEnableOption "Go toolchain" // {
        default = true;
      };
      python = lib.mkEnableOption "Python toolchain" // {
        default = true;
      };
      node = lib.mkEnableOption "Node.js toolchain";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      with pkgs;
      [
        # Editors
        neovim

        # Containers / cloud
        docker-compose
        kubectl
        kubernetes-helm
        google-cloud-sdk
        terraform
      ]
      ++ lib.optionals cfg.languages.go [
        go
        gopls
        golangci-lint
        delve
      ]
      ++ lib.optionals cfg.languages.python [
        python3
        python3Packages.pip
        python3Packages.virtualenv
        ruff
        uv
      ]
      ++ lib.optionals cfg.languages.node [
        nodejs_20
        pnpm
      ];
  };
}
