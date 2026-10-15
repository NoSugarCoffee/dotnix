"""Sandbox the generated copyApps block against fake bundles.

CI runs this via `python3 -m unittest discover`. Requires `rsync` on PATH
(present on ubuntu-latest and in the lint nix shell).
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
HOME_NIX = REPO / "home.nix"


def nix_unescape(s: str) -> str:
    return s.replace("'''", "''").replace("''$", "$").replace("''\\", "\\")


def nix_dedent(s: str) -> str:
    lines = s.split("\n")
    indents = [len(line) - len(line.lstrip(" ")) for line in lines if line.strip()]
    strip = min(indents) if indents else 0
    return "\n".join(line[strip:] if len(line) >= strip else line for line in lines)


def extract_copyapps_block() -> str:
    home_nix = HOME_NIX.read_text()
    start = home_nix.index('lib.hm.dag.entryAfter [ "installPackages" "linkGeneration" ] \'\'')
    start = home_nix.index("\n", start) + 1
    end = home_nix.index("\n      ''", start)
    block = nix_dedent(nix_unescape(home_nix[start:end]))
    block = re.sub(
        r"targetFolder=\$\{lib\.escapeShellArg config\.targets\.darwin\.copyApps\.directory\}",
        "targetFolder=$TARGET_FOLDER",
        block,
        count=1,
    )
    block = re.sub(
        r"markerFolder=\$\{lib\.escapeShellArg \"\$\{config\.xdg\.stateHome\}/home-manager/copied-apps\"\}",
        "markerFolder=$MARKER_FOLDER",
        block,
        count=1,
    )
    block = re.sub(
        r"systemFolder=/Applications",
        "systemFolder=$SYSTEM_FOLDER",
        block,
        count=1,
    )
    block = re.sub(
        r"systemMarkerFolder=\$\{lib\.escapeShellArg \"\$\{config\.xdg\.stateHome\}/home-manager/copied-system-apps\"\}",
        "systemMarkerFolder=$SYSTEM_MARKER_FOLDER",
        block,
        count=1,
    )
    block = re.sub(
        r"sourceFolder=\$\{.*?\}/Applications",
        "sourceFolder=$SOURCE_FOLDER",
        block,
        count=1,
        flags=re.S,
    )
    leftover = [m for m in re.findall(r"\$\{[^}]+\}", block) if m.startswith("${lib.") or "pkgs." in m]
    leftover = [m for m in leftover if m != "${lib.getExe pkgs.rsync}"]
    if leftover:
        raise AssertionError(f"unsubstituted nix interpolations: {leftover}")
    if block.count("${lib.getExe pkgs.rsync}") != 3:
        raise AssertionError("expected 3 rsync interpolations in copyApps")
    return block


def plist_xml(bundle_id: str) -> str:
    return textwrap.dedent(
        f"""\
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleIdentifier</key>
          <string>{bundle_id}</string>
        </dict>
        </plist>
        """
    )


class CopyAppsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.rsync = shutil.which("rsync")
        if not cls.rsync:
            raise unittest.SkipTest("rsync is required for copyApps sandbox tests")
        cls.block = extract_copyapps_block()

    def setUp(self) -> None:
        self.box = Path(tempfile.mkdtemp(prefix="copyapps-"))
        self.addCleanup(shutil.rmtree, self.box, ignore_errors=True)
        self.source = self.box / "source" / "Applications"
        self.hm = self.box / "Home Manager Apps"
        self.apps = self.box / "Applications"
        self.markers = self.box / "state" / "copied-apps"
        self.sys_markers = self.box / "state" / "copied-system-apps"
        self.home = self.box / "home"
        for path in (self.source, self.hm, self.apps, self.markers, self.sys_markers, self.home):
            path.mkdir(parents=True)

    def env(self) -> dict[str, str]:
        env = os.environ.copy()
        env.update(
            {
                "TARGET_FOLDER": str(self.hm),
                "MARKER_FOLDER": str(self.markers),
                "SYSTEM_FOLDER": str(self.apps),
                "SYSTEM_MARKER_FOLDER": str(self.sys_markers),
                "SOURCE_FOLDER": str(self.source),
                "HOME": str(self.home),
            }
        )
        return env

    def write_script(self, rsync: str, name: str = "copyapps.sh") -> Path:
        text = self.block.replace("${lib.getExe pkgs.rsync}", rsync)
        path = self.box / name
        path.write_text(text)
        return path

    def make_app(
        self,
        dest: Path,
        *,
        ext: bool = True,
        bundle_id: str = "com.example.extapp",
        payload: str = "store-bytes\n",
    ) -> Path:
        macos = dest / "Contents" / "MacOS"
        macos.mkdir(parents=True)
        (macos / "app").write_text(payload)
        (dest / "Contents" / "Info.plist").write_text(plist_xml(bundle_id))
        if ext:
            sysext = dest / "Contents" / "Library" / "SystemExtensions"
            sysext.mkdir(parents=True)
            (sysext / "fake.systemextension").write_text("ext\n")
        return dest

    def stamp(self, app: Path, value: str = "store") -> None:
        (app / ".home-manager-copied").write_text(value)

    def run_copyapps(self, script: Path | None = None) -> subprocess.CompletedProcess[str]:
        if script is None:
            script = self.write_script(self.rsync)
        runner = self.box / "run.sh"
        runner.write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            'run() { if [[ -v DRY_RUN ]]; then echo "$@"; else "$@"; fi; }\n'
            f"source {script}\n"
        )
        return subprocess.run(
            ["bash", str(runner)],
            cwd=self.box,
            env=self.env(),
            text=True,
            capture_output=True,
            check=False,
        )

    def test_hand_installed_without_sidecar_is_left_alone(self) -> None:
        self.make_app(self.source / "ExtApp.app")
        dest = self.make_app(self.apps / "ExtApp.app", payload="HAND-INSTALLED\n")
        result = self.run_copyapps()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((dest / "Contents" / "MacOS" / "app").read_text(), "HAND-INSTALLED\n")
        self.assertFalse((self.sys_markers / "ExtApp.app").exists())
        self.assertFalse((dest / ".home-manager-copied").exists())
        self.assertEqual((self.hm / "ExtApp.app" / "Contents" / "MacOS" / "app").read_text(), "store-bytes\n")

    def test_sidecar_only_same_bundle_id_is_adopted(self) -> None:
        self.make_app(self.source / "ExtApp.app", bundle_id="io.tailscale.ipn.macsys")
        dest = self.make_app(
            self.apps / "ExtApp.app",
            bundle_id="io.tailscale.ipn.macsys",
            payload="MAIN-SIDE-CAR\n",
        )
        (self.sys_markers / "ExtApp.app").write_text("/nix/store/old-main-copy")
        result = self.run_copyapps()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("adopting sidecar-only", result.stderr)
        self.assertEqual((dest / "Contents" / "MacOS" / "app").read_text(), "store-bytes\n")
        self.assertTrue((dest / ".home-manager-copied").exists())
        self.assertTrue((self.sys_markers / "ExtApp.app").exists())

    def test_hand_replace_different_bundle_id_keeps_bundle_drops_sidecar(self) -> None:
        self.make_app(self.source / "ExtApp.app", bundle_id="io.tailscale.ipn.macsys")
        dest = self.make_app(
            self.apps / "ExtApp.app",
            bundle_id="com.hand.replaced",
            payload="HAND-REPLACED\n",
        )
        (self.sys_markers / "ExtApp.app").write_text("/nix/store/old-main-copy")
        result = self.run_copyapps()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((dest / "Contents" / "MacOS" / "app").read_text(), "HAND-REPLACED\n")
        self.assertFalse((self.sys_markers / "ExtApp.app").exists())
        self.assertFalse((dest / ".home-manager-copied").exists())
        self.assertEqual((self.hm / "ExtApp.app" / "Contents" / "MacOS" / "app").read_text(), "store-bytes\n")

    def test_interrupted_copy_with_sentinel_no_sidecar_is_recovered(self) -> None:
        self.make_app(self.source / "ExtApp.app")
        dest = self.make_app(self.apps / "ExtApp.app", payload="PARTIAL\n")
        self.stamp(dest, "partial-store")
        result = self.run_copyapps()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((dest / "Contents" / "MacOS" / "app").read_text(), "store-bytes\n")
        self.assertTrue((self.sys_markers / "ExtApp.app").exists())
        self.assertTrue((dest / ".home-manager-copied").exists())

    def test_rsync_failure_falls_back_without_aborting(self) -> None:
        self.make_app(self.source / "ExtApp.app")
        dest = self.make_app(self.apps / "ExtApp.app", payload="OLD-OWNED\n")
        self.stamp(dest, "old-store")
        (self.sys_markers / "ExtApp.app").write_text("old-store")
        wrapper = self.box / "failing-rsync"
        wrapper.write_text(
            "#!/usr/bin/env bash\n"
            f'if [[ "$*" == *{self.apps}* ]]; then\n'
            '  echo "simulated rsync failure to system folder" >&2\n'
            "  exit 1\n"
            "fi\n"
            f'exec "{self.rsync}" "$@"\n'
        )
        wrapper.chmod(wrapper.stat().st_mode | stat.S_IXUSR)
        result = self.run_copyapps(self.write_script(str(wrapper), "fail.sh"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("falling back", result.stderr)
        self.assertEqual((dest / "Contents" / "MacOS" / "app").read_text(), "OLD-OWNED\n")
        self.assertEqual((self.hm / "ExtApp.app" / "Contents" / "MacOS" / "app").read_text(), "store-bytes\n")

    def test_rsync_that_strips_sentinel_is_restamped(self) -> None:
        self.make_app(self.source / "ExtApp.app")
        wrapper = self.box / "stripping-rsync"
        wrapper.write_text(
            "#!/usr/bin/env bash\n"
            f'"{self.rsync}" "$@"\n'
            "status=$?\n"
            'dest="${@: -1}"\n'
            'rm -f "$dest/.home-manager-copied"\n'
            "exit $status\n"
        )
        wrapper.chmod(wrapper.stat().st_mode | stat.S_IXUSR)
        result = self.run_copyapps(self.write_script(str(wrapper), "strip.sh"))
        self.assertEqual(result.returncode, 0, result.stderr)
        dest = self.apps / "ExtApp.app"
        self.assertEqual((dest / "Contents" / "MacOS" / "app").read_text(), "store-bytes\n")
        self.assertTrue((dest / ".home-manager-copied").exists())
        self.assertTrue((self.sys_markers / "ExtApp.app").exists())

    def test_cleanup_removes_sentinel_without_sidecar_when_package_gone(self) -> None:
        self.make_app(self.source / "Other.app", ext=False, bundle_id="com.example.other")
        orphan = self.make_app(self.apps / "ExtApp.app")
        self.stamp(orphan, "orphan")
        result = self.run_copyapps()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(orphan.exists())
        self.assertTrue((self.hm / "Other.app").exists())


if __name__ == "__main__":
    unittest.main()
