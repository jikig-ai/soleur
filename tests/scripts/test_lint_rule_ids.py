#!/usr/bin/env python3
"""Tests for scripts/lint-rule-ids.py."""

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


if __name__ == "__main__":
    unittest.main()
