{ lib, pkgs, ... }:
{
  home.packages = [ pkgs.nix-zsh-completions ];
  # home.sessionPath / sessionVariables only reach a real terminal if the
  # shell sources home-manager's session-vars file; a stock macOS zsh never
  # does, leaving the asdf shims silently off PATH. Managing zsh makes the
  # generated ~/.zshrc do that sourcing. A pre-existing hand-written
  # ~/.zshrc must be moved aside once (home-manager refuses to overwrite);
  # fold its content into programs.zsh.initContent if it should be kept.
  programs.zsh = {
    enable = true;
    syntaxHighlighting.enable = true;
    autosuggestion.enable = true;
    # Option+Left/Right jump by word. kitty's macos_option_as_alt makes
    # Option send Alt, which arrives as CSI 1;3 arrow sequences; zsh only
    # binds Alt-b/Alt-f out of the box. zellij is configured to pass
    # Alt+Left/Right through (see apps/zellij/config.kdl).
    initContent = lib.mkMerge [
      ''
        bindkey "^[[1;3D" backward-word
        bindkey "^[[1;3C" forward-word
      ''
      # Escape hatch for shell config that must not reach a public repo
      # (employer hostnames, internal registries, credentials) or that is
      # machine-specific. Sourced at mkOrder 1500 -- after everything this
      # module declares -- so a local definition wins, and guarded so a
      # machine without the file still gets a working shell.
      (lib.mkOrder 1500 ''
        [ -f "$HOME/.zshrc-local" ] && . "$HOME/.zshrc-local"
      '')
    ];
  };
}
