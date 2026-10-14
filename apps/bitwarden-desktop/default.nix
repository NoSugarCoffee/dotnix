{ lib, pkgs, ... }:
{
  # nixpkgs' bitwarden-desktop builds the Electron app from source (its
  # darwin build sets electron-builder's `mac.identity` to null and patches
  # out the after-pack/after-sign steps, then ad-hoc signs the result with
  # darwin.autoSignDarwinBinariesHook) rather than repackaging the vendor's
  # notarized DMG, so it is already ad-hoc signed exactly like kitty and
  # Albert -- no custom package.nix or Homebrew cask needed, and it is left
  # to copyApps' existing re-sign-on-copy logic the same way.
  #
  # Scoped to darwin: upstream meta.platforms also lists the Linux systems
  # this flake builds for, but the GUI app isn't wanted there, only on this
  # macOS setup. availableOn still gates x86_64-darwin, which upstream
  # doesn't list (no aarch64-only native dependency has an x86_64-darwin
  # build), so this follows platform support instead of hardcoding a system.
  home.packages = lib.optionals pkgs.stdenv.isDarwin (
    lib.filter (lib.meta.availableOn pkgs.stdenv.hostPlatform) [ pkgs.bitwarden-desktop ]
  );
}
