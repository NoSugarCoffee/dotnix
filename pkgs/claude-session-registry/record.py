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
from typing import Final

# A conversation whose terminal died leaves no SessionEnd at all, and one
# killed along with its terminal reports "other" -- both must stay restorable,
# so only a deliberate exit retires a record.
DELIBERATE_EXITS: Final[frozenset[str]] = frozenset(
    {"clear", "logout", "prompt_input_exit"}
)


def registry_dir() -> Path:
    state_home = os.environ.get("XDG_STATE_HOME")
    root = Path(state_home) if state_home else Path.home() / ".local" / "state"
    return root / "claude-session-registry"


def build_record(
    payload: dict[str, object], session_id: str
) -> dict[str, str]:
    cwd = payload.get("cwd")
    return {
        "session_id": session_id,
        # Hooks are spawned by the conversation's own process, so the payload
        # directory and the hook's own cwd name the same place.
        "cwd": cwd if isinstance(cwd, str) and cwd else os.getcwd(),
        "transcript_path": str(payload.get("transcript_path") or ""),
        "zellij_session": os.environ.get("ZELLIJ_SESSION_NAME", ""),
        "zellij_pane_id": os.environ.get("ZELLIJ_PANE_ID", ""),
    }


def write_record(path: Path, record: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    staged = path.with_name(path.name + ".tmp")
    staged.write_text(json.dumps(record, indent=2) + "\n")
    staged.replace(path)


def main() -> int:
    payload: dict[str, object] = json.loads(sys.stdin.read())
    session_id = payload.get("session_id")
    if not isinstance(session_id, str) or not session_id:
        raise ValueError(f"hook payload carries no session_id: {payload!r}")

    event = payload.get("hook_event_name")
    path = registry_dir() / f"{session_id}.json"

    if event == "SessionEnd":
        if payload.get("reason") in DELIBERATE_EXITS:
            path.unlink(missing_ok=True)
        return 0
    if event != "SessionStart":
        raise ValueError(f"hook registered on unsupported event: {event!r}")

    write_record(path, build_record(payload, session_id))
    return 0


if __name__ == "__main__":
    sys.exit(main())
