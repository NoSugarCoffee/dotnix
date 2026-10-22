{ lib, pkgs, ... }:
let
  inherit (import ../../lib/proxy.nix) proxyUrl noProxy;
in
{
  # nixpkgs' build on Linux, nur-packages' repack on macOS.
  home.packages =
    lib.filter (lib.meta.availableOn pkgs.stdenv.hostPlatform) [ pkgs.clash-verge-rev ]
    ++ lib.optional (pkgs.nosugarcoffee ? clash-verge-rev) pkgs.nosugarcoffee.clash-verge-rev;
  # The routing policy. The "Merge" override (uid: Merge) is applied to every
  # subscription, after the profile's own rules override, and its `rules:` key
  # replaces that list wholesale — so this file, not the GUI, is the source of
  # truth. The target is a read-only symlink into the store: editing the global
  # override through Clash Verge would fail to save.
  home.file."Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/Merge.yaml".source =
    ./Merge.yaml;
  # Route shell tools through the local Clash Verge proxy (the mixed port in
  # lib/proxy.nix — Clash Verge's own default is 7897, so what it actually
  # listens on has to match this value). Both spellings are set because tools
  # disagree on which they read (curl honors lowercase, some Go/Java tools only
  # uppercase). Reaches terminals via the managed zsh sourcing the session-vars
  # file.
  home.sessionVariables = {
    HTTP_PROXY = proxyUrl;
    HTTPS_PROXY = proxyUrl;
    NO_PROXY = noProxy;
    http_proxy = proxyUrl;
    https_proxy = proxyUrl;
    no_proxy = noProxy;
  };
}
