{ lib, pkgs, ... }:
{
  # Installs zellij; the full config (a dump of the 0.43.1 defaults, kept
  # in ./config.kdl for easy keybinding edits) is written directly as
  # KDL rather than through programs.zellij.settings, whose nix-attrs form
  # can't express the keybinds tree well. On macOS the default
  # OSC52 clipboard escape doesn't reach the system clipboard from every
  # terminal, so selections are piped to pbcopy explicitly; Linux keeps
  # the OSC52 default, which its terminals handle.
  programs.zellij.enable = true;
  xdg.configFile."zellij/config.kdl".text =
    builtins.readFile ./config.kdl
    + lib.optionalString pkgs.stdenv.isDarwin ''
      copy_command "pbcopy"
    '';
}
