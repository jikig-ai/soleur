#!/usr/bin/env python3
"""Tests for scripts/lint-rule-bodies.py — the hard-rule body-weakening gate.

Hermetic fixtures: each test builds a throwaway git repo with small
AGENTS.{core,docs,rest}.md sidecars, generates the body-hash manifest via
`--write`, optionally mutates + commits a body change, then runs
`--check --base <merge-base>` and asserts BLOCK (exit non-zero) vs PASS.

The live calibration over the real ~194-rule corpus is a separate `--check`
invocation wired in scripts/test-all.sh (mirrors the `lint-rule-ids-live`
convention); the AC7 zero-findings-on-baseline claim is asserted there.

Run: python3 -m unittest tests.scripts.test_lint_rule_bodies
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "lint-rule-bodies.py"

# A minimal but structurally faithful sidecar trio. Bodies live under a
# `## <SECTION>` heading matching scripts/_agents_md_sections.py; pointer
# lines (`- [id: x] → core`) live in the index and are ignored by the gate.
CORE = """# AGENTS Core

## Hard Rules

- Never do the dangerous thing [id: hr-never-dangerous]. Do the safe thing instead.
- Always gate regulated data [id: hr-gdpr-example] [hook-enforced: some-hook.sh]. Mandatory on every write.

## Workflow Gates

- Ship only after review [id: wg-ship-after-review]. Do not skip.
"""

DOCS = """# AGENTS Docs

## Code Quality

- Rule ids are immutable [id: cq-rule-ids-immutable]. Never reuse a retired id.
"""

REST = """# AGENTS Rest

## Workflow Gates

- Verified work ships [id: wg-verified-ships]. No extra ask needed.
"""


def _git(repo: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True, text=True, check=True,
    )


def _run(repo: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--root", str(repo), *args],
        capture_output=True, text=True,
    )


class _RepoFixture:
    """Context manager that yields a committed temp repo with a fresh manifest."""

    def __init__(self, core: str = CORE, docs: str = DOCS, rest: str = REST):
        self._core, self._docs, self._rest = core, docs, rest

    def __enter__(self) -> Path:
        self._tmp = tempfile.TemporaryDirectory()
        repo = Path(self._tmp.name)
        _git(repo, "init", "-q", "-b", "main")
        _git(repo, "config", "user.email", "t@t")
        _git(repo, "config", "user.name", "t")
        (repo / "AGENTS.core.md").write_text(self._core)
        (repo / "AGENTS.docs.md").write_text(self._docs)
        (repo / "AGENTS.rest.md").write_text(self._rest)
        (repo / ".claude").mkdir()
        (repo / ".claude" / "rule-weakening-acks.txt").write_text(
            "# id|sha256|date|PR|reason\n"
        )
        # Generate the baseline manifest over the committed corpus.
        r = _run(repo, "--write")
        assert r.returncode == 0, f"--write failed: {r.stderr}"
        _git(repo, "add", "-A")
        _git(repo, "commit", "-q", "-m", "baseline")
        self.repo = repo
        return repo

    def __exit__(self, *exc):
        self._tmp.cleanup()


MANIFEST_REL = Path(".claude") / "rule-body-hashes.txt"


def _manifest_map(repo: Path) -> dict[str, str]:
    """Parse the hash-first text manifest (`<sha256>  <id>`) → {id: hash}."""
    out: dict[str, str] = {}
    for line in (repo / MANIFEST_REL).read_text().splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        h, rid = s.split()
        out[rid] = h
    return out


def _body_hash(repo: Path, rid: str) -> str:
    return _manifest_map(repo)[rid]


def _regen_manifest(repo: Path) -> None:
    r = _run(repo, "--write")
    assert r.returncode == 0, f"--write failed: {r.stderr}"


def _append_ack(repo: Path, line: str) -> None:
    p = repo / ".claude" / "rule-weakening-acks.txt"
    p.write_text(p.read_text() + line + "\n")


def _hash_body(raw_line: str) -> str:
    """Mirror the gate's normalize+sha256 (`" ".join(line.split())`)."""
    import hashlib

    return hashlib.sha256(" ".join(raw_line.split()).encode("utf-8")).hexdigest()


