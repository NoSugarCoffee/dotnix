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
      # Python comes prebuilt from nixpkgs rather than asdf: asdf's python
      # plugin compiles from source and needs Xcode CLT on macOS, and its
      # "latest" resolution picks the free-threaded 3.14t variant. Switch
      # major version by swapping this for pkgs.python312/313/314.
      [
        pkgs.codex
        pkgs.claude-code
        pkgs.asdf-vm
        pkgs.gh
        pkgs.glab
        pkgs.python3
        # IntelliJ IDEA Ultimate; unfree, activation needs your JetBrains license.
        pkgs.jetbrains.idea
        browserUsePackage
      ]
      ++ lib.optionals (claudeDesktopPackage != null) [ claudeDesktopPackage ]
      # clash-verge-rev is Linux-only in nixpkgs; on darwin the local
      # clash-verge-rev-darwin package (pkgs/clash-verge-rev-darwin) repacks
      # the official prebuilt DMG instead.
      ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.copyq pkgs.clash-verge-rev ]
      ++ lib.optionals pkgs.stdenv.isDarwin [ pkgs.google-chrome pkgs.clash-verge-rev-darwin pkgs.maccy ];
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
  # Route shell tools through the local Clash Verge proxy (default mixed
  # port 7890). Both spellings are set because tools disagree on which
  # they read (curl honors lowercase, some Go/Java tools only uppercase).
  # Reaches terminals via the managed zsh sourcing the session-vars file.
  home.sessionVariables =
    let
      proxyUrl = "http://127.0.0.1:7890";
      noProxy = "localhost,127.0.0.1,10.96.0.0/12,192.168.59.0/24,192.168.49.0/24,192.168.39.0/24,.ctripcorp.com,.tripqate.com,.larkenterprise.com";
    in
    {
      HTTP_PROXY = proxyUrl;
      HTTPS_PROXY = proxyUrl;
      NO_PROXY = noProxy;
      http_proxy = proxyUrl;
      https_proxy = proxyUrl;
      no_proxy = noProxy;
    };
  # home.sessionPath / sessionVariables only reach a real terminal if the
  # shell sources home-manager's session-vars file; a stock macOS zsh never
  # does, leaving the asdf shims silently off PATH. Managing zsh makes the
  # generated ~/.zshrc do that sourcing. A pre-existing hand-written
  # ~/.zshrc must be moved aside once (home-manager refuses to overwrite);
  # fold its content into programs.zsh.initContent if it should be kept.
  programs.zsh.enable = true;
  # Installs zellij and writes its config. On macOS the default OSC52
  # clipboard escape doesn't reach the system clipboard from every
  # terminal, so selections are piped to pbcopy explicitly; Linux keeps
  # the OSC52 default, which its terminals handle.
  programs.zellij = {
    enable = true;
    settings = lib.optionalAttrs pkgs.stdenv.isDarwin {
      copy_command = "pbcopy";
    };
  };
  # Bounds generation history so the store can't fill the disk again (a
  # full root disk once broke everything on the Linux box): a weekly timer
  # (systemd on Linux, launchd on macOS) deletes generations older than two
  # weeks and garbage-collects what they referenced. Time-bounded because
  # Nix has no "keep at most N generations" -- rollback still works within
  # the 14-day window.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  # Installs git and writes ~/.config/git/config. Deliberately minimal:
  # only portable identity/editor settings live here -- work-internal URL
  # rewrites and machine-specific credential helpers stay out of this
  # public repo and belong in ~/.gitconfig, which git reads on top of the
  # managed file (and which wins on conflicting single-valued keys).
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "NoSugarCoffee";
        email = "1353025854@qq.com";
      };
      core.editor = "vim";
      init.defaultBranch = "main";
      # Route https clones through SSH. On a machine whose SSH key isn't
      # registered with the host yet, these make https clones fail with
      # "Permission denied (publickey)" -- set up keys (gh auth login)
      # before cloning. Activation scripts are immune: they mask user git
      # config (see asdfLanguages).
      url."git@github.com:".insteadOf = "https://github.com/";
      url."git@git.dev.sh.ctripcorp.com:".insteadOf = [
        "https://git.dev.sh.ctripcorp.com/"
        "http://git.dev.sh.ctripcorp.com/"
      ];
    };
    # Repos whose remote points at the internal GitLab use the work identity
    # instead of the GitHub one above; matching is by remote URL, so no
    # per-repo setup is needed. The identity itself lives in an untracked
    # per-machine file so it never enters this public repo and can't be
    # reverted by syncing it -- create it once per machine:
    #   printf '[user]\n\temail = you@work.example\n' > ~/.gitconfig-work
    # Git silently skips includes whose target file doesn't exist, so
    # machines without the file simply keep the default identity. The three
    # patterns cover the URL shapes remotes take (ssh://, scp-style, https).
    includes =
      let
        workIdentityPath = "${homeDirectory}/.gitconfig-work";
      in
      [
        {
          condition = "hasconfig:remote.*.url:ssh://git@git.dev.sh.ctripcorp.com:*/**";
          path = workIdentityPath;
        }
        {
          condition = "hasconfig:remote.*.url:git@git.dev.sh.ctripcorp.com:*/**";
          path = workIdentityPath;
        }
        {
          condition = "hasconfig:remote.*.url:https://git.dev.sh.ctripcorp.com/**";
          path = workIdentityPath;
        }
      ];
  };
  programs.home-manager.enable = true;
}
