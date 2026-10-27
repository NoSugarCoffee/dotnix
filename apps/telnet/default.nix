{ pkgs, ... }:
{
  # GNU inetutils provides the telnet client on macOS and Linux.
  home.packages = [ pkgs.inetutils ];
}
