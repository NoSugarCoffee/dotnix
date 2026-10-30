"""The /Applications copy must not replace a bundle home-manager did not stamp.

CI runs this via `python3 -m unittest discover`. The activation is Darwin-only
in the module; the sentinel helper follows home.nix (xattr there, a hidden
file elsewhere). ditto, codesign, and pkill are stubbed on PATH so the copy
and failure paths do not depend on the host having those tools.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
MODULE = REPO / "apps" / "cua-driver" / "default.nix"

IS_DARWIN = sys.platform == "darwin"
SENTINEL_ATTR = "home-manager.copied"
SENTINEL_FILE = ".home-manager-copied"


def nix_dedent(s: str) -> str:
    lines = s.split("\n")
    indents = [len(line) - len(line.lstrip(" ")) for line in lines if line.strip()]
    strip = min(indents) if indents else 0
    return "\n".join(line[strip:] if len(line) >= strip else line for line in lines)


def extract_activation() -> str:
    text = MODULE.read_text()
    marker = text.index("sourceApp=")
    start = text.rfind("\n", 0, marker) + 1
    end = text.index("\n", text.index("''", marker))
    block = text[start:end]
    closer = block.rfind("''")
    if closer < 0:
        raise AssertionError("activation string terminator not found")
    return nix_dedent(block[:closer])


def stamp(app: Path, value: str) -> None:
    if IS_DARWIN:
        subprocess.run(["/usr/bin/xattr", "-w", SENTINEL_ATTR, value, str(app)], check=True)
    else:
        (app / SENTINEL_FILE).write_text(value)


def has_sentinel(app: Path) -> bool:
    if IS_DARWIN:
        result = subprocess.run(
            ["/usr/bin/xattr", "-p", SENTINEL_ATTR, str(app)],
            capture_output=True,
            check=False,
        )
        return result.returncode == 0
    return (app / SENTINEL_FILE).exists()


class CuaDriverAppActivationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        bash_version = subprocess.run(
            ["bash", "-c", 'echo "${BASH_VERSINFO[0]} ${BASH_VERSINFO[1]}"'],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.split()
        if tuple(map(int, bash_version)) < (4, 2):
            raise unittest.SkipTest(f"bash {'.'.join(bash_version)} on PATH is older than 4.2")
        cls.block = extract_activation()

    def setUp(self) -> None:
        self.box = Path(tempfile.mkdtemp(prefix="cua-driver-app-"))
        self.addCleanup(shutil.rmtree, self.box, ignore_errors=True)
        self.apps = self.box / "Applications"
        self.apps.mkdir()
        self.store = self.box / "store" / "CuaDriver.app"
        macos = self.store / "Contents" / "MacOS"
        macos.mkdir(parents=True)
        (macos / "cua-driver").write_text("store\n")
        self.marker = self.box / "state" / "cua-driver-app-source"
        self.marker.parent.mkdir()
        self.dest = self.apps / "CuaDriver.app"

    def run_activation(self, stubs: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        script = self.box / "activate.sh"
        text = self.block
        text = text.replace(
            'sourceApp=${lib.escapeShellArg "${cua-driver}/Applications/CuaDriver.app"}',
            f"sourceApp={self.store}",
        )
        text = text.replace("dest=/Applications/CuaDriver.app", f"dest={self.dest}")
        text = text.replace(
            'marker=${lib.escapeShellArg "${config.xdg.stateHome}/home-manager/cua-driver-app-source"}',
            f"marker={self.marker}",
        )
        env = os.environ.copy()
        if stubs:
            stubdir = self.box / "bin"
            stubdir.mkdir()
            for name, body in stubs.items():
                path = stubdir / name
                path.write_text(f"#!/bin/sh\n{body}")
                path.chmod(0o755)
                text = text.replace(f"/usr/bin/{name}", name)
            env["PATH"] = f"{stubdir}{os.pathsep}{env.get('PATH', '')}"
        if "${" in text:
            raise AssertionError(f"activation still has nix syntax:\n{text}")
        script.write_text(text)
        runner = self.box / "run.sh"
        runner.write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            "DRY_RUN_CMD=\n"
            "warnEcho() { echo \"$@\" >&2; }\n"
            f"source {script}\n"
        )
        return subprocess.run(
            ["bash", str(runner)],
            cwd=self.box,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def make_installed(self, payload: str) -> None:
        macos = self.dest / "Contents" / "MacOS"
        macos.mkdir(parents=True)
        (macos / "cua-driver").write_text(payload)

    def test_unstamped_app_is_left_in_place(self) -> None:
        self.make_installed("UPSTREAM\n")
        result = self.run_activation()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("was not placed by home-manager", result.stderr)
        self.assertEqual((self.dest / "Contents" / "MacOS" / "cua-driver").read_text(), "UPSTREAM\n")
        self.assertFalse(has_sentinel(self.dest))
        self.assertFalse((self.apps / ".CuaDriver.app.hm-new").exists())

    def test_stamped_app_is_not_removed_when_copy_fails(self) -> None:
        self.make_installed("OURS\n")
        stamp(self.dest, "old-store")
        self.marker.symlink_to(self.box / "old-store")
        result = self.run_activation(stubs={"ditto": "echo ditto-failed >&2\nexit 1\n"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("cua-driver: copying CuaDriver.app", result.stderr)
        self.assertNotIn("signature verification", result.stderr)
        self.assertEqual((self.dest / "Contents" / "MacOS" / "cua-driver").read_text(), "OURS\n")
        self.assertTrue(self.dest.is_dir())

    def test_stamped_app_is_replaced_when_the_store_path_changes(self) -> None:
        self.make_installed("OLD\n")
        stamp(self.dest, "old-store")
        self.marker.symlink_to(self.box / "old-store")
        # Nix store bundles are mode 555. ditto keeps that, and stamping then
        # fails unless the staged copy is made writable first.
        for path in [self.store, *self.store.rglob("*")]:
            path.chmod(0o555)
        result = self.run_activation(
            stubs={
                "ditto": 'cp -a "$1" "$2"\n',
                "codesign": "exit 0\n",
                "pkill": "exit 0\n",
            }
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.dest / "Contents" / "MacOS" / "cua-driver").read_text(), "store\n")
        self.assertEqual(os.readlink(self.marker), str(self.store))
        self.assertTrue(has_sentinel(self.dest))
        self.assertFalse((self.apps / ".CuaDriver.app.hm-new").exists())

    def test_current_stamped_app_is_left_untouched(self) -> None:
        self.make_installed("CURRENT\n")
        stamp(self.dest, str(self.store))
        self.marker.symlink_to(self.store)
        result = self.run_activation()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("was not placed by home-manager", result.stderr)
        self.assertEqual((self.dest / "Contents" / "MacOS" / "cua-driver").read_text(), "CURRENT\n")


if __name__ == "__main__":
    unittest.main()
