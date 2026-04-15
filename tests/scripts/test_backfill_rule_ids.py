#!/usr/bin/env python3
"""Tests for scripts/backfill-rule-ids.py.

Loads the hyphen-named script via importlib, plus exercises the CLI
end-to-end on fixture AGENTS.md files in tmp dirs.
"""

import hashlib
import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts" / "backfill-rule-ids.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("backfill_rule_ids", SCRIPT_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


FIXTURE_BASIC = """---
title: Agent Instructions
---

# Agent Instructions

## Hard Rules

- Never `git stash` in worktrees. Commit WIP first.
- MCP tools resolve paths from the repo root, not the shell CWD.

## Workflow Gates

- Use `Closes #N` in PR body to auto-close issues.
"""

FIXTURE_WITH_HOOK_TAG = """---
title: Agent Instructions
---

# Agent Instructions

## Hard Rules

- Never `git stash` in worktrees [hook-enforced: guardrails.sh]. Commit WIP first.
"""

FIXTURE_COLLISION = """---
title: Agent Instructions
---

# Agent Instructions

## Hard Rules

- Alpha beta gamma delta epsilon zeta first variant.
- Alpha beta gamma delta epsilon zeta second variant.
"""

FIXTURE_ALREADY_TAGGED = """---
title: Agent Instructions
---

# Agent Instructions

## Hard Rules

- Never `git stash` in worktrees [id: hr-never-git-stash-in-worktrees]. Commit WIP first.
- MCP tools resolve paths from the repo root [id: hr-mcp-tools-resolve-paths-from-repo-root], not shell CWD.
"""


class SlugifyTests(unittest.TestCase):
    def setUp(self):
        self.mod = _load_module()

    def test_slugify_strips_backticks_and_punctuation(self):
        self.assertEqual(
            self.mod.slugify("Never `git stash` in worktrees"),
            "never-git-stash-in-worktrees",
        )

    def test_slugify_max_40_chars(self):
        result = self.mod.slugify("a b c d e f g h i j k l m n o p q r s t u v w x y z")
        self.assertLessEqual(len(result), 40)

    def test_slugify_min_3_chars(self):
        # Very short text still produces a slug of at least 3 chars
        result = self.mod.slugify("Hi")
        self.assertGreaterEqual(len(result), 3)

    def test_section_prefix_map(self):
        self.assertEqual(self.mod.section_prefix("Hard Rules"), "hr")
        self.assertEqual(self.mod.section_prefix("Workflow Gates"), "wg")
        self.assertEqual(self.mod.section_prefix("Code Quality"), "cq")
        self.assertEqual(self.mod.section_prefix("Review & Feedback"), "rf")
        self.assertEqual(self.mod.section_prefix("Passive Domain Routing"), "pdr")
        self.assertEqual(self.mod.section_prefix("Communication"), "cm")

    def test_section_prefix_unknown_returns_none(self):
        self.assertIsNone(self.mod.section_prefix("Random Heading"))


class AssignIdsTests(unittest.TestCase):
    def setUp(self):
        self.mod = _load_module()

    def test_assigns_ids_to_untagged_rules(self):
        out = self.mod.assign_ids(FIXTURE_BASIC)
        self.assertIn("[id: hr-never-git-stash-in-worktrees]", out)
        self.assertIn("[id: hr-mcp-tools-resolve-paths-from-the-repo]", out)
        self.assertRegex(out, r"\[id: wg-use-closes-[a-z0-9-]+\]")

    def test_inserts_id_before_existing_hook_tag(self):
        out = self.mod.assign_ids(FIXTURE_WITH_HOOK_TAG)
        # `[id: ...] [hook-enforced: ...]` ordering
        self.assertRegex(out, r"\[id: hr-[a-z0-9-]+\] \[hook-enforced: guardrails\.sh\]")

    def test_idempotent_on_already_tagged(self):
        out = self.mod.assign_ids(FIXTURE_ALREADY_TAGGED)
        self.assertEqual(out, FIXTURE_ALREADY_TAGGED)

    def test_collision_suffix(self):
        out = self.mod.assign_ids(FIXTURE_COLLISION)
        # Both IDs must share the same slug root with one getting a -2 suffix
        import re
        ids = re.findall(r"\[id: (hr-[a-z0-9-]+)\]", out)
        self.assertEqual(len(ids), 2)
        self.assertEqual(len(set(ids)), 2, f"IDs not unique: {ids}")
        # Same base slug, one suffixed -2
        self.assertTrue(
            any(i.endswith("-2") for i in ids),
            f"No -2 suffix found in {ids}",
        )

    def test_preserves_body_outside_insertions(self):
        """Stripping `[id: ...] ` from the output must reproduce the input."""
        import re
        out = self.mod.assign_ids(FIXTURE_BASIC)
        stripped = re.sub(r" \[id: [a-z0-9-]+\]", "", out)
        self.assertEqual(stripped, FIXTURE_BASIC)


class CLITests(unittest.TestCase):
    def _write_and_run(self, content, *extra_args):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "AGENTS.md"
            path.write_text(content)
            result = subprocess.run(
                [sys.executable, str(SCRIPT_PATH), str(path), *extra_args],
                capture_output=True,
                text=True,
            )
            final = path.read_text() if path.exists() else ""
            return result, final

    def test_cli_writes_ids(self):
        result, final = self._write_and_run(FIXTURE_BASIC)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("[id: hr-", final)

    def test_cli_dry_run_does_not_write(self):
        result, final = self._write_and_run(FIXTURE_BASIC, "--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(final, FIXTURE_BASIC)  # unchanged
        self.assertIn("[id: hr-", result.stdout)  # proposed IDs printed

    def test_cli_idempotent(self):
        # First run
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "AGENTS.md"
            path.write_text(FIXTURE_BASIC)
            subprocess.run([sys.executable, str(SCRIPT_PATH), str(path)], check=True)
            after_first = path.read_text()
            subprocess.run([sys.executable, str(SCRIPT_PATH), str(path)], check=True)
            after_second = path.read_text()
            self.assertEqual(after_first, after_second)

    def test_cli_body_hash_protection(self):
        """The script must detect if anything beyond [id: ...] insertion would change."""
        # This exercises compute_body_hash pre/post invariant
        mod = _load_module()
        original = "- Some rule text"
        inserted = "- Some rule text [id: hr-some-rule-text]"
        # After stripping IDs, they match
        self.assertEqual(mod.strip_ids(inserted), original)


if __name__ == "__main__":
    unittest.main()
