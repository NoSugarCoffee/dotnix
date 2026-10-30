{ lib, pkgs, ... }:
let
  cli = pkgs.nosugarcoffee._1password-cli or pkgs._1password-cli;
  gui = pkgs.nosugarcoffee._1password-gui or null;
in
{
  # The CLI's desktop-app integration and service accounts both work with
  # nur-packages' signed `op`; nixpkgs' lags several releases behind.
  home.packages = [ cli ] ++ lib.optional (pkgs.stdenv.isDarwin && gui != null) gui;

  # 1Password refuses to start outside /Applications ("not installed inside
  # of /Applications") and ships no system extension that copyApps could key on.
  dotnix.darwin.systemFolderApps = lib.optional pkgs.stdenv.isDarwin "1Password.app";
}
