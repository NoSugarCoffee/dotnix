"""Unit tests for claude-session-restore's session naming."""

from __future__ import annotations

import importlib.util
import subprocess
import unittest
from pathlib import Path

SOURCE = (
    Path(__file__).resolve().parents[1]
    / "pkgs"
    / "claude-session-registry"
    / "restore.py"
)
_spec = importlib.util.spec_from_file_location("claude_session_restore", SOURCE)
restore = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(restore)


def conversation(cwd: str, zellij_session: str = "") -> restore.Conversation:
    return restore.Conversation(
        session_id="069d51bc-ff63-4183-912e-99640196f2bd",
        cwd=Path(cwd),
        transcript=Path("/dev/null"),
        zellij_session=zellij_session,
    )


class TargetSessionTests(unittest.TestCase):
    def test_recorded_session_name_is_used_verbatim(self):
        target = conversation("/Users/x/code/dotnix", "brave-zebra").target_session
        self.assertEqual(target, "brave-zebra")

    def test_synthesized_name_fits_the_socket_path_budget(self):
        target = conversation("/Users/liangliangdai").target_session
        self.assertLessEqual(len(target), restore.SYNTHESIZED_NAME_LIMIT)

    def test_long_directory_name_is_truncated_to_the_budget(self):
        target = conversation("/Users/x/a-very-long-project-directory-name")
        self.assertLessEqual(len(target), restore.SYNTHESIZED_NAME_LIMIT)

    def test_directories_sharing_a_basename_get_distinct_names(self):
        first = conversation("/Users/x/one/shared-basename").target_session
        second = conversation("/Users/x/two/shared-basename").target_session
        self.assertNotEqual(first, second)

    def test_synthesized_name_is_stable_across_calls(self):
        cwd = "/Users/x/code/dotnix"
        self.assertEqual(
            conversation(cwd).target_session, conversation(cwd).target_session
        )


class ReportedTests(unittest.TestCase):
    def test_reported_carries_the_stderr_subprocess_drops(self):
        error = subprocess.CalledProcessError(
            1,
            ["/nix/store/abc-zellij/bin/zellij", "attach", "--create-background", "s"],
            stderr="Error: the IPC socket path is too long\n",
        )
        message = restore.reported(error)
        self.assertIn("zellij attach --create-background s", message)
        self.assertIn("IPC socket path is too long", message)
        self.assertNotIn("/nix/store", message)


if __name__ == "__main__":
    unittest.main()
