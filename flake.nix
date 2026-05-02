{
  description = "Personal NixOS + home-manager starter — pinned, modular, batteries-included.";

  ##############################################################################
  # Inputs                                                                       #
  #                                                                              #
  # nixpkgs is pinned to the current stable channel (nixos-25.11). home-manager  #
  # is pinned to the matching release branch and made to follow the same        #
  # nixpkgs so you only have to update one place.                                #
  #                                                                              #
  # `flake-utils` is used to generate per-system devShells/formatter outputs    #
  # for x86_64-linux, aarch64-linux, x86_64-darwin and aarch64-darwin.          #
  ##############################################################################
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # An always-fresh unstable channel for cherry-picking newer packages.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";

    # Optional but very common quality-of-life inputs. Comment out anything
    # you don't want — none of them are required by the example modules.
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  ##############################################################################
  # Outputs                                                                      #
  ##############################################################################
  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      flake-utils,
      treefmt-nix,
      ...
    }:
    let
      # Systems we want to build devShells / formatter / checks for.
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      # Helper: import nixpkgs for a given system with our overlays applied.
      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ (import ./overlays { inherit inputs; }) ];
        };

      # `specialArgs` exposes flake inputs (and an `unstable` package set) to
      # every NixOS / home-manager module so you can reference them without
      # importing inputs everywhere.
      mkSpecialArgs = system: {
        inherit inputs self;
        unstable = import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      };
    in
    # Per-system outputs (devShell, formatter, checks).
    (flake-utils.lib.eachSystem supportedSystems (
      system:
      let
        pkgs = mkPkgs system;
        treefmtEval = treefmt-nix.lib.evalModule pkgs ./nix/treefmt.nix;
      in
      {
        ########################################################################
        # `nix develop` — drops you into a shell with all the tools you'll      #
        # actually use day-to-day on this repo.                                 #
        ########################################################################
        devShells.default = pkgs.mkShell {
          name = "nix-flake-starter";

          packages = with pkgs; [
            # Source pinning (the user explicitly asked for niv).
            niv

            # Formatters / linters / static analysis for Nix.
            nixpkgs-fmt
            nixfmt-rfc-style
            statix
            deadnix
            nil # Nix language server

            # Inspection / debugging.
            nix-tree
            nix-diff
            nix-output-monitor
            nvd

            # Home-manager CLI for standalone usage.
            home-manager.packages.${system}.default

            # General convenience.
            git
            just
            jq
            gnumake
          ];

          shellHook = ''
            echo ""
            echo "  nix-flake-starter devshell"
            echo "  -------------------------"
            echo "  just            # list available tasks"
            echo "  niv             # pin extra non-flake sources"
            echo "  home-manager    # standalone home-manager CLI"
            echo "  statix check .  # lint Nix files"
            echo "  deadnix .       # find unused bindings"
            echo ""
          '';
        };

        ########################################################################
        # `nix fmt` — formats every file in the repo using treefmt.             #
        ########################################################################
        formatter = treefmtEval.config.build.wrapper;

        ########################################################################
        # `nix flake check` — runs treefmt + statix + deadnix.                  #
        ########################################################################
        checks = {
          formatting = treefmtEval.config.build.check self;

          statix = pkgs.runCommand "statix-check" { nativeBuildInputs = [ pkgs.statix ]; } ''
            cp -r ${self} src
            chmod -R +w src
            statix check src
            touch $out
          '';

          deadnix = pkgs.runCommand "deadnix-check" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
            cp -r ${self} src
            chmod -R +w src
            deadnix --fail src
            touch $out
          '';
        };
      }
    ))
    //
      ##########################################################################
      # System-independent outputs: NixOS hosts and standalone home-manager    #
      # users. Add your own under each attribute set.                          #
      ##########################################################################
      {
        ########################################################################
        # NixOS configurations.                                                 #
        # Build & switch with:                                                  #
        #   sudo nixos-rebuild switch --flake .#example-host                    #
        ########################################################################
        nixosConfigurations.example-host = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = mkSpecialArgs "x86_64-linux";
          modules = [
            ./hosts/example-host/configuration.nix

            # Wire home-manager into NixOS so users defined in the host get
            # their home-manager config built and activated as part of
            # `nixos-rebuild switch`.
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = mkSpecialArgs "x86_64-linux";
              home-manager.users.liangliangdai = import ./home/liangliangdai/home.nix;
            }
          ];
        };

        ########################################################################
        # Standalone home-manager configurations (no NixOS required).          #
        # Build & switch with:                                                  #
        #   home-manager switch --flake .#liangliangdai@example-host             #
        ########################################################################
        homeConfigurations."liangliangdai@example-host" = home-manager.lib.homeManagerConfiguration {
          pkgs = mkPkgs "x86_64-linux";
          extraSpecialArgs = mkSpecialArgs "x86_64-linux";
          modules = [ ./home/liangliangdai/home.nix ];
        };

        ########################################################################
        # Re-export modules and overlays so other flakes can consume them.     #
        ########################################################################
        nixosModules = import ./modules/nixos;
        homeManagerModules = import ./modules/home-manager;
        overlays.default = import ./overlays { inherit inputs; };

        # Make this repo usable as a `nix flake init -t` template.
        templates.default = {
          path = ./.;
          description = "Personal NixOS + home-manager starter (pinned, modular, devshell)";
        };
      };
}
