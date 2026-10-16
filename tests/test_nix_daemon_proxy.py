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

            conf.write_text(
                "impure-env = http_proxy=http://127.0.0.1:7890 "
                "https_proxy=http://127.0.0.1:7890 no_proxy=127.0.0.1\n"
            )
            result = run_lib(
                f'if dotnix_conf_has_impure_env "{conf}"; then echo yes; else echo no; fi'
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


class StripProxyImpureEnvTest(unittest.TestCase):
    def test_drops_proxy_line_keeps_custom(self) -> None:
        result = run_lib(
            textwrap.dedent(
                """\
                dotnix_strip_proxy_impure_env <<'EOF'
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
            "impure-env = FOO=bar\n"
            "extra-experimental-features = configurable-impure-env\n",
        )

    def test_drops_stale_proxy_url(self) -> None:
        result = run_lib(
            textwrap.dedent(
                """\
                dotnix_strip_proxy_impure_env <<'EOF'
                impure-env = http_proxy=http://127.0.0.1:1080 https_proxy=http://127.0.0.1:1080
                EOF
                """
            )
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")


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

    def test_direct_opt_out_wins(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "nix.custom.conf"
            conf.write_text("impure-env = https_proxy=http://127.0.0.1:7890\n")
            self.assertEqual(
                self._plan(conf=str(conf), hm=tmp, proxy_up="0", env={"DOTNIX_DIRECT": "1"}),
                "direct",
            )

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


class EnablePathTest(unittest.TestCase):
    def test_direct_opt_out_is_a_noop(self) -> None:
        env = os.environ.copy()
        env["PATH"] = "/usr/bin:/bin"
        env["DOTNIX_DIRECT"] = "1"
        result = subprocess.run(
            ["bash", str(SCRIPT)],
            check=False,
            text=True,
            capture_output=True,
            timeout=10,
            env=env,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("DOTNIX_DIRECT=1", result.stdout)
        self.assertNotIn("listening", result.stderr)

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
