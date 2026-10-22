{ lib, pkgs, ... }:
let
  inherit (import ../../lib/proxy.nix) proxyUrl noProxy;
  # Clash Verge Rev APP_ID (src-tauri/src/utils/dirs.rs). app_home_dir() is
  # dirs::data_dir()/APP_ID: ~/Library/Application Support/<id> on macOS,
  # $XDG_DATA_HOME/<id> (usually ~/.local/share/<id>) on Linux. Confirmed in
  # the official privacy docs and Linux issues that name profiles/Merge.yaml.
  clashAppId = "io.github.clash-verge-rev.clash-verge-rev";
  mergeFile = {
    source = ./Merge.yaml;
    # Clash Verge creates profiles/Merge.yaml itself. This repo does not set
    # backupFileExtension and `just switch` does not pass -b, so without force
    # checkLinkTargets refuses to clobber the existing unmanaged file.
    force = true;
  };
in
{
  home = {
    # nixpkgs' build on Linux, nur-packages' repack on macOS.
    packages =
      lib.filter (lib.meta.availableOn pkgs.stdenv.hostPlatform) [ pkgs.clash-verge-rev ]
      ++ lib.optional (pkgs.nosugarcoffee ? clash-verge-rev) pkgs.nosugarcoffee.clash-verge-rev;
    # The routing policy. Clash Verge applies the global Merge (uid: Merge)
    # after the per-profile seq items, and its `rules:` replaces that list
    # wholesale. A per-profile Merge item or Script runs after the global
    # Merge, so a subscription that has its own `rules:` would override this
    # policy. The target is a read-only symlink into the store: editing the
    # global override through Clash Verge would fail to save.
    file."Library/Application Support/${clashAppId}/profiles/Merge.yaml" =
      lib.mkIf pkgs.stdenv.isDarwin mergeFile;
    # Route shell tools through the local Clash Verge proxy (the mixed port in
    # lib/proxy.nix — Clash Verge's own default is 7897, so what it actually
    # listens on has to match this value). Both spellings are set because tools
    # disagree on which they read (curl honors lowercase, some Go/Java tools only
    # uppercase). Reaches terminals via the managed zsh sourcing the session-vars
    # file.
    sessionVariables = {
      HTTP_PROXY = proxyUrl;
      HTTPS_PROXY = proxyUrl;
      NO_PROXY = noProxy;
      http_proxy = proxyUrl;
      https_proxy = proxyUrl;
      no_proxy = noProxy;
    };
  };
  xdg.dataFile."${clashAppId}/profiles/Merge.yaml" = lib.mkIf pkgs.stdenv.isLinux mergeFile;
}
