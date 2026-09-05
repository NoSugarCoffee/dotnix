"""Unit tests for Autoloop scheduling helpers."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1] / ".github" / "workflows" / "scripts"
sys.path.insert(0, str(SCRIPTS))

import autoloop_scheduler as sched  # noqa: E402


class DashboardIssueClassificationTests(unittest.TestCase):
    def test_dashboard_title_maps_to_matching_file_program(self):
        name = sched.dashboard_program_name(
            "[Autoloop: darwin-packages-freshness]",
            {"darwin-packages-freshness", "nixpkgs-freshness"},
        )
        self.assertEqual(name, "darwin-packages-freshness")

    def test_unrelated_autoloop_issue_is_not_a_dashboard(self):
        name = sched.dashboard_program_name(
            "[Autoloop: reduce-latency]",
            {"darwin-packages-freshness", "nixpkgs-freshness"},
        )
        self.assertIsNone(name)

    def test_classify_drops_dashboard_issues_and_keeps_the_oldest(self):
        issue_programs = {
            "autoloop-darwin-packages-freshness": {
                "issue_number": 115,
                "file": "/tmp/gh-aw/issue-programs/autoloop-darwin-packages-freshness.md",
                "title": "[Autoloop: darwin-packages-freshness]",
            },
            "autoloop-darwin-packages-freshness-91": {
                "issue_number": 91,
                "file": "/tmp/gh-aw/issue-programs/autoloop-darwin-packages-freshness-91.md",
                "title": "[Autoloop: darwin-packages-freshness]",
            },
            "reduce-latency": {
                "issue_number": 8,
                "file": "/tmp/gh-aw/issue-programs/reduce-latency.md",
                "title": "[Autoloop: reduce-latency]",
            },
        }
        remaining, dashboards = sched.classify_issue_programs(
            issue_programs,
            {"darwin-packages-freshness", "nixpkgs-freshness"},
        )
        self.assertEqual(set(remaining), {"reduce-latency"})
        self.assertEqual(dashboards, {"darwin-packages-freshness": 91})

    def test_file_program_resolves_to_dashboard_issue(self):
        issue_number = sched.resolve_selected_issue(
            "darwin-packages-freshness",
            {},
            {"darwin-packages-freshness": 91},
        )
        self.assertEqual(issue_number, 91)

    def test_issue_based_program_still_uses_its_own_issue(self):
        issue_number = sched.resolve_selected_issue(
            "reduce-latency",
            {"reduce-latency": {"issue_number": 8, "file": "x", "title": "Reduce Latency"}},
            {"darwin-packages-freshness": 91},
        )
        self.assertEqual(issue_number, 8)


class RepoMemoryPathTests(unittest.TestCase):
    def test_scheduler_reads_the_framework_memory_dir(self):
        self.assertEqual(sched.REPO_MEMORY_DIR, "/tmp/gh-aw/repo-memory/default")


if __name__ == "__main__":
    unittest.main()
