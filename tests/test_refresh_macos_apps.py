"""Exercise scoped registration cleanup with a fake LaunchServices database."""

import json
import os
import plistlib
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]


class RefreshMacOSAppsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.copies = self.root / "Home Manager Apps"
        self.system = self.root / "Applications"
        self.browser = self.app(self.copies, "Browser (Personal).app", "example.browser")
        self.vpn = self.app(self.system, "VPN.app", "example.vpn", owned=True)
        self.app(self.system, "Manual.app", "example.manual")
        (self.copies / "Store Link.app").symlink_to(self.vpn)
        self.log = self.root / "calls.jsonl"
        self.dump = self.root / "dump"
        self.old = "/nix/store/old-browser/Applications/Browser (Personal).app"
        self.missing = "/nix/store/missing-browser/Applications/Renamed Browser.app"
        self.old_vpn = "/nix/store/old-vpn/Applications/VPN.app"
        records = [
            (self.old, "example.browser"),
            (self.old, "example.browser"),
            (self.old + "/Contents/Frameworks/Helper (GPU).app", "example.helper"),
            (str(self.browser), "example.browser"),
            ("/nix/store/other-profile/Applications/Browser (Personal).app", "other.browser"),
            ("/nix/store/other-profile/Applications/Standalone.app", "other.standalone"),
            ("/nix/store/manual/Applications/Manual.app", "example.manual"),
            (self.old_vpn, "example.vpn"),
            ("/nix/store/not-an-app.txt", "example.browser"),
            ("/nix/store/no-id/Applications/Browser.app", ""),
        ]
        self.dump.write_text("".join(
            f"bundle id: App (0x{i:x})\npath:    {path} (0x{i:X})\n"
            + (f"identifier:    {identifier}\n" if identifier else "")
            for i, (path, identifier) in enumerate(records)
        ) + f"bundle id: Missing\nidentifier: example.browser\npath: {self.missing}\n")
        lsregister = self.stub("lsregister", r"""
import json, os, sys
from pathlib import Path
with open(os.environ['CALL_LOG'], 'a') as f:
    f.write(json.dumps(sys.argv[1:]) + '\n')
if sys.argv[1] == '-dump':
    if os.environ.get('FAIL_DUMP'): sys.exit(1)
    print(Path(os.environ['DUMP']).read_text())
if sys.argv[1] == '-f' and 'Browser (Personal)' in sys.argv[2]:
    if os.environ.get('FAIL_REGISTER'): sys.exit(1)
if sys.argv[1] == '-u' and os.environ.get('FAIL_REMOVE'):
    sys.exit(1)
""")
        plist_buddy = self.stub("PlistBuddy", """
import os, plistlib, sys
if os.environ.get('FAIL_ID') and 'Browser (Personal)' in sys.argv[-1]:
    sys.exit(1)
with open(sys.argv[-1], 'rb') as f:
    print(plistlib.load(f)['CFBundleIdentifier'])
""")
        xattr = self.stub("xattr", """
import sys
from pathlib import Path
assert sys.argv[1:3] == ['-p', 'home-manager.copied']
sys.exit(0 if (Path(sys.argv[3]) / '.owned').exists() else 1)
""")
        self.script = (REPO / "scripts/refresh-macos-apps.sh").read_text()
        for name, value in {
            "lsregister": lsregister, "plistBuddy": plist_buddy,
            "xattr": xattr, "systemApps": self.system,
        }.items():
            self.script = "\n".join(
                f"{name}={shlex.quote(str(value))}" if line.startswith(name + "=") else line
                for line in self.script.split("\n")
            )

    def app(self, folder, name, identifier, owned=False):
        app = folder / name
        (app / "Contents").mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(
            plistlib.dumps({"CFBundleIdentifier": identifier})
        )
        if owned:
            (app / ".owned").touch()
        return app

    def stub(self, name, source):
        path = self.root / name
        path.write_text(f"#!{sys.executable}\n" + source)
        path.chmod(0o755)
        return path

    def run_refresh(self, **extra):
        self.log.write_text("")
        result = subprocess.run(
            ["bash", "-c", self.script, "refresh-macos-apps", str(self.copies)],
            env=dict(os.environ, CALL_LOG=str(self.log), DUMP=str(self.dump), **extra),
            capture_output=True, text=True,
        )
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        return result, calls

    def test_only_duplicates_of_managed_copies_are_removed(self):
        result, calls = self.run_refresh()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[:3], [
            ["-dump"], ["-f", str(self.browser)], ["-f", str(self.vpn)],
        ])
        self.assertEqual(
            sorted(call[1] for call in calls if call[0] == "-u"),
            sorted([self.old, self.missing, self.old_vpn]),
        )

    def test_failed_dump_does_not_change_registrations(self):
        result, calls = self.run_refresh(FAIL_DUMP="1")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(calls, [["-dump"]])

    def test_failed_replacement_preserves_its_store_registrations(self):
        for mode in ("FAIL_REGISTER", "FAIL_ID"):
            with self.subTest(mode=mode):
                result, calls = self.run_refresh(**{mode: "1"})
                self.assertEqual(result.returncode, 1)
                self.assertEqual([call for call in calls if call[0] == "-u"], [
                    ["-u", self.old_vpn],
                ])

    def test_failed_removal_is_reported_and_cleanup_continues(self):
        result, calls = self.run_refresh(FAIL_REMOVE="1")
        self.assertEqual(result.returncode, 1)
        self.assertIn("could not unregister", result.stderr)
        self.assertEqual(len([call for call in calls if call[0] == "-u"]), 3)

    def test_no_managed_copies_leaves_all_store_registrations(self):
        self.browser.rename(self.root / "Browser.app")
        (self.vpn / ".owned").unlink()
        result, calls = self.run_refresh()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [["-dump"]])
