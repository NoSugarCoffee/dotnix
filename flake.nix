{
  description = "Home Manager configuration that installs Codex CLI.";

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
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      homeManagerApp = {
        type = "app";
        program = "${home-manager.packages.${system}.default}/bin/home-manager";
      };
    in
    {
      apps.${system} = {
        default = homeManagerApp;
        home-manager = homeManagerApp;
      };

      homeConfigurations.liangliangdai = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home/liangliangdai/home.nix ];
      };
    };
}
