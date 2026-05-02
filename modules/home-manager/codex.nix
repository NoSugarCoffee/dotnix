# OpenAI Codex CLI — installed declaratively from nixpkgs and configured via
# ~/.codex/config.toml. Enable per-user with:
#
#   modules.codex.enable = true;
#
# Run `codex login` once after activation to authenticate (browser flow).
# Credentials are cached at ~/.codex/auth.json (or your OS keyring).
{
  config,
  lib,
  pkgs,
  unstable ? pkgs,
  ...
}:
let
  cfg = config.modules.codex;
in
{
  options.modules.codex = {
    enable = lib.mkEnableOption "OpenAI Codex CLI";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.codex;
      defaultText = lib.literalExpression "pkgs.codex";
      description = ''
        The codex package to install. Override with `unstable.codex` if you
        need a newer release than the pinned channel ships, e.g.:

          modules.codex.package = unstable.codex;
      '';
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "gpt-5-codex";
      description = "Default model used by Codex CLI.";
    };

    approvalPolicy = lib.mkOption {
      type = lib.types.enum [
        "untrusted"
        "on-request"
        "never"
      ];
      default = "on-request";
      description = "When Codex pauses for human approval before running commands.";
    };

    sandboxMode = lib.mkOption {
      type = lib.types.enum [
        "read-only"
        "workspace-write"
        "danger-full-access"
      ];
      default = "workspace-write";
      description = "Filesystem sandbox level applied to Codex tool calls.";
    };

    networkAccess = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow network access from inside the workspace-write sandbox.";
    };

    fileOpener = lib.mkOption {
      type = lib.types.enum [
        "vscode"
        "vscode-insiders"
        "windsurf"
        "cursor"
        "none"
      ];
      default = "cursor";
      description = "Editor used to open file:line citations from Codex output.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra raw TOML appended to ~/.codex/config.toml.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # Declarative ~/.codex/config.toml. Auth tokens are NOT managed here —
    # they're written by `codex login` to ~/.codex/auth.json.
    home.file.".codex/config.toml".text = ''
      # Managed by home-manager — edit modules/home-manager/codex.nix instead.

      model            = "${cfg.model}"
      approval_policy  = "${cfg.approvalPolicy}"
      sandbox_mode     = "${cfg.sandboxMode}"
      file_opener      = "${cfg.fileOpener}"

      [sandbox_workspace_write]
      network_access = ${lib.boolToString cfg.networkAccess}

      [tui]
      notifications = true

      [history]
      persistence = "save-all"

      [shell_environment_policy]
      inherit = "all"
    ''
    + lib.optionalString (cfg.extraConfig != "") ("\n" + cfg.extraConfig + "\n");

    # Make sure ~/.codex exists and is writable; codex login drops auth.json
    # there on first authentication.
    home.activation.codexHomeDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p $HOME/.codex
      $DRY_RUN_CMD chmod 700 $HOME/.codex
    '';
  };
}
