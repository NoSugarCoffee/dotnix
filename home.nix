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

        signingIdentity="dotnix local code signing"
        loginKeychain="$HOME/Library/Keychains/login.keychain-db"

        isAdhocSigned() {
          local signatureInfo
          signatureInfo=$(/usr/bin/codesign -dv "$1" 2>&1) || return 1
          grep -qx 'Signature=adhoc' <<< "$signatureInfo"
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
          if /usr/bin/security find-certificate -c "$signingIdentity" "$loginKeychain" >/dev/null 2>&1; then
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

        run mkdir -p "$targetFolder" "$markerFolder"

        for entry in "$sourceFolder"/*; do
          name=$(basename "$entry")
          storePath=$(readlink -f "$entry")
          marker="$markerFolder/$name"
          storeIsAdhoc=$(isAdhocSigned "$storePath" && echo 1 || echo 0)
          if [[ -d "$targetFolder/$name" && -f "$marker" && "$(< "$marker")" == "$storePath" ]] \
            && ! { (( storeIsAdhoc )) && isAdhocSigned "$targetFolder/$name"; }; then
            continue
          fi
          echo "copying $name..." >&2
          run ${lib.getExe pkgs.rsync} --recursive --checksum --perms --links --copy-unsafe-links \
            --specials --delete --chmod=+w "$storePath/" "$targetFolder/$name"
          if (( storeIsAdhoc )); then
            if [[ -v DRY_RUN ]] || hasLoginKeychain; then
              [[ -v DRY_RUN ]] || ensureSigningIdentity
              echo "re-signing $name with \"$signingIdentity\"..." >&2
              run /usr/bin/codesign --force --sign "$signingIdentity" "$targetFolder/$name"
            else
              echo "warning: no login keychain at $loginKeychain; leaving $name ad-hoc signed (privacy grants may not survive future rebuilds)" >&2
            fi
          fi
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
