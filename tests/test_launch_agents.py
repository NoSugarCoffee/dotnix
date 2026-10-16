"""Assertions for the launchAgentsWithoutWait activation block.

CI runs this via `python3 -m unittest discover`. The block is extracted from
home.nix the same way test_copy_apps.py extracts copyApps: Nix interpolations
are substituted, then the shell is executed against fake LaunchAgents dirs
and a stub launchctl.
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


def extract_launch_agents_block() -> str:
    home_nix = HOME_NIX.read_text()
    start = home_nix.index(
        'lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ] \'\''
    )
    start = home_nix.index("\n", start) + 1
    end = home_nix.index("\n    ''", start)
    block = nix_dedent(nix_unescape(home_nix[start:end]))
    block = re.sub(
        r"dstDir=\$\{lib\.escapeShellArg \"\$\{homeDirectory\}/Library/LaunchAgents\"\}",
        "dstDir=$DST_DIR",
        block,
        count=1,
    )
    leftover = [m for m in re.findall(r"\$\{[^}]+\}", block) if m.startswith("${lib.")]
    if leftover:
        raise AssertionError(f"unsubstituted nix interpolations: {leftover}")
    return block.replace("/bin/launchctl", "$LAUNCHCTL")


STUB_LAUNCHCTL = textwrap.dedent(
    """\
    #!/usr/bin/env bash
    set -euo pipefail
    log=${LAUNCHCTL_LOG:?}
    mode=${LAUNCHCTL_MODE:?}
    printf '%s\\n' "$*" >> "$log"
    if [[ $1 == bootout && $2 == --wait ]]; then
      echo "Unrecognized target specifier" >&2
      exit 64
    fi
    if [[ $1 == bootout ]]; then
      exit 0
    fi
    if [[ $1 == print ]]; then
      if [[ $mode == still-loaded ]]; then
        exit 0
      fi
      # After the first print, the job is gone (bootout has taken effect).
      if [[ -f ${LAUNCHCTL_UNLOADED:-/dev/null} ]]; then
        exit 1
      fi
      mkdir -p "$(dirname "${LAUNCHCTL_UNLOADED}")"
      : > "${LAUNCHCTL_UNLOADED}"
      exit 0
    fi
    echo "unexpected launchctl $*" >&2
    exit 99
    """
)


class LaunchAgentsWithoutWaitTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        bash_version = subprocess.run(
            ["bash", "-c", 'echo "${BASH_VERSINFO[0]} ${BASH_VERSINFO[1]}"'],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.split()
        if tuple(map(int, bash_version)) < (4, 2):
            raise unittest.SkipTest(
                f"bash {'.'.join(bash_version)} on PATH is older than 4.2; run `just test`"
            )
        cls.block = extract_launch_agents_block()

    def setUp(self) -> None:
        self.box = Path(tempfile.mkdtemp(prefix="launchagents-"))
        self.addCleanup(shutil.rmtree, self.box, ignore_errors=True)
        self.dst = self.box / "LaunchAgents"
        self.new_gen = self.box / "new" / "LaunchAgents"
        self.old_gen = self.box / "old" / "LaunchAgents"
        self.dst.mkdir(parents=True)
        self.new_gen.mkdir(parents=True)
        self.old_gen.mkdir(parents=True)
        self.launchctl = self.box / "launchctl"
        self.launchctl.write_text(STUB_LAUNCHCTL)
        self.launchctl.chmod(self.launchctl.stat().st_mode | stat.S_IEXEC)
        self.log = self.box / "launchctl.log"

    def write_plist(self, directory: Path, name: str, body: str) -> None:
        directory.joinpath(name).write_text(body)

    def run_block(
        self,
        *,
        mode: str,
        old_gen: bool = True,
        extra_env: dict[str, str] | None = None,
        rm_is_failing: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        script = self.box / "activate-fragment.sh"
        rm_override = ""
        if rm_is_failing:
            fail_rm = self.box / "fail-rm"
            fail_rm.write_text(
                "#!/usr/bin/env bash\n"
                'if [[ $1 == -f ]]; then echo "rm failed" >&2; exit 1; fi\n'
                "exec /bin/rm \"$@\"\n"
            )
            fail_rm.chmod(fail_rm.stat().st_mode | stat.S_IEXEC)
            rm_override = f'rm() {{ "{fail_rm}" "$@"; }}\n'
        script.write_text(
            "#!/usr/bin/env bash\n"
            "set -eu\n"
            "set -o pipefail\n"
            "run() { \"$@\"; }\n"
            "warnEcho() { echo \"$*\" >&2; }\n"
            "sleep() { :; }\n"
            f"{rm_override}"
            f"newGenPath={self.box / 'new'}\n"
            f"{'oldGenPath=' + str(self.box / 'old') if old_gen else ''}\n"
            f"DST_DIR={self.dst}\n"
            f"export LAUNCHCTL={self.launchctl}\n"
            f"export LAUNCHCTL_LOG={self.log}\n"
            f"export LAUNCHCTL_MODE={mode}\n"
            f"export LAUNCHCTL_UNLOADED={self.box / 'unloaded'}\n"
            f"{self.block}\n"
            "echo SURVIVED\n"
        )
        env = os.environ.copy()
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            ["bash", str(script)],
            capture_output=True,
            text=True,
            env=env,
        )

    def test_dag_sits_between_write_boundary_and_setup(self) -> None:
        source = HOME_NIX.read_text()
        self.assertIn(
            'lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ]',
            source,
        )
        self.assertNotIn(
            'lib.hm.dag.entryBefore [ "setupLaunchAgents" ]',
            source,
        )

    def test_subshell_disables_errexit(self) -> None:
        self.assertIn("set +e", self.block)

    def test_changed_agent_is_removed_once_unloaded(self) -> None:
        self.write_plist(self.dst, "org.example.agent.plist", "old\n")
        self.write_plist(self.new_gen, "org.example.agent.plist", "new\n")
        result = self.run_block(mode="unloads")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SURVIVED", result.stdout)
        self.assertFalse((self.dst / "org.example.agent.plist").exists())

    def test_still_loaded_warns_and_leaves_plist(self) -> None:
        self.write_plist(self.dst, "org.example.agent.plist", "old\n")
        self.write_plist(self.new_gen, "org.example.agent.plist", "new\n")
        result = self.run_block(mode="still-loaded")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("still loaded after 5s", result.stderr)
        self.assertTrue((self.dst / "org.example.agent.plist").exists())
        self.assertEqual((self.dst / "org.example.agent.plist").read_text(), "old\n")

    def test_failing_rm_does_not_abort_activation(self) -> None:
        self.write_plist(self.dst, "org.example.agent.plist", "old\n")
        self.write_plist(self.new_gen, "org.example.agent.plist", "new\n")
        result = self.run_block(mode="unloads", rm_is_failing=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SURVIVED", result.stdout)

    def test_dropped_agent_matching_old_generation_is_removed(self) -> None:
        self.write_plist(self.dst, "org.example.gone.plist", "same\n")
        self.write_plist(self.old_gen, "org.example.gone.plist", "same\n")
        result = self.run_block(mode="unloads")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.dst / "org.example.gone.plist").exists())

    def test_noop_when_probe_does_not_reject_wait(self) -> None:
        # Replace the stub so --wait is accepted (empty stderr, success).
        self.launchctl.write_text(
            "#!/usr/bin/env bash\n"
            "exit 0\n"
        )
        self.write_plist(self.dst, "org.example.agent.plist", "old\n")
        self.write_plist(self.new_gen, "org.example.agent.plist", "new\n")
        result = self.run_block(mode="unloads")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.dst / "org.example.agent.plist").exists())


if __name__ == "__main__":
    unittest.main()
