"""Tests for the runner-side Autoloop evaluator wrapper."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
EVAL_SH = REPO / ".github" / "workflows" / "scripts" / "autoloop_eval.sh"


def _run(repo: Path, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    merged = os.environ.copy()
    merged.update(env)
    return subprocess.run(
        ["bash", str(EVAL_SH)],
        cwd=repo,
        env=merged,
        check=False,
        text=True,
        capture_output=True,
    )


def _git(repo: Path, *args: str) -> None:
    subprocess.run(
        ["git", *args],
        cwd=repo,
        check=True,
        capture_output=True,
        text=True,
    )


def _init_repo(root: Path) -> tuple[Path, Path]:
    origin = root / "origin.git"
    work = root / "work"
    origin.mkdir()
    subprocess.run(["git", "init", "--bare", str(origin)], check=True, capture_output=True)
    subprocess.run(["git", "clone", str(origin), str(work)], check=True, capture_output=True)
    _git(work, "config", "user.email", "test@example.com")
    _git(work, "config", "user.name", "Test")
    scripts = work / ".github" / "workflows" / "scripts"
    scripts.mkdir(parents=True)
    (work / "MARKER").write_text("main\n")
    _git(work, "add", "MARKER")
    _git(work, "commit", "-m", "main")
    _git(work, "branch", "-M", "main")
    _git(work, "push", "-u", "origin", "main")
    return origin, work


def _write_stub_eval(work: Path, executable: bool) -> Path:
    scripts = work / ".github" / "workflows" / "scripts"
    scripts.mkdir(parents=True, exist_ok=True)
    stub = scripts / "eval_darwin_packages_freshness.sh"
    stub.write_text(
        "#!/usr/bin/env bash\n"
        'jq -n --arg tree "$(tr -d "\\n" < MARKER)" \'{packages_current: 0, tree: $tree}\'\n'
    )
    mode = 0o755 if executable else 0o644
    stub.chmod(mode)
    return stub


class AutoloopEvalTests(unittest.TestCase):
    def test_runs_child_eval_without_execute_bit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _origin, work = _init_repo(root)
            stub = _write_stub_eval(work, executable=False)
            self.assertFalse(os.access(stub, os.X_OK))

            config = root / "autoloop.json"
            out = root / "eval.json"
            config.write_text(
                '{"selected": "darwin-packages-freshness", "head_branch": null}'
            )
            result = _run(
                work,
                {
                    "AUTOLOOP_JSON": str(config),
                    "AUTOLOOP_EVAL_JSON": str(out),
                },
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            payload = out.read_text()
            self.assertIn('"packages_current": 0', payload)
            self.assertIn('"selected": "darwin-packages-freshness"', payload)

    def test_evaluates_the_autoloop_branch_not_the_default_ref(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _origin, work = _init_repo(root)
            _write_stub_eval(work, executable=True)

            _git(work, "checkout", "-b", "autoloop/darwin-packages-freshness")
            (work / "MARKER").write_text("branch\n")
            _git(work, "add", "MARKER")
            _git(work, "commit", "-m", "branch")
            _git(work, "push", "-u", "origin", "autoloop/darwin-packages-freshness")
            _git(work, "checkout", "main")

            config = root / "autoloop.json"
            out = root / "eval.json"
            config.write_text(
                '{"selected": "darwin-packages-freshness",'
                ' "head_branch": "autoloop/darwin-packages-freshness"}'
            )
            result = _run(
                work,
                {
                    "AUTOLOOP_JSON": str(config),
                    "AUTOLOOP_EVAL_JSON": str(out),
                },
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            payload = out.read_text()
            self.assertIn('"tree": "branch"', payload)
            head = subprocess.run(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                cwd=work,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.strip()
            self.assertEqual(head, "autoloop/darwin-packages-freshness")


if __name__ == "__main__":
    unittest.main()
