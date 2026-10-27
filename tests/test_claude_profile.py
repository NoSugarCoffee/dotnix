"""Run apps/claude-code/claude-profile.sh against a throwaway HOME with a fake claude."""

from __future__ import annotations

import json
import os
import shutil
import signal
import subprocess
import tempfile
import textwrap
import time
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "apps" / "claude-code" / "claude-profile.sh"

# Stands in for claude: optionally replaces settings.json the way an atomic
# write does, creates a profile-only file, or adds an MCP server, then exits
# with FAKE_CLAUDE_STATUS. wait-ready writes a sentinel and blocks until
# continue is touched so tests can signal the wrapper or edit ~/.claude.json.
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
    case " $* " in *" break-json "*)
      printf 'not-json' >"$d/.claude.json";;
    esac
    case " $* " in *" wait-ready "*)
      : >"$HOME/.fake-claude-ready"
      while [ ! -f "$HOME/.fake-claude-continue" ]; do sleep 0.05; done;;
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

    def start_profile(self, *args: str) -> subprocess.Popen[str]:
        return subprocess.Popen(
            ["bash", str(SCRIPT), "work", *args],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
            env={**self.env, "FAKE_CLAUDE_STATUS": "0"},
        )

    def wait_for(self, path: Path, timeout: float = 5.0) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if path.exists():
                return
            time.sleep(0.05)
        self.fail(f"timed out waiting for {path}")

    def finish_profile(self, proc: subprocess.Popen[str]) -> subprocess.CompletedProcess[str]:
        (self.home / ".fake-claude-continue").touch()
        stdout, stderr = proc.communicate(timeout=30)
        return subprocess.CompletedProcess(proc.args, proc.returncode or 0, stdout, stderr)

    def shared_json(self) -> dict:
        return json.loads((self.home / ".claude.json").read_text())

    def profile_json(self) -> dict:
        return json.loads((self.profile / ".claude.json").read_text())

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

    def _kill_group(self, pid: int) -> None:
        try:
            os.killpg(pid, signal.SIGKILL)
        except OSError:
            pass

    def wait_exited(self, proc: subprocess.Popen[str], timeout: float = 5.0) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                if proc.stdout:
                    proc.stdout.close()
                if proc.stderr:
                    proc.stderr.close()
                return
            time.sleep(0.05)
        proc.kill()
        self.fail("wrapper did not exit after signal")

    def test_mcp_added_before_signal_survives_the_next_run(self) -> None:
        for sig in (signal.SIGTERM, signal.SIGHUP):
            with self.subTest(signal=sig.name):
                (self.home / ".fake-claude-ready").unlink(missing_ok=True)
                (self.home / ".fake-claude-continue").unlink(missing_ok=True)
                (self.home / ".claude.json").write_text(
                    json.dumps(
                        {"oauthAccount": "shared-account", "mcpServers": {"gitlab": {}}, "projects": {"/repo": {}}}
                    )
                )
                proc = self.start_profile("add-mcp", "wait-ready")
                self.addCleanup(proc.kill)
                self.addCleanup(lambda pid=proc.pid: self._kill_group(pid))
                self.wait_for(self.home / ".fake-claude-ready")
                self.assertIn("added", self.profile_json()["mcpServers"])

                os.kill(proc.pid, sig)
                self.wait_exited(proc)

                follow_up = self.run_profile()
                self.assertEqual(follow_up.returncode, 0, follow_up.stderr)
                self.assertIn("added", self.shared_json()["mcpServers"])
                self.assertIn("added", self.profile_json()["mcpServers"])
                self.assertEqual(self.shared_json()["oauthAccount"], "shared-account")

    def test_prunes_shared_symlinks_whose_targets_are_gone(self) -> None:
        plugins = self.shared / "plugins"
        plugins.mkdir()

        result = self.run_profile()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.profile / "plugins").is_symlink())
        outside = self.profile / "kept-link"
        outside.symlink_to(self.home / "does-not-exist")
        shutil.rmtree(plugins)

        result = self.run_profile()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.profile / "plugins").is_symlink())
        self.assertFalse((self.profile / "plugins").exists())
        self.assertTrue(outside.is_symlink())
        self.assertEqual((self.profile / "settings.json").resolve(), (self.shared / "settings.json").resolve())
        (self.profile / "plugins").mkdir()

    def test_absent_shared_key_is_deleted_instead_of_written_back(self) -> None:
        self.profile.mkdir(parents=True)
        (self.profile / ".claude.json").write_text(
            json.dumps(
                {
                    "oauthAccount": "work-account",
                    "userID": "w",
                    "mcpServers": {"stale": {}},
                    "projects": {"/old": {}},
                }
            )
        )
        (self.home / ".claude.json").write_text(
            json.dumps({"oauthAccount": "shared-account", "projects": {"/repo": {}}})
        )

        result = self.run_profile()

        self.assertEqual(result.returncode, 0, result.stderr)
        profile_json = self.profile_json()
        self.assertEqual(profile_json["oauthAccount"], "work-account")
        self.assertEqual(profile_json["userID"], "w")
        self.assertNotIn("mcpServers", profile_json)
        self.assertEqual(profile_json["projects"], {"/repo": {}})
        shared_json = self.shared_json()
        self.assertNotIn("mcpServers", shared_json)
        self.assertEqual(shared_json["oauthAccount"], "shared-account")
        self.assertEqual(shared_json["projects"], {"/repo": {}})

    def test_write_back_failure_keeps_claude_status(self) -> None:
        result = self.run_profile("break-json", "new-file", status=7)

        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertIn("failed to write shared config back", result.stderr)
        self.assertIn("new-feature.json exists only in", result.stderr)
        shared_json = self.shared_json()
        self.assertEqual(shared_json["mcpServers"], {"gitlab": {}})
        self.assertEqual(shared_json["oauthAccount"], "shared-account")

    def test_synced_json_stays_private(self) -> None:
        previous = os.umask(0)
        try:
            result = self.run_profile()
        finally:
            os.umask(previous)

        self.assertEqual(result.returncode, 0, result.stderr)
        for path in (self.home / ".claude.json", self.profile / ".claude.json"):
            self.assertEqual(path.stat().st_mode & 0o777, 0o600, path)

    def test_writeback_keeps_projects_a_concurrent_claude_added(self) -> None:
        proc = self.start_profile("add-mcp", "wait-ready")
        self.addCleanup(proc.kill)
        self.addCleanup(lambda pid=proc.pid: self._kill_group(pid))
        self.wait_for(self.home / ".fake-claude-ready")

        concurrent = self.shared_json()
        concurrent["projects"]["/repo"]["hasTrustDialogAccepted"] = True
        concurrent["projects"]["/other"] = {"allowedTools": ["Bash"]}
        (self.home / ".claude.json").write_text(json.dumps(concurrent))

        result = self.finish_profile(proc)
        self.assertEqual(result.returncode, 0, result.stderr)
        shared = self.shared_json()
        self.assertEqual(shared["mcpServers"], {"gitlab": {}, "added": {}})
        self.assertEqual(shared["projects"]["/repo"], {"hasTrustDialogAccepted": True})
        self.assertEqual(shared["projects"]["/other"], {"allowedTools": ["Bash"]})
        self.assertEqual(shared["oauthAccount"], "shared-account")

    def test_does_not_link_shared_json_or_legacy_config_into_the_profile(self) -> None:
        self.profile.mkdir(parents=True)
        (self.profile / ".claude.json").write_text(json.dumps({"oauthAccount": "work-account", "userID": "w"}))
        (self.shared / ".claude.json").write_text(json.dumps({"oauthAccount": "shared-account"}))
        (self.shared / ".claude.json.bak").write_text("{}")
        (self.shared / ".config.json").write_text("{}")

        result = self.run_profile()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.profile / ".claude.json").is_symlink())
        self.assertFalse((self.profile / ".claude.json.bak").exists())
        self.assertFalse((self.profile / ".config.json").exists())
        self.assertEqual(self.profile_json()["oauthAccount"], "work-account")
        migrated = list((self.home / ".claude-profiles" / ".migrated").glob("*/*/.claude.json"))
        self.assertEqual(migrated, [])

    def test_rejects_dot_prefixed_profile_names(self) -> None:
        result = subprocess.run(
            ["bash", str(SCRIPT), ".migrated"], check=False, text=True, capture_output=True, env=self.env
        )

        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.home / ".claude-profiles" / ".migrated" / ".migrated").exists())


if __name__ == "__main__":
    unittest.main()
