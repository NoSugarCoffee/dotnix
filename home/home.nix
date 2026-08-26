{ claudeDesktopPackage, username, homeDirectory, lib, pkgs, ... }:
let
  proxyUrl = "http://127.0.0.1:7890";
  noProxy = "localhost,127.0.0.1,10.96.0.0/12,192.168.59.0/24,192.168.49.0/24,192.168.39.0/24,.ctripcorp.com,.tripqate.com,.larkenterprise.com";
  # Only the portable subset of Claude Code settings is managed; hooks,
  # plugins, and anything set via /config stay machine-owned (see the
  # claudeCodeSettings activation below for the merge semantics).
  claudeManagedSettings = pkgs.writeText "claude-managed-settings.json" (
    builtins.toJSON {
      "$schema" = "https://json.schemastore.org/claude-code-settings.json";
      env = {
        HTTP_PROXY = proxyUrl;
        HTTPS_PROXY = proxyUrl;
        NO_PROXY = noProxy;
      };
      permissions = {
        deny = [ "Read(.env)" ];
        # Sessions start with no permission prompts at all.
        defaultMode = "bypassPermissions";
      };
      # Skips the are-you-sure prompt bypassPermissions otherwise shows.
      skipDangerousModePermissionPrompt = true;
      # "opus" is the rolling alias for the newest Opus model, so this
      # tracks upgrades without pinning a dated model id.
      model = "opus";
      theme = "dark";
      tui = "fullscreen";
      remoteControlAtStartup = true;
    }
  );
