"""Tests for the Autoloop CI gate: verdict reporting and CI dispatch."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCRIPTS = REPO / ".github" / "workflows" / "scripts"
VERIFY_SH = SCRIPTS / "autoloop_verify_ci.sh"
DISPATCH_SH = SCRIPTS / "autoloop_dispatch_ci.sh"


def _stub_gh(root: Path, responses: dict[str, str]) -> Path:
    """A `gh` that echoes a canned payload per subcommand, recording its calls.

    Keys are matched as prefixes of the joined arguments, in insertion order, so
    list the most specific ones first.
    """
    bin_dir = root / "bin"
    bin_dir.mkdir(exist_ok=True)
    stub = bin_dir / "gh"
    cases = "\n".join(
        f'  "{key}"*) cat <<\'PAYLOAD\'\n{value}\nPAYLOAD\n    ;;'
        for key, value in responses.items()
    )
    stub.write_text(
        "#!/usr/bin/env bash\n"
        f'echo "$*" >> "{root}/gh-calls.log"\n'
        'case "$*" in\n'
        f"{cases}\n"
        "  *) echo '' ;;\n"
        "esac\n"
    )
    stub.chmod(0o755)
    return bin_dir


def _run(
    script: Path, cwd: Path, env: dict[str, str], bin_dir: Path
) -> subprocess.CompletedProcess[str]:
    merged = os.environ.copy()
    merged.update(env)
    merged["PATH"] = f"{bin_dir}:{merged['PATH']}"
    return subprocess.run(
        ["bash", str(script)],
        cwd=cwd,
        env=merged,
        check=False,
        text=True,
        capture_output=True,
    )


def _completed_run(conclusion: str, url: str) -> str:
    return json.dumps(
        {"workflow_runs": [{"status": "completed", "conclusion": conclusion, "html_url": url}]}
    )


def _verdict(root: Path, head_sha: str | None, runs: str) -> dict[str, object]:
    """Run the verifier against a stubbed API. head_sha None means no branch."""
    config_path = root / "autoloop.json"
    out = root / "ci.json"
    config_path.write_text(json.dumps({"head_branch": "autoloop/p"}))
    branch = {} if head_sha is None else {"commit": {"sha": head_sha}}
    bin_dir = _stub_gh(
        root,
        {
            "api repos/o/r/branches/autoloop/p": json.dumps(branch),
            "api repos/o/r/commits/main": json.dumps({"sha": "a" * 40}),
            "api repos/o/r/actions/workflows/ci.yml/runs": runs,
        },
    )
    result = _run(
        VERIFY_SH,
        root,
        {
            "AUTOLOOP_JSON": str(config_path),
            "AUTOLOOP_CI_JSON": str(out),
            "GITHUB_REPOSITORY": "o/r",
            "DEFAULT_BRANCH": "main",
        },
        bin_dir,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(out.read_text())


class VerifyCiTests(unittest.TestCase):
    def test_reports_none_when_the_branch_does_not_exist(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            verdict = _verdict(Path(tmp), None, '{"workflow_runs": []}')
            self.assertEqual(verdict["state"], "none")
            self.assertIsNone(verdict["head_sha"])

    def test_reports_none_when_the_branch_sits_at_the_default_branch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            verdict = _verdict(Path(tmp), "a" * 40, '{"workflow_runs": []}')
            self.assertEqual(verdict["state"], "none")
            self.assertEqual(verdict["branch"], "autoloop/p")
            self.assertEqual(verdict["head_sha"], "a" * 40)

    def test_reports_verified_when_ci_passed_on_the_head(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            verdict = _verdict(
                Path(tmp), "b" * 40, _completed_run("success", "https://example.invalid/run/1")
            )
            self.assertEqual(verdict["state"], "verified")
            self.assertEqual(verdict["head_sha"], "b" * 40)
            self.assertEqual(verdict["run_url"], "https://example.invalid/run/1")

    def test_reports_failed_when_the_build_failed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            for conclusion in ("failure", "timed_out", "startup_failure"):
                verdict = _verdict(
                    Path(tmp),
                    "b" * 40,
                    _completed_run(conclusion, "https://example.invalid/run/2"),
                )
                self.assertEqual(verdict["state"], "failed", conclusion)

    def test_treats_a_build_that_never_ran_as_pending_not_failed(self) -> None:
        # cancelled/skipped/neutral say nothing about the commit; calling them
        # failures would spend the repair budget on a build that never happened.
        with tempfile.TemporaryDirectory() as tmp:
            for conclusion in ("cancelled", "skipped", "neutral", "action_required"):
                verdict = _verdict(
                    Path(tmp),
                    "b" * 40,
                    _completed_run(conclusion, "https://example.invalid/run/3"),
                )
                self.assertEqual(verdict["state"], "pending", conclusion)

    def test_reports_pending_when_no_run_covers_the_head(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            verdict = _verdict(Path(tmp), "b" * 40, '{"workflow_runs": []}')
            self.assertEqual(verdict["state"], "pending")

    def test_reports_pending_while_the_run_is_still_going(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            runs = json.dumps(
                {
                    "workflow_runs": [
                        {
                            "status": "in_progress",
                            "conclusion": None,
                            "html_url": "https://example.invalid/run/4",
                        }
                    ]
                }
            )
            verdict = _verdict(Path(tmp), "b" * 40, runs)
            self.assertEqual(verdict["state"], "pending")


class DispatchCiTests(unittest.TestCase):
    def _dispatch(self, root: Path, branches: list[dict[str, object]], run_count: int) -> str:
        bin_dir = _stub_gh(
            root,
            {
                "api repos/o/r/actions/runs": json.dumps({"total_count": run_count}),
                "api repos/o/r/commits/main": json.dumps({"sha": "a" * 40}),
                "api --paginate repos/o/r/branches": json.dumps(branches),
                "api repos/o/r": json.dumps({"default_branch": "main"}),
            },
        )
        result = _run(DISPATCH_SH, root, {"GITHUB_REPOSITORY": "o/r"}, bin_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        return (root / "gh-calls.log").read_text()

    def test_dispatches_ci_for_an_unbuilt_head(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            calls = self._dispatch(
                Path(tmp), [{"name": "autoloop/p", "commit": {"sha": "b" * 40}}], run_count=0
            )
            self.assertIn("workflow run ci.yml --ref autoloop/p", calls)

    def test_skips_a_head_that_already_has_a_run(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            calls = self._dispatch(
                Path(tmp), [{"name": "autoloop/p", "commit": {"sha": "b" * 40}}], run_count=1
            )
            self.assertNotIn("workflow run", calls)

    def test_skips_a_branch_sitting_at_the_default_branch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            calls = self._dispatch(
                Path(tmp), [{"name": "autoloop/p", "commit": {"sha": "a" * 40}}], run_count=0
            )
            self.assertNotIn("workflow run", calls)

    def test_ignores_branches_outside_the_autoloop_namespace(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            calls = self._dispatch(
                Path(tmp),
                [
                    {"name": "main", "commit": {"sha": "a" * 40}},
                    {"name": "feat/x", "commit": {"sha": "c" * 40}},
                ],
                run_count=0,
            )
            self.assertNotIn("workflow run", calls)

    def test_dispatches_every_unbuilt_branch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            calls = self._dispatch(
                Path(tmp),
                [
                    {"name": "autoloop/one", "commit": {"sha": "b" * 40}},
                    {"name": "autoloop/two", "commit": {"sha": "c" * 40}},
                ],
                run_count=0,
            )
            self.assertIn("workflow run ci.yml --ref autoloop/one", calls)
            self.assertIn("workflow run ci.yml --ref autoloop/two", calls)


if __name__ == "__main__":
    unittest.main()
