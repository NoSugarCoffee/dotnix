"""Exercise cida release detection through the nightly freshness evaluator."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / ".github/workflows/scripts/eval_darwin_packages_freshness.sh"
PACKAGES = (
    "clash-verge-rev-darwin",
    "ego-lite-darwin",
    "cida-darwin",
)
MOCK_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="


class EvalDarwinPackagesFreshnessTest(unittest.TestCase):
    def _run(self, *, cida_build: str) -> dict[str, object]:
        work = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, work, ignore_errors=True)
        for package in PACKAGES:
            source = REPO / "pkgs" / package / "default.nix"
            target = work / "pkgs" / package / "default.nix"
            target.parent.mkdir(parents=True, exist_ok=True)
            text = source.read_text()
            if package == "cida-darwin":
                text = re.sub(r'  version = "[^"]+";', '  version = "1.4.0";', text)
                text = re.sub(r'  build = "[^"]+";', f'  build = "{cida_build}";', text)
            if package == "ego-lite-darwin":
                text = re.sub(r'sha256-[^"\s]+', MOCK_HASH, text)
            target.write_text(text)

        release = {
            "tag_name": "v1.4.0",
            "assets": [
                {"name": "Cida-1.4.0-200.dmg"},
                {"name": "Cida-1.4.0-200.dmg.sha256"},
            ],
        }
        (work / "release.json").write_text(json.dumps(release))
        bin_dir = work / "bin"
        bin_dir.mkdir()
        clash_version = re.search(r'  version = "([^"]+)";', (work / "pkgs/clash-verge-rev-darwin/default.nix").read_text()).group(1)
        gh = bin_dir / "gh"
        gh.write_text(
            "#!/bin/sh\n"
            'case "$*" in\n'
            f'  *clash-verge-rev/releases/latest*) echo v{clash_version} ;;\n'
            '  *Xuanwo/cida/releases/latest*) cat "$CIDA_RELEASE_JSON" ;;\n'
            '  *) exit 1 ;;\n'
            'esac\n'
        )
        gh.chmod(0o755)
        nix = bin_dir / "nix"
        nix.write_text(f'#!/bin/sh\nprintf \'%s\\n\' \'{{"hash":"{MOCK_HASH}"}}\'\n')
        nix.chmod(0o755)

        env = os.environ.copy()
        env["PATH"] = f"{bin_dir}:{env['PATH']}"
        env["CIDA_RELEASE_JSON"] = str(work / "release.json")
        proc = subprocess.run(
            ["bash", str(SCRIPT)], cwd=work, env=env,
            check=False, text=True, capture_output=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return json.loads(proc.stdout)

    def test_current_cida_release_needs_no_bump(self) -> None:
        result = self._run(cida_build="200")
        self.assertEqual(result["packages_current"], 3)
        self.assertTrue(result["cida"]["current"])
        self.assertNotIn("cida", result["proposed"])

    def test_new_build_in_same_version_is_proposed(self) -> None:
        result = self._run(cida_build="199")
        self.assertEqual(result["packages_current"], 2)
        self.assertFalse(result["cida"]["current"])
        self.assertEqual(
            result["proposed"]["cida"],
            {"version": "1.4.0", "build": "200", "hash": MOCK_HASH},
        )


if __name__ == "__main__":
    unittest.main()
