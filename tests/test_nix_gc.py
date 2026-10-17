"""Sandbox the generated nix-gc script against fake profile directories.

CI runs this via `python3 -m unittest discover`. The script is extracted from
apps/nix/default.nix the same way test_copy_apps.py extracts copyApps: Nix
interpolations are substituted, then the shell is executed with stub
nix-env / nix-collect-garbage on PATH.
"""

from __future__ import annotations

import os
import re
import shutil
import stat
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
NIX_FILE = REPO / "apps" / "nix" / "default.nix"


def nix_unescape(s: str) -> str:
    return s.replace("'''", "''").replace("''$", "$").replace("''\\", "\\")


def nix_dedent(s: str) -> str:
    lines = s.split("\n")
    indents = [len(line) - len(line.lstrip(" ")) for line in lines if line.strip()]
    strip = min(indents) if indents else 0
    return "\n".join(line[strip:] if len(line) >= strip else line for line in lines)


def generations_to_keep() -> int:
    match = re.search(r"(?m)^  generationsToKeep = (\d+);$", NIX_FILE.read_text())
    if not match:
        raise AssertionError("could not parse generationsToKeep from apps/nix/default.nix")
    return int(match.group(1))


def extract_nix_gc() -> str:
    keep = str(generations_to_keep())
    text = NIX_FILE.read_text()
    start_tok = 'pkgs.writeShellScript "nix-gc" \'\'\n'
    start = text.index(start_tok) + len(start_tok)
    end = text.index("\n  '';", start)
    block = nix_dedent(nix_unescape(text[start:end]))
    block = block.replace("${config.nix.package}/bin/nix-env", "nix-env")
    block = block.replace("${config.nix.package}/bin/nix-collect-garbage", "nix-collect-garbage")
    block = block.replace("${config.xdg.stateHome}", "${XDG_STATE_HOME}")
    block = block.replace("${toString generationsToKeep}", keep)
    leftovers = re.findall(r"\$\{(?:config|lib|pkgs|toString)[^}]*\}", block)
    if leftovers:
        raise AssertionError(f"unsubstituted nix interpolations: {leftovers}")
    return block


STUB_NIX_ENV = textwrap.dedent(
    """\
    #!/bin/sh
    set -eu
    log=${NIX_ENV_LOG:?}
    printf '%s\\n' "$*" >> "$log"
    for arg in "$@"; do
      case "$arg" in
        *stray*)
          echo "error: '$arg' is not a Nix profile" >&2
          exit 1
          ;;
      esac
    done
    exit 0
    """
)

STUB_NIX_COLLECT_GARBAGE = textwrap.dedent(
    """\
    #!/bin/sh
    set -eu
    log=${NIX_GC_LOG:?}
    echo ran >> "$log"
    exit 0
    """
)


class NixGcCommentTest(unittest.TestCase):
    def test_comment_does_not_claim_rollback_is_exactly_one_switch(self) -> None:
        text = NIX_FILE.read_text()
        self.assertNotIn("rollback reaches back exactly one switch", text)
        self.assertIn("after the job runs", text)

    def test_keep_count_is_read_from_nix_declaration(self) -> None:
        keep = generations_to_keep()
        self.assertGreaterEqual(keep, 1)
        self.assertIn(f"generationsToKeep = {keep};", NIX_FILE.read_text())


class NixGcScriptTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.keep = generations_to_keep()
        cls.block = extract_nix_gc()
        if cls.keep < 1:
            raise AssertionError(f"generationsToKeep must be >= 1, got {cls.keep}")
        default = f"${{GENERATIONS_TO_KEEP:-{cls.keep}}}"
        if default not in cls.block:
            raise AssertionError(f"extracted script does not default to {default}")

    def setUp(self) -> None:
        self.box = Path(tempfile.mkdtemp(prefix="nix-gc-"))
        self.addCleanup(shutil.rmtree, self.box, ignore_errors=True)
        self.home = self.box / "home"
        self.xdg_state = self.home / ".local" / "state"
        self.xdg_profiles = self.xdg_state / "nix" / "profiles"
        self.user_profiles = self.box / "var" / "nix" / "profiles" / "per-user" / "alice"
        self.bin = self.box / "bin"
        self.env_log = self.box / "nix-env.log"
        self.gc_log = self.box / "nix-gc.log"
        for path in (self.home, self.bin):
            path.mkdir(parents=True)
        self.env_log.write_text("")
        self.gc_log.write_text("")
        self._install_stub("nix-env", STUB_NIX_ENV)
        self._install_stub("nix-collect-garbage", STUB_NIX_COLLECT_GARBAGE)
        self.script = self.box / "nix-gc.sh"
        self.script.write_text(self.block)

    def _install_stub(self, name: str, body: str) -> None:
        path = self.bin / name
        path.write_text(body)
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def make_profile(self, directory: Path, name: str) -> Path:
        directory.mkdir(parents=True, exist_ok=True)
        gen = directory / f"{name}-1-link"
        if not gen.exists():
            gen.symlink_to("/nix/store/fake-generation")
        profile = directory / name
        if not profile.exists():
            profile.symlink_to(gen.name)
        return profile

    def env(self, **extra: str) -> dict[str, str]:
        merged = os.environ.copy()
        merged.update(
            {
                "HOME": str(self.home),
                "USER": "alice",
                "XDG_STATE_HOME": str(self.xdg_state),
                "XDG_NIX_PROFILES": str(self.xdg_profiles),
                "NIX_USER_PROFILES": str(self.user_profiles),
                "NIX_PROFILE_LINK": str(self.home / ".nix-profile"),
                "NIX_ENV_LOG": str(self.env_log),
                "NIX_GC_LOG": str(self.gc_log),
                "PATH": f"{self.bin}:/usr/bin:/bin",
            }
        )
        merged.update(extra)
        return merged

    def run_gc(self, **extra: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(self.script)],
            cwd=self.box,
            env=self.env(**extra),
            text=True,
            capture_output=True,
            check=False,
        )

    def env_profiles(self) -> list[str]:
        if not self.env_log.read_text().strip():
            return []
        profiles: list[str] = []
        for line in self.env_log.read_text().splitlines():
            parts = line.split()
            self.assertIn("--profile", parts, line)
            self.assertIn("--delete-generations", parts, line)
            self.assertIn(f"+{self.keep}", parts, line)
            profiles.append(parts[parts.index("--profile") + 1])
        return profiles

    def assert_collected(self, collected: bool = True) -> None:
        if collected:
            self.assertEqual(self.gc_log.read_text().strip(), "ran")
        else:
            self.assertEqual(self.gc_log.read_text(), "")

    def test_xdg_profiles_are_pruned(self) -> None:
        hm = self.make_profile(self.xdg_profiles, "home-manager")
        user = self.make_profile(self.xdg_profiles, "profile")
        result = self.run_gc()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertCountEqual(self.env_profiles(), [str(hm), str(user)])
        self.assert_collected()
        self.assertIn(str(hm), result.stderr)
        self.assertIn(str(user), result.stderr)

    def test_per_user_profiles_are_pruned_when_xdg_is_missing(self) -> None:
        legacy = self.make_profile(self.user_profiles, "profile")
        result = self.run_gc()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.env_profiles(), [str(legacy)])
        self.assertIn(str(legacy), result.stderr)
        self.assert_collected()

    def test_nix_profile_parent_is_pruned(self) -> None:
        other = self.box / "elsewhere" / "profiles"
        profile = self.make_profile(other, "profile")
        (self.home / ".nix-profile").symlink_to(profile)
        result = self.run_gc()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.env_profiles(), [str(profile)])
        self.assertIn(str(profile), result.stderr)
        self.assert_collected()

    def test_relative_nix_profile_parent_is_pruned(self) -> None:
        other = self.home / "alt-profiles"
        profile = self.make_profile(other, "profile")
        (self.home / ".nix-profile").symlink_to("alt-profiles/profile")
        result = self.run_gc()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.env_profiles(), [str(profile)])

    def test_duplicate_dirs_are_pruned_once(self) -> None:
        hm = self.make_profile(self.xdg_profiles, "home-manager")
        (self.home / ".nix-profile").symlink_to(self.xdg_profiles / "home-manager")
        result = self.run_gc()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.env_profiles(), [str(hm)])

    def test_generation_links_are_not_passed_to_nix_env(self) -> None:
        hm = self.make_profile(self.xdg_profiles, "home-manager")
        result = self.run_gc()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.env_profiles(), [str(hm)])
        self.assertNotIn("-link", "\n".join(self.env_profiles()))

    def test_xdg_and_per_user_are_both_pruned(self) -> None:
        hm = self.make_profile(self.xdg_profiles, "home-manager")
        legacy = self.make_profile(self.user_profiles, "profile")
        result = self.run_gc()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertCountEqual(self.env_profiles(), [str(hm), str(legacy)])
        self.assert_collected()

    def test_missing_dirs_are_skipped_when_another_has_profiles(self) -> None:
        hm = self.make_profile(self.xdg_profiles, "home-manager")
        result = self.run_gc()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.env_profiles(), [str(hm)])
        self.assertFalse(self.user_profiles.exists())

    def test_unwritable_dirs_are_skipped(self) -> None:
        hm = self.make_profile(self.xdg_profiles, "home-manager")
        legacy = self.make_profile(self.user_profiles, "profile")
        self.user_profiles.chmod(0o555)
        try:
            if os.access(self.user_profiles, os.W_OK):
                self.skipTest("process can write mode 555 directories (likely root)")
            result = self.run_gc()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.env_profiles(), [str(hm)])
            self.assertNotIn(str(legacy), self.env_profiles())
        finally:
            self.user_profiles.chmod(0o755)

    def test_fails_when_no_profile_is_pruned(self) -> None:
        result = self.run_gc()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("no profile was pruned", result.stderr)
        self.assertEqual(self.env_log.read_text(), "")
        self.assert_collected(False)

    def test_fails_when_profile_dir_has_no_profile_symlinks(self) -> None:
        self.xdg_profiles.mkdir(parents=True)
        (self.xdg_profiles / "notes.txt").write_text("not a profile\n")
        result = self.run_gc()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("no profile was pruned", result.stderr)
        self.assert_collected(False)

    def test_nix_env_failure_warns_and_continues(self) -> None:
        good = self.make_profile(self.xdg_profiles, "home-manager")
        stray = self.xdg_profiles / "stray"
        stray.symlink_to("/tmp/not-a-profile")
        result = self.run_gc()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("warning", result.stderr)
        self.assertIn(str(stray), result.stderr)
        self.assertIn(str(good), result.stderr)
        self.assertCountEqual(self.env_profiles(), [str(good), str(stray)])
        self.assert_collected()

    def test_all_nix_env_failures_fail_loudly_without_collecting_garbage(self) -> None:
        stray = self.xdg_profiles / "stray"
        self.xdg_profiles.mkdir(parents=True)
        stray.symlink_to("/tmp/not-a-profile")
        result = self.run_gc()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("warning", result.stderr)
        self.assertIn("no profile was pruned", result.stderr)
        self.assert_collected(False)