def _merge_base(repo: Path) -> str:
    # In these fixtures HEAD's parent (or the baseline commit) is the base.
    return _git(repo, "rev-parse", "HEAD").stdout.strip()


class TestBodyWeakeningGate(unittest.TestCase):
    def test_baseline_head_vs_head_zero_findings(self):
        """AC7 calibration: clean tree, base==HEAD → PASS, no findings."""
        with _RepoFixture() as repo:
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            r = _run(repo, "--check", "--base", base)
            self.assertEqual(r.returncode, 0, r.stderr)

    def test_body_change_without_ack_blocks(self):
        """AC1: hr-* body change under a stable id, no ack → BLOCK naming id."""
        with _RepoFixture() as repo:
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            (repo / "AGENTS.core.md").write_text(
                CORE.replace("Do the safe thing instead.", "Optional: maybe do it.")
            )
            _regen_manifest(repo)
            _git(repo, "commit", "-qam", "weaken")
            r = _run(repo, "--check", "--base", base)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("hr-never-dangerous", r.stderr)

    def test_body_change_with_valid_ack_passes(self):
        """AC2: body change + ack whose sha256 == new body hash → PASS."""
        with _RepoFixture() as repo:
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            (repo / "AGENTS.core.md").write_text(
                CORE.replace("Do the safe thing instead.", "Optional: maybe do it.")
            )
            _regen_manifest(repo)
            new_hash = _body_hash(repo, "hr-never-dangerous")
            _append_ack(
                repo,
                f"hr-never-dangerous|{new_hash}|{date.today().isoformat()}|#6103|reworded",
            )
            _git(repo, "commit", "-qam", "weaken+ack")
            r = _run(repo, "--check", "--base", base)
            self.assertEqual(r.returncode, 0, r.stderr)

    def test_stale_ack_wrong_hash_blocks(self):
        """AC3: ack present for the id but sha256 != current body hash → BLOCK."""
        with _RepoFixture() as repo:
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            (repo / "AGENTS.core.md").write_text(
                CORE.replace("Do the safe thing instead.", "Optional: maybe do it.")
            )
            _regen_manifest(repo)
            _append_ack(
                repo,
                f"hr-never-dangerous|{'0' * 64}|{date.today().isoformat()}|#6103|stale",
            )
            _git(repo, "commit", "-qam", "weaken+staleack")
            r = _run(repo, "--check", "--base", base)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("hr-never-dangerous", r.stderr)

    def test_deletion_without_ack_blocks(self):
        """AC4: deletion of a body line under a retained-index id → BLOCK."""
        with _RepoFixture() as repo:
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            lines = [
                ln for ln in CORE.splitlines()
                if "hr-never-dangerous" not in ln
            ]
            (repo / "AGENTS.core.md").write_text("\n".join(lines) + "\n")
            _regen_manifest(repo)
            _git(repo, "commit", "-qam", "delete-body")
            r = _run(repo, "--check", "--base", base)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("hr-never-dangerous", r.stderr)

    def test_deletion_with_deleted_ack_passes(self):
        """AC4 companion: deletion + `<id>|DELETED|...` ack → PASS."""
        with _RepoFixture() as repo:
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            lines = [
                ln for ln in CORE.splitlines()
                if "hr-never-dangerous" not in ln
            ]
            (repo / "AGENTS.core.md").write_text("\n".join(lines) + "\n")
            _regen_manifest(repo)
            _append_ack(
                repo,
                f"hr-never-dangerous|DELETED|{date.today().isoformat()}|#6103|retired",
            )
            _git(repo, "commit", "-qam", "delete-body+ack")
            r = _run(repo, "--check", "--base", base)
            self.assertEqual(r.returncode, 0, r.stderr)

    def test_new_rule_passes(self):
        """AC5: benign additive edit (new rule, fresh id) → PASS."""
        with _RepoFixture() as repo:
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            (repo / "AGENTS.core.md").write_text(
                CORE + "- A brand new rule [id: hr-brand-new]. Do this.\n"
            )
            _regen_manifest(repo)
            _git(repo, "commit", "-qam", "add-rule")
            r = _run(repo, "--check", "--base", base)
            self.assertEqual(r.returncode, 0, r.stderr)

    def test_new_security_tagged_rule_annotates_but_passes(self):
        """AC5: new id carrying a security tag → mandatory-human-review annotation, still PASS."""
        with _RepoFixture() as repo:
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            (repo / "AGENTS.core.md").write_text(
                CORE
                + "- New compliance control [id: hr-new-compliance] [compliance-tier]. Mandatory.\n"
            )
            _regen_manifest(repo)
            _git(repo, "commit", "-qam", "add-tagged-rule")
            r = _run(repo, "--check", "--base", base)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("hr-new-compliance", r.stdout + r.stderr)

    def test_security_tagged_change_emits_mandatory_review(self):
        """AC-annotation: changing a [hook-enforced] body emits the louder annotation (ack still required)."""
        with _RepoFixture() as repo:
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            (repo / "AGENTS.core.md").write_text(
                CORE.replace("Mandatory on every write.", "Advisory only.")
            )
            _regen_manifest(repo)
            _git(repo, "commit", "-qam", "weaken-tagged")
            r = _run(repo, "--check", "--base", base)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("hr-gdpr-example", r.stderr)
            self.assertIn("mandatory-human-review", (r.stdout + r.stderr).lower())

    def test_rule_added_without_manifest_regen_does_not_block(self):
        """Cross-PR staleness: a NEW rule present in head but absent from a stale
        manifest must NOT block (additive; integrity is intersection-scoped).

        Simulates a sibling PR that added a rule on main without this branch's
        manifest — the next unrelated PR must stay green ("all-members drift
        guard must rebase before ship" class)."""
        with _RepoFixture() as repo:
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            # Add a new rule but do NOT regenerate the manifest (stale baseline).
            (repo / "AGENTS.core.md").write_text(
                CORE + "- A sibling-added rule [id: hr-sibling-added]. Do this.\n"
            )
            _git(repo, "commit", "-qam", "sibling-add-no-regen")
            r = _run(repo, "--check", "--base", base)
            self.assertEqual(r.returncode, 0, r.stderr)

    def test_tampered_manifest_blocks(self):
        """AC6: a hand-edited manifest value not matching the body → BLOCK (gate re-derives)."""
        with _RepoFixture() as repo:
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            man = repo / MANIFEST_REL
            # Replace hr-never-dangerous's hash with a bogus one (keep hash-first shape).
            new_lines = []
            for line in man.read_text().splitlines():
                if line.strip().endswith("hr-never-dangerous"):
                    new_lines.append(f"{'f' * 64}  hr-never-dangerous")
                else:
                    new_lines.append(line)
            man.write_text("\n".join(new_lines) + "\n")
            _git(repo, "commit", "-qam", "tamper-manifest")
            r = _run(repo, "--check", "--base", base)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("hr-never-dangerous", r.stderr)

    def test_trailing_whitespace_reformat_is_noop(self):
        """AC7: trailing-whitespace-only reformat → PASS (normalized before hashing)."""
        with _RepoFixture() as repo:
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            (repo / "AGENTS.core.md").write_text(
                CORE.replace(
                    "Do the safe thing instead.",
                    "Do the safe thing instead.   ",  # trailing spaces
                )
            )
            _regen_manifest(repo)
            _git(repo, "commit", "-qam", "reformat")
            r = _run(repo, "--check", "--base", base)
            self.assertEqual(r.returncode, 0, r.stderr)

    def test_wg_body_moved_core_to_rest_and_weakened_is_caught(self):
        """AC12: a wg-* body moved core→rest AND weakened is caught via the unioned base map."""
        with _RepoFixture() as repo:
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            # Remove wg-ship-after-review from core, re-add a WEAKENED copy in rest.
            core_lines = [
                ln for ln in CORE.splitlines()
                if "wg-ship-after-review" not in ln
            ]
            (repo / "AGENTS.core.md").write_text("\n".join(core_lines) + "\n")
            (repo / "AGENTS.rest.md").write_text(
                REST + "- Ship only after review [id: wg-ship-after-review]. Optional.\n"
            )
            _regen_manifest(repo)
            _git(repo, "commit", "-qam", "move+weaken")
            r = _run(repo, "--check", "--base", base)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("wg-ship-after-review", r.stderr)

    def test_missing_manifest_fails_closed(self):
        """Fail-closed: missing manifest → exit 2 with a 'fail-closed' message."""
        with _RepoFixture() as repo:
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            (repo / MANIFEST_REL).unlink()
            _git(repo, "commit", "-qam", "drop-manifest")
            r = _run(repo, "--check", "--base", base)
            self.assertEqual(r.returncode, 2)
            self.assertIn("fail-closed", r.stderr)

    def test_missing_base_ref_fails_closed(self):
        """Fail-closed: unresolvable base ref → exit 2, named."""
        with _RepoFixture() as repo:
            r = _run(repo, "--check", "--base", "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
            self.assertEqual(r.returncode, 2)
            self.assertIn("cannot resolve base", r.stderr)

    def test_wrong_schema_fails_closed(self):
        """Fail-closed: manifest schema mismatch → exit 2 (schema is validated on read)."""
        with _RepoFixture() as repo:
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            man = repo / MANIFEST_REL
            # Corrupt the schema header line (drop the `schema N` marker).
            body = "\n".join(
                ln for ln in man.read_text().splitlines()
                if "schema" not in ln
            )
            man.write_text(body + "\n")
            _git(repo, "commit", "-qam", "bad-schema")
            r = _run(repo, "--check", "--base", base)
            self.assertEqual(r.returncode, 2)
            self.assertIn("schema", r.stderr)

    def test_cross_sidecar_duplicate_id_fails_closed(self):
        """F1: a same-id decoy in a 2nd sidecar (masking a weakening of the real,
        runtime-loaded core body) is fail-closed, not silently last-file-wins."""
        with _RepoFixture() as repo:
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            # Weaken the real core body AND add a same-id strong decoy in rest.
            (repo / "AGENTS.core.md").write_text(
                CORE.replace("Mandatory on every write.", "Advisory only.")
            )
            (repo / "AGENTS.rest.md").write_text(
                REST
                + "- Always gate regulated data [id: hr-gdpr-example] [hook-enforced: some-hook.sh]. Mandatory on every write.\n"
            )
            # --write would also fail-closed; regenerate under the honest (base) tree first.
            _git(repo, "commit", "-qam", "dup-id-decoy")
            r = _run(repo, "--check", "--base", base)
            self.assertEqual(r.returncode, 2)
            self.assertIn("hr-gdpr-example", r.stderr)
            self.assertIn("duplicate", r.stderr.lower())

    def test_ack_replay_blocks(self):
        """F2: reverting a body to a PREVIOUSLY-acked form (ack already present at
        base) is BLOCKED — the ack must be newly added in THIS diff."""
        with _RepoFixture() as repo:
            # weak form + its hash
            weak_line = "- Never do the dangerous thing [id: hr-never-dangerous]. Optional maybe."
            weak_hash = _hash_body(weak_line)
            # Seed the baseline ack file with a historical ack for the weak hash,
            # while the body itself is STRONG. base := this commit.
            _append_ack(
                repo, f"hr-never-dangerous|{weak_hash}|2026-01-01|#1|prior weakening"
            )
            _git(repo, "commit", "-qam", "seed-historical-ack")
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            # Head reverts the body to the weak form; NO new ack added.
            core_weak = CORE.replace(
                "- Never do the dangerous thing [id: hr-never-dangerous]. Do the safe thing instead.",
                weak_line,
            )
            (repo / "AGENTS.core.md").write_text(core_weak)
            _regen_manifest(repo)
            _git(repo, "commit", "-qam", "replay-weak-no-new-ack")
            r = _run(repo, "--check", "--base", base)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("hr-never-dangerous", r.stderr)

    def test_short_ack_does_not_satisfy(self):
        """A reason-less / short ack (<5 fields) is not a valid ack → still BLOCK."""
        with _RepoFixture() as repo:
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            (repo / "AGENTS.core.md").write_text(
                CORE.replace("Do the safe thing instead.", "Optional: maybe.")
            )
            _regen_manifest(repo)
            new_hash = _body_hash(repo, "hr-never-dangerous")
            _append_ack(repo, f"hr-never-dangerous|{new_hash}")  # 2 fields only
            _git(repo, "commit", "-qam", "short-ack")
            r = _run(repo, "--check", "--base", base)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("hr-never-dangerous", r.stderr)

    def test_tagged_deletion_emits_mandatory_review(self):
        """A security-tagged body DELETION emits the louder annotation (id named)."""
        with _RepoFixture() as repo:
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            # Delete the [hook-enforced] hr-gdpr-example body line.
            lines = [ln for ln in CORE.splitlines() if "hr-gdpr-example" not in ln]
            (repo / "AGENTS.core.md").write_text("\n".join(lines) + "\n")
            _regen_manifest(repo)
            _git(repo, "commit", "-qam", "delete-tagged")
            r = _run(repo, "--check", "--base", base)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("hr-gdpr-example", r.stderr)
            self.assertIn("mandatory-human-review", (r.stdout + r.stderr).lower())

    def test_sections_oracle_narrowing_does_not_hide_weakening(self):
        """SECTIONS-oracle: narrowing `SECTIONS` in _agents_md_sections.py while
        weakening a body in the same diff must still BLOCK (base∪head sections)."""
        sections_full = (
            'SECTIONS = frozenset({\n'
            '    "Hard Rules",\n'
            '    "Workflow Gates",\n'
            '    "Code Quality",\n'
            '})\n'
        )
        sections_narrowed = (
            'SECTIONS = frozenset({\n'
            '    "Workflow Gates",\n'
            '    "Code Quality",\n'
            '})\n'
        )
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            _git(repo, "init", "-q", "-b", "main")
            _git(repo, "config", "user.email", "t@t")
            _git(repo, "config", "user.name", "t")
            (repo / "AGENTS.core.md").write_text(CORE)
            (repo / "AGENTS.docs.md").write_text(DOCS)
            (repo / "AGENTS.rest.md").write_text(REST)
            (repo / "scripts").mkdir()
            (repo / "scripts" / "_agents_md_sections.py").write_text(sections_full)
            (repo / ".claude").mkdir()
            (repo / ".claude" / "rule-weakening-acks.txt").write_text("# acks\n")
            assert _run(repo, "--write").returncode == 0
            _git(repo, "add", "-A")
            _git(repo, "commit", "-qm", "baseline")
            base = _git(repo, "rev-parse", "HEAD").stdout.strip()
            # Attack: narrow SECTIONS (drop "Hard Rules") AND weaken a hard rule.
            (repo / "scripts" / "_agents_md_sections.py").write_text(sections_narrowed)
            (repo / "AGENTS.core.md").write_text(
                CORE.replace("Do the safe thing instead.", "Optional: maybe.")
            )
            _regen_manifest(repo)
            _git(repo, "commit", "-qam", "narrow-sections+weaken")
            r = _run(repo, "--check", "--base", base)
            self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn("hr-never-dangerous", r.stderr)


class TestExtractSections(unittest.TestCase):
    def test_extracts_names(self):
        import importlib.util

        spec = importlib.util.spec_from_file_location("_lrb", SCRIPT)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        got = mod.extract_sections(
            'SECTIONS = frozenset({\n    "Hard Rules",\n    "Workflow Gates",\n})\n'
        )
        self.assertEqual(got, {"Hard Rules", "Workflow Gates"})
        self.assertEqual(mod.extract_sections("no frozenset here"), set())


if __name__ == "__main__":
    unittest.main()
