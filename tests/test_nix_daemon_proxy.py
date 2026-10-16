"""Helpers in scripts/nix-daemon-proxy.sh: sourceable, no sudo / launchctl."""

from __future__ import annotations

import os
import stat
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "scripts" / "nix-daemon-proxy.sh"
BOOTSTRAP = REPO / "scripts" / "bootstrap-macos.sh"


def run_lib(body: str, *, env: dict[str, str] | None = None, timeout: float = 10) -> subprocess.CompletedProcess[str]:
    """Source the proxy script (helpers only) and run *body*."""
    script = f'source "{SCRIPT}"\n{body}\n'
    merged = os.environ.copy()
    if env:
        merged.update(env)
    return subprocess.run(
        ["bash", "-c", script],
        check=False,
        text=True,
        capture_output=True,
        timeout=timeout,
        env=merged,
    )


class SourceableHelpersTest(unittest.TestCase):
    def test_sourcing_does_not_run_main(self) -> None:
        # A PATH with no nix/nc would make main fail; sourcing must still work.
        env = os.environ.copy()
        env["PATH"] = "/usr/bin:/bin"
        env.pop("DOTNIX_DIRECT", None)
        result = run_lib(
            'type dotnix_wait_for_nix_daemon >/dev/null && echo sourced',
            env=env,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "sourced")


