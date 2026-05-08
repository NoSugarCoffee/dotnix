{
  description = "Home Manager configuration for personal desktop tools and CLI.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";

    claude-desktop = {
      url = "github:k3d3/claude-desktop-linux-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      nixpkgs,
      home-manager,
      claude-desktop,
      uv2nix,
      pyproject-nix,
      pyproject-build-systems,
      ...
    }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = lib.genAttrs systems;
      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      mkBrowserUsePackage =
        system:
        let
          pkgs = mkPkgs system;
          workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./pkgs/browser-use; };
          overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };
          python = pkgs.python311;
          pythonBase = pkgs.callPackage pyproject-nix.build.packages { inherit python; };
          pythonSet = pythonBase.overrideScope (
            lib.composeManyExtensions [
              pyproject-build-systems.overlays.wheel
              overlay
            ]
          );
          venv = pythonSet.mkVirtualEnv "browser-use-env" { "browser-use" = [ ]; };
          inherit (pkgs.callPackages pyproject-nix.build.util { }) mkApplication;
        in
        mkApplication {
          inherit venv;
          package = pythonSet."browser-use";
        };
      mkHomeConfiguration =
        system:
        let
          isLinux = lib.elem system [ "x86_64-linux" "aarch64-linux" ];
          claudeDesktopPackage = if
            (
              isLinux
              && builtins.hasAttr system claude-desktop.packages
            )
          then claude-desktop.packages.${system}.claude-desktop
          else null;
          browserUsePackage = mkBrowserUsePackage system;
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = mkPkgs system;
          extraSpecialArgs = {
            inherit claudeDesktopPackage browserUsePackage;
          };
          modules = [ ./home/liangliangdai/home.nix ];
        };
    in
    {
      apps = forAllSystems (
        system:
        let
          homeManagerApp = {
            type = "app";
            program = "${home-manager.packages.${system}.default}/bin/home-manager";
          };
        in
        {
          default = homeManagerApp;
          home-manager = homeManagerApp;
        }
      );

      homeConfigurations = {
        liangliangdai = mkHomeConfiguration "x86_64-linux";
        liangliangdai-x86_64-linux = mkHomeConfiguration "x86_64-linux";
        liangliangdai-aarch64-darwin = mkHomeConfiguration "aarch64-darwin";
        liangliangdai-x86_64-darwin = mkHomeConfiguration "x86_64-darwin";
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          default = pkgs.mkShell {
            packages = [ pkgs.just ];
          };
        }
      );
    };
}
