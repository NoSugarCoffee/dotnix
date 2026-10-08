"""Exercise managed_settings through its sync interface, against real files in a temp dir."""

from __future__ import annotations

import importlib.util
import json
import os
import shutil
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("managed_settings", REPO / "home" / "managed_settings.py")
assert _spec is not None and _spec.loader is not None
managed_settings = importlib.util.module_from_spec(_spec)
sys.modules["managed_settings"] = managed_settings
_spec.loader.exec_module(managed_settings)

CODEX_MANAGED = (REPO / "home" / "codex" / "managed.toml").read_text()
CODEX_SEED = (REPO / "home" / "codex" / "config.toml").read_text()


class ManagedSettingsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)

    def test_fresh_codex_config_is_seed_plus_managed_keys(self) -> None:
        target = self.dir / ".codex" / "config.toml"

        self.assertTrue(managed_settings.sync("toml", CODEX_MANAGED, CODEX_SEED, target, 0o600))

        config = tomllib.loads(target.read_text())
        self.assertEqual(config["file_opener"], "cursor")
        for key, value in tomllib.loads(CODEX_MANAGED).items():
            self.assertEqual(config[key], value)
        self.assertEqual(os.stat(target).st_mode & 0o777, 0o600)

    def test_toml_resets_managed_keys_and_keeps_trust_decisions(self) -> None:
        target = self.dir / "config.toml"
        target.write_text(
            '# mine\nmodel = "old"\nfile_opener = "vscode"\n\n[projects."/work"]\ntrust_level = "trusted"\n'
        )

        managed_settings.sync("toml", 'model = "new"\nsandbox_mode = "read-only"\n', "", target, 0o600)

        self.assertEqual(
            target.read_text(),
            '# mine\nmodel = "new"\nfile_opener = "vscode"\n\nsandbox_mode = "read-only"\n'
            '[projects."/work"]\ntrust_level = "trusted"\n',
        )

    def test_toml_leaves_a_same_named_key_inside_a_table_alone(self) -> None:
        target = self.dir / "config.toml"
        target.write_text('model = "new"\n\n[profiles.fast]\nmodel = "mini"\n')

        changed = managed_settings.sync("toml", 'model = "new"\n', "", target, 0o600)

        self.assertFalse(changed)
        self.assertIn('model = "mini"', target.read_text())

    def test_managed_toml_with_tables_is_rejected(self) -> None:
        with self.assertRaises(managed_settings.ManagedSettingsError):
            managed_settings.merge_toml("", "[tui]\nnotifications = true\n")

    def test_json_deep_merges_objects_and_replaces_arrays(self) -> None:
        target = self.dir / "settings.json"
        target.write_text(json.dumps({
            "env": {"KEEP": "1", "HTTP_PROXY": "old"},
            "permissions": {"deny": ["Read(a)", "Read(b)"], "allow": ["Bash"]},
            "enabledPlugins": {"x": True},
        }))
        managed = json.dumps({"env": {"HTTP_PROXY": "new"}, "permissions": {"deny": ["Read(.env)"]}})

        managed_settings.sync("json", managed, "{}\n", target, 0o644)

        self.assertEqual(json.loads(target.read_text()), {
            "env": {"KEEP": "1", "HTTP_PROXY": "new"},
            "permissions": {"deny": ["Read(.env)"], "allow": ["Bash"]},
            "enabledPlugins": {"x": True},
        })

    def test_json_keeps_non_ascii_unescaped(self) -> None:
        target = self.dir / "settings.json"
        target.write_text('{"note": "中文"}')

        managed_settings.sync("json", '{"theme": "dark"}', "{}\n", target, 0o644)

        self.assertIn("中文", target.read_text())

    def test_unchanged_file_is_not_rewritten(self) -> None:
        target = self.dir / "settings.json"
        target.write_text('{\n  "theme": "dark"\n}\n')
        os.chmod(target, 0o640)

        self.assertFalse(managed_settings.sync("json", '{"theme": "dark"}', "{}\n", target, 0o644))
        self.assertEqual(os.stat(target).st_mode & 0o777, 0o640)

    def test_malformed_machine_file_fails_without_touching_it(self) -> None:
        for fmt, broken in (("json", "{not json"), ("toml", "model = ")):
            target = self.dir / f"broken.{fmt}"
            target.write_text(broken)
            with self.assertRaises(managed_settings.ManagedSettingsError):
                managed_settings.sync(fmt, "{}" if fmt == "json" else "", "", target, 0o600)
            self.assertEqual(target.read_text(), broken)

    def test_symlinked_target_is_refused(self) -> None:
        real = self.dir / "store.json"
        real.write_text("{}")
        link = self.dir / "settings.json"
        link.symlink_to(real)

        with self.assertRaises(managed_settings.ManagedSettingsError):
            managed_settings.sync("json", '{"theme": "dark"}', "{}\n", link, 0o644)

    def test_cli_reports_a_malformed_file_as_a_clean_exit(self) -> None:
        target = self.dir / "settings.json"
        target.write_text("{not json")
        managed = self.dir / "managed.json"
        managed.write_text("{}")

        with self.assertRaises(SystemExit) as raised:
            managed_settings.main(["--format", "json", "--managed", str(managed), "--mode", "644", str(target)])
        self.assertIn("malformed", str(raised.exception.code))


if __name__ == "__main__":
    unittest.main()
