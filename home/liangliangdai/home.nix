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
    export ASDF_DATA_DIR="$HOME/.asdf"
    asdf="${pkgs.asdf-vm}/bin/asdf"

    install_latest() {
      plugin="$1"
      query="''${2:-}"
      "$asdf" plugin add "$plugin" >/dev/null 2>&1 || true

      version=$("$asdf" latest "$plugin" "$query" 2>/dev/null) || {
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
  '';
  # asdf itself comes from home.packages; this exposes the shims it installs
  # into (~/.asdf/shims) so `go`/`node`/`python`/`java` resolve without
  # extra shell config.
  home.sessionPath = [ "${homeDirectory}/.asdf/shims" ];
  programs.home-manager.enable = true;
}
