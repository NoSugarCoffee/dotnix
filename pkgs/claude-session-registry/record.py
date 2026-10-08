"""Record which Claude Code conversations are live, keyed by conversation id.

Claude Code persists every conversation under ~/.claude/projects, but nothing
on disk says which of them were *open*, or in which pane. `claude --continue`
only resolves to the newest conversation in a directory, so a project running
several panes at once cannot be restored from the transcripts alone. This hook
keeps one record per live conversation; claude-session-restore replays them.
"""

import json
import os
import sys
from pathlib import Path
from typing import Final, Mapping

import registry

# A conversation whose terminal died leaves no SessionEnd at all, and one
# killed along with its terminal reports "other" -- both must stay restorable,
# so only a deliberate exit retires a record.
DELIBERATE_EXITS: Final[frozenset[str]] = frozenset({"clear", "logout", "prompt_input_exit"})


def handle(payload: dict[str, object], directory: Path, env: Mapping[str, str], cwd: str) -> None:
    session_id = payload.get("session_id")
    if not isinstance(session_id, str) or not session_id:
        raise ValueError(f"hook payload carries no session_id: {payload!r}")

    event = payload.get("hook_event_name")
    if event == "SessionEnd":
        if payload.get("reason") in DELIBERATE_EXITS:
            registry.remove(directory, session_id)
        return
    if event != "SessionStart":
        raise ValueError(f"hook registered on unsupported event: {event!r}")

    payload_cwd = payload.get("cwd")
    registry.write(
        directory,
        registry.Conversation(
            session_id=session_id,
            # Hooks are spawned by the conversation's own process, so the
            # payload directory and the hook's own cwd name the same place.
            cwd=Path(payload_cwd if isinstance(payload_cwd, str) and payload_cwd else cwd),
            transcript=Path(str(payload.get("transcript_path") or "")),
            zellij_session=env.get("ZELLIJ_SESSION_NAME", ""),
        ),
    )


def main() -> int:
    handle(
        json.loads(sys.stdin.read()),
        registry.registry_dir(os.environ, Path.home()),
        os.environ,
        os.getcwd(),
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