in
{
  home = {
    inherit username homeDirectory;
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
        pkgs.just
        pkgs.nix-zsh-completions
        pkgs.python3
        pkgs.python3Packages.ipython
        # IntelliJ IDEA Ultimate; unfree, activation needs your JetBrains license.
        pkgs.jetbrains.idea
      ]
      ++ lib.optionals (claudeDesktopPackage != null) [ claudeDesktopPackage ]
      # clash-verge-rev is Linux-only in nixpkgs; on darwin the local
      # clash-verge-rev-darwin package (pkgs/clash-verge-rev-darwin) repacks
      # the official prebuilt DMG instead.
      ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.copyq pkgs.clash-verge-rev ]
      # claude-desktop's flake input is Linux-only; pkgs/claude-desktop-darwin
      # repacks the official DMG for macOS.
      # pulsar is Linux-only in nixpkgs; pkgs/pulsar-darwin repacks the
      # official prebuilt zip for macOS.
      ++ lib.optionals pkgs.stdenv.isDarwin [ pkgs.google-chrome pkgs.clash-verge-rev-darwin pkgs.maccy pkgs.claude-desktop-darwin pkgs.macshot pkgs.pulsar-darwin pkgs.albert-darwin pkgs.scroll-reverser ];
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
  # Claude Code writes settings.json itself (/config, plugin toggles), so it
  # can't be a read-only store symlink. Instead the managed subset is merged
  # in on every switch: managed keys reset to their declared values, every
  # other key (hooks, plugins, /config tweaks) is preserved. The file stays
  # a normal writable file owned by the machine.
  home.activation.claudeCodeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    claudeSettings="$HOME/.claude/settings.json"
    $DRY_RUN_CMD mkdir -p "$HOME/.claude"
    if [ -f "$claudeSettings" ]; then
      ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$claudeSettings" ${claudeManagedSettings} > "$claudeSettings.hm-tmp" \
        && $DRY_RUN_CMD mv "$claudeSettings.hm-tmp" "$claudeSettings"
      rm -f "$claudeSettings.hm-tmp"
    else
      $DRY_RUN_CMD cp ${claudeManagedSettings} "$claudeSettings"
      $DRY_RUN_CMD chmod 644 "$claudeSettings"
    fi
  '';
  # Auto-launch Albert at login. macOS user LaunchAgents fire once the user's
  # Aqua session comes up -- the earliest legitimate hook for a GUI app.
  launchd.agents.albert = {
    enable = pkgs.stdenv.isDarwin;
    config = {
      ProgramArguments = [
        "${pkgs.albert-darwin}/Applications/Albert.app/Contents/MacOS/Albert"
      ];
      RunAtLoad = true;
      KeepAlive = false;
      ProcessType = "Interactive";
    };
  };
  # Scroll Reverser only reverses scroll direction while its process is
  # running, so it has to come up with the login session.
  launchd.agents.scroll-reverser = {
    enable = pkgs.stdenv.isDarwin;
    config = {
      ProgramArguments = [
        "${pkgs.scroll-reverser}/Applications/Scroll Reverser.app/Contents/MacOS/Scroll Reverser"
      ];
      RunAtLoad = true;
      KeepAlive = false;
      ProcessType = "Interactive";
    };
  };
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
        $DRY_RUN_CMD "$asdf" set -u "$plugin" "$version"
      }

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

      install_latest golang
      install_latest nodejs
      # Java default is pinned (no more "latest" drift). Freeze here matches
      # what `asdf latest java temurin` resolved to at pin time -- it's a JRE
      # (no javac); if you need compilation on the default, bump this to the
      # matching temurin-<major>.<...> JDK string. Bump manually to move.
      install_pinned java temurin-jre-26.0.2+10
      # Temurin 21 LTS JDK kept alongside for projects that require the 21
      # line -- install-only, does not change `asdf global`. Switch per
      # project with `.tool-versions` or `asdf shell java temurin-21.0.12+101.0.LTS`.
      # Bump this string manually when a new 21.x patch lands.
      install_only java temurin-21.0.12+101.0.LTS
      # Rides the same asdf-managed Java: mvn resolves java via PATH (the
      # asdf shims), so builds run under the temurin above rather than a
      # separate nixpkgs JDK that pkgs.maven would pin.
      install_latest maven

      # The Lark/Feishu CLI is an npm package with no nixpkgs derivation, so
      # it rides on the asdf-managed Node: npm puts the binary inside the
      # active Node version and `asdf reshim` exposes it via ~/.asdf/shims
      # (already on PATH). Same tracking-latest, best-effort model as above.
      npm="$ASDF_DATA_DIR/shims/npm"
      if [ -x "$npm" ]; then
        # npm's internal scripts use `#!/usr/bin/env node`, so `node` must be
        # resolvable in PATH -- not just via the explicit shim path we call
        # here. The activation PATH above doesn't include the shims dir.
        # --allow-scripts: npm >= 11.19 blocks postinstall scripts of global
        # installs by default, and this package needs its postinstall step.
        PATH="$ASDF_DATA_DIR/shims:$PATH" $DRY_RUN_CMD "$npm" install --global --allow-scripts=@larksuite/cli @larksuite/cli \
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
  home.sessionVariables = {
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
  programs.zsh = {
    enable = true;
    # Option+Left/Right jump by word. kitty's macos_option_as_alt makes
    # Option send Alt, which arrives as CSI 1;3 arrow sequences; zsh only
    # binds Alt-b/Alt-f out of the box. zellij is configured to pass
    # Alt+Left/Right through (see zellij/config.kdl).
    initContent = ''
      bindkey "^[[1;3D" backward-word
      bindkey "^[[1;3C" forward-word
      # mvn (and other JVM launchers) resolve Java through JAVA_HOME -- on
      # macOS falling back to /usr/libexec/java_home, which knows nothing
      # about asdf installs. asdf-java's hook keeps JAVA_HOME pointed at the
      # active asdf java on every prompt.
      [ -f "$HOME/.asdf/plugins/java/set-java-home.zsh" ] && . "$HOME/.asdf/plugins/java/set-java-home.zsh"
    '';
  };
  # Smarter cd: tracks visited directories, jump with `z <fragment>`.
  # enableZshIntegration defaults to true, wiring the init hook into the
  # managed ~/.zshrc.
  programs.zoxide.enable = true;
  # Installs zellij; the full config (a dump of the 0.43.1 defaults, kept
  # in zellij/config.kdl for easy keybinding edits) is written directly as
  # KDL rather than through programs.zellij.settings, whose nix-attrs form
  # can't express the keybinds tree well. On macOS the default OSC52
  # clipboard escape doesn't reach the system clipboard from every
  # terminal, so selections are piped to pbcopy explicitly; Linux keeps
  # the OSC52 default, which its terminals handle.
  programs.zellij.enable = true;
  xdg.configFile."zellij/config.kdl".text =
    builtins.readFile ./zellij/config.kdl
    + lib.optionalString pkgs.stdenv.isDarwin ''
      copy_command "pbcopy"
    '';
  # kitty replaces Terminal.app as the terminal emulator: Terminal.app
  # translates Option+arrows into Esc-prefixed sequences (e.g. Esc f) that
  # collide with zellij's Alt bindings, and its settings live in a plist
  # nix can't reliably own. macos_option_as_alt makes Option send Alt so
  # the zellij keybindings work; it is ignored on Linux.
  programs.kitty = {
    enable = true;
    themeFile = "Catppuccin-Mocha";
    settings = {
      macos_option_as_alt = "yes";
      shell = "${pkgs.zellij}/bin/zellij";
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
  # Prefer the China mirrors over cache.nixos.org: the system-level
  # /etc/nix/nix.custom.conf only *appends* them (extra-substituters), so
  # the slow upstream is always tried first. This user-level list overrides
  # the order; nix falls back per-path to later entries automatically.
  # HARD PREREQUISITE: the daemon silently ignores user-level substituters
  # unless the user is in trusted-users. bootstrap-macos.sh ensures that on
  # macOS; on other machines add it manually to the system nix.conf
  # (e.g. `extra-trusted-users = ${username}`) or this list is a no-op
  # and downloads just fall through to the system substituters.
  # nix.package is required by home-manager to generate nix.conf; it only
  # names the nix version used for config validation, nothing is installed.
  nix.package = pkgs.nix;
  nix.settings.substituters = [
    "https://mirror.sjtu.edu.cn/nix-channels/store"
    "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
    "https://mirrors.ustc.edu.cn/nix-channels/store"
    "https://cache.nixos.org/"
  ];
  # Installs git and writes ~/.config/git/config with portable settings.
  # Machine-specific or work-internal config (URL rewrites, credential
  # helpers, work identity) belongs in ~/.gitconfig-local, which is
  # included unconditionally but silently skipped when absent.
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "NoSugarCoffee";
        email = "25247325+NoSugarCoffee@users.noreply.github.com";
      };
      core.editor = "vim";
      http.postBuffer = 524288000;
      init.defaultBranch = "main";
      url."git@github.com:".insteadOf = "https://github.com/";
    };
    includes = [
      { path = "${homeDirectory}/.gitconfig-local"; }
    ];
  };
  programs.home-manager.enable = true;
}
