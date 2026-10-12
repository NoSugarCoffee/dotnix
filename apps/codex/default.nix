{ lib, pkgs, ... }:
{
  home.packages = [ pkgs.codex ];
  # Codex and Claude Code both write their own settings files (trust
  # decisions, /config, plugin toggles), so neither can be a store symlink.
  # managed_settings.py seeds the file on a fresh machine and resets only the
  # declared keys on every switch; everything else stays machine-owned.
  # Ordered after linkGeneration so an old store symlink is already gone.
  home.activation.codexManagedSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    $DRY_RUN_CMD mkdir -p $HOME/.codex
    $DRY_RUN_CMD chmod 700 $HOME/.codex
    $DRY_RUN_CMD ${pkgs.python3}/bin/python3 ${../../lib/managed_settings.py} \
      --format toml --managed ${./managed.toml} --seed ${./config.toml} \
      --mode 600 "$HOME/.codex/config.toml"
  '';
}
