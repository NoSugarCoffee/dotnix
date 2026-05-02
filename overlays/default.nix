# Overlays added on top of nixpkgs for this flake.
#
# Add your own package overrides or fetch packages from `unstable` here.
# Example:
#
#   final: prev: {
#     myCustomTool = final.callPackage ../pkgs/my-custom-tool { };
#     # Pull a single package from nixpkgs-unstable:
#     neovim = inputs.nixpkgs-unstable.legacyPackages.${prev.system}.neovim;
#   }
{ inputs, ... }:
final: prev: {
  # Example: a no-op overlay. Replace with your own overrides.
}
