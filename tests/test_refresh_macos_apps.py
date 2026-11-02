"""Exercise registration cleanup with a fake LaunchServices database."""

import json
import os
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


class RefreshMacOSAppsTest(unittest.TestCase):
    def test_cleanup_preserves_copies_and_handles_missing_store_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            copies = root / "Home Manager Apps"
            system = root / "Applications"
            (copies / "Browser (Personal).app").mkdir(parents=True)
            (system / "VPN.app").mkdir(parents=True)
            (copies / "Store Link.app").symlink_to(system / "VPN.app")
            log = root / "calls.jsonl"
            dump = root / "dump"
            old = "/nix/store/old-browser/Applications/Browser (Personal).app"
            helper = old + "/Contents/Frameworks/Helper (GPU).app"
            missing = "/nix/store/missing-browser/Applications/Browser.app"
            dump.write_text(
                f"path:    {old} (0x123a)\n"
                f"path:    {old} (0x456b)\n"
                f"path:    {helper} (0xABCD)\n"
                f"path:    {missing}\n"
                f"path:    {copies}/Browser (Personal).app (0xab)\n"
                "path:    /Applications/Unrelated.app (0xcd)\n"
                "path:    /nix/store/not-an-app.txt (0xef)\n"
            )
            stub = root / "lsregister"
            stub.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "from pathlib import Path\n"
                "with open(os.environ['CALL_LOG'], 'a') as f:\n"
                "    f.write(json.dumps(sys.argv[1:]) + '\\n')\n"
                "if sys.argv[1] == '-dump':\n"
                "    if os.environ.get('FAIL_DUMP'): sys.exit(1)\n"
                "    print(Path(os.environ['DUMP']).read_text())\n"
                "if sys.argv[1] == '-u' and os.environ.get('FAIL_REMOVE'):\n"
                "    sys.exit(1)\n"
            )
            stub.chmod(0o755)
            script = (REPO / "scripts/refresh-macos-apps.sh").read_text()
            script = script.replace(
                "lsregister=/System/Library/Frameworks/CoreServices.framework/"
                "Frameworks/LaunchServices.framework/Support/lsregister",
                f"lsregister={shlex.quote(str(stub))}",
            ).replace("systemApps=/Applications", f"systemApps={shlex.quote(str(system))}")
            env = dict(os.environ, CALL_LOG=str(log), DUMP=str(dump))
            for mode in ("success", "FAIL_DUMP", "FAIL_REMOVE"):
                with self.subTest(mode=mode):
                    log.write_text("")
                    result = subprocess.run(
                        ["bash", "-c", script, "refresh-macos-apps", str(copies)],
                        env=env if mode == "success" else dict(env, **{mode: "1"}),
                        capture_output=True,
                        text=True,
                    )
                    calls = [json.loads(line) for line in log.read_text().splitlines()]
                    self.assertEqual(result.returncode, 0 if mode == "success" else 1)
                    if mode == "FAIL_DUMP":
                        self.assertEqual(calls, [["-dump"]])
                        continue
                    self.assertEqual(calls[:3], [
                        ["-dump"],
                        ["-f", str(copies / "Browser (Personal).app")],
                        ["-f", str(system / "VPN.app")],
                    ])
                    self.assertEqual(
                        sorted(call[1] for call in calls if call[0] == "-u"),
                        sorted([old, helper, missing]),
                    )
