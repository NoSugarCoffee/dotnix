{ pkgs, ... }:
{
  # The macOS app includes its own CLI and sets up the VPN extension on first launch.
  # Linux needs a system-level tailscaled service, managed by the host OS.
  home.packages = if pkgs.stdenv.isDarwin then [ pkgs.tailscale-gui ] else [ pkgs.tailscale ];
}
