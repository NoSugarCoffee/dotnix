"""Tests for the non-agent darwin DMG pin updater."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / ".github" / "workflows" / "scripts" / "update_darwin_packages.sh"

CLASH = Path("pkgs/clash-verge-rev-darwin/default.nix")
DESKTOP = Path("pkgs/claude-desktop-darwin/default.nix")
EGO = Path("pkgs/ego-lite-darwin/default.nix")
ORCA = Path("pkgs/orca-darwin/default.nix")

FRESH_AARCH64 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
FRESH_X86_64 = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="
FRESH_DESKTOP = "sha256-CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC="
FRESH_EGO_AARCH64 = "sha256-DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD="
FRESH_ORCA_AARCH64 = "sha256-EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE="
FRESH_ORCA_X86_64 = "sha256-FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF="


def _eval_json(
    *, clash: bool, desktop: bool, ego: bool = False, orca: bool = False, pinned: str = "2.5.2"
) -> dict[str, object]:
    proposed: dict[str, object] = {}
    if clash:
        proposed["clash-verge-rev"] = {
            "version": "9.9.9",
            "archHash": {
                "aarch64-darwin": FRESH_AARCH64,
                "x86_64-darwin": FRESH_X86_64,
            },
        }
    if desktop:
        proposed["claude-desktop"] = {"hash": FRESH_DESKTOP}
    if ego:
        proposed["ego-lite"] = {"archHash": {"aarch64-darwin": FRESH_EGO_AARCH64}}
    if orca:
        proposed["orca"] = {
            "version": "9.9.9",
            "archHash": {
                "aarch64-darwin": FRESH_ORCA_AARCH64,
                "x86_64-darwin": FRESH_ORCA_X86_64,
            },
        }
    return {
        "packages_current": 4 - len(proposed),
        "clash-verge-rev": {"pinned": pinned, "latest": "9.9.9", "current": not clash},
        "claude-desktop": {"current": not desktop},
        "ego-lite": {"current": not ego},
        "orca": {"pinned": "1.4.211", "latest": "9.9.9", "current": not orca},
        "proposed": proposed,
    }


class UpdateDarwinPackagesTest(unittest.TestCase):
    def _run(
        self, payload: dict[str, object]
    ) -> tuple[subprocess.CompletedProcess[str], Path, dict[str, str]]:
        work = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, work, ignore_errors=True)
        for rel in (CLASH, DESKTOP, EGO, ORCA):
            (work / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(REPO / rel, work / rel)

        eval_file = work / "eval.json"
        eval_file.write_text(json.dumps(payload))
        output = work / "github_output"
        output.touch()

        env = os.environ.copy()
        env.update(
            DARWIN_EVAL_JSON=str(eval_file),
            GITHUB_OUTPUT=str(output),
        )
        proc = subprocess.run(
            ["bash", str(SCRIPT)],
            cwd=work,
            env=env,
            check=False,
            text=True,
            capture_output=True,
        )
        return proc, work, _parse_output(output.read_text())

    def test_bumps_version_and_both_arch_hashes(self) -> None:
        proc, work, outputs = self._run(_eval_json(clash=True, desktop=False))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        text = (work / CLASH).read_text()

        self.assertIn('  version = "9.9.9";', text)
        self.assertIn(f'    aarch64-darwin = "{FRESH_AARCH64}";', text)
        self.assertIn(f'    x86_64-darwin = "{FRESH_X86_64}";', text)
        self.assertEqual(outputs["changed"], "true")
        self.assertIn("2.5.2 -> 9.9.9", outputs["summary"])

    def test_leaves_the_arch_name_table_alone(self) -> None:
        """archName's keys are the same nix attrs as archHash's, one block up."""
        _, work, _ = self._run(_eval_json(clash=True, desktop=False))
        text = (work / CLASH).read_text()

        self.assertIn('    aarch64-darwin = "aarch64";', text)
        self.assertIn('    x86_64-darwin = "x64";', text)

    def test_bumps_the_desktop_hash_and_keeps_its_version_label(self) -> None:
        proc, work, outputs = self._run(_eval_json(clash=False, desktop=True))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        text = (work / DESKTOP).read_text()
        original = (REPO / DESKTOP).read_text()

        self.assertIn(f'    hash = "{FRESH_DESKTOP}";', text)
        label = [ln for ln in original.splitlines() if ln.startswith("  version = ")]
        self.assertEqual([ln for ln in text.splitlines() if ln.startswith("  version = ")], label)
        self.assertIn(label[0].split('"')[1], outputs["summary"])

    def test_reports_no_change_when_both_pins_are_current(self) -> None:
        proc, work, outputs = self._run(_eval_json(clash=False, desktop=False))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(outputs["changed"], "false")
        self.assertEqual((work / CLASH).read_text(), (REPO / CLASH).read_text())
        self.assertEqual((work / DESKTOP).read_text(), (REPO / DESKTOP).read_text())
        self.assertEqual((work / EGO).read_text(), (REPO / EGO).read_text())
        self.assertEqual((work / ORCA).read_text(), (REPO / ORCA).read_text())

    def test_bumps_orca_version_and_both_arch_hashes_without_touching_clash(self) -> None:
        proc, work, outputs = self._run(_eval_json(clash=False, desktop=False, orca=True))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        text = (work / ORCA).read_text()

        self.assertIn('  version = "9.9.9";', text)
        self.assertIn(f'    aarch64-darwin = "{FRESH_ORCA_AARCH64}";', text)
        self.assertIn(f'    x86_64-darwin = "{FRESH_ORCA_X86_64}";', text)
        self.assertIn('    aarch64-darwin = "arm64";', text)
        self.assertIn('    x86_64-darwin = "x64";', text)
        self.assertEqual((work / CLASH).read_text(), (REPO / CLASH).read_text())
        self.assertIn("`orca-darwin`: 1.4.211 -> 9.9.9", outputs["summary"])

    def test_bumps_only_the_ego_arch_that_actually_changed(self) -> None:
        """Upstream can republish one arch without the other."""
        proc, work, outputs = self._run(_eval_json(clash=False, desktop=False, ego=True))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        text = (work / EGO).read_text()
        original = (REPO / EGO).read_text()

        self.assertIn(f'    aarch64-darwin = "{FRESH_EGO_AARCH64}";', text)
        untouched = [ln for ln in original.splitlines() if ln.startswith("    x86_64-darwin = \"sha256-")]
        self.assertEqual(
            [ln for ln in text.splitlines() if ln.startswith("    x86_64-darwin = \"sha256-")],
            untouched,
        )
        self.assertEqual(outputs["changed"], "true")

    def test_keeps_ego_arch_name_and_version_tables_intact(self) -> None:
        """archName, archHash and archVersion share their keys across three blocks."""
        _, work, outputs = self._run(_eval_json(clash=False, desktop=False, ego=True))
        text = (work / EGO).read_text()

        self.assertIn('    aarch64-darwin = "arm64";', text)
        self.assertIn('    x86_64-darwin = "x64";', text)
        version = [ln for ln in (REPO / EGO).read_text().splitlines() if ln.startswith("    aarch64-darwin = \"0")]
        self.assertEqual(
            [ln for ln in text.splitlines() if ln.startswith("    aarch64-darwin = \"0")],
            version,
        )
        self.assertIn(version[0].split('"')[1], outputs["summary"])

    def test_fails_when_only_part_of_a_proposal_matches(self) -> None:
        """A version bump landing without its hashes would pin a broken pair."""
        work = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, work, ignore_errors=True)
        (work / CLASH).parent.mkdir(parents=True, exist_ok=True)
        original = (REPO / CLASH).read_text()
        (work / CLASH).write_text(
            original.replace('    aarch64-darwin = "sha256-', '  aarch64-darwin = "sha256-')
        )

        eval_file = work / "eval.json"
        eval_file.write_text(json.dumps(_eval_json(clash=True, desktop=False)))
        env = os.environ.copy()
        env.update(DARWIN_EVAL_JSON=str(eval_file), GITHUB_OUTPUT=str(work / "out"))
        proc = subprocess.run(
            ["bash", str(SCRIPT)],
            cwd=work,
            env=env,
            check=False,
            text=True,
            capture_output=True,
        )

        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("aarch64-darwin", proc.stderr)
        self.assertNotIn('version = "9.9.9"', (work / CLASH).read_text())

    def test_fails_loudly_when_a_proposal_matches_nothing(self) -> None:
        """A silent no-op here would open an empty PR every night."""
        work = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, work, ignore_errors=True)
        (work / CLASH).parent.mkdir(parents=True, exist_ok=True)
        (work / CLASH).write_text("{ }\n")

        eval_file = work / "eval.json"
        eval_file.write_text(json.dumps(_eval_json(clash=True, desktop=False)))
        env = os.environ.copy()
        env.update(DARWIN_EVAL_JSON=str(eval_file), GITHUB_OUTPUT=str(work / "out"))
        proc = subprocess.run(
            ["bash", str(SCRIPT)],
            cwd=work,
            env=env,
            check=False,
            text=True,
            capture_output=True,
        )

        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("no line in", proc.stderr)


def _parse_output(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        if "<<" in lines[index]:
            key, _, delimiter = lines[index].partition("<<")
            body: list[str] = []
            index += 1
            while index < len(lines) and lines[index] != delimiter:
                body.append(lines[index])
                index += 1
            values[key] = "\n".join(body)
        else:
            key, _, value = lines[index].partition("=")
            values[key] = value
        index += 1
    return values


if __name__ == "__main__":
    unittest.main()
