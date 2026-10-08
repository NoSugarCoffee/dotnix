"""Exercise the session registry module and the record hook against a temp registry."""

from __future__ import annotations

import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

PACKAGE = Path(__file__).resolve().parents[1] / "pkgs" / "claude-session-registry"
sys.path.insert(0, str(PACKAGE))
import registry  # noqa: E402

_spec = importlib.util.spec_from_file_location("claude_session_record", PACKAGE / "record.py")
assert _spec is not None and _spec.loader is not None
record = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(record)

SESSION = "069d51bc-ff63-4183-912e-99640196f2bd"


class RegistryTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.directory = self.root / "registry"
        self.project = self.root / "project"
        self.project.mkdir()

    def transcript(self, *entries: dict[str, object]) -> Path:
        path = self.root / f"{len(list(self.root.glob('*.jsonl')))}.jsonl"
        path.write_text("".join(json.dumps(entry) + "\n" for entry in entries))
        return path

    def conversation(self, transcript: Path) -> registry.Conversation:
        return registry.Conversation(SESSION, self.project, transcript, "")


class RegistryTests(RegistryTestCase):
    def test_registry_dir_honours_xdg_state_home(self) -> None:
        self.assertEqual(
            registry.registry_dir({"XDG_STATE_HOME": "/state"}, Path("/home/u")),
            Path("/state/claude-session-registry"),
        )
        self.assertEqual(
            registry.registry_dir({}, Path("/home/u")),
            Path("/home/u/.local/state/claude-session-registry"),
        )

    def test_written_record_loads_back_unchanged(self) -> None:
        written = registry.Conversation(SESSION, self.project, self.root / "t.jsonl", "brave-zebra")
        registry.write(self.directory, written)

        self.assertEqual(registry.load_all(self.directory), [written])
        self.assertEqual(list(self.directory.iterdir()), [self.directory / f"{SESSION}.json"])

    def test_record_from_before_this_module_still_loads(self) -> None:
        self.directory.mkdir()
        (self.directory / f"{SESSION}.json").write_text(json.dumps({
            "session_id": SESSION,
            "cwd": str(self.project),
            "transcript_path": "",
            "zellij_session": "",
            "zellij_pane_id": "terminal_3",
        }))

        [loaded] = registry.load_all(self.directory)
        self.assertEqual(loaded.cwd, self.project)
        self.assertEqual(loaded.zellij_session, "")

    def test_headers_only_transcript_holds_no_conversation(self) -> None:
        transcript = self.transcript({"type": "summary"}, {"type": "mode"})
        self.assertTrue(registry.holds_no_conversation(transcript))

    def test_a_message_makes_a_conversation(self) -> None:
        transcript = self.transcript({"type": "summary"}, {"type": "user"})
        self.assertFalse(registry.holds_no_conversation(transcript))

    def test_a_torn_last_line_is_not_evidence_of_emptiness(self) -> None:
        transcript = self.root / "torn.jsonl"
        transcript.write_bytes(b'{"type": "summary"}\n{"type": "us\xe4')
        self.assertFalse(registry.holds_no_conversation(transcript))

    def test_open_conversation_is_never_retired(self) -> None:
        conversation = self.conversation(self.root / "missing.jsonl")
        self.assertIsNone(registry.retirable_reason(conversation, {SESSION}))

    def test_closed_never_messaged_conversation_is_retired(self) -> None:
        conversation = self.conversation(self.transcript({"type": "summary"}))
        self.assertEqual(registry.retirable_reason(conversation, set()), "never messaged")

    def test_closed_conversation_without_transcript_is_retired(self) -> None:
        reason = registry.retirable_reason(self.conversation(self.root / "missing.jsonl"), set())
        self.assertIn("no transcript was ever written", reason or "")

    def test_messaged_conversation_is_kept_and_restorable(self) -> None:
        conversation = self.conversation(self.transcript({"type": "assistant"}))
        self.assertIsNone(registry.retirable_reason(conversation, set()))
        self.assertIsNone(registry.unrestorable_reason(conversation))

    def test_conversation_in_a_deleted_directory_is_unrestorable(self) -> None:
        conversation = registry.Conversation(SESSION, self.root / "gone", self.transcript({"type": "user"}), "")
        self.assertIn("directory is gone", registry.unrestorable_reason(conversation) or "")


class RecordHookTests(RegistryTestCase):
    def start(self, **payload: object) -> None:
        record.handle(
            {"session_id": SESSION, "hook_event_name": "SessionStart", **payload},
            self.directory,
            {"ZELLIJ_SESSION_NAME": "brave-zebra", "ZELLIJ_PANE_ID": "3"},
            "/fallback",
        )

    def end(self, reason: str) -> None:
        record.handle(
            {"session_id": SESSION, "hook_event_name": "SessionEnd", "reason": reason},
            self.directory,
            {},
            "/fallback",
        )

    def test_session_start_records_the_conversation(self) -> None:
        self.start(cwd=str(self.project), transcript_path="/t.jsonl")

        [loaded] = registry.load_all(self.directory)
        self.assertEqual(loaded, registry.Conversation(SESSION, self.project, Path("/t.jsonl"), "brave-zebra"))

    def test_session_start_without_cwd_falls_back_to_the_hook_cwd(self) -> None:
        self.start()
        self.assertEqual(registry.load_all(self.directory)[0].cwd, Path("/fallback"))

    def test_deliberate_exit_retires_the_record(self) -> None:
        self.start(cwd=str(self.project))
        self.end("prompt_input_exit")
        self.assertEqual(registry.load_all(self.directory), [])

    def test_terminal_death_keeps_the_record_restorable(self) -> None:
        self.start(cwd=str(self.project))
        self.end("other")
        self.assertEqual(len(registry.load_all(self.directory)), 1)

    def test_payload_without_session_id_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            record.handle({"hook_event_name": "SessionStart"}, self.directory, {}, "/")

    def test_unsupported_event_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            record.handle({"session_id": SESSION, "hook_event_name": "Stop"}, self.directory, {}, "/")


if __name__ == "__main__":
    unittest.main()
