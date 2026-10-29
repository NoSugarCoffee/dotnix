{
  config,
  lib,
  pkgs,
  homeDirectory,
  ...
}:
let
  # The signed release lives in NoSugarCoffee/nur-packages. This module only
  # puts it on PATH, copies the macOS bundle to the path `mcp` relaunches,
  # and registers it with Claude Code.
  cua-driver = pkgs.nosugarcoffee.cua-driver or null;

  # ~/.claude.json is the file `claude mcp add` writes and the file
  # claude-profile syncs (SHARED_KEYS includes mcpServers). settings.json
  # is a different file. Deep merge keeps every other server and the
  # account fields. bounded is intentionally unset: the driver refuses to
  # start in that mode unless CUA_DRIVER_CAPABILITY_MANIFEST_FILE and
  # CUA_DRIVER_CAPABILITY_MANIFEST_APPROVED=1 are set, and on macOS the
  # relaunched app does not inherit this env as its permission mode.
  mcpServers =
    if cua-driver == null then
      null
    else
      pkgs.writeText "claude-cua-driver-mcp.json" (
        builtins.toJSON {
          mcpServers."cua-driver" = {
            type = "stdio";
            command = "${cua-driver}/bin/cua-driver";
            args = [ "mcp" ];
          };
        }
      );
in
{
  home = {
    packages = lib.optional (cua-driver != null) cua-driver;

    file = lib.mkIf (cua-driver != null) {
      # The driver's own skill directory, and the Claude Code link. The
      # Claude link targets the home copy so `cua-driver skills install`
      # sees one pack.
      ".cua-driver/skills/cua-driver".source = cua-driver.skills;
      ".claude/skills/cua-driver".source =
        config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/.cua-driver/skills/cua-driver";
    };

    activation = {
      # A real directory, not a symlink: TCC grants and the relaunch are
      # keyed to /Applications/CuaDriver.app. copyApps would place this
      # bundle under ~/Applications instead, because it has no system
      # extension.
      cuaDriverApp = lib.mkIf (cua-driver != null && pkgs.stdenv.isDarwin) (
        lib.hm.dag.entryAfter [ "installPackages" ] ''
          sourceApp=${lib.escapeShellArg "${cua-driver}/Applications/CuaDriver.app"}
          dest=/Applications/CuaDriver.app
          staging=/Applications/.CuaDriver.app.hm-new
          marker=${lib.escapeShellArg "${config.xdg.stateHome}/home-manager/cua-driver-app-source"}

          if [[ ! -w /Applications ]]; then
            warnEcho "cua-driver: /Applications is not writable, so CuaDriver.app was not copied. mcp relaunches /Applications/CuaDriver.app; grant write access there and switch again."
          elif [[ ! -d "$dest" || "$(readlink "$marker" 2>/dev/null || true)" != "$sourceApp" ]]; then
            $DRY_RUN_CMD mkdir -p "$(dirname "$marker")"
            $DRY_RUN_CMD rm -rf "$staging"
            if ! $DRY_RUN_CMD /usr/bin/ditto "$sourceApp" "$staging"; then
              warnEcho "cua-driver: copying CuaDriver.app to /Applications failed"
            elif ! $DRY_RUN_CMD /usr/bin/codesign --verify --deep --strict "$staging"; then
              warnEcho "cua-driver: copied CuaDriver.app failed signature verification; the previous app was left in place"
              $DRY_RUN_CMD rm -rf "$staging"
            else
              # The running daemon holds the old binary. Replace only when the
              # store path changed, then the next mcp launch starts this build.
              $DRY_RUN_CMD /usr/bin/pkill -x cua-driver || true
              $DRY_RUN_CMD rm -rf "$dest"
              $DRY_RUN_CMD mv "$staging" "$dest"
              $DRY_RUN_CMD ln -sfn "$sourceApp" "$marker"
            fi
          fi
        ''
      );

      cuaDriverMcp = lib.mkIf (cua-driver != null) (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD ${pkgs.python3}/bin/python3 ${../../lib/managed_settings.py} \
            --format json --managed ${mcpServers} \
            --mode 600 "$HOME/.claude.json"
        ''
      );
    };
  };
}
