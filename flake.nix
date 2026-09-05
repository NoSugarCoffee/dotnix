{
  description = "Home Manager configuration for personal desktop tools and CLI.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # For packages not yet in the stable release branch (e.g. macshot).
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";

    claude-desktop = {
      url = "github:k3d3/claude-desktop-linux-flake";
      # Intentionally *not* following our nixpkgs: this flake's build recipe
      # still references `nodePackages.asar`, which nixpkgs removed on
      # 2026-03-03. Letting it use its own pinned (older) nixpkgs keeps the
      # Linux build working at the cost of an extra nixpkgs in the closure.
      inputs.flake-utils.follows = "flake-utils";
    };
  };
  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      claude-desktop,
      ...
    }:
    let
      # Single source of truth for the user this config is applied to.
      # Fork this repo: change just this string. Everything else (attribute
      # names, home.username, homeDirectory, CI env, bootstrap script) reads
      # from here directly or via `nix eval --raw .#username`.
      username = "liangliangdai";

      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = lib.genAttrs systems;
      localPackagesOverlay = final: _prev: {
        clash-verge-rev-darwin = final.callPackage ./pkgs/clash-verge-rev-darwin { };
        claude-desktop-darwin = final.callPackage ./pkgs/claude-desktop-darwin { };
        pulsar-darwin = final.callPackage ./pkgs/pulsar-darwin { };
        ping-island-darwin = final.callPackage ./pkgs/ping-island-darwin { };
        obs-studio-darwin = final.callPackage ./pkgs/obs-studio-darwin { };
        jetbrains-air-darwin = final.callPackage ./pkgs/jetbrains-air-darwin { };
        claude-session-registry = final.callPackage ./pkgs/claude-session-registry { };
        translate-selection = final.callPackage ./pkgs/translate-selection { };
        apm = final.callPackage ./pkgs/apm { };
        agent-access = final.callPackage ./pkgs/agent-access { };
        ccstatusline = final.callPackage ./pkgs/ccstatusline { };
        # from unstable: stable's albert (33.x) predates the source layout
        # pkgs/albert-darwin's patches target (35.x)
        albert-darwin =
          (mkPkgsUnstable final.stdenv.hostPlatform.system).callPackage ./pkgs/albert-darwin
            { };
        # code-cursor from unstable: the stable branch pins 3.5.17, dozens of
        # releases behind upstream, and Cursor nags to update on every launch.
        inherit (mkPkgsUnstable final.stdenv.hostPlatform.system) macshot code-cursor;
        # nixpkgs' undmg leaves AppleDouble sidecars (._Foo) inside the app
        # bundle. Those files are not in the Developer ID seal, so Gatekeeper
        # rejects the bundle with "damaged." Deleting them restores the seal;
        # no re-signing needed.
        scroll-reverser = _prev.scroll-reverser.overrideAttrs (o: {
          postFixup = (o.postFixup or "") + ''
            find "$out/Applications/Scroll Reverser.app" -name '._*' -delete
          '';
        });
      };
      mkPkgsUnstable =
        system:
        import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ localPackagesOverlay ];
        };
      mkHomeConfiguration =
        system:
        let
          isLinux = lib.elem system [
            "x86_64-linux"
            "aarch64-linux"
          ];
          isDarwin = lib.hasSuffix "darwin" system;
          homeDirectory = if isDarwin then "/Users/${username}" else "/home/${username}";
          claudeDesktopPackage =
            if (isLinux && builtins.hasAttr system claude-desktop.packages) then
              claude-desktop.packages.${system}.claude-desktop
            else
              null;
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = mkPkgs system;
          extraSpecialArgs = {
            inherit claudeDesktopPackage username homeDirectory;
          };
          modules = [ ./home/home.nix ];
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

      # Exposed so CI and bootstrap-macos.sh can read the fork's username
      # via `nix eval --raw .#username` instead of duplicating the string.
      inherit username;

      homeConfigurations = {
        ${username} = mkHomeConfiguration "x86_64-linux";
        "${username}-x86_64-linux" = mkHomeConfiguration "x86_64-linux";
        "${username}-aarch64-darwin" = mkHomeConfiguration "aarch64-darwin";
        "${username}-x86_64-darwin" = mkHomeConfiguration "x86_64-darwin";
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
