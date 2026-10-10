"""Exercise the release pin module through its interface, with upstreams faked in-process."""

from __future__ import annotations

import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location(
    "release_pins", REPO / ".github" / "workflows" / "scripts" / "release_pins.py"
)
assert _spec is not None and _spec.loader is not None
release_pins = importlib.util.module_from_spec(_spec)
sys.modules["release_pins"] = release_pins
_spec.loader.exec_module(release_pins)

FRESH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="


class FakeUpstreams:
    def __init__(self, responses: dict[str, object], hashes: dict[str, str]) -> None:
        self.responses = responses
        self.hashes = hashes
        self.prefetched: list[str] = []

    def http_get_json(self, url: str) -> object:
        return self.responses[url]

    def prefetch(self, url: str) -> str:
        self.prefetched.append(url)
        return self.hashes.get(url, FRESH)


def github_latest(repo: str, tag: str, assets: list[str]) -> dict[str, object]:
    return {
        f"https://api.github.com/repos/{repo}/releases/latest": {
            "tag_name": tag,
            "assets": [{"name": name} for name in assets],
        }
    }


class ReleasePinsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.pkgs = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.pkgs, ignore_errors=True)

    def write_pin(self, name: str, doc: dict[str, object]) -> Path:
        path = self.pkgs / name / "pin.json"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps(doc, indent=2) + "\n")
        return path

    def read_pin(self, name: str) -> dict[str, object]:
        return json.loads((self.pkgs / name / "pin.json").read_text())

    def test_every_real_pin_parses_and_renders_a_url_per_system(self) -> None:
        pin_files = sorted((REPO / "pkgs").glob("*/pin.json"))
        self.assertGreaterEqual(len(pin_files), 7)
        for pin_file in pin_files:
            pin = release_pins.parse_pin(json.loads(pin_file.read_text()), str(pin_file))
            for system in pin.hash:
                self.assertTrue(release_pins.render_url(pin, system).startswith("https://"))
            self.assertEqual(release_pins.dump_pin(pin), pin_file.read_text(), pin_file)

    def test_bumps_version_and_every_arch_hash(self) -> None:
        self.write_pin("clash", {
            "source": {"type": "github", "repo": "o/clash"},
            "version": "2.5.2",
            "url": "https://x/v{version}/Clash_{version}_{arch}.dmg",
            "arch": {"aarch64-darwin": "aarch64", "x86_64-darwin": "x64"},
            "hash": {"aarch64-darwin": "sha256-old1", "x86_64-darwin": "sha256-old2"},
        })
        upstreams = FakeUpstreams(github_latest("o/clash", "v9.9.9", []), {})

        summaries = release_pins.bump_all(self.pkgs, upstreams.http_get_json, upstreams.prefetch)

        pin = self.read_pin("clash")
        self.assertEqual(pin["version"], "9.9.9")
        self.assertEqual(pin["hash"], {"aarch64-darwin": FRESH, "x86_64-darwin": FRESH})
        self.assertEqual(pin["arch"], {"aarch64-darwin": "aarch64", "x86_64-darwin": "x64"})
        self.assertEqual(
            sorted(upstreams.prefetched),
            ["https://x/v9.9.9/Clash_9.9.9_aarch64.dmg", "https://x/v9.9.9/Clash_9.9.9_x64.dmg"],
        )
        self.assertEqual(summaries, ["- `clash`: 2.5.2 -> 9.9.9"])

    def test_current_versioned_pin_downloads_nothing(self) -> None:
        path = self.write_pin("obs", {
            "source": {"type": "github", "repo": "o/obs"},
            "version": "32.2.2",
            "url": "https://x/{version}.dmg",
            "hash": {"aarch64-darwin": "sha256-same"},
        })
        before = path.read_text()
        upstreams = FakeUpstreams(github_latest("o/obs", "32.2.2", []), {})

        summaries = release_pins.bump_all(self.pkgs, upstreams.http_get_json, upstreams.prefetch)

        self.assertEqual(summaries, [])
        self.assertEqual(upstreams.prefetched, [])
        self.assertEqual(path.read_text(), before)

    def test_asset_pattern_captures_extra_url_vars(self) -> None:
        self.write_pin("cida", {
            "source": {"type": "github", "repo": "o/cida", "asset": "^Cida-{version}-(?P<build>[0-9]+)[.]dmg$"},
            "version": "1.4.0",
            "vars": {"build": "199"},
            "url": "https://x/v{version}/Cida-{version}-{build}.dmg",
            "hash": {"aarch64-darwin": "sha256-old"},
        })
        upstreams = FakeUpstreams(
            github_latest("o/cida", "v1.4.0", ["Cida-1.4.0-200.dmg", "Cida-1.4.0-200.dmg.sha256"]), {}
        )

        summaries = release_pins.bump_all(self.pkgs, upstreams.http_get_json, upstreams.prefetch)

        pin = self.read_pin("cida")
        self.assertEqual(pin["vars"], {"build": "200"})
        self.assertEqual(upstreams.prefetched, ["https://x/v1.4.0/Cida-1.4.0-200.dmg"])
        self.assertEqual(summaries, ["- `cida`: 1.4.0 (build 199) -> 1.4.0 (build 200)"])

    def test_ambiguous_asset_match_fails_without_writing(self) -> None:
        path = self.write_pin("cida", {
            "source": {"type": "github", "repo": "o/cida", "asset": "^Cida-{version}-(?P<build>[0-9]+)[.]dmg$"},
            "version": "1.4.0",
            "vars": {"build": "199"},
            "url": "https://x/{version}-{build}.dmg",
            "hash": {"aarch64-darwin": "sha256-old"},
        })
        before = path.read_text()
        upstreams = FakeUpstreams(github_latest("o/cida", "v1.5.0", ["Cida-1.5.0-1.dmg", "Cida-1.5.0-2.dmg"]), {})

        with self.assertRaises(release_pins.PinError):
            release_pins.bump_all(self.pkgs, upstreams.http_get_json, upstreams.prefetch)
        self.assertEqual(path.read_text(), before)

    def test_unversioned_url_bumps_only_the_arch_that_changed(self) -> None:
        self.write_pin("ego", {
            "source": {"type": "unversioned-url"},
            "version": "0.5.1.13",
            "url": "https://cdn/{arch}/ego.dmg",
            "arch": {"aarch64-darwin": "arm64", "x86_64-darwin": "x64"},
            "hash": {"aarch64-darwin": "sha256-old", "x86_64-darwin": "sha256-same"},
        })
        upstreams = FakeUpstreams({}, {"https://cdn/x64/ego.dmg": "sha256-same"})

        summaries = release_pins.bump_all(self.pkgs, upstreams.http_get_json, upstreams.prefetch)

        pin = self.read_pin("ego")
        self.assertEqual(pin["hash"], {"aarch64-darwin": FRESH, "x86_64-darwin": "sha256-same"})
        self.assertEqual(pin["version"], "0.5.1.13")
        self.assertIn("version label `0.5.1.13` left as is", summaries[0])

    def test_unversioned_url_with_same_bytes_is_current(self) -> None:
        self.write_pin("ego", {
            "source": {"type": "unversioned-url"},
            "version": "1",
            "url": "https://cdn/ego.dmg",
            "hash": {"aarch64-darwin": "sha256-same"},
        })
        upstreams = FakeUpstreams({}, {"https://cdn/ego.dmg": "sha256-same"})

        self.assertEqual(release_pins.bump_all(self.pkgs, upstreams.http_get_json, upstreams.prefetch), [])

    def _grok_pin(self, version: str = "0.68.1") -> dict[str, object]:
        return {
            "source": {
                "type": "cursor-download",
                "product": "sand",
                "platform": {"aarch64-darwin": "darwin-arm64", "x86_64-darwin": "darwin-x64"},
            },
            "version": version,
            "url": "https://downloads.cursor.com/grokbot/stable/{platform}/{version}/Grok_Bot_{version}{suffix}.dmg",
            "suffix": {"aarch64-darwin": "", "x86_64-darwin": "_x64"},
            "hash": {"aarch64-darwin": "sha256-old-arm", "x86_64-darwin": "sha256-old-x64"},
        }

    def _grok_feed(self, version: str) -> dict[str, object]:
        def url(platform: str, suffix: str) -> str:
            return f"https://downloads.cursor.com/grokbot/stable/{platform}/{version}/Grok_Bot_{version}{suffix}.dmg"

        return {
            "https://api2.cursor.sh/updates/api/download/stable/darwin-arm64/sand": {
                "version": version,
                "downloadUrl": url("darwin-arm64", ""),
            },
            "https://api2.cursor.sh/updates/api/download/stable/darwin-x64/sand": {
                "version": version,
                "downloadUrl": url("darwin-x64", "_x64"),
            },
        }

    def test_cursor_download_feed_bumps_version_and_both_arch_hashes(self) -> None:
        self.write_pin("grok-bot-darwin", self._grok_pin())
        upstreams = FakeUpstreams(self._grok_feed("0.69.0"), {})

        summaries = release_pins.bump_all(self.pkgs, upstreams.http_get_json, upstreams.prefetch)

        pin = self.read_pin("grok-bot-darwin")
        self.assertEqual(pin["version"], "0.69.0")
        self.assertEqual(pin["hash"], {"aarch64-darwin": FRESH, "x86_64-darwin": FRESH})
        self.assertEqual(
            sorted(upstreams.prefetched),
            [
                "https://downloads.cursor.com/grokbot/stable/darwin-arm64/0.69.0/Grok_Bot_0.69.0.dmg",
                "https://downloads.cursor.com/grokbot/stable/darwin-x64/0.69.0/Grok_Bot_0.69.0_x64.dmg",
            ],
        )
        self.assertEqual(summaries, ["- `grok-bot-darwin`: 0.68.1 -> 0.69.0"])

    def test_cursor_download_feed_at_the_pinned_version_downloads_nothing(self) -> None:
        path = self.write_pin("grok-bot-darwin", self._grok_pin())
        before = path.read_text()
        upstreams = FakeUpstreams(self._grok_feed("0.68.1"), {})

        summaries = release_pins.bump_all(self.pkgs, upstreams.http_get_json, upstreams.prefetch)

        self.assertEqual(summaries, [])
        self.assertEqual(upstreams.prefetched, [])
        self.assertEqual(path.read_text(), before)

    def test_cursor_download_feed_rejects_a_url_the_template_cannot_render(self) -> None:
        path = self.write_pin("grok-bot-darwin", self._grok_pin())
        before = path.read_text()
        feed = self._grok_feed("0.69.0")
        feed["https://api2.cursor.sh/updates/api/download/stable/darwin-arm64/sand"] = {
            "version": "0.69.0",
            "downloadUrl": "https://downloads.cursor.com/grokbot/stable/unexpected.dmg",
        }
        upstreams = FakeUpstreams(feed, {})

        with self.assertRaises(release_pins.PinError):
            release_pins.bump_all(self.pkgs, upstreams.http_get_json, upstreams.prefetch)
        self.assertEqual(path.read_text(), before)
        self.assertEqual(upstreams.prefetched, [])

    def test_jetbrains_source_follows_the_latest_build(self) -> None:
        self.write_pin("air", {
            "source": {"type": "jetbrains", "code": "AIR"},
            "version": "262.579.44",
            "url": "https://dl/Air-{version}-aarch64.dmg",
            "hash": {"aarch64-darwin": "sha256-old"},
        })
        upstreams = FakeUpstreams(
            {"https://data.services.jetbrains.com/products?code=AIR": [{"releases": [{"build": "262.834.70"}]}]},
            {},
        )

        summaries = release_pins.bump_all(self.pkgs, upstreams.http_get_json, upstreams.prefetch)

        self.assertEqual(self.read_pin("air")["version"], "262.834.70")
        self.assertEqual(upstreams.prefetched, ["https://dl/Air-262.834.70-aarch64.dmg"])
        self.assertEqual(summaries, ["- `air`: 262.579.44 -> 262.834.70"])

    def test_unresolved_placeholder_is_rejected(self) -> None:
        pin = release_pins.parse_pin({
            "source": {"type": "unversioned-url"},
            "version": "1",
            "url": "https://x/{build}.dmg",
            "hash": {"aarch64-darwin": "sha256-x"},
        }, "inline")

        with self.assertRaises(release_pins.PinError):
            release_pins.render_url(pin, "aarch64-darwin")

    def test_unknown_source_type_is_rejected(self) -> None:
        with self.assertRaises(release_pins.PinError):
            release_pins.parse_pin({"source": {"type": "gitlab"}, "version": "1", "url": "u", "hash": {}}, "inline")

    def test_step_output_marks_change_and_carries_the_summary(self) -> None:
        output = self.pkgs / "github_output"
        release_pins.write_step_output(["- `a`: 1 -> 2"], output)
        self.assertEqual(output.read_text(), "changed=true\nsummary<<SUMMARY_EOF\n- `a`: 1 -> 2\nSUMMARY_EOF\n")


if __name__ == "__main__":
    unittest.main()
