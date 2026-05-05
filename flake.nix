{
  description = "Home Manager configuration for personal desktop tools and CLI.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      nixpkgs,
      home-manager,
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
      mkHomeConfiguration =
        system:
        home-manager.lib.homeManagerConfiguration {
          pkgs = mkPkgs system;
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
