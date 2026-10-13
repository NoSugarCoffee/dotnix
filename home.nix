{
  username,
  homeDirectory,
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = lib.mapAttrsToList (name: _: ./apps + "/${name}") (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./apps)
  );
  home = {
    inherit username homeDirectory;
    stateVersion = "25.11";
    sessionPath = [ "${homeDirectory}/.local/bin" ];
  };
  home.activation.copyApps = lib.mkIf config.targets.darwin.copyApps.enable (
    lib.mkForce (
      lib.hm.dag.entryAfter [ "installPackages" "linkGeneration" ] ''
        targetFolder=${lib.escapeShellArg config.targets.darwin.copyApps.directory}
        markerFolder=${lib.escapeShellArg "${config.xdg.stateHome}/home-manager/copied-apps"}
        sourceFolder=${
          pkgs.buildEnv {
            name = "home-manager-applications";
            paths = config.home.packages;
            pathsToLink = [ "/Applications" ];
          }
        }/Applications

        run mkdir -p "$targetFolder" "$markerFolder"

        for entry in "$sourceFolder"/*; do
          name=$(basename "$entry")
          storePath=$(readlink -f "$entry")
          marker="$markerFolder/$name"
          if [[ -d "$targetFolder/$name" && -f "$marker" && "$(< "$marker")" == "$storePath" ]]; then
            continue
          fi
          echo "copying $name..." >&2
          run ${lib.getExe pkgs.rsync} --recursive --checksum --perms --links --copy-unsafe-links \
            --specials --delete --chmod=+w "$storePath/" "$targetFolder/$name"
          [[ -v DRY_RUN ]] || printf '%s' "$storePath" > "$marker"
        done

        for existing in "$targetFolder"/*.app "$markerFolder"/*; do
          name=$(basename "$existing")
          if [[ -e "$existing" && ! -e "$sourceFolder/$name" ]]; then
            echo "removing $name..." >&2
            run rm -rf "$existing"
          fi
        done
      ''
    )
  );
  programs.home-manager.enable = true;
}
