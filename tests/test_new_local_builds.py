"""scripts/new-local-builds.sh: cache-miss gate over nix dry-run output.

A fake `nix` on PATH prints canned dry-run plans (or fails). The real binary
is never invoked.
"""

from __future__ import annotations

import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "scripts" / "new-local-builds.sh"

FAKE_NIX = """\
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1-} != build || ${2-} != --dry-run || $# -ne 3 ]]; then
  echo "unexpected nix invocation: $*" >&2
  exit 2
fi
flake=${3%%#*}
case $flake in
  fail-*)
    echo "error: could not fetch inputs for $flake" >&2
    exit 1
    ;;
esac
plan=${NIX_PLAN_DIR:?}/$flake
if [[ ! -f $plan ]]; then
  echo "no dry-run plan for $flake" >&2
  exit 1
fi
# nix prints the build plan on stderr; the gate discards stdout.
cat "$plan" >&2
"""


def plan(*paths: str, fetched: tuple[str, ...] = ()) -> str:
    """Dry-run text in the shape `nix build --dry-run` writes to stderr."""
    lines = [f"these {len(paths)} derivations will be built:"]
    lines.extend(f"  {path}" for path in paths)
    lines.append(f"these {len(fetched)} paths will be fetched:")
    lines.extend(f"  {path}" for path in fetched)
    return "\n".join(lines) + "\n"


def store(name: str, digest: str) -> str:
    return f"/nix/store/{digest}-{name}.drv"


class NewLocalBuildsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.plans = root / "plans"
        self.plans.mkdir()
        bindir = root / "bin"
        bindir.mkdir()
        nix = bindir / "nix"
        nix.write_text(FAKE_NIX)
        nix.chmod(nix.stat().st_mode | stat.S_IEXEC)
        self.env = os.environ.copy()
        self.env["PATH"] = f"{bindir}{os.pathsep}{self.env.get('PATH', '')}"
        self.env["NIX_PLAN_DIR"] = str(self.plans)

    def write_plan(self, flake: str, text: str) -> None:
        (self.plans / flake).write_text(text)

    def run_gate(self, base: str, candidate: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(SCRIPT), base, candidate, "pkg"],
            check=False,
            text=True,
            capture_output=True,
            env=self.env,
            timeout=10,
        )

    def test_candidate_dry_run_failure_is_not_an_empty_build_list(self) -> None:
        home = store("home-manager-files", "a" * 32)
        self.write_plan("base", plan(home))
        result = self.run_gate("base", "fail-candidate")
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("No new local builds.", result.stdout)
        self.assertIn("could not fetch inputs for fail-candidate", result.stderr)

    def test_base_dry_run_failure_is_not_compared(self) -> None:
        home = store("home-manager-files", "a" * 32)
        self.write_plan("candidate", plan(home))
        result = self.run_gate("fail-base", "candidate")
        self.assertNotEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("No new local builds.", result.stdout)
        # A failed base scan must not look like "base built nothing", which
        # would report every candidate build as a new cache miss.
        self.assertNotIn("builds these locally", result.stdout)
        self.assertIn("could not fetch inputs for fail-base", result.stderr)

    def test_new_local_build_fails_without_claiming_base_fetched_it(self) -> None:
        # Absent from the base closure entirely: base did not fetch it either.
        home = store("home-manager-files", "a" * 32)
        gh = store("gh-2.104.0", "b" * 32)
        self.write_plan("base", plan(home))
        self.write_plan("candidate", plan(home, gh))
        result = self.run_gate("base", "candidate")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(
            "::error::candidate builds these locally, but base does not:",
            result.stdout,
        )
        self.assertNotIn("fetched them from a cache", result.stdout)
        self.assertEqual(result.stdout.splitlines()[1], "gh")

    def test_fetch_only_plans_pass(self) -> None:
        fetched = "/nix/store/" + ("f" * 32) + "-hello-2.12"
        text = plan(fetched=(fetched,))
        self.write_plan("base", text)
        self.write_plan("candidate", text)
        result = self.run_gate("base", "candidate")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "No new local builds.")

    def test_version_bump_of_a_shared_local_build_is_not_new(self) -> None:
        old = store("gh-2.100.0", "a" * 32)
        new = store("gh-2.104.0", "b" * 32)
        files = store("home-manager-files", "c" * 32)
        self.write_plan("base", plan(files, old))
        self.write_plan("candidate", plan(files, new))
        result = self.run_gate("base", "candidate")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), "No new local builds.")

    def test_package_base_fetched_and_candidate_builds_is_still_a_miss(self) -> None:
        files = store("home-manager-files", "a" * 32)
        fetched = "/nix/store/" + ("d" * 32) + "-bitwarden-cli-2026.1.0"
        built = store("bitwarden-cli-2026.1.1", "e" * 32)
        self.write_plan("base", plan(files, fetched=(fetched,)))
        self.write_plan("candidate", plan(files, built))
        result = self.run_gate("base", "candidate")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("bitwarden-cli", result.stdout.splitlines())
        self.assertNotIn("home-manager-files", result.stdout)


if __name__ == "__main__":
    unittest.main()
