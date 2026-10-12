{
  homeDirectory,
  lib,
  pkgs,
  ...
}:
let
  # Referenced by both the asdf pin and the @larksuite/cli paths below, which
  # must agree on one Node tree.
  nodeVersion = "26.7.0";
in
{
  home = {
    packages = [ pkgs.asdf-vm ];
    # Keeps Go/Node at whatever asdf considers "latest"; Java is pinned to
    # explicit Temurin builds instead, because the JVM ecosystem is picky about
    # majors and silent drift onto a new major (or from JDK to JRE) breaks
    # projects here. Re-checks on every switch, so Go/Node can silently move
    # forward when upstream releases land -- that's the point of tracking
    # "latest" rather than a pinned nixpkgs version. Each install is
    # best-effort: a network hiccup or (on a bare Mac without Xcode Command
    # Line Tools) a failed Python source build logs a warning instead of
    # aborting the whole `home-manager switch`.
    #
    # Runs after linkGeneration (not just installPackages) on purpose: these
    # downloads can be slow (a full Python source build, or any of them over a
    # slow connection), and linkGeneration is what actually creates file links
    # like ~/.config/nix/nix.conf. Running asdf first
    # would block those files from existing until the slowest download finishes.
    activation.asdfLanguages = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
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

        install_pinned() {
          plugin="$1"
          version="$2"
          "$asdf" plugin add "$plugin"

          if ! $DRY_RUN_CMD "$asdf" install "$plugin" "$version"; then
            echo "warning: asdfLanguages: asdf install $plugin $version failed" >&2
            return
          fi
          $DRY_RUN_CMD "$asdf" set -u "$plugin" "$version"
        }

        install_only() {
          plugin="$1"
          version="$2"
          "$asdf" plugin add "$plugin"

          if ! $DRY_RUN_CMD "$asdf" install "$plugin" "$version"; then
            echo "warning: asdfLanguages: asdf install $plugin $version failed" >&2
            return
          fi
        }

        install_pinned golang 1.27.1
        install_pinned nodejs ${nodeVersion}
        # Java default is a JRE (no javac); if you need compilation on the
        # default, bump this to the matching temurin-<major>.<...> JDK string.
        install_pinned java temurin-jre-26.0.2+10
        # Temurin 21 LTS JDK kept alongside for projects that require the 21
        # line -- install-only, does not change `asdf global`. Switch per
        # project with `.tool-versions` or `asdf shell java temurin-21.0.12+101.0.LTS`.
        # Bump this string manually when a new 21.x patch lands.
        install_only java temurin-21.0.12+101.0.LTS
        # Rides the same asdf-managed Java: mvn resolves java via PATH (the
        # asdf shims), so builds run under the temurin above rather than a
        # separate nixpkgs JDK that pkgs.maven would pin.
        install_pinned maven 3.9.16

        # The Lark/Feishu CLI is an npm package with no nixpkgs derivation, so
        # it rides on the asdf-managed Node: npm puts the binary inside a Node
        # version's own tree and `asdf reshim` exposes it via ~/.asdf/shims
        # (already on PATH). Same best-effort model as above.
        #
        # Every path here names ${nodeVersion} explicitly rather than going
        # through `asdf where nodejs` or the shims: those resolve against the
        # cwd's .tool-versions, and activation can be run from any directory.
        # A project pinning another Node would otherwise be asked whether the
        # CLI is in *its* tree and have it installed there.
        nodeRoot="$ASDF_DATA_DIR/installs/nodejs/${nodeVersion}"
        npm="$nodeRoot/bin/npm"
        if [ ! -x "$npm" ]; then
          echo "warning: asdfLanguages: no npm in nodejs ${nodeVersion}, skipping @larksuite/cli" >&2
        elif [ -d "$nodeRoot/lib/node_modules/@larksuite/cli" ]; then
          # Present but unshimmed (wiped shims dir, interrupted reshim) leaves
          # lark-cli off PATH; reshimming is free, reinstalling is not.
          [ -x "$ASDF_DATA_DIR/shims/lark-cli" ] || $DRY_RUN_CMD "$asdf" reshim nodejs ${nodeVersion}
        else
          # npm's internal scripts use `#!/usr/bin/env node`, so `node` must be
          # resolvable in PATH -- and it must be the same Node whose tree we
          # just tested, not whichever one the shims would pick.
          # --allow-scripts: npm >= 11.19 blocks postinstall scripts of global
          # installs by default, and this package needs its postinstall step.
          PATH="$nodeRoot/bin:$PATH" $DRY_RUN_CMD "$npm" install --global --allow-scripts=@larksuite/cli @larksuite/cli \
            && $DRY_RUN_CMD "$asdf" reshim nodejs ${nodeVersion} \
            || echo "warning: asdfLanguages: npm install @larksuite/cli failed" >&2
        fi
        true # this subshell's own exit status must always be 0
      )
    '';
    # asdf itself comes from home.packages; this exposes the shims it installs
    # into (~/.asdf/shims) so `go`/`node`/`python`/`java` resolve without
    # extra shell config.
    sessionPath = [ "${homeDirectory}/.asdf/shims" ];
  };
  # mvn (and other JVM launchers) resolve Java through JAVA_HOME -- on
  # macOS falling back to /usr/libexec/java_home, which knows nothing
  # about asdf installs. asdf-java's hook keeps JAVA_HOME pointed at the
  # active asdf java on every prompt.
  programs.zsh.initContent = ''
    [ -f "$HOME/.asdf/plugins/java/set-java-home.zsh" ] && . "$HOME/.asdf/plugins/java/set-java-home.zsh"
  '';
}
