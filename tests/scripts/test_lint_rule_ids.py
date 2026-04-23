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


def _run_with_retired(agents_content: str, retired_content: str | None) -> subprocess.CompletedProcess:
    """Invoke the linter with an optional --retired-file flag.

    When retired_content is None, the flag is omitted (backward-compat path).
    When provided, the allowlist is written to a sibling file inside the same
    tempdir and passed via --retired-file.
    """
    with tempfile.TemporaryDirectory() as tmp:
        agents = Path(tmp) / "AGENTS.md"
        agents.write_text(agents_content)
        argv = [sys.executable, str(SCRIPT)]
        if retired_content is not None:
            retired = Path(tmp) / "retired-rule-ids.txt"
            retired.write_text(retired_content)
            argv.extend(["--retired-file", str(retired)])
        argv.append(str(agents))
        return subprocess.run(argv, capture_output=True, text=True)


def _run_git_seeded(agents_head: str, agents_working: str, retired_content: str | None) -> subprocess.CompletedProcess:
    """Seed a git repo with agents_head committed, then overwrite with agents_working.

    Optionally writes retired-rule-ids.txt and passes --retired-file. Invokes
    linter with the RELATIVE path "AGENTS.md" (cwd=repo) so `git show HEAD:<path>`
    resolves the committed blob.
    """
    tmp = tempfile.mkdtemp()
    try:
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
        agents.write_text(agents_head)
        subprocess.run(["git", "-C", str(repo), "add", "AGENTS.md"], check=True, env=env)
        subprocess.run(["git", "-C", str(repo), "commit", "-q", "-m", "seed"], check=True, env=env)
        agents.write_text(agents_working)
        argv = [sys.executable, str(SCRIPT)]
        if retired_content is not None:
            retired = repo / "retired-rule-ids.txt"
            retired.write_text(retired_content)
            argv.extend(["--retired-file", str(retired)])
        argv.append("AGENTS.md")
        return subprocess.run(argv, capture_output=True, text=True, cwd=str(repo))
    finally:
        subprocess.run(["rm", "-rf", tmp], check=False)


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


    def test_retired_id_passes_when_in_allowlist(self):
        """Rule present at HEAD, absent from working copy, listed in allowlist → linter passes."""
        agents_head = (
            "# Agent Instructions\n\n## Hard Rules\n\n"
            "- Rule one [id: hr-rule-one].\n"
            "- Rule two [id: hr-rule-two].\n"
        )
        agents_working = (
            "# Agent Instructions\n\n## Hard Rules\n\n"
            "- Rule one [id: hr-rule-one].\n"
        )
        retired = "hr-rule-two | 2026-04-23 | #2865 | -\n"
        r = _run_git_seeded(agents_head, agents_working, retired)
        self.assertEqual(r.returncode, 0, f"stdout={r.stdout!r} stderr={r.stderr!r}")

    def test_missing_retired_file_backward_compat(self):
        """No --retired-file passed → linter behaves identically to pre-change.

        Valid AGENTS.md (no HEAD diff to worry about) should pass.
        Duplicate IDs should still fail.
        """
        r_valid = _run_with_retired(FIXTURE_VALID, None)
        self.assertEqual(r_valid.returncode, 0, r_valid.stderr)

        r_dup = _run_with_retired(FIXTURE_DUPLICATE, None)
        self.assertEqual(r_dup.returncode, 1)
        self.assertIn("duplicate", r_dup.stderr)

    def test_reintroduced_retired_id_fails(self):
        """ID listed as retired AND present as active rule → linter rejects."""
        agents_head = (
            "# Agent Instructions\n\n## Hard Rules\n\n"
            "- Rule one [id: hr-rule-one].\n"
            "- Rule two [id: hr-rule-two].\n"
        )
        agents_working = agents_head  # hr-rule-two still active
        retired = "hr-rule-two | 2026-04-23 | #2865 | -\n"
        r = _run_git_seeded(agents_head, agents_working, retired)
        self.assertEqual(r.returncode, 1, f"stdout={r.stdout!r} stderr={r.stderr!r}")
        self.assertTrue(
            "reintroduced" in r.stderr or "retired" in r.stderr,
            f"Expected 'reintroduced' or 'retired' in stderr; got: {r.stderr!r}",
        )


if __name__ == "__main__":
    unittest.main()
