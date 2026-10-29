{
  config,
  lib,
  pkgs,
  homeDirectory,
  ...
}:
let
  # Pinned signed release of the MIT driver (libs/cua-driver). The upstream
  # flake builds that crate from source for Linux only and publishes no
  # Darwin package and no binary cache, so every system here uses the
  # release archive the upstream installer installs. Cua Spaces (FSL) and
  # the optional perception extension are not in these archives and are
  # not installed. The pin lives next to the /Applications copy below:
  # `cua-driver mcp` relaunches exactly /Applications/CuaDriver.app.
  version = "0.38.0";
  tag = "cua-driver-rs-v${version}";

  sources = {
    aarch64-darwin = {
      label = "darwin-arm64";
      hash = "sha256-X3EZHAgsoHyd/BO3yabuxgqCgYwkWpNTTMDreRFHHXI=";
    };
    x86_64-darwin = {
      label = "darwin-x86_64";
      hash = "sha256-aHIakW8tmyAjOhRiPg9mPK9hMLqQGEZaV6F4Eg2WvE4=";
    };
    x86_64-linux = {
      label = "linux-x86_64";
      hash = "sha256-owXL1TH5TWQTxdswDDPfaOOtvouSuWBM+OZFxfbLH6M=";
    };
  };
  source = sources.${pkgs.stdenv.hostPlatform.system} or null;

  skills = pkgs.fetchurl {
    url = "https://github.com/trycua/cua/releases/download/${tag}/${tag}-skills.tar.gz";
    hash = "sha256-D+PWB+chLWxYByokGRYzQgYdz1y4m6EkPepZPX4zvg8=";
  };
  # `cua-driver skills install` keeps the host platform's guide and drops
  # the other two. SKILL.md still links the kept file.
  excludedSkillDocs =
    if pkgs.stdenv.isDarwin then
      [
        "WINDOWS.md"
        "LINUX.md"
      ]
    else
      [
        "WINDOWS.md"
        "MACOS.md"
      ];

  installSkills = ''
    mkdir -p "$out/share/cua-driver/skill"
    tar -xzf ${skills} -C "$out/share/cua-driver/skill" --strip-components=1
    rm -f ${lib.concatMapStringsSep " " (name: "$out/share/cua-driver/skill/${name}") excludedSkillDocs}
  '';

  cua-driver =
    if source == null then
      null
    else if pkgs.stdenv.isDarwin then
      pkgs.stdenv.mkDerivation {
        pname = "cua-driver";
        inherit version;

        src = pkgs.fetchurl {
          url = "https://github.com/trycua/cua/releases/download/${tag}/cua-driver-rs-${version}-${source.label}.tar.gz";
          inherit (source) hash;
        };
        sourceRoot = "cua-driver-rs-${version}-${source.label}";

        # The Developer ID signature has to survive into /Applications.
        # Fixup would rewrite the Mach-O and invalidate it.
        dontBuild = true;
        dontFixup = true;

        installPhase = ''
          runHook preInstall
          mkdir -p "$out/libexec" "$out/bin"
          cp -a CuaDriver.app "$out/libexec/CuaDriver.app"
          # PATH entry. `mcp` relaunches /Applications/CuaDriver.app when
          # that copy exists; the store bundle is the fallback for
          # --version before the copy, and for a switch that could not
          # write /Applications.
          cat > "$out/bin/cua-driver" <<EOF
          #!/bin/sh
          installed=/Applications/CuaDriver.app/Contents/MacOS/cua-driver
          bundled=$out/libexec/CuaDriver.app/Contents/MacOS/cua-driver
          if [ -x "\$installed" ]; then
            exec "\$installed" "\$@"
          fi
          exec "\$bundled" "\$@"
          EOF
          chmod 755 "$out/bin/cua-driver"
          ${installSkills}
          runHook postInstall
        '';

        meta = {
          description = "Computer-use MCP server and CLI";
          homepage = "https://github.com/trycua/cua";
          license = lib.licenses.mit;
          mainProgram = "cua-driver";
          platforms = [
            "aarch64-darwin"
            "x86_64-darwin"
          ];
          sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
        };
      }
    else
      pkgs.stdenv.mkDerivation {
        pname = "cua-driver";
        inherit version;

        src = pkgs.fetchurl {
          url = "https://github.com/trycua/cua/releases/download/${tag}/cua-driver-rs-${version}-${source.label}.tar.gz";
          inherit (source) hash;
        };
        sourceRoot = "cua-driver-rs-${version}-${source.label}";

        nativeBuildInputs = [
          pkgs.autoPatchelfHook
          pkgs.makeWrapper
        ];
        buildInputs = [
          pkgs.xorg.libX11
          pkgs.xorg.libXi
          pkgs.libxkbcommon
          pkgs.stdenv.cc.cc.lib
        ];

        dontBuild = true;

        # Only cua-driver is linked onto PATH. cua-cursor-theme stays beside
        # the binary; ImageMagick's import is on that process's PATH because
        # window capture shells out to it. The SDK, Node addon, and Wayland
        # helper from the same archive are left unpacked and unused.
        installPhase = ''
          runHook preInstall
          mkdir -p "$out/libexec/cua-driver" "$out/bin"
          install -m 755 cua-driver cua-cursor-theme "$out/libexec/cua-driver/"
          makeWrapper "$out/libexec/cua-driver/cua-driver" "$out/bin/cua-driver" \
            --prefix PATH : "$out/libexec/cua-driver:${lib.makeBinPath [ pkgs.imagemagick ]}"
          ${installSkills}
          runHook postInstall
        '';

        meta = {
          description = "Computer-use MCP server and CLI";
          homepage = "https://github.com/trycua/cua";
          license = lib.licenses.mit;
          mainProgram = "cua-driver";
          platforms = [ "x86_64-linux" ];
          sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
        };
      };

  # ~/.claude.json is the file `claude mcp add` writes and the file
  # claude-profile syncs (SHARED_KEYS includes mcpServers). settings.json
  # is a different file. Deep merge keeps every other server and the
  # account fields. bounded is intentionally unset: the driver refuses to
  # start in that mode unless CUA_DRIVER_CAPABILITY_MANIFEST_FILE and
  # CUA_DRIVER_CAPABILITY_MANIFEST_APPROVED=1 are set, and on macOS the
  # relaunched app does not inherit this env as its permission mode.
  mcpServers = pkgs.writeText "claude-cua-driver-mcp.json" (
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
      ".cua-driver/skills/cua-driver".source = "${cua-driver}/share/cua-driver/skill";
      ".claude/skills/cua-driver".source =
        config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/.cua-driver/skills/cua-driver";
    };

    activation = {
      cuaDriverApp = lib.mkIf (cua-driver != null && pkgs.stdenv.isDarwin) (
        lib.hm.dag.entryAfter [ "installPackages" ] ''
          sourceApp=${lib.escapeShellArg "${cua-driver}/libexec/CuaDriver.app"}
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
