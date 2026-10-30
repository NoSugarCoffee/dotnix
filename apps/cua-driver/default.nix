{
  config,
  lib,
  pkgs,
  homeDirectory,
  ...
}:
let
  # The signed release lives in NoSugarCoffee/nur-packages. This module only
  # puts the CLI on PATH and copies the macOS bundle to the path `mcp`
  # relaunches. Claude Code's MCP server list is owned by dotai (APM), not
  # by a switch.
  cua-driver = pkgs.nosugarcoffee.cua-driver or null;

  # The package also ships $out/Applications/CuaDriver.app. home.packages
  # feeds copyApps, which links every package's /Applications into
  # ~/Applications/Home Manager Apps. This nixpkgs buildEnv lndirs the
  # whole package and does not honor pathsToLink, so a symlinkJoin would
  # still expose the bundle. Link only the CLI. The wrapper script execs
  # the store bundle or /Applications/CuaDriver.app by absolute path.
  cuaDriverBin =
    if cua-driver == null then
      null
    else
      pkgs.runCommand "cua-driver" { } ''
        mkdir -p "$out/bin"
        ln -s "${cua-driver}/bin/cua-driver" "$out/bin/cua-driver"
      '';
in
{
  home = {
    packages = lib.optional (cuaDriverBin != null) cuaDriverBin;

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
      # keyed to /Applications/CuaDriver.app. Ownership matches copyApps:
      # `home-manager.copied` on the bundle directory. A bundle without
      # that stamp (the upstream installer) is left alone.
      cuaDriverApp = lib.mkIf (cua-driver != null && pkgs.stdenv.isDarwin) (
        lib.hm.dag.entryAfter [ "copyApps" ] ''
          sourceApp=${lib.escapeShellArg "${cua-driver}/Applications/CuaDriver.app"}
          dest=/Applications/CuaDriver.app
          destParent=$(dirname "$dest")
          staging="$destParent/.CuaDriver.app.hm-new"
          marker=${lib.escapeShellArg "${config.xdg.stateHome}/home-manager/cua-driver-app-source"}

          # Same sentinel as copyApps in home.nix. An xattr on the .app
          # directory, not a file inside the bundle (that would break the
          # signature). The hidden file is the non-Darwin stand-in.
          copySentinelAttr=home-manager.copied
          copySentinelFile=.home-manager-copied

          hasCopySentinel() {
            local app="$1"
            if [[ "$(uname -s)" == Darwin ]]; then
              /usr/bin/xattr -p "$copySentinelAttr" "$app" >/dev/null 2>&1
            else
              [[ -f "$app/$copySentinelFile" ]]
            fi
          }

          writeCopySentinel() {
            local app="$1" value="$2"
            if [[ "$(uname -s)" == Darwin ]]; then
              /usr/bin/xattr -w "$copySentinelAttr" "$value" "$app"
            else
              printf '%s' "$value" > "$app/$copySentinelFile"
            fi
          }

          if [[ ! -w "$destParent" ]]; then
            warnEcho "cua-driver: $destParent is not writable, so CuaDriver.app was not copied. mcp relaunches /Applications/CuaDriver.app; grant write access there and switch again."
          elif [[ -e "$dest" ]] && ! hasCopySentinel "$dest"; then
            warnEcho "cua-driver: $dest already exists and was not placed by home-manager; leaving it in place"
          elif [[ -d "$dest" && "$(readlink "$marker" 2>/dev/null || true)" == "$sourceApp" ]]; then
            :
          elif [[ -v DRY_RUN ]]; then
            echo "would copy $sourceApp to $dest" >&2
          else
            $DRY_RUN_CMD mkdir -p "$(dirname "$marker")"
            $DRY_RUN_CMD rm -rf "$staging"
            # The store bundle is mode 555. ditto keeps that, and xattr/rm then
            # fail on the staged copy (macOS CI aborted the whole switch).
            # Owner can chmod a 555 tree; the signature hashes contents, not mode.
            if ! $DRY_RUN_CMD /usr/bin/ditto "$sourceApp" "$staging"; then
              warnEcho "cua-driver: copying CuaDriver.app to $destParent failed"
            elif ! $DRY_RUN_CMD /bin/chmod -R u+w "$staging"; then
              warnEcho "cua-driver: could not make the staged CuaDriver.app writable"
              $DRY_RUN_CMD rm -rf "$staging" || warnEcho "cua-driver: could not remove $staging"
            elif ! $DRY_RUN_CMD /usr/bin/codesign --verify --deep --strict "$staging"; then
              warnEcho "cua-driver: copied CuaDriver.app failed signature verification; the previous app was left in place"
              $DRY_RUN_CMD rm -rf "$staging" || warnEcho "cua-driver: could not remove $staging"
            elif ! writeCopySentinel "$staging" "$sourceApp"; then
              warnEcho "cua-driver: failed to stamp CuaDriver.app; leaving the previous app in place"
              $DRY_RUN_CMD rm -rf "$staging" || warnEcho "cua-driver: could not remove $staging"
            else
              # Only reached when $dest is missing or already stamped.
              # The running daemon holds the old binary.
              if [[ -d "$dest" ]]; then
                $DRY_RUN_CMD /usr/bin/pkill -x cua-driver || true
                $DRY_RUN_CMD rm -rf "$dest"
              fi
              $DRY_RUN_CMD mv "$staging" "$dest"
              writeCopySentinel "$dest" "$sourceApp"
              $DRY_RUN_CMD ln -sfn "$sourceApp" "$marker"
            fi
          fi
        ''
      );
    };
  };
}
