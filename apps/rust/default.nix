{ pkgs, ... }:
{
  # Rust comes prebuilt from nixpkgs rather than rustup or asdf, for the same
  # reason as Python: nothing is downloaded or compiled during activation, and
  # every tool in the toolchain is the same release. rust-analyzer needs the
  # standard library's source to resolve `std`; nixpkgs ships it separately, so
  # point RUST_SRC_PATH at it instead of letting rust-analyzer look for a
  # rustup sysroot that doesn't exist.
  home = {
    packages = with pkgs; [
      rustc
      cargo
      rust-analyzer
      clippy
      rustfmt
    ];
    sessionVariables.RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
  };
}
