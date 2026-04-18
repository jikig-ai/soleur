#!/usr/bin/env python3
"""Tests for scripts/lint-rule-ids.py."""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "lint-rule-ids.py"


FIXTURE_MISSING = """# Agent Instructions

## Hard Rules

- Rule one missing id.
- Rule two [id: hr-rule-two-has-id].
"""

FIXTURE_DUPLICATE = """# Agent Instructions

## Hard Rules

- Rule one [id: hr-dup].
- Rule two [id: hr-dup].
"""

FIXTURE_INVALID_FORMAT = """# Agent Instructions

## Hard Rules

- Rule one [id: xx-bad-prefix].
"""

FIXTURE_VALID = """# Agent Instructions

## Hard Rules

- Rule one [id: hr-rule-one].

## Communication

- Rule two [id: cm-rule-two].
"""


def _run(content: str) -> subprocess.CompletedProcess:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "AGENTS.md"
        path.write_text(content)
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(path)],
            capture_output=True, text=True,
        )


class LintTests(unittest.TestCase):
    def test_valid_passes(self):
        r = _run(FIXTURE_VALID)
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_missing_id_fails(self):
        r = _run(FIXTURE_MISSING)
        self.assertEqual(r.returncode, 1)
        self.assertIn("missing [id:", r.stderr)

    def test_duplicate_fails(self):
        r = _run(FIXTURE_DUPLICATE)
        self.assertEqual(r.returncode, 1)
        self.assertIn("duplicate", r.stderr)

    def test_invalid_format_fails(self):
        r = _run(FIXTURE_INVALID_FORMAT)
        self.assertEqual(r.returncode, 1)
        self.assertIn("invalid id format", r.stderr)

    def test_removed_id_exits_1(self):
        """An id present at HEAD but absent from the working copy must
        hard-fail (exit 1). The stale comment in lint-rule-ids.py that
        claimed this was warn-only has been reconciled with the actual
        behavior.
        """
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "repo"
            repo.mkdir()
            env = {
                **os.environ,
                "GIT_AUTHOR_NAME": "t",
                "GIT_AUTHOR_EMAIL": "t@test",
                "GIT_COMMITTER_NAME": "t",
                "GIT_COMMITTER_EMAIL": "t@test",
            }
            subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True, env=env)
            agents = repo / "AGENTS.md"
            agents.write_text(
                "# Agent Instructions\n\n## Hard Rules\n\n"
                "- Rule one [id: hr-rule-one].\n"
                "- Rule two [id: hr-rule-two].\n"
            )
            subprocess.run(["git", "-C", str(repo), "add", "AGENTS.md"], check=True, env=env)
            subprocess.run(["git", "-C", str(repo), "commit", "-q", "-m", "seed"], check=True, env=env)
            # Remove hr-rule-two from the working copy without committing.
            agents.write_text(
                "# Agent Instructions\n\n## Hard Rules\n\n"
                "- Rule one [id: hr-rule-one].\n"
            )
            # Pass a RELATIVE path (AGENTS.md) so `git show HEAD:<path>`
            # resolves inside the temp repo. Absolute paths would produce
            # an empty HEAD blob and silently skip the removed-id check.
            r = subprocess.run(
                [sys.executable, str(REPO_ROOT / "scripts" / "lint-rule-ids.py"), "AGENTS.md"],
                capture_output=True, text=True, cwd=str(repo),
            )
            self.assertEqual(r.returncode, 1, f"stdout={r.stdout!r} stderr={r.stderr!r}")
            self.assertIn("removed id(s) detected", r.stderr)
            self.assertIn("hr-rule-two", r.stderr)


if __name__ == "__main__":
    unittest.main()
