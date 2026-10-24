"""The push_wiki safe output accepts one string argument named files.

Run 39432673119 prepared real pages, then stopped: the prompt's bare filename
map was rejected as unknown parameters, and a files object was rejected because
files must be a string. The retry limit ended the run before the string form
that later runs used successfully.
"""

from __future__ import annotations

import base64
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
WORKFLOW = REPO / ".github" / "workflows" / "agentic-wiki-writer.md"
LOCK = REPO / ".github" / "workflows" / "agentic-wiki-writer.lock.yml"

# The writer decodes .files and unwraps a single nested files key. Keep this
# in lockstep with the push-wiki job; the test below requires the workflow to
# contain it.
WRITER_FILTER = """
.items[] | select(.type == "push_wiki") | .files | fromjson
| (if (type == "object" and has("files") and (keys | length) == 1) then .files else . end)
| to_entries[] | @base64
""".strip()

# Proven on run 39791379008 after a files-as-object rejection. jq -Rs wraps the
# filename map as a string, which is the only shape the tool schema accepts.
CALL = "jq -Rs '{files:.}' | safeoutputs push_wiki ."


def step_3f(workflow: str) -> str:
    return workflow.split("### 3f. Push to wiki", 1)[1].split("### 3g.", 1)[0]


class AgenticWikiWriterPushTest(unittest.TestCase):
    def setUp(self) -> None:
        self.workflow = WORKFLOW.read_text()

    def test_prompt_calls_push_wiki_with_files_string(self) -> None:
        step = step_3f(self.workflow)
        self.assertIn(CALL, step)
        self.assertNotIn("do NOT nest this under an extra", self.workflow)
        self.assertNotIn("A single-batch JSON object looks like", step)
        description = self.workflow.split("inputs:", 1)[1].split("required: true", 1)[0]
        self.assertIn("JSON string", description)
        self.assertNotIn("JSON object mapping", description)
        lock = LOCK.read_text()
        self.assertIn("The files argument is a JSON string, not an object.", lock)
        self.assertNotIn("do NOT nest this under an extra", lock)

    def test_writer_filter_is_the_job_script(self) -> None:
        compact = " ".join(self.workflow.split())
        for line in WRITER_FILTER.splitlines():
            self.assertIn(" ".join(line.split()), compact)

    def test_documented_pipeline_is_a_files_string(self) -> None:
        script = """
home=$(cat <<'EOF'
## Overview
hello
EOF
)
architecture=$(cat <<'EOF'
## System Design
there
EOF
)
jq -n --arg home "$home" --arg architecture "$architecture" \\
  '{"Home.md":$home,"Architecture.md":$architecture}' \\
  | jq -Rs '{files:.}'
"""
        raw = subprocess.run(
            ["bash", "-c", script],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        payload = json.loads(raw)
        self.assertIsInstance(payload["files"], str)
        written = write_pages({"items": [{"type": "push_wiki", "files": payload["files"]}]})
        # jq --arg drops one trailing newline. The job's printf '%s\n' puts it back
        # when the page is written, so the published file matches the heredoc.
        self.assertEqual(written["Home.md"], "## Overview\nhello")
        self.assertEqual(written["Architecture.md"], "## System Design\nthere")

    def test_string_payload_and_nested_string_both_write_pages(self) -> None:
        pages = {
            "Architecture.md": "alpha\n",
            "_Sidebar.md": "- [[Home|Home]]\n",
        }
        cases = {
            "string": json.dumps(pages),
            "nested-string": json.dumps({"files": pages}),
        }
        for name, files in cases.items():
            with self.subTest(name=name):
                written = write_pages({"items": [{"type": "push_wiki", "files": files}]})
                self.assertEqual(written, pages)


def write_pages(agent_output: dict) -> dict[str, str]:
    """Run the job's jq filter and decode entries the same way the shell loop does."""
    with tempfile.TemporaryDirectory() as tmp:
        payload = Path(tmp) / "agent.json"
        payload.write_text(json.dumps(agent_output))
        result = subprocess.run(
            ["jq", "-r", WRITER_FILTER, str(payload)],
            check=True,
            capture_output=True,
            text=True,
        )
        pages: dict[str, str] = {}
        for entry in result.stdout.splitlines():
            decoded = json.loads(base64.b64decode(entry))
            pages[decoded["key"]] = decoded["value"]
        return pages


if __name__ == "__main__":
    unittest.main()
