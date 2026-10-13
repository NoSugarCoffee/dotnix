{
  homeDirectory,
  lib,
  pkgs,
  ...
}:
let
  # Pi user extensions: computer-use (screen/GUI), browser-native (web automation),
  # a2a-adaptor (agent-to-agent calls), provider-kiro (Kiro API model provider,
  # OAuth-authenticated), auto-name (names the Pi session and the containing
  # tmux/herdr/zellij surfaces from the conversation). These are not ordinary
  # packages on PATH; they are Pi agent capabilities installed into
  # ~/.pi/agent/npm/node_modules/ via `pi install`. An activation script ensures
  # they exist after a fresh machine bootstrap, so switching PCs doesn't require
  # manual re-installation.
  piExtensions = [
    "npm:@injaneity/pi-computer-use"
    "npm:pi-agent-browser-native"
    "npm:pi-a2a-adaptor"
    "npm:pi-provider-kiro"
    "npm:@normful/pi-auto-name"
  ];
  # Extension sources that must not linger on the machine, either because they
  # were superseded or because they were dropped outright: machines provisioned
  # before the switch to @injaneity/pi-computer-use still have the unscoped
  # package, remote-pi and pi-mcp-adapter were removed deliberately, and
  # pi-zellij-tab-namer was superseded by @normful/pi-auto-name (it called modelRegistry.getApiKey,
  # removed in current Pi, so it silently never renamed anything). `pi remove`
  # drops them from ~/.pi/agent/settings.json.
  piRemovedExtensions = [
    "npm:pi-computer-use"
    "npm:remote-pi"
    "npm:pi-mcp-adapter"
    "npm:pi-zellij-tab-namer"
  ];
in
{
  home = {
    packages = [ pkgs.pi-coding-agent ];
    # Pi extensions (the sources in piExtensions above) are installed
    # imperatively via `pi install`. On a fresh machine they are missing entirely.
    # This activation checks `pi list` first, installs only the ones that are
    # absent, and removes any sources listed in piRemovedExtensions, so it is a
    # cheap no-op on every-day switches.
    activation.piPackages = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      (
        set +e
        pi="${pkgs.pi-coding-agent}/bin/pi"
        grep="${pkgs.gnugrep}/bin/grep"
        installed=$($pi list 2>/dev/null)
        for ext in ${lib.concatStringsSep " " piExtensions}; do
          if $grep -Fq "$ext" <<< "$installed"; then
            continue
          fi
          $DRY_RUN_CMD "$pi" install "$ext" || echo "warning: piPackages: failed to install $ext" >&2
        done
        # @normful/pi-auto-name 1.1.0 resolves the current zellij tab as the first
        # pane whose numeric id matches ZELLIJ_PANE_ID, without skipping plugin
        # panes. Plugin and terminal pane ids collide (both report the same
        # integer), so a floating plugin pane (e.g. About Zellij) makes it rename
        # the plugin's tab instead of the active one. Skip plugin panes.
        # Idempotent: only rewrites the source while the unpatched form is present,
        # so it re-applies after a `pi update`/reinstall on the next switch.
        surfaces="${homeDirectory}/.pi/agent/npm/node_modules/@normful/pi-auto-name/src/surfaces.ts"
        if [ -f "$surfaces" ] && $grep -Fq 'panes.find((p) => p.id === paneId)' "$surfaces"; then
          $DRY_RUN_CMD "${pkgs.gnused}/bin/sed" -i -e 's/Array<{ id?: number; tab_id?: number }>/Array<{ id?: number; tab_id?: number; is_plugin?: boolean }>/' -e 's/panes\.find((p) => p\.id === paneId)/panes.find((p) => !p.is_plugin \&\& p.id === paneId)/' "$surfaces"
          echo "piPackages: patched pi-auto-name zellij tab lookup (skip plugin panes)"
        fi
        # Prune removed/superseded sources only once every desired extension is
        # present. The install loop swallows failures, so without this guard a
        # transient npm/network error could remove the old source and leave the
        # machine with no computer-use extension at all.
        complete=1
        installed=$($pi list 2>/dev/null)
        for ext in ${lib.concatStringsSep " " piExtensions}; do
          $grep -Fq "$ext" <<< "$installed" || complete=0
        done
        if [ "$complete" = 1 ]; then
          for ext in ${lib.concatStringsSep " " piRemovedExtensions}; do
            if $grep -Fq "$ext" <<< "$installed"; then
              $DRY_RUN_CMD "$pi" remove "$ext" || echo "warning: piPackages: failed to remove $ext" >&2
            fi
          done
        else
          echo "piPackages: not all extensions installed; skipping removal of piRemovedExtensions" >&2
        fi
        true
      )
    '';
    activation.piManagedSettings = lib.hm.dag.entryAfter [ "piPackages" ] ''
      $DRY_RUN_CMD ${pkgs.python3}/bin/python3 ${../../lib/managed_settings.py} \
        --format json --managed ${./managed.json} \
        --mode 644 "$HOME/.pi/agent/settings.json"
    '';
  };
}
