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
  # Scoped to exactly aarch64-darwin, not pkgs.stdenv.isDarwin: nixpkgs
  # (nixos-26.05, this flake's pin) lists bitwarden-desktop's meta.platforms
  # for both darwin architectures (and both Linux ones this flake also
  # builds for), so neither isDarwin nor availableOn alone narrows it down
  # to this macOS setup's one actual target. The exact-system check is what
  # keeps it off x86_64-darwin and Linux; availableOn stays as a guard in
  # case upstream ever drops aarch64-darwin support instead.
  home.packages = lib.optionals (pkgs.stdenv.hostPlatform.system == "aarch64-darwin") (
    lib.filter (lib.meta.availableOn pkgs.stdenv.hostPlatform) [ pkgs.bitwarden-desktop ]
  );
}
