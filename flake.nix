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

    pi = {
      url = "github:lukasl-dev/pi.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Source of prebuilt AI-agent packages that nixpkgs doesn't carry or
    # carries late (apm, ccstatusline, claude-desktop, orca, paperclip).
    # Intentionally *not* following our nixpkgs: its packages are built
    # against its own nixpkgs-unstable pin and cached on cache.numtide.com,
    # which only hits when the revisions match.
    llm-agents.url = "github:numtide/llm-agents.nix";
  };
  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      pi,
      llm-agents,
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
        pulsar-darwin = final.callPackage ./pkgs/pulsar-darwin { };
        obs-studio-darwin = final.callPackage ./pkgs/obs-studio-darwin { };
        jetbrains-air-darwin = final.callPackage ./pkgs/jetbrains-air-darwin { };
        ego-lite-darwin = final.callPackage ./pkgs/ego-lite-darwin { };
        agent-access = final.callPackage ./pkgs/agent-access { };
        cida-darwin = final.callPackage ./pkgs/cida-darwin { };
        # from unstable: stable's albert (33.x) predates the source layout
        # pkgs/albert-darwin's patches target (35.x)
        albert-darwin =
          (mkPkgsUnstable final.stdenv.hostPlatform.system).callPackage ./pkgs/albert-darwin
            { };
        # code-cursor from unstable: the stable branch pins 3.5.17, dozens of
        # releases behind upstream, and Cursor nags to update on every launch.
        inherit (mkPkgsUnstable final.stdenv.hostPlatform.system)
          macshot
          code-cursor
          claude-code
          codex
          chatgpt
          ;
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
          overlays = [
            localPackagesOverlay
            pi.overlays.default
          ];
        };
      mkHomeConfiguration =
        system:
        let
          isDarwin = lib.hasSuffix "darwin" system;
          homeDirectory = if isDarwin then "/Users/${username}" else "/home/${username}";
          # llm-agents.nix only builds for x86_64-linux, aarch64-linux and
          # aarch64-darwin; on x86_64-darwin it has no packages at all.
          llmAgentsPackages = lib.optionals (llm-agents.packages ? ${system}) (
            lib.attrVals [
              "apm"
              "ccstatusline"
              "claude-desktop"
              "orca"
              "paperclip"
            ] llm-agents.packages.${system}
          );
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = mkPkgs system;
          extraSpecialArgs = {
            inherit
              llmAgentsPackages
              username
              homeDirectory
              ;
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
