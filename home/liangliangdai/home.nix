{ claudeDesktopPackage, browserUsePackage, lib, pkgs, ... }:
let
  homeDirectory = if pkgs.stdenv.isDarwin then "/Users/liangliangdai" else "/home/liangliangdai";
in
{
  home = {
    username = "liangliangdai";
    inherit homeDirectory;
    stateVersion = "25.11";
    packages =
      [ pkgs.codex pkgs.claude-code pkgs.asdf-vm pkgs.git pkgs.gh pkgs.glab browserUsePackage ]
      ++ lib.optionals (claudeDesktopPackage != null) [ claudeDesktopPackage ]
      ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.copyq pkgs.ghostty ]
      # ghostty-bin on darwin: the official prebuilt .app bundle; the source
      # ghostty package would compile the whole thing with zig instead.
      ++ lib.optionals pkgs.stdenv.isDarwin [ pkgs.google-chrome pkgs.ghostty-bin ];
    file.".codex/config.toml" = {
      force = true;
      text = ''
        # Managed by home-manager. Authentication is created by `codex login`.

        model = "gpt-5-codex"
        approval_policy = "on-request"
        sandbox_mode = "workspace-write"
        file_opener = "cursor"

        [sandbox_workspace_write]
        network_access = true

        [tui]
        notifications = true

        [history]
        persistence = "save-all"

        [shell_environment_policy]
        inherit = "all"
      '';
    };
  };
  home.activation.codexHomeDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p $HOME/.codex
    $DRY_RUN_CMD chmod 700 $HOME/.codex
  '';
  # Keeps Go/Node/Python/Java at whatever asdf considers "latest" (Java
  # pinned to the Temurin build, since asdf-java's versions are vendor-
  # prefixed rather than plain semver). Re-checks on every switch, so the
  # active toolchain can silently move forward when upstream releases land --
  # that's the point of tracking "latest" rather than a pinned nixpkgs
  # version. Each install is best-effort: a network hiccup or (on a bare
  # Mac without Xcode Command Line Tools) a failed Python source build logs
  # a warning instead of aborting the whole `home-manager switch`.
  #
  # Runs after linkGeneration (not just installPackages) on purpose: these
  # downloads can be slow (a full Python source build, or any of them over a
  # slow connection), and linkGeneration is what actually creates file links
  # like ~/.config/nix/nix.conf and ~/.codex/config.toml. Running asdf first
  # would block those files from existing until the slowest download finishes.
  home.activation.asdfLanguages = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    ( # Subshell: everything in here, including the PATH override, is scoped
      # to this block. Activation steps all run in the same parent shell
      # otherwise, and a later step (linkGeneration) needs the nix-provided
      # bash this script itself is running under -- not macOS's ancient
      # system bash that /usr/bin:/bin would shadow it with if exported here.
      set +e

      export ASDF_DATA_DIR="$HOME/.asdf"
      # Plugin repos are cloned over plain https. A user gitconfig with
      # url.insteadOf rewrites (e.g. https://github.com/ -> git@github.com:)
      # would silently reroute those clones through SSH and fail on any
      # machine whose key isn't registered yet -- activation must not depend
      # on the user's git identity, so user/system git config is masked here.
      export GIT_CONFIG_GLOBAL=/dev/null
      export GIT_CONFIG_SYSTEM=/dev/null
      # asdf's plugin/install scripts shell out to a bunch of ordinary POSIX
      # tools (git, awk, sed, curl, tar, the asdf binary itself, ...). The
      # activation script's own $PATH is a minimal nix-store-only one (it
      # reflects the pre-activation shell, not any profile installPackages
      # just built), so anything these scripts need must be listed
      # explicitly. /usr/bin:/bin is appended as a fallback for macOS-native
      # tools nixpkgs doesn't (and shouldn't) reimplement -- e.g.
      # python-build's use of `sw_vers`, or `shasum` for checksum verification.
      export PATH="${
        lib.makeBinPath [
          pkgs.asdf-vm
          pkgs.git
          pkgs.gawk
          pkgs.gnused
          pkgs.gnugrep
          pkgs.curl
          pkgs.gnutar
          pkgs.gzip
          pkgs.xz
          pkgs.bzip2
          pkgs.unzip
          pkgs.coreutils
          pkgs.which
        ]
      }:/usr/bin:/bin:$PATH"
      asdf="${pkgs.asdf-vm}/bin/asdf"

      install_latest() {
        plugin="$1"
        query="''${2:-}"
        "$asdf" plugin add "$plugin"

        version=$("$asdf" latest "$plugin" "$query") || {
          echo "warning: asdfLanguages: could not resolve latest $plugin $query" >&2
          return
        }

        if ! $DRY_RUN_CMD "$asdf" install "$plugin" "$version"; then
          echo "warning: asdfLanguages: asdf install $plugin $version failed" >&2
          return
        fi
        $DRY_RUN_CMD "$asdf" global "$plugin" "$version"
      }

      install_latest golang
      install_latest nodejs
      install_latest python
      install_latest java temurin

      # The Lark/Feishu CLI is an npm package with no nixpkgs derivation, so
      # it rides on the asdf-managed Node: npm puts the binary inside the
      # active Node version and `asdf reshim` exposes it via ~/.asdf/shims
      # (already on PATH). Same tracking-latest, best-effort model as above.
      npm="$ASDF_DATA_DIR/shims/npm"
      if [ -x "$npm" ]; then
        # --allow-scripts: npm >= 11.19 blocks postinstall scripts of global
        # installs by default, and this package needs its postinstall step.
        $DRY_RUN_CMD "$npm" install --global --allow-scripts=@larksuite/cli @larksuite/cli \
          && $DRY_RUN_CMD "$asdf" reshim nodejs \
          || echo "warning: asdfLanguages: npm install @larksuite/cli failed" >&2
      else
        echo "warning: asdfLanguages: npm shim missing, skipping @larksuite/cli" >&2
      fi
      true # this subshell's own exit status must always be 0
    )
  '';
  # asdf itself comes from home.packages; this exposes the shims it installs
  # into (~/.asdf/shims) so `go`/`node`/`python`/`java` resolve without
  # extra shell config.
  home.sessionPath = [ "${homeDirectory}/.asdf/shims" ];
  programs.home-manager.enable = true;
}
