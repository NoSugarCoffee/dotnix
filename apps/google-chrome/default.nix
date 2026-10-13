{
  config,
  lib,
  pkgs,
  homeDirectory,
  ...
}:
{
  home.packages = lib.optionals pkgs.stdenv.isDarwin [ pkgs.google-chrome ];
  home.file."Applications/Google Chrome.app" = lib.mkIf pkgs.stdenv.isDarwin {
    source = config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/${config.targets.darwin.copyApps.directory}/Google Chrome.app";
  };
}
