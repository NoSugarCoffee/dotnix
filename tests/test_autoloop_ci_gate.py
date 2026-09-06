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


def _git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", *args],
        cwd=repo,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def _init_repo(root: Path) -> Path:
    """A clone with origin/main plus an autoloop branch one commit ahead."""
    origin = root / "origin.git"
    work = root / "work"
    subprocess.run(["git", "init", "--bare", str(origin)], check=True, capture_output=True)
    subprocess.run(["git", "clone", str(origin), str(work)], check=True, capture_output=True)
    _git(work, "config", "user.email", "test@example.com")
    _git(work, "config", "user.name", "Test")
    (work / "MARKER").write_text("main\n")
    _git(work, "add", "MARKER")
    _git(work, "commit", "-m", "main")
    _git(work, "branch", "-M", "main")
    _git(work, "push", "-u", "origin", "main")
    return work


def _add_branch_commit(work: Path, branch: str) -> str:
    _git(work, "checkout", "-b", branch)
    (work / "MARKER").write_text("branch\n")
    _git(work, "add", "MARKER")
    _git(work, "commit", "-m", "iteration")
    _git(work, "push", "-u", "origin", branch)
    _git(work, "checkout", "main")
    return _git(work, "rev-parse", f"refs/remotes/origin/{branch}")


def _stub_gh(root: Path, responses: dict[str, str]) -> Path:
    """A `gh` that echoes a canned payload per subcommand, recording its calls."""
    bin_dir = root / "bin"
    bin_dir.mkdir(exist_ok=True)
    stub = bin_dir / "gh"
    cases = "\n".join(
        f'  "{key}"*) cat <<\'PAYLOAD\'\n{value}\nPAYLOAD\n    ;;' for key, value in responses.items()
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


def _run(script: Path, cwd: Path, env: dict[str, str], bin_dir: Path) -> subprocess.CompletedProcess[str]:
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


def _verdict(root: Path, work: Path, config: dict[str, object], runs: str) -> dict[str, object]:
    config_path = root / "autoloop.json"
    out = root / "ci.json"
    config_path.write_text(json.dumps(config))
    bin_dir = _stub_gh(root, {"run list": runs})
    result = _run(
        VERIFY_SH,
        work,
        {"AUTOLOOP_JSON": str(config_path), "AUTOLOOP_CI_JSON": str(out)},
        bin_dir,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(out.read_text())


class VerifyCiTests(unittest.TestCase):
    def test_reports_none_when_the_branch_does_not_exist(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = _init_repo(root)
            verdict = _verdict(root, work, {"head_branch": "autoloop/absent"}, "[]")
            self.assertEqual(verdict["state"], "none")

    def test_reports_verified_when_ci_passed_on_the_head(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = _init_repo(root)
            sha = _add_branch_commit(work, "autoloop/p")
            runs = json.dumps(
                [
                    {
                        "headSha": sha,
                        "status": "completed",
                        "conclusion": "success",
                        "url": "https://example.invalid/run/1",
                    }
                ]
            )
            verdict = _verdict(root, work, {"head_branch": "autoloop/p"}, runs)
            self.assertEqual(verdict["state"], "verified")
            self.assertEqual(verdict["head_sha"], sha)
            self.assertEqual(verdict["run_url"], "https://example.invalid/run/1")

    def test_reports_failed_when_ci_failed_on_the_head(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = _init_repo(root)
            sha = _add_branch_commit(work, "autoloop/p")
            runs = json.dumps(
                [
                    {
                        "headSha": sha,
                        "status": "completed",
                        "conclusion": "failure",
                        "url": "https://example.invalid/run/2",
                    }
                ]
            )
            verdict = _verdict(root, work, {"head_branch": "autoloop/p"}, runs)
            self.assertEqual(verdict["state"], "failed")

    def test_reports_pending_when_no_run_covers_the_head(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = _init_repo(root)
            _add_branch_commit(work, "autoloop/p")
            runs = json.dumps(
                [
                    {
                        "headSha": "0" * 40,
                        "status": "completed",
                        "conclusion": "success",
                        "url": "https://example.invalid/run/3",
                    }
                ]
            )
            verdict = _verdict(root, work, {"head_branch": "autoloop/p"}, runs)
            self.assertEqual(verdict["state"], "pending")

    def test_reports_pending_while_the_run_is_still_going(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = _init_repo(root)
            sha = _add_branch_commit(work, "autoloop/p")
            runs = json.dumps(
                [
                    {
                        "headSha": sha,
                        "status": "in_progress",
                        "conclusion": None,
                        "url": "https://example.invalid/run/4",
                    }
                ]
            )
            verdict = _verdict(root, work, {"head_branch": "autoloop/p"}, runs)
            self.assertEqual(verdict["state"], "pending")


class DispatchCiTests(unittest.TestCase):
    def _dispatch(self, root: Path, branch_sha: str, existing_runs: str) -> str:
        # Most specific prefixes first: the stub's case statement takes the first
        # match, and every key here starts with "api repos/o/r".
        bin_dir = _stub_gh(
            root,
            {
                "api repos/o/r/branches/autoloop/p": json.dumps({"commit": {"sha": branch_sha}}),
                "api repos/o/r/branches?": json.dumps([{"name": "autoloop/p"}, {"name": "main"}]),
                "api repos/o/r/commits/main": json.dumps({"sha": "a" * 40}),
                "api repos/o/r": json.dumps({"default_branch": "main"}),
                "run list": existing_runs,
            },
        )
        result = _run(DISPATCH_SH, root, {"GITHUB_REPOSITORY": "o/r"}, bin_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        return (root / "gh-calls.log").read_text()

    def test_dispatches_ci_for_an_unbuilt_head(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            calls = self._dispatch(Path(tmp), "b" * 40, "[]")
            self.assertIn("workflow run ci.yml --ref autoloop/p", calls)

    def test_skips_a_head_that_already_has_a_run(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            calls = self._dispatch(Path(tmp), "b" * 40, json.dumps([{"headSha": "b" * 40}]))
            self.assertNotIn("workflow run", calls)

    def test_skips_a_branch_sitting_at_the_default_branch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            calls = self._dispatch(Path(tmp), "a" * 40, "[]")
            self.assertNotIn("workflow run", calls)


if __name__ == "__main__":
    unittest.main()
