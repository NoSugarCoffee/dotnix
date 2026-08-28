"""Reopen every recorded Claude Code conversation in a zellij tab.

Replays the records written by claude-session-record as `claude --resume <id>`,
which is the only way to land a pane back on the exact conversation it held:
`claude --continue` resolves to the newest conversation in a directory however
many panes that directory had.

Zellij tabs are added to detached (background) sessions, so this needs no
terminal of its own; a kitty tab is then opened per session to attach to it,
which is the half that would otherwise be typed out by hand.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from collections import defaultdict
from pathlib import Path
from typing import Final, NamedTuple

ZELLIJ: Final[str] = "@zellij@"
# A new tab inherits the zellij *server's* environment, not this process's. A
# server kitty spawned at startup carries a PATH without ~/.nix-profile/bin, so
# a bare `claude` is not found and the pane dies the instant it opens.
CLAUDE: Final[str] = "@claude@"
KITTY: Final[str] = "@kitty@"
# The transcript entry types that constitute something to resume; the rest are
# headers and metadata a conversation writes before any message arrives.
CONTENT_ENTRIES: Final[frozenset[str]] = frozenset({"user", "assistant"})
RESUME_PROCESS: Final[re.Pattern[str]] = re.compile(
    r"claude --resume (\S+)"
)
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
        digest = hashlib.sha256(str(self.cwd).encode()).hexdigest()[:12]
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


def retirable_reason(
    conversation: Conversation, active: set[str]
) -> str | None:
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


def retire_empty_records(
    directory: Path,
    conversations: list[Conversation],
    active: set[str],
    dry_run: bool,
) -> list[Conversation]:
    """Drop records that nothing could ever be restored from.

    A terminal that dies takes its SessionEnd hook with it, so the records of
    conversations that were never messaged accumulate with nothing to resume --
    every later run then reports them as skipped, forever.
    """
    kept: list[Conversation] = []
    retired: list[tuple[Conversation, str]] = []
    for conversation in conversations:
        reason = retirable_reason(conversation, active)
        if reason:
            retired.append((conversation, reason))
        else:
            kept.append(conversation)

    if not retired:
        return kept

    print(f"retiring {len(retired)} record(s) with nothing to resume:")
    for conversation, reason in retired:
        print(f"  {conversation.tab_name}/{conversation.session_id}: {reason}")
        if not dry_run:
            (directory / f"{conversation.session_id}.json").unlink(
                missing_ok=True
            )
    return kept


def unrestorable_reason(conversation: Conversation) -> str | None:
    if not conversation.cwd.is_dir():
        return f"directory is gone: {conversation.cwd}"
    if not conversation.transcript.is_file():
        # A conversation writes no transcript until its first message, so one
        # just opened is indistinguishable on disk from one whose transcript
        # was deleted. Neither can be resumed, so say what is actually known
        # rather than asserting the alarming half of it.
        return f"no transcript at {conversation.transcript} (deleted, or " \
               f"never written because the conversation was never messaged)"
    return None


def session_states() -> dict[str, bool]:
    """Map every zellij session name to whether its server is still running.

    `zellij ls` lists exited-but-resurrectable sessions alongside live ones and
    `-s` prints only their names, so the two are indistinguishable there. A
    terminal restart leaves exactly those husks behind -- read as live, they
    suppress the restore that is the whole point of this command.
    """
    # `zellij ls` exits non-zero when there are simply no sessions.
    result = subprocess.run(
        [ZELLIJ, "ls", "-n"], capture_output=True, text=True, check=False
    )
    states: dict[str, bool] = {}
    for line in result.stdout.splitlines():
        # Session names may contain spaces, and one could contain "EXITED"
        # itself, so split on the suffix zellij appends rather than on
        # whitespace.
        name, separator, details = line.partition(" [Created ")
        if not separator:
            continue
        states[name] = "EXITED" not in details
    return states


def live_sessions() -> set[str]:
    return {name for name, live in session_states().items() if live}


def zellij(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [ZELLIJ, *args], capture_output=True, text=True, check=True
    )


def discard_exited_session(name: str) -> None:
    """Drop an exited session's husk so the name is free for a fresh one.

    Attaching to a husk resurrects its serialized layout instead of creating an
    empty session, mixing the restored tabs in with the dead panes.
    """
    zellij("delete-session", name)


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
        "--", CLAUDE, "--resume", conversation.session_id,
    )


def active_session_ids() -> set[str]:
    """Conversations Claude Code already holds open, in a pane or in the
    background.

    Authoritative where the process table is not. A background agent owns its
    session and `--resume` refuses to take it over, so a pane opened for one
    dies the instant it starts -- indistinguishable, afterwards, from a pane
    that was never restored at all.
    """
    listed = subprocess.run(
        [CLAUDE, "agents", "--json"], capture_output=True, text=True,
    )
    if listed.returncode != 0:
        # Guessing "nothing is open" here would hand every background agent a
        # pane that dies on arrival, which is the failure this check exists to
        # prevent.
        raise SystemExit(
            f"`claude agents --json` failed ({listed.returncode}) -- cannot "
            f"tell which conversations are already open: "
            f"{listed.stderr.strip()}"
        )
    agents = {entry["sessionId"] for entry in json.loads(listed.stdout)}

    # `claude agents` knows every background agent and every conversation
    # started bare, but not the ones this command itself resumed into a pane.
    processes = subprocess.run(
        ["ps", "-u", str(os.getuid()), "-o", "args="],
        capture_output=True, text=True, check=True,
    )
    return agents | set(RESUME_PROCESS.findall(processes.stdout))


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


def has_client(session: str) -> bool:
    """Whether a terminal is already attached to this session.

    `zellij ls` cannot tell attached from detached, but a session's own
    list-clients prints one row per connected client under a header row.
    """
    result = zellij("-s", session, "action", "list-clients")
    return any(line.strip() for line in result.stdout.splitlines()[1:])


def detached_sessions(names: list[str]) -> list[str]:
    """Which of the caller's sessions have no terminal on them.

    Callers pass only names that this run has left standing; a name not live
    among those is one a dry run would have created, so it needs a terminal
    just as much as a live-but-unattached one does.
    """
    live = live_sessions()
    return [name for name in names if name not in live or not has_client(name)]


def open_terminal(session: str, socket: str) -> None:
    window = os.environ.get("KITTY_WINDOW_ID")
    # Without a window to anchor to, kitty puts the tab in whichever OS window
    # happens to be focused when the call lands.
    placement = ["--match", f"window_id:{window}"] if window else []
    subprocess.run(
        [
            KITTY, "@", "--to", socket, "launch",
            "--type=tab", "--dont-take-focus", *placement,
            "--", ZELLIJ, "attach", session,
        ],
        capture_output=True, text=True, check=True,
    )


def attach_sessions(names: list[str], dry_run: bool) -> None:
    if not names:
        print("\nno session to attach to")
        return

    detached = detached_sessions(names)
    if not detached:
        print("\nevery session already has a terminal attached")
        return

    print(f"\nattaching {len(detached)} session(s) in new kitty tabs:")
    for name in detached:
        print(f"  zellij attach {name}")
    if dry_run:
        return

    socket = os.environ.get("KITTY_LISTEN_ON", "")
    if not socket:
        # Restoring already succeeded; only the terminals are missing, and
        # saying which ones beats failing the whole command over it.
        print(
            "  KITTY_LISTEN_ON is unset (not running under kitty, or "
            "allow_remote_control is off) -- run those by hand",
            file=sys.stderr,
        )
        return
    for name in detached:
        try:
            open_terminal(name, socket)
        except subprocess.CalledProcessError as error:
            # A KITTY_LISTEN_ON left over from an exited kitty fails every
            # launch. The sessions are restored either way, so name the ones
            # that ended up without a terminal rather than abandoning the rest.
            print(
                f"  warning: no kitty tab for {name!r}, attach by hand: "
                f"{error.stderr.strip()}",
                file=sys.stderr,
            )


def group_by_session(
    conversations: list[Conversation],
) -> dict[str, list[Conversation]]:
    grouped: dict[str, list[Conversation]] = defaultdict(list)
    for conversation in conversations:
        grouped[conversation.target_session].append(conversation)
    return dict(grouped)


def announce(conversations: list[Conversation]) -> None:
    for conversation in conversations:
        print(f"  {conversation.tab_name} -> claude --resume "
              f"{conversation.session_id}")


def top_up_session(
    name: str, missing: list[Conversation], dry_run: bool
) -> None:
    """Add the tabs a live session is missing rather than skipping it whole.

    A session that came up half-populated -- or one the user opened by hand --
    is still live, so treating liveness as "done" strands every conversation
    that has no pane in it.
    """
    print(f"{name}: live, adding {len(missing)} missing conversation(s)")
    announce(missing)
    if dry_run:
        return
    for conversation in missing:
        open_tab(name, conversation)


def restore_session(
    name: str, conversations: list[Conversation], exited: bool, dry_run: bool
) -> None:
    state = " (exited, will be recreated)" if exited else ""
    print(f"{name}: {len(conversations)} conversation(s){state}")
    announce(conversations)
    if dry_run:
        return
    if exited:
        discard_exited_session(name)
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
    parser.add_argument(
        "--no-attach",
        dest="attach",
        action="store_false",
        help="leave the restored sessions detached instead of opening a "
             "kitty tab for each",
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

    active = active_session_ids()
    states = session_states()
    conversations = retire_empty_records(
        directory, conversations, active, arguments.dry_run
    )

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

    grouped = group_by_session(restorable)
    # Only the sessions this run leaves standing can be attached to: `zellij
    # attach` on a name with no server creates an empty session rather than
    # reaching the conversations that name was recorded for.
    attachable: list[str] = []
    for name in sorted(grouped):
        missing = [c for c in grouped[name] if c.session_id not in active]
        if not missing:
            print(f"{name}: every conversation is already open, left alone")
            # "Already open" also covers background agents, which hold a
            # conversation without a zellij session of their own -- so being
            # left alone is no promise that the session exists.
            if states.get(name, False):
                attachable.append(name)
            continue
        attachable.append(name)
        if states.get(name, False):
            top_up_session(name, missing, arguments.dry_run)
            continue
        restore_session(name, missing, name in states, arguments.dry_run)

    if arguments.attach:
        attach_sessions(attachable, arguments.dry_run)
    elif not arguments.dry_run:
        print("\nattach with: zellij attach <name>")
    return 0


if __name__ == "__main__":
    sys.exit(main())
