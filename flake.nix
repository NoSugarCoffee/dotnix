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
    # carries late (apm, ccstatusline, claude-desktop, grok-bot, orca, paperclip).
    # Intentionally *not* following our nixpkgs: its packages are built
    # against its own nixpkgs-unstable pin and cached on cache.numtide.com,
    # which only hits when the revisions match.
    llm-agents.url = "github:numtide/llm-agents.nix";

    # Our own packages that nixpkgs lacks or ships Linux-only (mostly macOS
    # app repacks), kept current upstream 4x daily and cached on
    # nosugarcoffee.cachix.org. Not following our nixpkgs, for the same
    # reason as llm-agents: the cache only hits on its own pin.
    # Temporary pin of NoSugarCoffee/nur-packages#12 (cua-driver). After that
    # PR merges, point this back at github:NoSugarCoffee/nur-packages and run
    # `nix flake update nur-packages`.
    nur-packages.url = "github:NoSugarCoffee/nur-packages/cursor/cua-driver-5d29";
  };
  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      pi,
      llm-agents,
      nur-packages,
      ...
    }:
    let
      # Single source of truth for the account this config is applied to.
      # Fork this repo: change just this string.
      #
      # This is the default for checkouts, CI and `just`. A new machine never
      # has to change it: `scripts/bootstrap-macos.sh` rewrites this very line
      # to the machine's $USER in a throwaway copy of the source. Keep it on
      # ONE line -- that rewrite is line-level.
      username = "liangliangdai";

      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = lib.genAttrs systems;
      extraPackagesOverlay = final: prev: {
        # NoSugarCoffee/nur-packages under its own namespace, prebuilt for
        # the systems it ships. nixpkgs-unstable dropped x86_64-darwin, so
        # there its overlay builds them against our 26.05 instead (the pins
        # keep their Intel hashes); either way only what the system supports.
        nosugarcoffee =
          nur-packages.packages.${final.stdenv.hostPlatform.system}
            or (lib.filterAttrs (
              _: lib.meta.availableOn final.stdenv.hostPlatform
            ) (nur-packages.overlays.default final prev).nosugarcoffee);
        # code-cursor from unstable: the stable branch pins 3.5.17, dozens of
        # releases behind upstream, and Cursor nags to update on every launch.
        inherit (mkPkgsUnstable final.stdenv.hostPlatform.system)
          macshot
          code-cursor
          codex
          ;
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
            extraPackagesOverlay
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
          # Skip names the selected system does not ship instead of vendoring
          # our own.
          llmAgentsPackages = lib.optionals (llm-agents.packages ? ${system}) (
            lib.attrVals (lib.filter (name: llm-agents.packages.${system} ? ${name}) [
              "apm"
              "ccstatusline"
              "claude-code"
              "claude-desktop"
              "grok-bot"
              "orca"
              "paperclip"
            ]) llm-agents.packages.${system}
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
          modules = [ ./home.nix ];
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
