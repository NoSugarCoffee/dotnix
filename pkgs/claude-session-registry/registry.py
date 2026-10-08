"""The on-disk registry of live Claude Code conversations.

claude-session-record writes one record per conversation; claude-session-restore
reads them back. Both go through this module, so the record schema, where it
lives, and which records are worth keeping are decided in one place.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Final, Mapping, NamedTuple

# The transcript entry types that constitute something to resume; the rest are
# headers and metadata a conversation writes before any message arrives.
CONTENT_ENTRIES: Final[frozenset[str]] = frozenset({"user", "assistant"})
# A session's name is the last component of its unix IPC socket path, and the
# 103-byte limit on those is nearly spent by macOS's per-user $TMPDIR before
# zellij appends anything of its own.
SYNTHESIZED_NAME_LIMIT: Final[int] = 20
SYNTHESIZED_DIGEST_LENGTH: Final[int] = 8


class Conversation(NamedTuple):
    session_id: str
    cwd: Path
    transcript: Path
    zellij_session: str

    @property
    def target_session(self) -> str:
        if self.zellij_session:
            return self.zellij_session
        # Conversations started outside zellij have no session to return to,
        # so one is invented per directory. The digest keeps two projects
        # sharing a basename from being merged into a single session.
        digest = hashlib.sha256(str(self.cwd).encode()).hexdigest()[:SYNTHESIZED_DIGEST_LENGTH]
        stem = self.cwd.name[: SYNTHESIZED_NAME_LIMIT - SYNTHESIZED_DIGEST_LENGTH - 1]
        return f"{stem}-{digest}"

    @property
    def tab_name(self) -> str:
        return self.cwd.name


def registry_dir(env: Mapping[str, str], home: Path) -> Path:
    state_home = env.get("XDG_STATE_HOME")
    root = Path(state_home) if state_home else home / ".local" / "state"
    return root / "claude-session-registry"


def record_path(directory: Path, session_id: str) -> Path:
    return directory / f"{session_id}.json"


def write(directory: Path, conversation: Conversation) -> None:
    path = record_path(directory, conversation.session_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    staged = path.with_name(path.name + ".tmp")
    staged.write_text(
        json.dumps(
            {
                "session_id": conversation.session_id,
                "cwd": str(conversation.cwd),
                "transcript_path": str(conversation.transcript),
                "zellij_session": conversation.zellij_session,
            },
            indent=2,
        )
        + "\n"
    )
    staged.replace(path)


def load_all(directory: Path) -> list[Conversation]:
    conversations: list[Conversation] = []
    for path in sorted(directory.glob("*.json")):
        raw = json.loads(path.read_text())
        conversations.append(
            Conversation(
                session_id=raw["session_id"],
                cwd=Path(raw["cwd"]),
                transcript=Path(raw.get("transcript_path") or ""),
                zellij_session=raw.get("zellij_session") or "",
            )
        )
    return conversations


def remove(directory: Path, session_id: str) -> None:
    record_path(directory, session_id).unlink(missing_ok=True)


def holds_no_conversation(transcript: Path) -> bool:
    """Whether a transcript records nothing that could be resumed.

    Claude Code writes headers -- a bridge-session line, titles, mode markers
    -- before the first message lands, so the file existing is no evidence that
    anything was ever said in it.
    """
    if not transcript.is_file():
        return True
    # Read bytes, not text: a conversation appending right now can cut its last
    # line mid-character, and an iterating text handle decodes before any of
    # this function's error handling can run.
    with transcript.open("rb") as handle:
        for line in handle:
            if not line.strip():
                continue
            try:
                entry = json.loads(line)
            except (json.JSONDecodeError, UnicodeDecodeError):
                # Unreadable is not evidence of emptiness, and this decides
                # whether to delete the record.
                return False
            if entry.get("type") in CONTENT_ENTRIES:
                return False
    return True


def retirable_reason(conversation: Conversation, active: set[str]) -> str | None:
    """Why a record can never be restored from, if it cannot.

    Only conversations no longer open are considered. One still open may yet
    receive its first message, and no second SessionStart will come to write
    the record again -- which also covers the transcript merely lagging, since
    a record can be written before its transcript appears, or the transcript
    may never appear at all.

    Liveness of the *zellij session* is deliberately not consulted. A session
    routinely outlives a conversation that was opened in it and never messaged,
    so it holds such records back forever while saying nothing about them.
    """
    if conversation.session_id in active:
        return None
    if not conversation.transcript.is_file():
        return f"no transcript was ever written at {conversation.transcript}"
    if holds_no_conversation(conversation.transcript):
        return "never messaged"
    return None


def unrestorable_reason(conversation: Conversation) -> str | None:
    if not conversation.cwd.is_dir():
        return f"directory is gone: {conversation.cwd}"
    if not conversation.transcript.is_file():
        # A conversation writes no transcript until its first message, so one
        # just opened is indistinguishable on disk from one whose transcript
        # was deleted. Neither can be resumed, so say what is actually known
        # rather than asserting the alarming half of it.
        return (
            f"no transcript at {conversation.transcript} (deleted, or "
            f"never written because the conversation was never messaged)"
        )
    return None
