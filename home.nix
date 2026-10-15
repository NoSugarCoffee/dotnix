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
        systemFolder=/Applications
        systemMarkerFolder=${lib.escapeShellArg "${config.xdg.stateHome}/home-manager/copied-system-apps"}
        sourceFolder=${
          pkgs.buildEnv {
            name = "home-manager-applications";
            paths = config.home.packages;
            pathsToLink = [ "/Applications" ];
          }
        }/Applications

        signingIdentity="dotnix local code signing"
        loginKeychain="$HOME/Library/Keychains/login.keychain-db"

        isAdhocSigned() {
          local signatureInfo
          signatureInfo=$(/usr/bin/codesign -dv "$1" 2>&1) || return 1
          grep -qx 'Signature=adhoc' <<< "$signatureInfo"
        }

        # macOS only activates a system extension (network, camera, driver,
        # ...) from an app inside /Applications. From anywhere else it is
        # refused -- OBS's virtual camera silently never installs, and
        # Tailscale's standalone app aborts at launch while trying to show
        # its "move to Applications" alert. Such bundles are copied to
        # /Applications instead of $targetFolder, keyed on the bundle itself
        # so a new app that ships one needs no per-app opt-in.
        hasSystemExtension() {
          [[ -d "$1/Contents/Library/SystemExtensions" ]]
        }

        # Ownership of an /Applications copy is bound to the bundle, not the
        # sidecar index. A file inside the bundle would break a notarized
        # seal, so macOS stores a `home-manager.copied` xattr on the .app
        # directory; elsewhere a hidden file stands in for tests.
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

        # Sidecar-only copies from before the bundle sentinel need a one-time
        # adopt. CFBundleIdentifier matching recovers main's Tailscale/OBS
        # installs; a different id is a hand-replace. Same-id hand-replace
        # (website Tailscale over ours) is indistinguishable and gets adopted.
        bundleIdentifier() {
          local app="$1"
          local plist="$app/Contents/Info.plist"
          [[ -f "$plist" ]] || return 1
          if [[ "$(uname -s)" == Darwin ]]; then
            /usr/bin/defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null
          else
            local id
            id=$(sed -n '/<key>CFBundleIdentifier<\/key>/{n;s/.*<string>\([^<]*\)<\/string>.*/\1/p;}' "$plist")
            [[ -n "$id" ]] || return 1
            printf '%s\n' "$id"
          fi
        }

        sameBundleId() {
          local left right
          left=$(bundleIdentifier "$1") || return 1
          right=$(bundleIdentifier "$2") || return 1
          [[ -n "$left" && "$left" == "$right" ]]
        }

        # CI/headless activation runs against a fresh HOME with no login
        # keychain, which `security import` cannot create on its own -- it
        # only fails loudly ("SecKeychainItemImport: The specified keychain
        # could not be found"). A real macOS login session always has one, so
        # this only ever bypasses re-signing off of that session.
        hasLoginKeychain() {
          [[ -f "$loginKeychain" ]]
        }

        ensureSigningIdentity() {
          # find-certificate only confirms a certificate object exists; an
          # "identity" (what codesign actually needs) also requires its
          # matching private key, which find-identity -p codesigning checks.
          if /usr/bin/security find-identity -p codesigning "$loginKeychain" 2>/dev/null \
            | grep -Fq "\"$signingIdentity\""; then
            return
          fi
          echo "creating code signing identity \"$signingIdentity\" in the login keychain..." >&2
          local workDir
          workDir=$(mktemp -d)
          cat > "$workDir/req.cnf" <<CNF
        [req]
        distinguished_name = dn
        prompt = no
        x509_extensions = ext
        [dn]
        CN = $signingIdentity
        [ext]
        basicConstraints = critical,CA:false
        keyUsage = critical,digitalSignature
        extendedKeyUsage = critical,codeSigning
        CNF
          /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 36500 -config "$workDir/req.cnf" \
            -keyout "$workDir/key.pem" -out "$workDir/cert.pem" 2>/dev/null
          /usr/bin/openssl pkcs12 -export -inkey "$workDir/key.pem" -in "$workDir/cert.pem" \
            -out "$workDir/identity.p12" -passout pass:dotnix
          /usr/bin/security import "$workDir/identity.p12" -k "$loginKeychain" -P dotnix -T /usr/bin/codesign
          rm -rf "$workDir"
        }

        # wrapProgram (e.g. Albert's wrapQtApp) moves an app's real executable
        # aside to a hidden ".<name>-wrapped" sibling and writes a wrapper
        # script that `exec`s that sibling by its *absolute* store path. A
        # copy of the bundle still re-execs the immutable store original --
        # carrying the store's own ad-hoc signature, not this copy's -- so the
        # copy's privacy grants would keep breaking on every rebuild exactly
        # like the unwrapped case this function exists to fix. Repoint any
        # such wrapper at this copy and re-sign the real executable it now
        # points to, before the bundle-level codesign below reseals it.
        resignWrappedBinaries() {
          local app="$1" storePath="$2"
          local wrapper hidden
          for wrapper in "$app/Contents/MacOS"/*; do
            [[ -f "$wrapper" && -x "$wrapper" ]] || continue
            [[ "$(head -c 2 -- "$wrapper" 2>/dev/null)" == '#!' ]] || continue
            grep -qF -- "$storePath" "$wrapper" 2>/dev/null || continue
            echo "repointing $(basename "$wrapper") at the copied bundle..." >&2
            run /usr/bin/sed -i ''' "s|$storePath|$app|g" "$wrapper"
            hidden="$(dirname "$wrapper")/.$(basename "$wrapper")-wrapped"
            if [[ -f "$hidden" ]]; then
              echo "re-signing nested $(basename "$hidden") with \"$signingIdentity\"..." >&2
              run /usr/bin/codesign --force --sign "$signingIdentity" "$hidden"
            fi
          done
        }

        run mkdir -p "$targetFolder" "$markerFolder" "$systemMarkerFolder"

        for entry in "$sourceFolder"/*; do
          name=$(basename "$entry")
          storePath=$(readlink -f "$entry")
          appFolder=$targetFolder
          appMarkerFolder=$markerFolder
          staleFolder=$systemFolder
          staleMarkerFolder=$systemMarkerFolder
          # /Applications is shared: never rsync over a bundle we did not
          # put there. Ownership is the bundle sentinel, not the sidecar --
          # a leftover sidecar after a hand-replace must not authorize
          # --delete. A dest we already stamped stays ours so an interrupted
          # copy (rsync then crash before the sidecar) can finish.
          removeStale=1
          if hasSystemExtension "$storePath"; then
            # /Applications is root:admin 0775, so an admin account writes it
            # without sudo; anyone else keeps the old behaviour plus a hint.
            if [[ -w "$systemFolder" ]]; then
              if [[ -e "$systemFolder/$name" ]] && ! hasCopySentinel "$systemFolder/$name"; then
                if [[ -f "$systemMarkerFolder/$name" ]] && sameBundleId "$systemFolder/$name" "$storePath"; then
                  echo "adopting sidecar-only $name in $systemFolder (CFBundleIdentifier matches the store app)..." >&2
                  if [[ -v DRY_RUN ]] || writeCopySentinel "$systemFolder/$name" "$storePath"; then
                    appFolder=$systemFolder
                    appMarkerFolder=$systemMarkerFolder
                    staleFolder=$targetFolder
                    staleMarkerFolder=$markerFolder
                  else
                    echo "warning: failed to stamp $name; leaving it in place and keeping a copy in $targetFolder" >&2
                    # Do not let the default staleFolder=/Applications plus
                    # the leftover sidecar rm -rf the bundle we failed to claim.
                    removeStale=0
                    [[ -v DRY_RUN ]] || rm -f "$systemMarkerFolder/$name"
                  fi
                else
                  echo "warning: $name already exists in $systemFolder and was not placed by home-manager; leaving it in place and keeping a copy in $targetFolder" >&2
                  if [[ -f "$systemMarkerFolder/$name" ]]; then
                    echo "warning: dropping stale home-manager marker for $name (bundle is not owned)" >&2
                    [[ -v DRY_RUN ]] || rm -f "$systemMarkerFolder/$name"
                  fi
                fi
              else
                appFolder=$systemFolder
                appMarkerFolder=$systemMarkerFolder
                staleFolder=$targetFolder
                staleMarkerFolder=$markerFolder
              fi
            else
              echo "warning: $name ships a system extension, which macOS only loads from $systemFolder; that is not writable by $USER, so $name stays in $targetFolder" >&2
            fi
          fi
          marker="$appMarkerFolder/$name"
          storeIsAdhoc=$(isAdhocSigned "$storePath" && echo 1 || echo 0)
          # Without a keychain, re-signing is deferred (see below) and the
          # copy stays ad-hoc every activation -- that alone must not force
          # a full checksum rsync on every run. Only treat "still ad-hoc" as
          # needing a retry once a keychain actually makes retrying useful;
          # dry runs keep previewing the retry regardless, as before.
          if [[ -d "$appFolder/$name" && -f "$marker" && "$(< "$marker")" == "$storePath" ]] \
            && { [[ "$appFolder" != "$systemFolder" ]] || hasCopySentinel "$appFolder/$name"; } \
            && ! { (( storeIsAdhoc )) && isAdhocSigned "$appFolder/$name" \
                   && { [[ -v DRY_RUN ]] || hasLoginKeychain; }; }; then
            :
          else
            echo "copying $name to $appFolder..." >&2
            rsync_ok=1
            if [[ "$appFolder" == "$systemFolder" && ! -v DRY_RUN ]]; then
              # Stamp the dest before rsync so a crash mid-copy is still
              # ours on the next activation. A root-owned bundle (or similar)
              # must not abort the whole activation; fall back to $targetFolder.
              if mkdir -p "$appFolder/$name" && writeCopySentinel "$appFolder/$name" "$storePath"; then
                if ${lib.getExe pkgs.rsync} --recursive --checksum --perms --links --copy-unsafe-links \
                  --specials --delete --chmod=+w --exclude='/.home-manager-copied' \
                  "$storePath/" "$appFolder/$name"; then
                  # Restamp defensively after the copy; we do not pass -X/-A,
                  # but a dest-directory xattr can still be dropped.
                  writeCopySentinel "$appFolder/$name" "$storePath" || rsync_ok=0
                else
                  rsync_ok=0
                fi
              else
                rsync_ok=0
              fi
            else
              run ${lib.getExe pkgs.rsync} --recursive --checksum --perms --links --copy-unsafe-links \
                --specials --delete --chmod=+w --exclude='/.home-manager-copied' \
                "$storePath/" "$appFolder/$name"
            fi
            if (( ! rsync_ok )); then
              echo "warning: failed to copy $name to $systemFolder; falling back to $targetFolder" >&2
              appFolder=$targetFolder
              appMarkerFolder=$markerFolder
              marker="$appMarkerFolder/$name"
              # Leave the /Applications dest (and its sentinel) alone so a
              # later activation can retry; do not treat it as stale.
              removeStale=0
              echo "copying $name to $appFolder..." >&2
              run ${lib.getExe pkgs.rsync} --recursive --checksum --perms --links --copy-unsafe-links \
                --specials --delete --chmod=+w --exclude='/.home-manager-copied' \
                "$storePath/" "$appFolder/$name"
            fi
            # Record the sidecar as soon as the dest is copied so a later
            # resign abort cannot leave a sentinel-only orphan. Cleanup also
            # scans $systemFolder for sentinels in case the sidecar is lost.
            if [[ "$appFolder" == "$systemFolder" && ! -v DRY_RUN ]]; then
              printf '%s' "$storePath" > "$systemMarkerFolder/$name"
            fi
            if (( storeIsAdhoc )); then
              if [[ -v DRY_RUN ]] || hasLoginKeychain; then
                [[ -v DRY_RUN ]] || ensureSigningIdentity
                resignWrappedBinaries "$appFolder/$name" "$storePath"
                echo "re-signing $name with \"$signingIdentity\"..." >&2
                run /usr/bin/codesign --force --sign "$signingIdentity" "$appFolder/$name"
              else
                echo "warning: no login keychain at $loginKeychain; leaving $name ad-hoc signed (privacy grants may not survive future rebuilds)" >&2
              fi
            fi
            [[ -v DRY_RUN ]] || printf '%s' "$storePath" > "$marker"
          fi
          # Drop the other folder's copy only after this folder's copy and
          # marker are in place, so a failed rsync cannot leave the app
          # missing from both locations.
          if (( removeStale )) && [[ -f "$staleMarkerFolder/$name" ]]; then
            echo "removing $name from $staleFolder..." >&2
            run rm -rf "$staleFolder/$name" "$staleMarkerFolder/$name"
          fi
        done

        for existing in "$targetFolder"/*.app "$markerFolder"/*; do
          name=$(basename "$existing")
          if [[ -e "$existing" && ! -e "$sourceFolder/$name" ]]; then
            echo "removing $name..." >&2
            run rm -rf "$existing"
          fi
        done

        # /Applications is shared with everything else on the Mac, so only
        # apps this activation recorded copying there are ever removed.
        for existing in "$systemMarkerFolder"/*; do
          name=$(basename "$existing")
          if [[ -e "$existing" && ! -e "$sourceFolder/$name" ]]; then
            if hasCopySentinel "$systemFolder/$name"; then
              echo "removing $name from $systemFolder..." >&2
              run rm -rf "$systemFolder/$name"
            fi
            run rm -f "$existing"
          fi
        done

        # A crash can leave an owned bundle with no sidecar. The sidecar
        # loop above would miss it; sweep /Applications for our sentinel.
        for app in "$systemFolder"/*.app; do
          [[ -e "$app" ]] || continue
          name=$(basename "$app")
          if hasCopySentinel "$app" && [[ ! -e "$sourceFolder/$name" ]]; then
            echo "removing $name from $systemFolder..." >&2
            run rm -rf "$app"
            run rm -f "$systemMarkerFolder/$name"
          fi
        done
      ''
    )
  );
  programs.home-manager.enable = true;
}
