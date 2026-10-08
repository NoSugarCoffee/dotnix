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
  makeWrapper,
  python3,
  stdenvNoCC,
  zellij,
}:
stdenvNoCC.mkDerivation {
  name = "claude-session-registry";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.fileFilter (file: file.hasExt "py") ./.;
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  # The restore command drives zellij, claude and kitty directly rather than
  # resolving them from PATH: it runs from a Claude Code hook context and after
  # a fresh login, neither of which is guaranteed to have the user profile on
  # PATH -- and the tabs it opens inherit the zellij server's PATH, not its own.
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/libexec/claude-session-registry" "$out/bin"
    cp registry.py record.py restore.py "$out/libexec/claude-session-registry/"
    substituteInPlace "$out/libexec/claude-session-registry/restore.py" \
      --replace-fail '@zellij@' '${zellij}/bin/zellij' \
      --replace-fail '@claude@' '${claude-code}/bin/claude' \
      --replace-fail '@kitty@' '${kitty}/bin/kitty'
    makeWrapper ${python3.interpreter} "$out/bin/claude-session-record" \
      --add-flags "$out/libexec/claude-session-registry/record.py"
    makeWrapper ${python3.interpreter} "$out/bin/claude-session-restore" \
      --add-flags "$out/libexec/claude-session-registry/restore.py"
    runHook postInstall
  '';

  meta = {
    description = "Records live Claude Code conversations and replays them into zellij tabs";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
