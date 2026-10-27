"""Run apps/claude-code/claude-profile.sh against a throwaway HOME with a fake claude."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "apps" / "claude-code" / "claude-profile.sh"

# Stands in for claude: optionally replaces settings.json the way an atomic
# write does, creates a profile-only file, or adds an MCP server, then exits
# with FAKE_CLAUDE_STATUS.
FAKE_CLAUDE = textwrap.dedent(
    """\
    #!/bin/sh
    d=$CLAUDE_CONFIG_DIR
    case " $* " in *" replace-settings "*)
      printf '{"theme":"edited"}' >"$d/settings.json.tmp" && mv "$d/settings.json.tmp" "$d/settings.json";;
    esac
    case " $* " in *" new-file "*) : >"$d/new-feature.json";; esac
    case " $* " in *" add-mcp "*)
      python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['mcpServers']['added']={}; json.dump(d, open(p,'w'))" "$d/.claude.json";;
    esac
    exit "${FAKE_CLAUDE_STATUS:-0}"
    """
)


class ClaudeProfileTest(unittest.TestCase):
    def setUp(self) -> None:
        self.home = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.shared = self.home / ".claude"
        self.profile = self.home / ".claude-profiles" / "work"
        (self.shared / "projects" / "shared-project").mkdir(parents=True)
        (self.shared / "settings.json").write_text('{"theme":"shared"}')
        (self.shared / "history.jsonl").write_text("shared\n")
        (self.shared / "remote-settings.json").write_text("{}")
        (self.home / ".claude.json").write_text(
            json.dumps({"oauthAccount": "shared-account", "mcpServers": {"gitlab": {}}, "projects": {"/repo": {}}})
        )
        bin_dir = self.home / "bin"
        bin_dir.mkdir()
        fake = bin_dir / "claude"
        fake.write_text(FAKE_CLAUDE)
        fake.chmod(0o755)
        self.env = {**os.environ, "HOME": str(self.home), "PATH": f"{bin_dir}:{os.environ['PATH']}"}

    def run_profile(self, *args: str, status: int = 0) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(SCRIPT), "work", *args],
            check=False,
            text=True,
            capture_output=True,
            timeout=30,
            env={**self.env, "FAKE_CLAUDE_STATUS": str(status)},
        )

    def write_existing_profile(self) -> None:
        (self.profile / "projects" / "profile-project").mkdir(parents=True)
        (self.profile / "settings.json").write_text('{"theme":"profile"}')
        (self.profile / "history.jsonl").write_text("profile\n")
        (self.profile / ".claude.json").write_text(json.dumps({"oauthAccount": "work-account", "userID": "w"}))

    def migrated_settings(self) -> list[str]:
        return sorted(p.read_text() for p in (self.home / ".claude-profiles" / ".migrated").glob("*/*/settings.json"))

    def test_links_shared_entries_except_account_bound_ones(self) -> None:
        result = self.run_profile()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.profile / "settings.json").resolve(), (self.shared / "settings.json").resolve())
        self.assertTrue((self.profile / "projects").is_symlink())
        self.assertFalse((self.profile / "remote-settings.json").exists())

    def test_first_run_merges_existing_profile_and_keeps_its_account(self) -> None:
        self.write_existing_profile()

        result = self.run_profile()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.shared / "settings.json").read_text(), '{"theme":"shared"}')
        self.assertEqual((self.shared / "history.jsonl").read_text(), "shared\nprofile\n")
        self.assertTrue((self.shared / "projects" / "profile-project").is_dir())
        self.assertEqual(self.migrated_settings(), ['{"theme":"profile"}'])
        profile_json = json.loads((self.profile / ".claude.json").read_text())
        self.assertEqual(profile_json["oauthAccount"], "work-account")
        self.assertEqual(profile_json["mcpServers"], {"gitlab": {}})
        self.assertEqual(profile_json["projects"], {"/repo": {}})

    def test_replaced_symlink_is_adopted_into_shared_on_exit(self) -> None:
        self.write_existing_profile()

        result = self.run_profile("replace-settings")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.shared / "settings.json").read_text(), '{"theme":"edited"}')
        self.assertTrue((self.profile / "settings.json").is_symlink())
        self.assertEqual(self.migrated_settings(), ['{"theme":"profile"}', '{"theme":"shared"}'])

    def test_mcp_changes_flow_back_without_touching_shared_account(self) -> None:
        result = self.run_profile("add-mcp")

        self.assertEqual(result.returncode, 0, result.stderr)
        shared_json = json.loads((self.home / ".claude.json").read_text())
        self.assertEqual(shared_json["mcpServers"], {"gitlab": {}, "added": {}})
        self.assertEqual(shared_json["oauthAccount"], "shared-account")

    def test_warns_about_profile_only_entries(self) -> None:
        result = self.run_profile("new-file")

        self.assertIn("new-feature.json exists only in", result.stderr)
        self.assertNotIn(".claude.json exists only in", result.stderr)

    def test_propagates_claude_exit_status(self) -> None:
        self.assertEqual(self.run_profile(status=7).returncode, 7)

    def test_rejects_path_like_profile_names(self) -> None:
        result = subprocess.run(
            ["bash", str(SCRIPT), "../escape"], check=False, text=True, capture_output=True, env=self.env
        )

        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.home / "escape").exists())


if __name__ == "__main__":
    unittest.main()
