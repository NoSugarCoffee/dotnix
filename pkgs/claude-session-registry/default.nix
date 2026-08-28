# Claude Code persists every conversation under ~/.claude/projects, but nothing
# records which of them were open, or in which pane. `claude --continue` only
# resolves to the newest conversation in a directory, so a project that ran
# several panes at once collapses to a single conversation on restore.
# claude-session-record is a SessionStart/SessionEnd hook that keeps one record
# per live conversation; claude-session-restore replays those records as
# `claude --resume <id>` in fresh zellij tabs.
{
  claude-code,
  kitty,
  lib,
  symlinkJoin,
  writers,
  zellij,
}:
let
  # The restore command drives zellij, claude and kitty directly rather than
  # resolving them from PATH: it runs from a Claude Code hook context and after
  # a fresh login, neither of which is guaranteed to have the user profile on
  # PATH -- and the tabs it opens inherit the zellij server's PATH, not its own.
  restoreSource =
    builtins.replaceStrings
      [ "@zellij@" "@claude@" "@kitty@" ]
      [ "${zellij}/bin/zellij" "${claude-code}/bin/claude" "${kitty}/bin/kitty" ]
      (builtins.readFile ./restore.py);
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