class DirectOptOutTest(unittest.TestCase):
    def test_unset_is_off(self) -> None:
        env = os.environ.copy()
        env.pop("DOTNIX_DIRECT", None)
        result = run_lib(
            'if dotnix_direct; then echo yes; else echo no; fi',
            env=env,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "no")

    def test_one_is_on(self) -> None:
        result = run_lib(
            'if dotnix_direct; then echo yes; else echo no; fi',
            env={**os.environ, "DOTNIX_DIRECT": "1"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "yes")

    def test_other_values_are_off(self) -> None:
        result = run_lib(
            'if dotnix_direct; then echo yes; else echo no; fi',
            env={**os.environ, "DOTNIX_DIRECT": "true"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "no")


class ImpureEnvDetectionTest(unittest.TestCase):
    def test_missing_file(self) -> None:
        result = run_lib(
            'if dotnix_conf_has_impure_env /no/such/nix.custom.conf; then echo yes; else echo no; fi'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "no")

    def test_absent_and_present_lines(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "nix.custom.conf"
            conf.write_text("extra-substituters = https://example.invalid\n")
            result = run_lib(
                f'if dotnix_conf_has_impure_env "{conf}"; then echo yes; else echo no; fi'
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "no")

            conf.write_text("impure-env = FOO=bar\n")
            result = run_lib(
                f'if dotnix_conf_has_impure_env "{conf}"; then echo yes; else echo no; fi'
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "no")

            conf.write_text(
                "impure-env = http_proxy=http://127.0.0.1:7890 "
                "https_proxy=http://127.0.0.1:7890 no_proxy=127.0.0.1\n"
            )
            result = run_lib(
                f'if dotnix_conf_has_impure_env "{conf}"; then echo yes; else echo no; fi'
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "yes")

    def test_proxy_line_vs_custom_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "nix.custom.conf"
            conf.write_text("impure-env = FOO=bar\n")
            result = run_lib(
                f'if dotnix_conf_has_proxy_impure_env "{conf}"; then echo yes; else echo no; fi'
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "no")
            conf.write_text("impure-env = https_proxy=http://127.0.0.1:7890\n")
            result = run_lib(
                f'if dotnix_conf_has_proxy_impure_env "{conf}"; then echo yes; else echo no; fi'
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "yes")
            conf.write_text("extra-impure-env = https_proxy=http://127.0.0.1:7890\n")
            result = run_lib(
                f'if dotnix_conf_has_proxy_impure_env "{conf}"; then echo yes; else echo no; fi'
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "yes")

            conf.write_text("  impure-env = https_proxy=http://127.0.0.1:7890\n")
            result = run_lib(
                f'if dotnix_conf_has_proxy_impure_env "{conf}"; then echo yes; else echo no; fi'
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "yes")

            conf.write_text("\textra-impure-env = https_proxy=http://127.0.0.1:7890\n")
            result = run_lib(
                f'if dotnix_conf_has_proxy_impure_env "{conf}"; then echo yes; else echo no; fi'
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "yes")

    def test_commented_line_does_not_count(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "nix.custom.conf"
            conf.write_text("# impure-env = http_proxy=http://127.0.0.1:7890\n")
            result = run_lib(
                f'if dotnix_conf_has_impure_env "{conf}"; then echo yes; else echo no; fi'
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "no")
            conf.write_text("impure-env = FOO=bar # https_proxy=http://127.0.0.1:7890\n")
            result = run_lib(
                f'if dotnix_conf_has_impure_env "{conf}"; then echo yes; else echo no; fi'
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "no")

    def test_unreadable_file_fails_loudly(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "nix.custom.conf"
            conf.write_text("impure-env = https_proxy=http://127.0.0.1:7890\n")
            conf.chmod(0)
            try:
                if os.access(conf, os.R_OK):
                    self.skipTest("process can read mode 000 files (likely root)")
                result = run_lib(
                    f'dotnix_conf_has_proxy_impure_env "{conf}"; echo st=$?'
                )
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertIn("cannot read", result.stderr)
                self.assertNotIn("st=", result.stdout)
                action = run_lib(f'dotnix_direct_action "{conf}"')
                self.assertEqual(action.returncode, 2, action.stdout)
                self.assertNotIn("noop", action.stdout)
                self.assertNotIn("clear", action.stdout)
                plan = run_lib(
                    f'dotnix_bootstrap_proxy_plan "{conf}" "{tmp}" 0'
                )
                self.assertEqual(plan.returncode, 2, plan.stdout)
                self.assertNotIn("install-clash", plan.stdout)
                self.assertNotIn("start-existing", plan.stdout)
            finally:
                if conf.exists():
                    conf.chmod(0o644)


class ApplyProxyImpureEnvTest(unittest.TestCase):
    def test_clear_merges_custom_and_drops_proxy(self) -> None:
        result = run_lib(
            textwrap.dedent(
                """\
                dotnix_apply_proxy_impure_env clear <<'EOF'
                extra-trusted-users = alice
                impure-env = FOO=bar
                impure-env = http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890 no_proxy=127.0.0.1
                extra-experimental-features = configurable-impure-env
                EOF
                """
            )
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "extra-trusted-users = alice\n"
            "extra-experimental-features = configurable-impure-env\n"
            "impure-env = FOO=bar\n",
        )

    def test_set_merges_custom_keys_onto_one_line(self) -> None:
        result = run_lib(
            textwrap.dedent(
                """\
                dotnix_apply_proxy_impure_env set http://127.0.0.1:7890 127.0.0.1 <<'EOF'
                extra-substituters = https://example.invalid
                impure-env = FOO=bar
                extra-impure-env = BAZ=qux
                EOF
                """
            )
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "extra-substituters = https://example.invalid\n"
            "impure-env = FOO=bar BAZ=qux "
            "http_proxy=http://127.0.0.1:7890 "
            "https_proxy=http://127.0.0.1:7890 "
            "no_proxy=127.0.0.1\n",
        )

    def test_clear_drops_only_proxy_line(self) -> None:
        result = run_lib(
            textwrap.dedent(
                """\
                dotnix_apply_proxy_impure_env clear <<'EOF'
                impure-env = http_proxy=http://127.0.0.1:1080 https_proxy=http://127.0.0.1:1080
                EOF
                """
            )
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_replace_file_leaves_complete_dest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "nix.custom.conf"
            dest.write_text("old\n")
            dest.chmod(0o600)
            result = run_lib(
                f'printf "%s\\n" "extra-substituters = https://example.invalid" '
                f'"impure-env = FOO=bar" | dotnix_replace_file "{dest}"'
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                dest.read_text(),
                "extra-substituters = https://example.invalid\n"
                "impure-env = FOO=bar\n",
            )
            self.assertEqual(dest.stat().st_mode & 0o777, 0o644)

    def test_sudo_replace_resets_mode_to_0644(self) -> None:
        # sudo install is the production path; this checkout cannot run it.
        text = SCRIPT.read_text()
        self.assertIn('sudo install -m 0644 -o root -g wheel', text)
        self.assertIn('sudo mv -f "$stage" "$dest"', text)

    def test_inline_comment_is_not_a_token(self) -> None:
        result = run_lib(
            textwrap.dedent(
                """\
                dotnix_apply_proxy_impure_env set http://127.0.0.1:7890 127.0.0.1 <<'EOF'
                impure-env = FOO=bar # https_proxy=http://evil.example *
                EOF
                """
            )
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "impure-env = FOO=bar "
            "http_proxy=http://127.0.0.1:7890 "
            "https_proxy=http://127.0.0.1:7890 "
            "no_proxy=127.0.0.1\n",
        )
        self.assertNotIn("#", result.stdout)
        self.assertNotIn("*", result.stdout)

    def test_indented_proxy_line_is_rewritten(self) -> None:
        result = run_lib(
            textwrap.dedent(
                """\
                dotnix_apply_proxy_impure_env clear <<'EOF'
                extra-trusted-users = alice
                  impure-env = FOO=bar http_proxy=http://127.0.0.1:7890 https_proxy=http://127.0.0.1:7890
                extra-experimental-features = configurable-impure-env
                EOF
                """
            )
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "extra-trusted-users = alice\n"
            "extra-experimental-features = configurable-impure-env\n"
            "impure-env = FOO=bar\n",
        )

    def test_empty_impure_env_line_is_not_unbound(self) -> None:
        result = run_lib(
            textwrap.dedent(
                """\
                set -u
                dotnix_apply_proxy_impure_env set http://127.0.0.1:7890 127.0.0.1 <<'EOF'
                extra-trusted-users = alice
                impure-env =
                EOF
                """
            )
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "extra-trusted-users = alice\n"
            "impure-env = "
            "http_proxy=http://127.0.0.1:7890 "
            "https_proxy=http://127.0.0.1:7890 "
            "no_proxy=127.0.0.1\n",
        )

    def test_script_does_not_pipe_into_replace(self) -> None:
        text = SCRIPT.read_text()
        self.assertNotRegex(text, r"\|\s*dotnix_(sudo_)?replace_file")


class FindAppBundleTest(unittest.TestCase):
    def test_find_any_app_and_clash_named(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            store_apps = Path(tmp) / "store"
            hm_apps = Path(tmp) / "hm"
            store_apps.mkdir()
            hm_apps.mkdir()
            (store_apps / "Clash Verge.app").mkdir()
            (hm_apps / "Kitty.app").mkdir()
            (hm_apps / "Clash Verge.app").mkdir()

            result = run_lib(
                f'printf "%s\\n" "$(dotnix_find_app_bundle "{store_apps}")" '
                f'"$(dotnix_find_clash_app "{hm_apps}")"'
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            lines = result.stdout.strip().splitlines()
            self.assertTrue(lines[0].endswith("Clash Verge.app"))
            self.assertTrue(lines[1].endswith("Clash Verge.app"))

    def test_clash_match_is_case_insensitive(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            hm_apps = Path(tmp) / "hm"
            hm_apps.mkdir()
            (hm_apps / "Kitty.app").mkdir()
            (hm_apps / "CLASH Verge.app").mkdir()
            result = run_lib(f'printf "%s" "$(dotnix_find_clash_app "{hm_apps}")"')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(result.stdout.endswith("CLASH Verge.app"))

    def test_lookup_does_not_call_find(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            store_apps = tmp_path / "store"
            store_apps.mkdir()
            (store_apps / "Clash Verge.app").mkdir()
            fake_bin = tmp_path / "bin"
            fake_bin.mkdir()
            find = fake_bin / "find"
            find.write_text(
                "#!/bin/sh\necho 'find: -quit: unknown primary or operator' >&2\nexit 1\n"
            )
            find.chmod(find.stat().st_mode | stat.S_IXUSR)
            env = os.environ.copy()
            env["PATH"] = f"{fake_bin}:{env.get('PATH', '')}"
            result = run_lib(
                f'printf "%s" "$(dotnix_find_app_bundle "{store_apps}")"',
                env=env,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(result.stdout.endswith("Clash Verge.app"))
            self.assertNotIn("unknown primary", result.stderr)

    def test_missing_dir_is_empty(self) -> None:
        result = run_lib('printf "[%s]" "$(dotnix_find_clash_app /no/such/apps)"')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "[]")


class BootstrapProxyPlanTest(unittest.TestCase):
    def _plan(self, *, conf: str, hm: str, proxy_up: str, env: dict[str, str] | None = None) -> str:
        merged = os.environ.copy()
        merged.pop("DOTNIX_DIRECT", None)
        if env:
            merged.update(env)
        result = run_lib(
            f'dotnix_bootstrap_proxy_plan "{conf}" "{hm}" "{proxy_up}"',
            env=merged,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def test_direct_action_clear_vs_noop(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            proxy = Path(tmp) / "proxy.conf"
            custom = Path(tmp) / "custom.conf"
            missing = Path(tmp) / "missing.conf"
            proxy.write_text("impure-env = https_proxy=http://127.0.0.1:7890\n")
            custom.write_text("impure-env = FOO=bar\n")
            result = run_lib(
                f'printf "%s\\n" "$(dotnix_direct_action "{proxy}")" '
                f'"$(dotnix_direct_action "{custom}")" '
                f'"$(dotnix_direct_action "{missing}")"'
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip().splitlines(), ["clear", "noop", "noop"])

    def test_indented_proxy_line_is_clear_not_noop(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "nix.custom.conf"
            conf.write_text("  impure-env = https_proxy=http://127.0.0.1:7890\n")
            result = run_lib(f'dotnix_direct_action "{conf}"')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "clear")
            self.assertEqual(
                self._plan(conf=str(conf), hm=tmp, proxy_up="0"),
                "tell-user",
            )

    def test_direct_opt_out_wins(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "nix.custom.conf"
            conf.write_text("impure-env = https_proxy=http://127.0.0.1:7890\n")
            self.assertEqual(
                self._plan(conf=str(conf), hm=tmp, proxy_up="0", env={"DOTNIX_DIRECT": "1"}),
                "direct",
            )

    def test_direct_with_existing_proxy_line_clears_keys(self) -> None:
        """DOTNIX_DIRECT=1 + existing proxy impure-env: plan is direct, apply clear drops it."""
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "nix.custom.conf"
            conf.write_text(
                "extra-substituters = https://example.invalid\n"
                "impure-env = FOO=bar http_proxy=http://127.0.0.1:7890 "
                "https_proxy=http://127.0.0.1:7890 no_proxy=127.0.0.1\n"
            )
            self.assertEqual(
                self._plan(conf=str(conf), hm=tmp, proxy_up="0", env={"DOTNIX_DIRECT": "1"}),
                "direct",
            )
            result = run_lib(
                f'dotnix_apply_proxy_impure_env clear <"{conf}" | dotnix_replace_file "{conf}"'
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            text = conf.read_text()
            self.assertIn("extra-substituters = https://example.invalid\n", text)
            self.assertIn("impure-env = FOO=bar\n", text)
            self.assertNotIn("https_proxy=", text)
            self.assertNotIn("http_proxy=", text)

    def test_proxy_up_enables(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "nix.custom.conf"
            conf.write_text("")
            self.assertEqual(self._plan(conf=str(conf), hm=tmp, proxy_up="1"), "enable")

    def test_configured_and_down_opens_existing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "nix.custom.conf"
            hm = Path(tmp) / "apps"
            hm.mkdir()
            (hm / "Clash Verge.app").mkdir()
            conf.write_text("impure-env = https_proxy=http://127.0.0.1:7890\n")
            self.assertEqual(self._plan(conf=str(conf), hm=str(hm), proxy_up="0"), "start-existing")

    def test_configured_and_down_without_app_tells_user(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "nix.custom.conf"
            hm = Path(tmp) / "apps"
            hm.mkdir()
            conf.write_text("impure-env = https_proxy=http://127.0.0.1:7890\n")
            self.assertEqual(self._plan(conf=str(conf), hm=str(hm), proxy_up="0"), "tell-user")

    def test_custom_impure_env_is_not_a_configured_proxy(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "nix.custom.conf"
            hm = Path(tmp) / "apps"
            hm.mkdir()
            (hm / "Clash Verge.app").mkdir()
            conf.write_text("impure-env = FOO=bar\n")
            self.assertEqual(self._plan(conf=str(conf), hm=str(hm), proxy_up="0"), "install-clash")

    def test_fresh_machine_installs_clash(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "nix.custom.conf"
            hm = Path(tmp) / "apps"
            hm.mkdir()
            (hm / "Clash Verge.app").mkdir()
            conf.write_text("extra-substituters = https://example.invalid\n")
            self.assertEqual(self._plan(conf=str(conf), hm=str(hm), proxy_up="0"), "install-clash")

    def test_fresh_machine_without_conf_installs_clash(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(
                self._plan(conf=f"{tmp}/missing.conf", hm=tmp, proxy_up="0"),
                "install-clash",
            )


def run_bootstrap_lib(body: str, *, cwd: str | None = None, timeout: float = 10) -> subprocess.CompletedProcess[str]:
    """Source bootstrap-macos.sh (helpers only) and run *body*."""
    script = f'source "{BOOTSTRAP}"\n{body}\n'
    return subprocess.run(
        ["bash", "-c", script],
        check=False,
        text=True,
        capture_output=True,
        timeout=timeout,
        cwd=cwd,
    )


_SHELL_PROXY_VARS = (
    "http_proxy",
    "https_proxy",
    "HTTP_PROXY",
    "HTTPS_PROXY",
    "all_proxy",
    "ALL_PROXY",
)
_DIRECT_UNSET = (
    "env -u http_proxy -u https_proxy -u HTTP_PROXY "
    "-u HTTPS_PROXY -u all_proxy -u ALL_PROXY"
)


class DirectClearsShellProxyTest(unittest.TestCase):
    """DOTNIX_DIRECT=1 must drop the Home Manager session proxy before any fetch."""

    def test_direct_unsets_shell_proxy_vars(self) -> None:
        assignments = "\n".join(
            f"export {name}=http://127.0.0.1:7890" for name in _SHELL_PROXY_VARS
        )
        prints = "\n".join(
            f'printf "%s=%s\\n" "{name}" "${{{name}-UNSET}}"'
            for name in _SHELL_PROXY_VARS
        )
        result = run_bootstrap_lib(
            f"""
            {assignments}
            DOTNIX_DIRECT=1
            dotnix_direct_clear_shell_proxy
            {prints}
            """
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip().splitlines(),
            [f"{name}=UNSET" for name in _SHELL_PROXY_VARS],
        )

    def test_without_direct_keeps_shell_proxy_vars(self) -> None:
        assignments = "\n".join(
            f"export {name}=http://127.0.0.1:7890" for name in _SHELL_PROXY_VARS
        )
        prints = "\n".join(
            f'printf "%s=%s\\n" "{name}" "${{{name}-UNSET}}"'
            for name in _SHELL_PROXY_VARS
        )
        result = run_bootstrap_lib(
            f"""
            unset DOTNIX_DIRECT
            {assignments}
            dotnix_direct_clear_shell_proxy
            {prints}
            """
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip().splitlines(),
            [f"{name}=http://127.0.0.1:7890" for name in _SHELL_PROXY_VARS],
        )

    def test_readme_direct_oneliner_unsets_proxy_for_curl_and_bash(self) -> None:
        text = (REPO / "README.md").read_text()
        self.assertIn(_DIRECT_UNSET, text)
        self.assertRegex(
            text,
            r"env -u http_proxy[\s\S]*?\bcurl\b[\s\S]*?\|"
            r"[\s\S]*?env -u http_proxy[\s\S]*?DOTNIX_DIRECT=1 bash",
        )
        self.assertNotRegex(
            text,
            r"(?m)^curl -fsSL \S+bootstrap-macos\.sh \| DOTNIX_DIRECT=1 bash$",
        )

    def test_bootstrap_clears_shell_proxy_before_any_curl(self) -> None:
        lines = BOOTSTRAP.read_text().splitlines()
        in_main = False
        helper_line = None
        curl_line = None
        for i, line in enumerate(lines, 1):
            stripped = line.lstrip()
            if stripped.startswith("#"):
                continue
            if not in_main:
                if stripped == "return 0":
                    in_main = True
                continue
            if helper_line is None and "dotnix_direct_clear_shell_proxy" in stripped:
                helper_line = i
            if curl_line is None and "curl" in stripped:
                curl_line = i
                break
        self.assertIsNotNone(
            helper_line, "main path must call dotnix_direct_clear_shell_proxy"
        )
        self.assertIsNotNone(curl_line, "expected a curl after the sourced-return")
        self.assertLess(helper_line, curl_line)

    def test_bootstrap_direct_recovery_oneliner_unsets_proxy(self) -> None:
        text = BOOTSTRAP.read_text()
        self.assertIn(_DIRECT_UNSET, text)
        self.assertNotRegex(
            text,
            r"(?m)^(?:#\s*)?curl -fsSL \S+ \| DOTNIX_DIRECT=1 bash",
        )


class SiblingProxyScriptTest(unittest.TestCase):
    def test_sourcing_bootstrap_does_not_run_main(self) -> None:
        result = run_bootstrap_lib(
            'type dotnix_resolve_proxy_script >/dev/null && echo sourced'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "sourced")

    def test_empty_bash_source_does_not_use_cwd(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            cwd = Path(tmp) / "cwd"
            srcdir = Path(tmp) / "tarball"
            cwd.mkdir()
            (srcdir / "scripts").mkdir(parents=True)
            (cwd / "nix-daemon-proxy.sh").write_text("DECOY\n")
            (srcdir / "scripts" / "nix-daemon-proxy.sh").write_text("REAL\n")
            result = run_bootstrap_lib(
                f'dotnix_resolve_proxy_script "{srcdir}" ""',
                cwd=str(cwd),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), str(srcdir / "scripts" / "nix-daemon-proxy.sh"))

    def test_sibling_script_wins_over_tarball(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            srcdir = Path(tmp) / "tarball"
            checkout = Path(tmp) / "checkout" / "scripts"
            (srcdir / "scripts").mkdir(parents=True)
            checkout.mkdir(parents=True)
            (srcdir / "scripts" / "nix-daemon-proxy.sh").write_text("TARBALL\n")
            (checkout / "nix-daemon-proxy.sh").write_text("SIBLING\n")
            caller = checkout / "bootstrap-macos.sh"
            caller.write_text("# caller path only\n")
            result = run_bootstrap_lib(
                f'dotnix_resolve_proxy_script "{srcdir}" "{caller}"'
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), str(checkout / "nix-daemon-proxy.sh"))


class EnablePathTest(unittest.TestCase):
    def _stub_sudo_and_plist(self, tmp: Path) -> dict[str, str]:
        """Reach the script's write path without a real Determinate install."""
        plist = tmp / "daemon.plist"
        plist.write_text("")
        fake_bin = tmp / "bin"
        fake_bin.mkdir()
        sudo = fake_bin / "sudo"
        sudo.write_text(
            textwrap.dedent(
                """\
                #!/bin/sh
                set -e
                if [ "$1" = "-v" ] || [ "$1" = "launchctl" ]; then
                  exit 0
                fi
                if [ "$1" = "install" ]; then
                  shift
                  src=""
                  dest=""
                  mode="0644"
                  while [ $# -gt 0 ]; do
                    case "$1" in
                      -m) mode=$2; shift 2 ;;
                      -o|-g) shift 2 ;;
                      *)
                        if [ -z "$src" ]; then src=$1; else dest=$1; fi
                        shift
                        ;;
                    esac
                  done
                  cp "$src" "$dest"
                  chmod "$mode" "$dest"
                  exit 0
                fi
                if [ "$1" = "mv" ]; then
                  shift
                  exec mv "$@"
                fi
                if [ "$1" = "rm" ]; then
                  shift
                  exec rm "$@"
                fi
                echo "unexpected sudo $*" >&2
                exit 90
                """
            )
        )
        sudo.chmod(sudo.stat().st_mode | stat.S_IXUSR)
        nix = fake_bin / "nix"
        nix.write_text("#!/bin/sh\nexit 0\n")
        nix.chmod(nix.stat().st_mode | stat.S_IXUSR)
        env = os.environ.copy()
        env["PATH"] = f"{fake_bin}:/usr/bin:/bin"
        env["DOTNIX_NIX_DAEMON_PLIST"] = str(plist)
        return env

    def test_direct_opt_out_is_noop_without_proxy_line(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "nix.custom.conf"
            conf.write_text("extra-substituters = https://example.invalid\n")
            env = os.environ.copy()
            env["PATH"] = "/usr/bin:/bin"
            env["DOTNIX_DIRECT"] = "1"
            env["DOTNIX_NIX_CUSTOM_CONF"] = str(conf)
            result = subprocess.run(
                ["bash", str(SCRIPT)],
                check=False,
                text=True,
                capture_output=True,
                timeout=10,
                env=env,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("no proxy impure-env", result.stdout)
            self.assertEqual(
                conf.read_text(),
                "extra-substituters = https://example.invalid\n",
            )
            self.assertNotIn("listening", result.stderr)

    def test_direct_opt_out_tries_to_clear_existing_line(self) -> None:
        if os.path.exists("/Library/LaunchDaemons/systems.determinate.nix-daemon.plist"):
            self.skipTest("Determinate Nix is installed here; cannot assert the Darwin gate")
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "nix.custom.conf"
            conf.write_text(
                "impure-env = http_proxy=http://127.0.0.1:7890 "
                "https_proxy=http://127.0.0.1:7890 no_proxy=127.0.0.1\n"
            )
            env = os.environ.copy()
            env["PATH"] = "/usr/bin:/bin"
            env["DOTNIX_DIRECT"] = "1"
            env["DOTNIX_NIX_CUSTOM_CONF"] = str(conf)
            result = subprocess.run(
                ["bash", str(SCRIPT)],
                check=False,
                text=True,
                capture_output=True,
                timeout=10,
                env=env,
            )
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn("not a Determinate Nix install", result.stderr)
            self.assertIn("https_proxy=http://127.0.0.1:7890", conf.read_text())
            self.assertNotIn("no proxy impure-env", result.stdout)

    def test_direct_unreadable_conf_is_left_untouched(self) -> None:
        """DOTNIX_DIRECT=1 must not truncate an unreadable nix.custom.conf."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            conf = tmp_path / "nix.custom.conf"
            original = (
                "extra-substituters = https://example.invalid\n"
                "extra-trusted-users = alice\n"
                "impure-env = https_proxy=http://127.0.0.1:7890\n"
            )
            conf.write_text(original)
            conf.chmod(0)
            try:
                if os.access(conf, os.R_OK):
                    self.skipTest("process can read mode 000 files (likely root)")
                env = self._stub_sudo_and_plist(tmp_path)
                env["DOTNIX_DIRECT"] = "1"
                env["DOTNIX_NIX_CUSTOM_CONF"] = str(conf)
                result = subprocess.run(
                    ["bash", str(SCRIPT)],
                    check=False,
                    text=True,
                    capture_output=True,
                    timeout=10,
                    env=env,
                )
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("cannot read", result.stderr)
                self.assertNotIn("removing the proxy", result.stdout)
                conf.chmod(0o644)
                self.assertEqual(conf.read_text(), original)
                self.assertGreater(conf.stat().st_size, 0)
            finally:
                if conf.exists():
                    conf.chmod(0o644)

    def test_linux_enable_fails_before_nc(self) -> None:
        if os.path.exists("/Library/LaunchDaemons/systems.determinate.nix-daemon.plist"):
            self.skipTest("Determinate Nix is installed here")
        env = os.environ.copy()
        env.pop("DOTNIX_DIRECT", None)
        with tempfile.TemporaryDirectory() as tmp:
            fake_nc = Path(tmp) / "nc"
            fake_nc.write_text("#!/bin/sh\necho nc-was-invoked >&2\nexit 1\n")
            fake_nc.chmod(fake_nc.stat().st_mode | stat.S_IXUSR)
            env["PATH"] = f"{tmp}:{env.get('PATH', '')}"
            result = subprocess.run(
                ["bash", str(SCRIPT)],
                check=False,
                text=True,
                capture_output=True,
                timeout=10,
                env=env,
            )
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("not a Determinate Nix install", result.stderr)
        self.assertNotIn("nc-was-invoked", result.stderr)
        self.assertNotIn("nothing is listening", result.stderr)


class WaitForDaemonTest(unittest.TestCase):
    def _fake_nix(self, directory: Path, fail_times: int) -> Path:
        wrapper = directory / "nix"
        wrapper.write_text(
            textwrap.dedent(
                f"""\
                #!/usr/bin/env bash
                set -euo pipefail
                count_file="{directory}/calls"
                if [[ "${{1:-}}" == store && "${{2:-}}" == info && "${{3:-}}" == --store && "${{4:-}}" == daemon ]]; then
                  n=0
                  [[ -e "$count_file" ]] && n=$(cat "$count_file")
                  n=$((n + 1))
                  printf '%s' "$n" >"$count_file"
                  if (( n > {fail_times} )); then
                    exit 0
                  fi
                  exit 1
                fi
                echo "unexpected nix $*" >&2
                exit 90
                """
            )
        )
        wrapper.chmod(wrapper.stat().st_mode | stat.S_IXUSR)
        return wrapper

    def test_succeeds_after_retries(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            self._fake_nix(tmp_path, fail_times=2)
            env = os.environ.copy()
            env["PATH"] = f"{tmp_path}:{env.get('PATH', '')}"
            result = run_lib("dotnix_wait_for_nix_daemon 5 0.01", env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((tmp_path / "calls").read_text(), "3")

    def test_fails_when_daemon_never_returns(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            self._fake_nix(tmp_path, fail_times=99)
            env = os.environ.copy()
            env["PATH"] = f"{tmp_path}:{env.get('PATH', '')}"
            result = run_lib("dotnix_wait_for_nix_daemon 3 0.01", env=env)
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertEqual((tmp_path / "calls").read_text(), "3")

    def test_unreachable_hint_names_the_log(self) -> None:
        result = run_lib("dotnix_print_daemon_unreachable")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("/var/log/determinate-nix-daemon.log", result.stderr)
        self.assertIn("systems.determinate.nix-daemon", result.stderr)


if __name__ == "__main__":
    unittest.main()
