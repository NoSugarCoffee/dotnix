{ lib, pkgs, ... }:
let
  # Claude Code's managed keys share the proxy settings declared in
  # lib/proxy.nix. Its other settings stay machine-owned (see the activation
  # merge below).
  claudeManagedSettings = pkgs.writeText "claude-managed-settings.json" (
    builtins.toJSON (import ./settings.nix { inherit (import ../../lib/proxy.nix) proxyUrl noProxy; })
  );
in
{
  home.packages = [ pkgs.claude-code ];
  home.activation.claudeCodeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.python3}/bin/python3 ${../../lib/managed_settings.py} \
      --format json --managed ${claudeManagedSettings} \
      --mode 644 "$HOME/.claude/settings.json"
  '';
  # Claude Code persists every conversation under ~/.claude/projects; these
  # are just short spellings of the two ways back into one. Not `cc`, which
  # would shadow the C compiler.
  programs.zsh.shellAliases = {
    clc = "claude --continue";
    clr = "claude --resume";
  };
}
