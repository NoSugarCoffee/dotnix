{ lib, pkgs, ... }:
let
  inherit (import ../../lib/proxy.nix) proxyUrl noProxy;
in
{
  # nixpkgs' build on Linux, nur-packages' repack on macOS.
  home.packages =
    lib.filter (lib.meta.availableOn pkgs.stdenv.hostPlatform) [ pkgs.clash-verge-rev ]
    ++ lib.optional (pkgs.nosugarcoffee ? clash-verge-rev) pkgs.nosugarcoffee.clash-verge-rev;
  # Route shell tools through the local Clash Verge proxy (default mixed
  # port 7890). Both spellings are set because tools disagree on which
  # they read (curl honors lowercase, some Go/Java tools only uppercase).
  # Reaches terminals via the managed zsh sourcing the session-vars file.
  home.sessionVariables = {
    HTTP_PROXY = proxyUrl;
    HTTPS_PROXY = proxyUrl;
    NO_PROXY = noProxy;
    http_proxy = proxyUrl;
    https_proxy = proxyUrl;
    no_proxy = noProxy;
  };
}
