{ pkgs, ... }:
{
  # Provides the `cursor` CLI that ~/.codex/config.toml's file_opener uses.
  home.packages = [ pkgs.code-cursor ];
}
