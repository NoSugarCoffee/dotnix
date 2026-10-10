{
  llmAgentsPackages,
  username,
  homeDirectory,
  config,
  lib,
  pkgs,
  ...
}:
let
  proxyUrl = "http://127.0.0.1:7890";
  gcOptions = [
    "--delete-older-than"
    "14d"
  ];
  # Referenced by both the asdf pin and the @larksuite/cli paths below, which
  # must agree on one Node tree.
  nodeVersion = "26.7.0";
  noProxy = "localhost,127.0.0.1,10.96.0.0/12,192.168.59.0/24,192.168.49.0/24,192.168.39.0/24,.ctripcorp.com,.tripqate.com,.larkenterprise.com";
  # Pi user extensions: computer-use (screen/GUI), browser-native (web automation),
  # a2a-adaptor (agent-to-agent calls), provider-kiro (Kiro API model provider,
  # OAuth-authenticated), auto-name (names the Pi session and the containing
  # tmux/herdr/zellij surfaces from the conversation). These are not ordinary
  # packages on PATH; they are Pi agent capabilities installed into
  # ~/.pi/agent/npm/node_modules/ via `pi install`. An activation script ensures
  # they exist after a fresh machine bootstrap, so switching PCs doesn't require
  # manual re-installation.
  piExtensions = [
    "npm:@injaneity/pi-computer-use"
    "npm:pi-agent-browser-native"
    "npm:pi-a2a-adaptor"
    "npm:pi-provider-kiro"
    "npm:@normful/pi-auto-name"
  ];
  # Extension sources that must not linger on the machine, either because they
  # were superseded or because they were dropped outright: machines provisioned
  # before the switch to @injaneity/pi-computer-use still have the unscoped
  # package, remote-pi and pi-mcp-adapter were removed deliberately, and
  # pi-zellij-tab-namer was superseded by @normful/pi-auto-name (it called modelRegistry.getApiKey,
  # removed in current Pi, so it silently never renamed anything). `pi remove`
  # drops them from ~/.pi/agent/settings.json.
  piRemovedExtensions = [
    "npm:pi-computer-use"
    "npm:remote-pi"
    "npm:pi-mcp-adapter"
    "npm:pi-zellij-tab-namer"
  ];
  # Claude Code's managed keys share the proxy settings declared here. Its
  # other settings stay machine-owned (see the activation merge below).
  claudeManagedSettings = pkgs.writeText "claude-managed-settings.json" (
    builtins.toJSON (import ./claude/settings.nix { inherit proxyUrl noProxy; })
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
        pkgs.pi-coding-agent
        pkgs.agent-access
        pkgs.bitwarden-cli
        pkgs.asdf-vm
        pkgs.pnpm
        pkgs.git
        # `git open` (paulirish/git-open): opens the repo/PR/issue URL for the
        # current branch in the browser. Picked up by git from PATH.
        pkgs.git-open
        pkgs.gh
        pkgs.glab
        pkgs.docker-client
        pkgs.docker-compose
        pkgs.just
        pkgs.nix-zsh-completions
        (pkgs.python3.withPackages (ps: [
          ps.pip
          ps.ipython
        ]))
        # IntelliJ IDEA Ultimate; unfree, activation needs your JetBrains license.
        pkgs.jetbrains.idea
        # Provides the `cursor` CLI that ~/.codex/config.toml's file_opener uses.
        pkgs.code-cursor
      ]
      ++ llmAgentsPackages
      ++ lib.filter (lib.meta.availableOn pkgs.stdenv.hostPlatform) [
        pkgs.chatgpt
        pkgs.clash-verge-rev
        pkgs.clash-verge-rev-darwin
        pkgs.copyq
        pkgs.maccy
        pkgs.macshot
        pkgs.obs-studio
        pkgs.obs-studio-darwin
        pkgs.pulsar-darwin
        pkgs.albert-darwin
        pkgs.scroll-reverser
        pkgs.jetbrains-air-darwin
        pkgs.ego-lite-darwin
        pkgs.cida-darwin
      ]
      ++ lib.optionals pkgs.stdenv.isDarwin [
        pkgs.google-chrome
        pkgs.colima
      ];
    file = {
      "Applications/Google Chrome.app" = lib.mkIf pkgs.stdenv.isDarwin {
        source = "${pkgs.google-chrome}/Applications/Google Chrome.app";
      };
      ".docker/cli-plugins/docker-compose".source =
        "${pkgs.docker-compose}/libexec/docker/cli-plugins/docker-compose";
    };
  };
  # Codex and Claude Code both write their own settings files (trust
  # decisions, /config, plugin toggles), so neither can be a store symlink.
  # managed_settings.py seeds the file on a fresh machine and resets only the
  # declared keys on every switch; everything else stays machine-owned.
  # Ordered after linkGeneration so an old store symlink is already gone.
  home.activation.codexManagedSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    $DRY_RUN_CMD mkdir -p $HOME/.codex
    $DRY_RUN_CMD chmod 700 $HOME/.codex
    $DRY_RUN_CMD ${pkgs.python3}/bin/python3 ${./managed_settings.py} \
      --format toml --managed ${./codex/managed.toml} --seed ${./codex/config.toml} \
      --mode 600 "$HOME/.codex/config.toml"
  '';
  home.activation.claudeCodeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.python3}/bin/python3 ${./managed_settings.py} \
      --format json --managed ${claudeManagedSettings} \
      --mode 644 "$HOME/.claude/settings.json"
  '';
  launchd.agents = {
    # Auto-launch Albert at login. macOS user LaunchAgents fire once the user's
    # Aqua session comes up -- the earliest legitimate hook for a GUI app.
    albert = {
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
    scroll-reverser = {
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
    colima = {
      enable = pkgs.stdenv.isDarwin;
      config = {
        ProgramArguments = [
          "${pkgs.colima}/bin/colima"
          "start"
        ];
        EnvironmentVariables = {
          PATH = "${pkgs.docker-client}/bin:/usr/bin:/bin";
          HTTP_PROXY = proxyUrl;
          HTTPS_PROXY = proxyUrl;
          NO_PROXY = noProxy;
          http_proxy = proxyUrl;
          https_proxy = proxyUrl;
          no_proxy = noProxy;
        };
        RunAtLoad = true;
        KeepAlive = false;
        ProcessType = "Background";
      };
    };
    nix-gc.config.ProgramArguments = lib.mkForce (
      [ "${config.nix.package}/bin/nix-collect-garbage" ] ++ gcOptions
    );
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
  # like ~/.config/nix/nix.conf. Running asdf first
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
  # Pi extensions (the sources in piExtensions above) are installed
  # imperatively via `pi install`. On a fresh machine they are missing entirely.
  # This activation checks `pi list` first, installs only the ones that are
  # absent, and removes any sources listed in piRemovedExtensions, so it is a
  # cheap no-op on every-day switches.
  home.activation.piPackages = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    (
      set +e
      pi="${pkgs.pi-coding-agent}/bin/pi"
      grep="${pkgs.gnugrep}/bin/grep"
      installed=$($pi list 2>/dev/null)
      for ext in ${lib.concatStringsSep " " piExtensions}; do
        if $grep -Fq "$ext" <<< "$installed"; then
          continue
        fi
        $DRY_RUN_CMD "$pi" install "$ext" || echo "warning: piPackages: failed to install $ext" >&2
      done
      # @normful/pi-auto-name 1.1.0 resolves the current zellij tab as the first
      # pane whose numeric id matches ZELLIJ_PANE_ID, without skipping plugin
      # panes. Plugin and terminal pane ids collide (both report the same
      # integer), so a floating plugin pane (e.g. About Zellij) makes it rename
      # the plugin's tab instead of the active one. Skip plugin panes.
      # Idempotent: only rewrites the source while the unpatched form is present,
      # so it re-applies after a `pi update`/reinstall on the next switch.
      surfaces="${homeDirectory}/.pi/agent/npm/node_modules/@normful/pi-auto-name/src/surfaces.ts"
      if [ -f "$surfaces" ] && $grep -Fq 'panes.find((p) => p.id === paneId)' "$surfaces"; then
        $DRY_RUN_CMD "${pkgs.gnused}/bin/sed" -i -e 's/Array<{ id?: number; tab_id?: number }>/Array<{ id?: number; tab_id?: number; is_plugin?: boolean }>/' -e 's/panes\.find((p) => p\.id === paneId)/panes.find((p) => !p.is_plugin \&\& p.id === paneId)/' "$surfaces"
        echo "piPackages: patched pi-auto-name zellij tab lookup (skip plugin panes)"
      fi
      # Prune removed/superseded sources only once every desired extension is
      # present. The install loop swallows failures, so without this guard a
      # transient npm/network error could remove the old source and leave the
      # machine with no computer-use extension at all.
      complete=1
      installed=$($pi list 2>/dev/null)
      for ext in ${lib.concatStringsSep " " piExtensions}; do
        $grep -Fq "$ext" <<< "$installed" || complete=0
      done
      if [ "$complete" = 1 ]; then
        for ext in ${lib.concatStringsSep " " piRemovedExtensions}; do
          if $grep -Fq "$ext" <<< "$installed"; then
            $DRY_RUN_CMD "$pi" remove "$ext" || echo "warning: piPackages: failed to remove $ext" >&2
          fi
        done
      else
        echo "piPackages: not all extensions installed; skipping removal of piRemovedExtensions" >&2
      fi
      true
    )
  '';
  home.activation.piManagedSettings = lib.hm.dag.entryAfter [ "piPackages" ] ''
    $DRY_RUN_CMD ${pkgs.python3}/bin/python3 ${./managed_settings.py} \
      --format json --managed ${./pi/managed.json} \
      --mode 644 "$HOME/.pi/agent/settings.json"
  '';
  # asdf itself comes from home.packages; this exposes the shims it installs
  # into (~/.asdf/shims) so `go`/`node`/`python`/`java` resolve without
  # extra shell config.
  home.sessionPath = [
    "${homeDirectory}/.asdf/shims"
    "${homeDirectory}/.local/bin"
  ];
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
  programs = {
    zsh = {
      enable = true;
      syntaxHighlighting.enable = true;
      autosuggestion.enable = true;
      # Option+Left/Right jump by word. kitty's macos_option_as_alt makes
      # Option send Alt, which arrives as CSI 1;3 arrow sequences; zsh only
      # binds Alt-b/Alt-f out of the box. zellij is configured to pass
      # Alt+Left/Right through (see zellij/config.kdl).
      initContent = lib.mkMerge [
        ''
          bindkey "^[[1;3D" backward-word
          bindkey "^[[1;3C" forward-word
          # mvn (and other JVM launchers) resolve Java through JAVA_HOME -- on
          # macOS falling back to /usr/libexec/java_home, which knows nothing
          # about asdf installs. asdf-java's hook keeps JAVA_HOME pointed at the
          # active asdf java on every prompt.
          [ -f "$HOME/.asdf/plugins/java/set-java-home.zsh" ] && . "$HOME/.asdf/plugins/java/set-java-home.zsh"
        ''
        # Escape hatch for shell config that must not reach a public repo
        # (employer hostnames, internal registries, credentials) or that is
        # machine-specific. Sourced at mkOrder 1500 -- after everything this
        # module declares -- so a local definition wins, and guarded so a
        # machine without the file still gets a working shell.
        (lib.mkOrder 1500 ''
          [ -f "$HOME/.zshrc-local" ] && . "$HOME/.zshrc-local"
        '')
      ];
      # Claude Code persists every conversation under ~/.claude/projects; these
      # are just short spellings of the two ways back into one. Not `cc`, which
      # would shadow the C compiler.
      shellAliases = {
        clc = "claude --continue";
        clr = "claude --resume";
      };
    };
    # Smarter cd: tracks visited directories, jump with `z <fragment>`.
    # enableZshIntegration defaults to true, wiring the init hook into the
    # managed ~/.zshrc.
    zoxide.enable = true;
    yazi = {
      enable = true;
      shellWrapperName = "y";
      extraPackages = [
        pkgs.fd
        pkgs.ripgrep
        pkgs.fzf
        pkgs.file
      ];
    };
    # Installs zellij; the full config (a dump of the 0.43.1 defaults, kept
    # in zellij/config.kdl for easy keybinding edits) is written directly as
    # KDL rather than through programs.zellij.settings, whose nix-attrs form
    # can't express the keybinds tree well. The config itself is written by
    # the xdg.configFile entry just below this block. On macOS the default
    # OSC52 clipboard escape doesn't reach the system clipboard from every
    # terminal, so selections are piped to pbcopy explicitly; Linux keeps
    # the OSC52 default, which its terminals handle.
    zellij.enable = true;
    # kitty replaces Terminal.app as the terminal emulator: Terminal.app
    # translates Option+arrows into Esc-prefixed sequences (e.g. Esc f) that
    # collide with zellij's Alt bindings, and its settings live in a plist
    # nix can't reliably own. macos_option_as_alt makes Option send Alt so
    # the zellij keybindings work; it is ignored on Linux.
    kitty = {
      enable = true;
      themeFile = "Catppuccin-Mocha";
      settings = {
        font_size = 14;
        macos_option_as_alt = "yes";
        # zellij is deliberately not kitty's `shell`: it daemonizes its server
        # with ppid 1, so a pane's process is a child of that server rather than
        # of kitty.app, and macOS attributes permissions (Screen Recording) to
        # the server -- which, being a bare nix-store binary, can never hold a
        # grant. Start it per window with `zellij` / `zellij attach`.
        # kitty runs one process for every window it owns, so session-level
        # activation can only raise "some" kitty window, not necessarily the
        # right one. Remote control on a fixed socket lets callers target the
        # exact window by KITTY_WINDOW_ID instead.
        # socket-only restricts control to this socket, not all local/network
        # access.
        allow_remote_control = "socket-only";
        listen_on = "unix:/tmp/kitty-remote-control";
      };
    };
    # git is installed as a plain package, not via programs.git: that module's
    # only other job is writing ~/.config/git/config, and git config is left
    # unmanaged here. Identity has to be switched per checkout (personal vs
    # employer), and git can only express that with `includeIf`, which takes a
    # path -- so the split needs a second, machine-local file no matter what.
    # Generating half a chain from the store while the other half stays
    # hand-written was worse than owning none of it: the values never change,
    # and a store symlink means a rebuild to correct an email address.
    # ~/.gitconfig is hand-maintained instead.
    home-manager.enable = true;
  };
  # zellij's config, written as KDL -- see programs.zellij above.
  xdg.configFile."zellij/config.kdl".text =
    builtins.readFile ./zellij/config.kdl
    + lib.optionalString pkgs.stdenv.isDarwin ''
      copy_command "pbcopy"
    '';
  # ccstatusline writes ~/.config/ccstatusline/settings.json on schema
  # migration and from its TUI, so that path cannot be a store symlink
  # (EACCES → "⚠ invalid config"). Leave the live file unmanaged; a copyable
  # export lives at ./ccstatusline/settings.json.
  nix = {
    # Bounds generation history so the store can't fill the disk again (a
    # full root disk once broke everything on the Linux box): a weekly timer
    # (systemd on Linux, launchd on macOS) deletes generations older than two
    # weeks and garbage-collects what they referenced. Time-bounded because
    # Nix has no "keep at most N generations" -- rollback still works within
    # the 14-day window.
    gc = {
      automatic = true;
      dates = "weekly";
      options = lib.concatStringsSep " " gcOptions;
    };
    # Required by home-manager to generate nix.conf; it only names the nix
    # version used for config validation, nothing is installed.
    package = pkgs.nix;
    # Prefer the China mirrors over cache.nixos.org: the system-level
    # /etc/nix/nix.custom.conf only *appends* them (extra-substituters), so
    # the slow upstream is always tried first. This user-level list overrides
    # the order; nix falls back per-path to later entries automatically.
    # pi.cachix.org serves the lukasl-dev/pi.nix builds (the flake's own
    # nixConfig is opt-in via --accept-flake-config and never reaches an
    # unattended switch); nix-community.cachix.org serves its bun2nix
    # toolchain. Without them pkgs.pi-coding-agent builds from source.
    # HARD PREREQUISITE: the daemon silently ignores user-level substituters
    # unless the user is in trusted-users. bootstrap-macos.sh ensures that on
    # macOS; on other machines add it manually to the system nix.conf
    # (e.g. `extra-trusted-users = ${username}`) or this list is a no-op
    # and downloads just fall through to the system substituters.
    settings.substituters = [
      "https://mirror.sjtu.edu.cn/nix-channels/store"
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
      "https://mirrors.ustc.edu.cn/nix-channels/store"
      "https://pi.cachix.org/"
      "https://nix-community.cachix.org/"
      "https://cache.numtide.com/"
      "https://cache.nixos.org/"
    ];
    settings.extra-trusted-public-keys = [
      "pi.cachix.org-1:lGeoGJaZ5ZDabuRzkcD5EBTNnDM4HJ1vqeOxlWk1Flk="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };
}
