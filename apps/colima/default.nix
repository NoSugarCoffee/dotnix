{ lib, pkgs, ... }:
let
  inherit (import ../../lib/proxy.nix) proxyUrl noProxy;
in
{
  home.packages = lib.optionals pkgs.stdenv.isDarwin [ pkgs.colima ];
  launchd.agents.colima = {
    enable = pkgs.stdenv.isDarwin;
    config = {
      ProgramArguments = [
        "${pkgs.colima}/bin/colima"
        "start"
      ];
      EnvironmentVariables = {
        PATH = "${pkgs.docker-client}/bin:/usr/bin:/bin";
        HTTP_PROXY = proxyUrl;
        HTTPS_PROXY = proxyUrl;
        NO_PROXY = noProxy;
        http_proxy = proxyUrl;
        https_proxy = proxyUrl;
        no_proxy = noProxy;
      };
      RunAtLoad = true;
      KeepAlive = false;
      ProcessType = "Background";
    };
  };
}
