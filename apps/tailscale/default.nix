{ pkgs, lib, ... }:
let
  # The app's CLI finds its bundle identifier through the path it was invoked by; run from the
  # symlink in bin/ it finds no Info.plist and aborts, so exec it from inside the bundle.
  darwinCli = lib.hiPrio (
    pkgs.writeShellScriptBin "tailscale" ''
      exec "${pkgs.tailscale-gui}/Applications/Tailscale.app/Contents/MacOS/Tailscale" "$@"
    ''
  );
in
{
  # The macOS app includes its own CLI and sets up the VPN extension on first launch.
  # Linux needs a system-level tailscaled service, managed by the host OS.
  home.packages =
    if pkgs.stdenv.isDarwin then
      [
        pkgs.tailscale-gui
        darwinCli
      ]
    else
      [ pkgs.tailscale ];
}
