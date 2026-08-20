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
      [ pkgs.codex pkgs.claude-code pkgs.asdf-vm pkgs.git browserUsePackage ]
      ++ lib.optionals (claudeDesktopPackage != null) [ claudeDesktopPackage ]
      ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.copyq ]
      ++ lib.optionals pkgs.stdenv.isDarwin [ pkgs.google-chrome ];
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
  # Mirrors are 1:1 mirrors of cache.nixos.org (same signing key, so no
  # extra-trusted-public-keys needed) that are much faster to reach from
  # mainland China. `extra-substituters` only appends to the daemon's list --
  # cache.nixos.org stays as the fallback for anything a mirror doesn't have.
  # Only takes effect if this user is a trusted-user in /etc/nix/nix.conf
  # (the Determinate Systems installer adds the installing user by default);
  # otherwise the daemon silently ignores user-supplied substituters.
  xdg.configFile."nix/nix.conf".text = ''
    extra-substituters = https://mirror.sjtu.edu.cn/nix-channels/store https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store
  '';
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
  home.activation.asdfLanguages = lib.hm.dag.entryAfter [ "installPackages" ] ''
    ( # Subshell: everything in here, including the PATH override, is scoped
      # to this block. Activation steps all run in the same parent shell
      # otherwise, and a later step (linkGeneration) needs the nix-provided
      # bash this script itself is running under -- not macOS's ancient
      # system bash that /usr/bin:/bin would shadow it with if exported here.
      set +e

      export ASDF_DATA_DIR="$HOME/.asdf"
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
      true # this subshell's own exit status must always be 0
    )
  '';
  # asdf itself comes from home.packages; this exposes the shims it installs
  # into (~/.asdf/shims) so `go`/`node`/`python`/`java` resolve without
  # extra shell config.
  home.sessionPath = [ "${homeDirectory}/.asdf/shims" ];
  programs.home-manager.enable = true;
}
