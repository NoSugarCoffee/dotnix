"""Reopen every recorded Claude Code conversation in a zellij tab.

Replays the records written by claude-session-record as `claude --resume <id>`,
which is the only way to land a pane back on the exact conversation it held:
`claude --continue` resolves to the newest conversation in a directory however
many panes that directory had.

Tabs are added to detached (background) sessions, so this needs no terminal of
its own -- attach afterwards with `zellij attach <name>`.
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
from collections import defaultdict
from pathlib import Path
from typing import Final, NamedTuple

ZELLIJ: Final[str] = "@zellij@"
SERVER_START_TIMEOUT: Final[float] = 10.0
SERVER_POLL_INTERVAL: Final[float] = 0.2


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
        digest = hashlib.sha256(str(self.cwd).encode()).hexdigest()[:6]
        return f"{self.cwd.name}-{digest}"

    @property
    def tab_name(self) -> str:
        return self.cwd.name


def registry_dir() -> Path:
    state_home = os.environ.get("XDG_STATE_HOME")
    root = Path(state_home) if state_home else Path.home() / ".local" / "state"
    return root / "claude-session-registry"


def load_conversations(directory: Path) -> list[Conversation]:
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


def unrestorable_reason(conversation: Conversation) -> str | None:
    if not conversation.cwd.is_dir():
        return f"directory is gone: {conversation.cwd}"
    if not conversation.transcript.is_file():
        return f"transcript is gone: {conversation.transcript}"
    return None


def live_sessions() -> set[str]:
    # `zellij ls` exits non-zero when there are simply no sessions.
    result = subprocess.run(
        [ZELLIJ, "ls", "-s"], capture_output=True, text=True, check=False
    )
    return {line.strip() for line in result.stdout.splitlines() if line.strip()}


def zellij(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [ZELLIJ, *args], capture_output=True, text=True, check=True
    )


def start_background_session(name: str) -> None:
    zellij("attach", "--create-background", name)
    deadline = time.monotonic() + SERVER_START_TIMEOUT
    while time.monotonic() < deadline:
        if name in live_sessions():
            return
        time.sleep(SERVER_POLL_INTERVAL)
    raise RuntimeError(
        f"zellij session {name!r} did not come up within "
        f"{SERVER_START_TIMEOUT:.0f}s"
    )


def open_tab(session: str, conversation: Conversation) -> None:
    zellij(
        "-s", session, "action", "new-tab",
        "--cwd", str(conversation.cwd),
        "--name", conversation.tab_name,
        "--", "claude", "--resume", conversation.session_id,
    )


def tab_ids(session: str) -> set[int]:
    result = zellij("-s", session, "action", "list-tabs")
    return {
        int(fields[0])
        for fields in (line.split() for line in result.stdout.splitlines())
        if fields and fields[0].isdigit()
    }


def close_tabs(session: str, ids: set[int]) -> None:
    """Drop the empty shell tab that creating a session leaves behind.

    Closing by id rather than by focus: a background session has no attached
    client, so the focus-relative close-tab is accepted and does nothing.
    """
    for tab_id in sorted(ids):
        try:
            zellij("-s", session, "action", "close-tab-by-id", str(tab_id))
        except subprocess.CalledProcessError as error:
            print(
                f"  warning: could not close placeholder tab {tab_id} in "
                f"{session!r}: {error.stderr.strip()}",
                file=sys.stderr,
            )


def group_by_session(
    conversations: list[Conversation],
) -> dict[str, list[Conversation]]:
    grouped: dict[str, list[Conversation]] = defaultdict(list)
    for conversation in conversations:
        grouped[conversation.target_session].append(conversation)
    return dict(grouped)


def restore_session(
    name: str, conversations: list[Conversation], dry_run: bool
) -> None:
    print(f"{name}: {len(conversations)} conversation(s)")
    for conversation in conversations:
        print(f"  {conversation.tab_name} -> claude --resume "
              f"{conversation.session_id}")
    if dry_run:
        return
    start_background_session(name)
    placeholders = tab_ids(name)
    try:
        for conversation in conversations:
            open_tab(name, conversation)
    except subprocess.CalledProcessError as error:
        # Half-populated sessions are worse than none: the session is live, so
        # a later run reports it as already running and never restores the
        # conversations that are missing from it.
        raise RuntimeError(
            f"{name!r} was only partly restored -- discard it with "
            f"`zellij kill-session {name}` before retrying: "
            f"{error.stderr.strip()}"
        ) from error
    finally:
        close_tabs(name, placeholders)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        # The live-session probe still runs: it is read-only, and skipping it
        # would make the preview promise sessions that are already up.
        help="print the restore plan without creating or changing anything",
    )
    arguments = parser.parse_args()

    directory = registry_dir()
    if not directory.is_dir():
        raise SystemExit(
            f"no registry at {directory} -- is claude-session-record "
            "registered as a SessionStart hook?"
        )

    conversations = load_conversations(directory)
    if not conversations:
        print(f"no recorded conversations in {directory}")
        return 0

    restorable: list[Conversation] = []
    for conversation in conversations:
        reason = unrestorable_reason(conversation)
        if reason:
            print(
                f"skipping {conversation.session_id}: {reason}",
                file=sys.stderr,
            )
            continue
        restorable.append(conversation)

    already_live = live_sessions()
    for name, group in sorted(group_by_session(restorable).items()):
        if name in already_live:
            print(f"{name}: already running, left alone")
            continue
        restore_session(name, group, arguments.dry_run)

    if not arguments.dry_run:
        print("\nattach with: zellij attach <name>")
    return 0


if __name__ == "__main__":
    sys.exit(main())
