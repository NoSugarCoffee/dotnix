# Claude Code persists every conversation under ~/.claude/projects, but nothing
# records which of them were open, or in which pane. `claude --continue` only
# resolves to the newest conversation in a directory, so a project that ran
# several panes at once collapses to a single conversation on restore.
# claude-session-record is a SessionStart/SessionEnd hook that keeps one record
# per live conversation; claude-session-restore replays those records as
# `claude --resume <id>` in fresh zellij tabs.
{
  lib,
  symlinkJoin,
  writers,
  zellij,
}:
let
  # The restore command drives zellij directly rather than resolving it from
  # PATH: it runs from a Claude Code hook context and after a fresh login,
  # neither of which is guaranteed to have the user profile on PATH.
  restoreSource = builtins.replaceStrings [ "@zellij@" ] [ "${zellij}/bin/zellij" ] (
    builtins.readFile ./restore.py
  );
in
symlinkJoin {
  name = "claude-session-registry";

  paths = [
    (writers.writePython3Bin "claude-session-record" { } (builtins.readFile ./record.py))
    (writers.writePython3Bin "claude-session-restore" { flakeIgnore = [ "E501" ]; } restoreSource)
  ];

  meta = {
    description = "Records live Claude Code conversations and replays them into zellij tabs";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
