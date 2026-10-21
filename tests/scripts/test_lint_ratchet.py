#!/usr/bin/env python3
"""Tests for plugins/soleur/scripts/lint-ratchet.py (PR3a and PR3b of #10331).

The script's filename is hyphenated, so it is loaded with importlib. The tool JSON under
tests/scripts/fixtures/lint-ratchet/ is the REAL output of the pinned ruff and eslint on the
synthetic ``sample.*.txt`` snippets next to it, with the scan root replaced by ``/__ROOT__``;
nothing here is hand-written from the author's model of those tools.

Violating sample sources are built at runtime in temp directories and never committed as ``.py``
files: ruff scans ``tests/**``, so a committed violation would itself become a baseline entry.
"""

from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import io
import json
import os
import platform
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

try:
    import tomllib
except ModuleNotFoundError:  # Python < 3.11: the ruff.toml pin class below is skipped
    tomllib = None

from tests.scripts._git_fixture_env import git_fixture_env

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "plugins" / "soleur" / "scripts" / "lint-ratchet.py"
REQUIREMENTS = REPO_ROOT / "plugins" / "soleur" / "scripts" / "ruff-requirements.txt"
FIXTURES = REPO_ROOT / "tests" / "scripts" / "fixtures" / "lint-ratchet"
MIN_CASES = 319
# Per-class lower bounds (the count when they were set): renaming or deleting a test of a guard class turns this
# red instead of leaving the total above MIN_CASES. Lowering one is a deliberate, reviewed act.
CLASS_FLOORS = {
    "TestAdapters": 9,
    "TestCarryIns": 2,
    "TestCheckVerdicts": 14,
    "TestConfigPins": 7,
    "TestDiscoverabilityProbe": 1,
    "TestEnsureRuff": 27,
    "TestEntries": 20,
    "TestEslintConfigBehaviour": 1,
    "TestFloors": 3,
    "TestGrowthArithmetic": 4,
    "TestHelpers": 8,
    "TestMain": 12,
    "TestMergeBaseDelta": 22,
    "TestPipArgvAndRequirements": 5,
    "TestRegistration": 6,
    "TestRunEslint": 7,
    "TestRunRuff": 13,
    "TestScopePins": 2,
    "TestSkillPointers": 4,
    "TestSoleurOutputIsUnchanged": 1,
    "TestToolFailures": 4,
    "TestUserModeFingerprint": 8,
    "TestUserModeFixRound": 35,
    "TestUserModeGuards": 34,
    "TestUserModeReviewFixes": 27,
    "TestUserModeSafety": 10,
    "TestUserModeStates": 18,
    "TestUserModeTotality": 5,
    "TestUserModeUpdateAndLadder": 5,
    "TestUserModeWaiversAndSoleurIsolation": 2,
}

# The synthetic sample and the rule rows its captured report holds (row numbers are 1-based).
SAMPLE_PY = (FIXTURES / "sample.py.txt").read_text()
EXPECTED_RUFF_ROWS = {("F401", 1), ("SIM115", 5), ("S110", 8), ("F841", 10)}

# sha256 of apps/web-platform/eslint.test-dirs.config.mjs. Weakening a rule or an ignore pattern
# there is a legal shrink of the baseline, so the file is pinned: changing it is a two-file edit.
# Re-pin with: sha256sum apps/web-platform/eslint.test-dirs.config.mjs
ESLINT_CONFIG_SHA256 = "b8b6f9db65badaa7e3900b97af6ef01055cfeee74275bf3b27e8a96af0b89b64"


def load_module():
    spec = importlib.util.spec_from_file_location("lint_ratchet", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules["lint_ratchet"] = module
    spec.loader.exec_module(module)
    return module


lr = load_module()

VIOLATION = "    handle = open(path)\n"  # a SIM115 finding when ruff sees it


def completed(argv, rc, out="", err=""):
    return subprocess.CompletedProcess(argv, rc, out, err)


class Repo:
    """A throwaway git repository whose files tests write by hand."""

    def __init__(self, test: unittest.TestCase):
        tmp = tempfile.TemporaryDirectory()
        test.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name).resolve()
        self.env = git_fixture_env(self.root)
        self.git("init", "-q", "-b", "main")

    def git(self, *args: str, check: bool = True) -> subprocess.CompletedProcess:
        cmd = [
            "git", "-C", str(self.root),
            "-c", "user.name=fixture", "-c", "user.email=fixture@example.com",
            "-c", "commit.gpgsign=false", *args,
        ]
        return subprocess.run(cmd, env=self.env, check=check, capture_output=True, text=True)

    def write(self, rel: str, text: str) -> None:
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def commit(self, message: str = "c") -> str:
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD").stdout.strip()


def make_config(findings_by_path, floor=0, file_count=None, baseline="base.txt", script=None):
    """A scope config whose tool is a function of the repo's files.

    ``findings_by_path`` maps a relative path to a list of (rule, needle) pairs: a finding is
    produced for every line of that file containing ``needle``.
    """

    def run(root):
        out = []
        for rel, specs in findings_by_path.items():
            path = Path(root) / rel
            if not path.exists():
                continue
            for row, line in enumerate(path.read_text().splitlines(), start=1):
                for rule, needle in specs:
                    if needle in line:
                        out.append(lr.Finding(rel, rule, row, f"{rule} message"))
        count = file_count if file_count is not None else len(findings_by_path)
        return out, count

    return {
        "name": "fixture",
        "baseline": baseline,
        "floor": floor,
        "run": run,
        "remedy": "REMEDY-TEXT",
        "script": script,
    }


class ScrubbedEnv(unittest.TestCase):
    """Every case starts without CI flags, pip config, a developer cache or a developer ruff."""

    def setUp(self):
        saved = dict(os.environ)
        self.addCleanup(self._restore, saved)
        for key in list(os.environ):
            if key in {"CI", "XDG_CACHE_HOME"} or key.startswith(("PIP_", "PYTHON")):
                del os.environ[key]
        self.fake_home = tempfile.TemporaryDirectory()
        self.addCleanup(self.fake_home.cleanup)
        os.environ["HOME"] = self.fake_home.name

    @staticmethod
    def _restore(saved):
        os.environ.clear()
        os.environ.update(saved)


class TestEntries(ScrubbedEnv):
    def test_normalise_collapses_whitespace_runs(self):
        self.assertEqual(lr.normalise("  a \t b\n"), "a b")

    def test_anchor_ignores_indentation_and_trailing_space(self):
        self.assertEqual(lr.anchor_of("    handle = open(path)  "), lr.anchor_of("handle = open(path)"))

    def test_anchor_is_twelve_hex_and_text_sensitive(self):
        a, b = lr.anchor_of("x = 1"), lr.anchor_of("x = 2")
        self.assertRegex(a, r"^[0-9a-f]{12}$")
        self.assertNotEqual(a, b)

    def test_format_entry_shape(self):
        self.assertEqual(lr.format_entry("a/b.py", "SIM115", "0123456789ab", 2), "a/b.py|SIM115|0123456789ab|2")

    def test_parse_baseline_ignores_blank_and_comment_lines_in_any_order(self):
        text = "# header\n\nb.py|S110|aaaaaaaaaaaa|1\n   \n# note\na.py|F401|bbbbbbbbbbbb|1\n"
        self.assertEqual(
            sorted(lr.parse_baseline(text)),
            [("a.py", "F401", "bbbbbbbbbbbb", 1), ("b.py", "S110", "aaaaaaaaaaaa", 1)],
        )

    def test_parse_baseline_rejects_a_malformed_line(self):
        with self.assertRaises(lr.InfraError):
            lr.parse_baseline("not-an-entry\n")

    def test_parse_baseline_rejects_a_duplicate_line(self):
        with self.assertRaises(lr.InfraError) as ctx:
            lr.parse_baseline("a.py|F401|bbbbbbbbbbbb|1\na.py|F401|bbbbbbbbbbbb|1\n")
        self.assertIn("duplicates", str(ctx.exception))

    def test_parse_baseline_names_the_recovery_for_a_conflict_marker(self):
        with self.assertRaises(lr.InfraError) as ctx:
            lr.parse_baseline("<<<<<<< HEAD\na.py|F401|bbbbbbbbbbbb|1\n")
        self.assertIn("take the base branch's copy", str(ctx.exception))

    def test_census_counts_identical_lines_by_ordinal(self):
        repo = Repo(self)
        repo.write("a.py", "x\n" + VIOLATION + VIOLATION)
        findings = [lr.Finding("a.py", "SIM115", 2, "m"), lr.Finding("a.py", "SIM115", 3, "m")]
        entries = lr.census(findings, repo.root)
        self.assertEqual([e[3] for e in entries], [1, 2])
        self.assertEqual(entries[0][2], entries[1][2])

    def test_census_identity_survives_a_line_move(self):
        repo = Repo(self)
        repo.write("a.py", VIOLATION)
        before = lr.census([lr.Finding("a.py", "SIM115", 1, "m")], repo.root)
        repo.write("a.py", "\n\n\n" + VIOLATION)
        after = lr.census([lr.Finding("a.py", "SIM115", 4, "m")], repo.root)
        self.assertEqual(before, after)

    def test_census_row_past_end_of_file_hashes_the_empty_string(self):
        repo = Repo(self)
        repo.write("a.py", "x\n")
        entries = lr.census([lr.Finding("a.py", "F401", 99, "m")], repo.root)
        self.assertEqual(entries[0][2], lr.anchor_of(""))

    def test_census_numbers_rows_the_way_the_tools_do(self):
        # Python's str.splitlines() also breaks on \x0c, which neither ruff nor eslint counts.
        repo = Repo(self)
        repo.write("a.py", "a\n\x0cb\nc = open(x)\n")
        entries = lr.census([lr.Finding("a.py", "SIM115", 3, "m")], repo.root)
        self.assertEqual(entries[0][2], lr.anchor_of("c = open(x)"))

    def test_census_hashes_a_last_line_that_has_no_trailing_newline(self):
        repo = Repo(self)
        repo.write("a.py", "x = 1\ny = open(p)")
        entries = lr.census([lr.Finding("a.py", "SIM115", 2, "m")], repo.root)
        self.assertEqual(entries[0][2], lr.anchor_of("y = open(p)"))

    def test_census_counts_a_lone_carriage_return_as_a_line_break(self):
        repo = Repo(self)
        repo.write("a.py", "a\rb\rc = open(x)\r")
        entries = lr.census([lr.Finding("a.py", "SIM115", 3, "m")], repo.root)
        self.assertEqual(entries[0][2], lr.anchor_of("c = open(x)"))

    def test_census_rejects_a_pipe_or_newline_in_a_path(self):
        repo = Repo(self)
        for bad in ("a|b.py", "a\nb.py"):
            with self.assertRaises(lr.InfraError):
                lr.census([lr.Finding(bad, "F401", 1, "m")], repo.root)

    def test_census_skips_a_tracked_symlink(self):
        repo = Repo(self)
        repo.write("real.py", VIOLATION)
        (repo.root / "link.py").symlink_to("real.py")
        entries = lr.census(
            [lr.Finding("link.py", "SIM115", 1, "m"), lr.Finding("real.py", "SIM115", 1, "m")], repo.root
        )
        self.assertEqual([e[0] for e in entries], ["real.py"])

    def test_census_output_is_sorted(self):
        repo = Repo(self)
        repo.write("b.py", "x\n")
        repo.write("a.py", "x\n")
        entries = lr.census([lr.Finding("b.py", "F401", 1, "m"), lr.Finding("a.py", "F401", 1, "m")], repo.root)
        self.assertEqual(entries, sorted(entries))

    def test_rendered_header_never_names_a_rule_code(self):
        text = lr.render_baseline("ruff", [])
        for code in ("SIM115", "S110", "S112", "F401", "F841", "no-unused-vars"):
            self.assertNotIn(code, text)

    def test_rendered_header_documents_the_recovery_path(self):
        text = lr.render_baseline("ruff", [])
        self.assertIn("--update", text)
        self.assertIn("--list", text)
        self.assertIn("conflict", text)

    def test_baseline_entries_contain_no_source_text(self):
        repo = Repo(self)
        repo.write("a.py", "secret_token = 'hunter2'\n")
        entries = lr.census([lr.Finding("a.py", "F841", 1, "message with hunter2")], repo.root)
        body = "\n".join(lr.format_entry(*e) for e in entries)
        self.assertNotIn("hunter2", body)
        for line in body.splitlines():
            self.assertRegex(line, r"^[^|]+\|[@A-Za-z0-9/_.-]+\|[0-9a-f]{12}\|[0-9]+$")


class TestHelpers(ScrubbedEnv):
    def test_is_ci_reads_the_value_not_just_its_presence(self):
        for value, expected in (("true", True), ("1", True), ("yes", True), ("false", False), ("0", False),
                                ("", False), ("No", False)):
            with self.subTest(value=value):
                self.assertIs(lr._is_ci({"CI": value}), expected)
        self.assertIs(lr._is_ci({}), False)

    def test_relative_accepts_a_dot_dot_prefixed_name_and_refuses_an_escape(self):
        self.assertEqual(lr._relative("/r/..foo.py", "/r"), "..foo.py")
        with self.assertRaises(lr.InfraError):
            lr._relative("/elsewhere/x.py", "/r")
        with self.assertRaises(lr.InfraError):
            lr._relative("/r/../x.py", "/r")

    def test_relative_joins_a_relative_name_to_the_root(self):
        self.assertEqual(lr._relative("a/b.py", "/r"), "a/b.py")

    def test_clean_strips_terminal_control_characters(self):
        self.assertEqual(lr._clean("a\x1b[31mred\x07\nb\u2028c"), "a [31mred  b c")

    def test_exec_maps_a_timeout_and_a_spawn_failure_to_infrastructure(self):
        def slow(argv, **kwargs):
            raise subprocess.TimeoutExpired(argv, kwargs["timeout"])

        def missing(argv, **kwargs):
            raise FileNotFoundError("no such tool")

        with self.assertRaises(lr.InfraError) as ctx:
            lr._exec(slow, ["tool"], 5)
        self.assertIn("timed out", str(ctx.exception))
        with self.assertRaises(lr.InfraError) as ctx:
            lr._exec(missing, ["tool"], 5)
        self.assertIn("could not run", str(ctx.exception))

    def test_clean_strips_every_invisible_character_class(self):
        for cp in (0x00AD, 0x061C, 0x180E, 0x2060, 0x2061, 0x206A, 0x206F):
            with self.subTest(codepoint=hex(cp)):
                self.assertEqual(lr._clean("a" + chr(cp) + "b"), "a b")

    def test_clean_strips_bidi_and_zero_width_characters(self):
        text = "a" + chr(0x202E) + "b" + chr(0x200B) + "c" + chr(0xFEFF) + "d" + chr(0x2066) + "e"
        self.assertEqual(lr._clean(text), "a b c d e")

    def test_exec_always_bounds_and_decodes_utf8(self):
        seen = {}

        def spy(argv, **kwargs):
            seen.update(kwargs)
            return completed(argv, 0)

        lr._exec(spy, ["tool"], 7)
        self.assertEqual(seen["timeout"], 7)
        self.assertEqual(seen["encoding"], "utf-8")
        self.assertTrue(seen["capture_output"])


class TestAdapters(ScrubbedEnv):
    def _fixture_root(self):
        repo = Repo(self)
        repo.write("sample.py", SAMPLE_PY)
        repo.write("test/sample.ts", (FIXTURES / "sample.ts.txt").read_text())
        repo.write("test/sample.mjs", (FIXTURES / "sample.mjs.txt").read_text())
        return repo

    def _report(self, name, root):
        return (FIXTURES / name).read_text().replace("/__ROOT__", str(root))

    def test_ruff_adapter_reads_the_captured_report_and_keeps_the_message(self):
        repo = self._fixture_root()
        findings = lr.adapt_ruff(self._report("ruff-report.json", repo.root), repo.root)
        self.assertEqual({(f.rule, f.row) for f in findings}, EXPECTED_RUFF_ROWS)
        self.assertTrue(all(f.path == "sample.py" and f.message for f in findings))

    def test_ruff_adapter_rejects_garbage_and_non_lists(self):
        with self.assertRaises(lr.InfraError):
            lr.adapt_ruff("not json", Path("/x"))
        with self.assertRaises(lr.InfraError):
            lr.adapt_ruff('{"a": 1}', Path("/x"))

    def test_ruff_adapter_accepts_a_clean_empty_report(self):
        self.assertEqual(lr.adapt_ruff("[]", Path("/x")), [])

    def test_ruff_adapter_treats_a_null_code_as_a_file_that_did_not_parse(self):
        report = json.dumps([{"filename": "/r/a.py", "code": None, "location": {"row": 1}, "message": "syntax"}])
        with self.assertRaises(lr.InfraError):
            lr.adapt_ruff(report, Path("/r"))

    def test_ruff_adapter_maps_a_malformed_item_to_infrastructure(self):
        for item in ({"code": "F401"}, {"filename": "/r/a.py", "code": "F401"}, "not-a-dict",
                     {"filename": "/r/a.py", "code": "F401", "location": None}):
            with self.subTest(item=item), self.assertRaises(lr.InfraError):
                lr.adapt_ruff(json.dumps([item]), Path("/r"))

    def test_eslint_adapter_reads_the_captured_report(self):
        repo = self._fixture_root()
        findings, file_count = lr.adapt_eslint(self._report("eslint-report.json", repo.root), repo.root)
        self.assertEqual(file_count, 2)
        self.assertEqual(
            {(f.path, f.rule, f.row) for f in findings},
            {
                ("test/sample.mjs", "no-unused-vars", 1),
                ("test/sample.ts", "@typescript-eslint/no-unused-vars", 1),
                ("test/sample.ts", "@typescript-eslint/no-unused-vars", 3),
            },
        )

    def test_eslint_adapter_filters_untracked_files_from_findings_and_count_alike(self):
        repo = self._fixture_root()
        seen = set()
        findings, file_count = lr.adapt_eslint(
            self._report("eslint-report.json", repo.root), repo.root, tracked={"test/sample.ts"}, seen=seen)
        self.assertEqual(file_count, 1)
        self.assertEqual(seen, {"test/sample.ts"})
        self.assertTrue(all(f.path == "test/sample.ts" for f in findings))

    def test_eslint_adapter_treats_a_fatal_parse_error_as_infrastructure(self):
        for report in (
            [{"filePath": "/r/a.ts", "fatalErrorCount": 1, "messages": [{"ruleId": None, "line": 1}]}],
            [{"filePath": "/r/a.ts", "messages": [{"ruleId": None, "fatal": True, "line": 1, "message": "x"}]}],
        ):
            with self.subTest(report=report), self.assertRaises(lr.InfraError):
                lr.adapt_eslint(json.dumps(report), Path("/r"))

    def test_eslint_adapter_rejects_garbage_and_malformed_items(self):
        with self.assertRaises(lr.InfraError):
            lr.adapt_eslint("{", Path("/r"))
        with self.assertRaises(lr.InfraError):
            lr.adapt_eslint(json.dumps([{"messages": []}]), Path("/r"))


class CheckBase(ScrubbedEnv):
    """A repository with one ruff-style file whose findings are the baseline."""

    def setUp(self):
        super().setUp()
        self.repo = Repo(self)
        self.repo.write("a.py", "import os\n" + VIOLATION)
        self.root_sha = self.repo.commit("root")
        self.repo.git("update-ref", "refs/remotes/origin/main", self.root_sha)
        self.specs = {"a.py": [("SIM115", "open(")]}
        self.config = make_config(self.specs, floor=0)

    def check(self, config=None, base=None, extra_env=None):
        env = dict(self.repo.env)
        env.update(extra_env or {})
        return lr.check(config or self.config, self.repo.root, base=base, env=env)

    def update(self, config=None, base=None):
        return lr.update(config or self.config, self.repo.root, base=base, env=dict(self.repo.env))

    def seed_baseline(self):
        code, _ = self.update()
        self.assertEqual(code, 0)
        return self.repo.commit("seed")

    def write_live_baseline(self, config=None):
        findings, _ = (config or self.config)["run"](self.repo.root)
        text = lr.render_baseline("fixture", lr.census(findings, self.repo.root))
        (self.repo.root / "base.txt").write_text(text)


class TestCheckVerdicts(CheckBase):
    def test_missing_baseline_is_infrastructure(self):
        code, lines = self.check()
        self.assertEqual(code, 2)
        self.assertIn("baseline", "\n".join(lines))

    def test_clean_tree_with_a_matching_baseline_passes(self):
        self.seed_baseline()
        code, _ = self.check()
        self.assertEqual(code, 0)

    def test_new_finding_fails_with_path_row_rule_message_and_remedy(self):
        self.seed_baseline()
        self.repo.write("a.py", "import os\n" + VIOLATION + "    other = open(path2)\n")
        code, lines = self.check()
        out = "\n".join(lines)
        self.assertEqual(code, 1)
        self.assertIn("a.py:3", out)
        self.assertIn("SIM115", out)
        self.assertIn("SIM115 message", out)
        self.assertIn("REMEDY-TEXT", out)
        self.assertIn("NOT honoured", out)
        self.assertIn("must not be used to admit a new finding", out)

    def test_empty_tool_output_makes_every_baseline_entry_stale(self):
        self.seed_baseline()
        self.repo.write("a.py", "import os\n")
        code, lines = self.check()
        out = "\n".join(lines)
        self.assertEqual(code, 1)
        self.assertIn("fixed: run", out)
        self.assertIn("--update", out)
        self.assertIn("conflict", out)

    def test_an_edited_baselined_line_is_not_reported_as_fixed(self):
        self.seed_baseline()
        self.repo.write("a.py", "import os\n    handle = open(path, 'w')\n")
        code, lines = self.check()
        out = "\n".join(lines)
        self.assertEqual(code, 1)
        self.assertIn("NEW a.py:2", out)
        self.assertIn("a line carrying this finding changed", out)
        self.assertNotIn("fixed: run", out)

    def test_duplicate_of_a_baselined_line_is_a_new_entry(self):
        self.seed_baseline()
        self.repo.write("a.py", "import os\n" + VIOLATION + VIOLATION)
        code, lines = self.check()
        self.assertEqual(code, 1)
        self.assertIn("a.py:3", "\n".join(lines))

    def test_line_move_is_not_a_change(self):
        self.seed_baseline()
        self.repo.write("a.py", "import os\n\n\n\n" + VIOLATION)
        code, _ = self.check()
        self.assertEqual(code, 0)

    def test_deleting_a_baseline_entry_whose_finding_is_live_fails(self):
        self.seed_baseline()
        (self.repo.root / "base.txt").write_text(lr.render_baseline("fixture", []))
        code, _ = self.check()
        self.assertEqual(code, 1)

    def test_in_place_edit_of_a_baselined_line_passes_after_update(self):
        self.seed_baseline()
        self.repo.write("a.py", "import os\n    handle = open(path, 'w')\n")
        code, _ = self.update()
        self.assertEqual(code, 0)
        code, _ = self.check()
        self.assertEqual(code, 0)

    def test_hand_written_baseline_with_shuffled_order_and_comments_passes(self):
        self.seed_baseline()
        entries = lr.parse_baseline((self.repo.root / "base.txt").read_text())
        shuffled = "# a\n\n" + "\n".join(lr.format_entry(*e) for e in reversed(entries)) + "\n# z\n"
        (self.repo.root / "base.txt").write_text(shuffled)
        code, _ = self.check()
        self.assertEqual(code, 0)

    def test_a_duplicated_baseline_line_is_infrastructure(self):
        self.seed_baseline()
        text = (self.repo.root / "base.txt").read_text()
        entry = [ln for ln in text.splitlines() if ln and not ln.startswith("#")][0]
        (self.repo.root / "base.txt").write_text(text + entry + "\n")
        code, lines = self.check()
        self.assertEqual(code, 2)
        self.assertIn("duplicates", "\n".join(lines))

    def test_two_pr_duplicate_delete_leaves_a_stale_entry(self):
        # Two identical lines baselined as n=1 and n=2; after both are fixed the baseline still
        # holds n=1, which the stale message tells the contributor to regenerate.
        self.repo.write("a.py", VIOLATION + VIOLATION)
        self.seed_baseline()
        (self.repo.root / "a.py").write_text("x = 1\n")
        code, lines = self.check()
        self.assertEqual(code, 1)
        self.assertIn("fixed: run", "\n".join(lines))

    def test_a_symlinked_baseline_is_refused_for_check_and_update(self):
        self.seed_baseline()
        real = self.repo.root / "real-base.txt"
        (self.repo.root / "base.txt").rename(real)
        (self.repo.root / "base.txt").symlink_to("real-base.txt")
        for verb in (self.check, self.update):
            with self.subTest(verb=verb.__name__):
                code, lines = verb()
                self.assertEqual(code, 2)
                self.assertIn("symlink", "\n".join(lines))

    def test_a_dangling_baseline_symlink_is_never_written_through(self):
        (self.repo.root / "base.txt").symlink_to("elsewhere.txt")
        code, _ = self.update()
        self.assertEqual(code, 2)
        self.assertFalse((self.repo.root / "elsewhere.txt").exists())
        code, _ = self.check()
        self.assertEqual(code, 2)


class TestFloors(CheckBase):
    def test_floor_boundaries_for_both_scopes(self):
        for name, expected_floor in (("ruff", 55), ("eslint-test-dirs", 105)):
            floor = lr.SCOPES[name]["floor"]
            self.assertEqual(floor, expected_floor)
            for count, expected in ((floor - 1, 1), (floor, 0)):
                with self.subTest(scope=name, count=count):
                    cfg = make_config(self.specs, floor=floor, file_count=count)
                    (self.repo.root / "base.txt").unlink(missing_ok=True)
                    code, _ = self.update(cfg)
                    if count < floor:
                        self.assertEqual(code, 1, "update must apply the floor too")
                        self.write_live_baseline(cfg)
                    code, _ = self.check(cfg)
                    self.assertEqual(code, expected)

    def test_an_empty_scan_never_reports_green(self):
        cfg = make_config({}, floor=1, file_count=0)
        (self.repo.root / "base.txt").write_text(lr.render_baseline("fixture", []))
        code, lines = self.check(cfg)
        self.assertEqual(code, 1)
        self.assertIn("scan", "\n".join(lines))

    def test_update_refuses_to_write_a_baseline_from_a_scan_below_the_floor(self):
        cfg = make_config(self.specs, floor=5, file_count=1)
        code, lines = self.update(cfg)
        self.assertEqual(code, 1)
        self.assertIn("floor", "\n".join(lines))
        self.assertFalse((self.repo.root / "base.txt").exists())


class TestGrowthArithmetic(unittest.TestCase):
    def test_growth_inside_an_existing_path_and_rule_is_named_exactly(self):
        base = [("a.py", "SIM115", "aaaaaaaaaaaa", 1), ("a.py", "F401", "bbbbbbbbbbbb", 1)]
        head = base + [("a.py", "SIM115", "cccccccccccc", 1)]
        self.assertEqual(lr.growth(head, base), [("a.py", "SIM115", 2, 1)])

    def test_a_swap_inside_one_path_and_rule_is_not_growth(self):
        base = [("a.py", "SIM115", "aaaaaaaaaaaa", 1)]
        head = [("a.py", "SIM115", "cccccccccccc", 1)]
        self.assertEqual(lr.growth(head, base), [])

    def test_a_rename_carries_the_base_counts_to_the_new_path(self):
        base = [("a.py", "S110", "aaaaaaaaaaaa", 1)]
        head = [("b.py", "S110", "aaaaaaaaaaaa", 1)]
        self.assertEqual(lr.growth(head, base, {"a.py": "b.py"}), [])
        self.assertEqual(lr.growth(head, base, {}), [("b.py", "S110", 1, 0)])

    def test_shrinking_is_never_growth(self):
        base = [("a.py", "S110", "aaaaaaaaaaaa", 1), ("a.py", "S110", "aaaaaaaaaaaa", 2)]
        self.assertEqual(lr.growth([], base), [])


class TestMergeBaseDelta(CheckBase):
    def test_baseline_absent_at_the_base_is_introduced_by_this_diff(self):
        self.update()
        code, lines = self.check(base=self.root_sha)
        self.assertEqual(code, 0)
        out = "\n".join(lines)
        self.assertIn("introduced by this diff", out)
        self.assertIn("shrink-only comparison skipped", out.splitlines()[-1])

    def test_an_unreadable_listing_is_not_read_as_absent(self):
        self.update()
        with mock.patch.object(lr, "_git", return_value=completed([], 128, "", "fatal: bad object")):
            with self.assertRaises(lr.InfraError):
                lr.baseline_at(self.repo.root, self.root_sha, "base.txt", self.repo.env)

    def test_growth_in_a_new_path_and_rule_fails_naming_the_growth(self):
        base = self.seed_baseline()
        self.repo.write("b.py", VIOLATION)
        cfg = make_config({"a.py": [("SIM115", "open(")], "b.py": [("SIM115", "open(")]})
        code, _ = self.update(cfg, base=base)
        self.assertEqual(code, 1, "--update must refuse to admit growth")
        entries = lr.parse_baseline((self.repo.root / "base.txt").read_text())
        hand = entries + lr.census([lr.Finding("b.py", "SIM115", 1, "m")], self.repo.root)
        (self.repo.root / "base.txt").write_text(lr.render_baseline("fixture", sorted(hand)))
        code, lines = self.check(cfg, base=base)
        out = "\n".join(lines)
        self.assertEqual(code, 1)
        self.assertIn("grew", out)
        self.assertIn("b.py", out)

    def test_growth_committed_on_the_branch_is_caught_against_an_earlier_base(self):
        base = self.seed_baseline()
        self.repo.write("a.py", "import os\n" + VIOLATION + "    again = open(other)\n")
        self.write_live_baseline()
        self.repo.commit("grow inside an existing path and rule")
        code, lines = self.check(base=base)
        self.assertEqual(code, 1)
        self.assertIn("2 entries now, 1 at the merge base", "\n".join(lines))

    def test_growth_is_measured_against_the_merge_base_not_the_main_tip(self):
        base = self.seed_baseline()
        grown = "import os\n" + VIOLATION + "    again = open(other)\n"
        self.repo.git("checkout", "-q", "-b", "feature")
        self.repo.write("a.py", grown)
        self.write_live_baseline()
        self.repo.commit("feature grows the baseline")
        self.repo.git("checkout", "-q", "main")
        self.repo.write("a.py", grown)
        self.write_live_baseline()
        tip = self.repo.commit("main tip already allows two")
        self.repo.git("update-ref", "refs/remotes/origin/main", tip)
        self.repo.git("checkout", "-q", "feature")
        self.assertEqual(self.repo.git("merge-base", "origin/main", "HEAD").stdout.strip(), base)
        for ref in (None, base):
            with self.subTest(base=ref):
                code, lines = self.check(base=ref)
                self.assertEqual(code, 1)
                self.assertIn("grew", "\n".join(lines))

    def test_edit_swap_inside_one_path_and_rule_is_not_growth(self):
        base = self.seed_baseline()
        self.repo.write("a.py", "import os\n    handle = open(other_path)\n")
        code, _ = self.update(base=base)
        self.assertEqual(code, 0)
        code, _ = self.check(base=base)
        self.assertEqual(code, 0)

    def test_staged_rename_passes_before_commit_and_after(self):
        base = self.seed_baseline()
        self.repo.git("mv", "a.py", "renamed.py")
        cfg = make_config({"renamed.py": [("SIM115", "open(")]})
        code, _ = self.update(cfg, base=base)
        self.assertEqual(code, 0)
        code, _ = self.check(cfg, base=base)
        self.assertEqual(code, 0, "staged rename must pass at pre-commit time")
        self.repo.commit("rename")
        code, _ = self.check(cfg, base=base)
        self.assertEqual(code, 0)

    def test_rename_map_reads_every_rename_in_a_mixed_diff(self):
        repo = Repo(self)
        repo.write("a.py", "".join("a%d\n" % i for i in range(10)))
        repo.write("b.py", "".join("b%d\n" % i for i in range(5)))
        repo.write("c.py", "c\n")
        base = repo.commit("base")
        repo.git("mv", "a.py", "a2.py")
        repo.git("mv", "b.py", "b2.py")
        repo.write("a2.py", "".join("a%d\n" % i for i in range(9)) + "changed\n")
        repo.write("c.py", "c changed\n")
        repo.write("d.py", "new\n")
        repo.git("add", "-A")
        self.assertEqual(lr.rename_map(repo.root, base, env=repo.env), {"a.py": "a2.py", "b.py": "b2.py"})

    def test_copy_to_a_new_path_is_growth(self):
        base = self.seed_baseline()
        self.repo.write("copy.py", "import os\n" + VIOLATION)
        cfg = make_config({"a.py": [("SIM115", "open(")], "copy.py": [("SIM115", "open(")]})
        entries = lr.parse_baseline((self.repo.root / "base.txt").read_text())
        hand = entries + lr.census([lr.Finding("copy.py", "SIM115", 2, "m")], self.repo.root)
        (self.repo.root / "base.txt").write_text(lr.render_baseline("fixture", sorted(hand)))
        code, lines = self.check(cfg, base=base)
        self.assertEqual(code, 1)
        self.assertIn("grew", "\n".join(lines))

    def test_update_that_shrinks_by_one_passes_and_removes_exactly_one_entry(self):
        self.repo.write("a.py", VIOLATION + "    again = open(p2)\n")
        base = self.seed_baseline()
        before = lr.parse_baseline((self.repo.root / "base.txt").read_text())
        self.repo.write("a.py", VIOLATION)
        code, _ = self.update(base=base)
        self.assertEqual(code, 0)
        after = lr.parse_baseline((self.repo.root / "base.txt").read_text())
        self.assertEqual(len(before) - len(after), 1)
        code, _ = self.check(base=base)
        self.assertEqual(code, 0)

    def test_hostile_base_refs_exit_2_and_never_reach_git_as_an_option(self):
        self.seed_baseline()
        for ref in ("-x", "--output=/tmp/pwned"):
            for verb in (self.check, self.update):
                with self.subTest(ref=ref, verb=verb.__name__):
                    code, _ = verb(base=ref)
                    self.assertEqual(code, 2)

    def test_unresolvable_base_warns_locally_and_exits_2_under_ci(self):
        self.seed_baseline()
        code, lines = self.check(base="no-such-ref-anywhere")
        self.assertEqual(code, 0)
        out = "\n".join(lines)
        self.assertIn("warning", out.lower())
        self.assertIn("shrink-only comparison skipped", out.splitlines()[-1])
        code, _ = self.check(base="no-such-ref-anywhere", extra_env={"CI": "true"})
        self.assertEqual(code, 2)
        code, _ = self.check(base="no-such-ref-anywhere", extra_env={"CI": "false"})
        self.assertEqual(code, 0, "CI=false is not CI")

    def test_update_with_an_existing_baseline_and_no_resolvable_base_is_refused(self):
        self.seed_baseline()
        code, lines = self.update(base="no-such-ref-anywhere")
        self.assertEqual(code, 2)
        self.assertIn("--base", "\n".join(lines))
        code, _ = self.update(base="HEAD")
        self.assertEqual(code, 0, "--base HEAD takes the committed baseline as the reference")

    def test_under_ci_a_baseline_missing_where_the_script_defines_the_scope_is_infrastructure(self):
        self.repo.write("tools/ratchet.py", 'SCOPES = {"fixture": {}}\n')
        base = self.repo.commit("the scope landed without a baseline")
        self.update()
        cfg = dict(self.config, script="tools/ratchet.py")
        code, lines = self.check(cfg, base=base, extra_env={"CI": "true"})
        self.assertEqual(code, 2)
        self.assertIn("missing at the merge base", "\n".join(lines))
        code, _ = self.check(cfg, base=base)
        self.assertEqual(code, 0, "locally the comparison is skipped as before")
        code, _ = self.check(base=base, extra_env={"CI": "true"})
        self.assertEqual(code, 0, "no script at the base: this PR introduces both")

    def test_a_comment_naming_the_scope_does_not_count_as_defining_it(self):
        self.repo.write("tools/ratchet.py", '# the "fixture" scope is planned\nSCOPES = {"other": {}}\n')
        base = self.repo.commit("only a comment mentions it")
        self.update()
        cfg = dict(self.config, script="tools/ratchet.py")
        code, _ = self.check(cfg, base=base, extra_env={"CI": "true"})
        self.assertEqual(code, 0)

    def test_a_new_scope_added_to_an_existing_script_is_admitted_under_ci(self):
        self.repo.write("tools/ratchet.py", 'SCOPES = {"other": {}}\n')
        base = self.repo.commit("a different scope exists")
        self.update()
        cfg = dict(self.config, script="tools/ratchet.py")
        code, lines = self.check(cfg, base=base, extra_env={"CI": "true"})
        self.assertEqual(code, 0)
        self.assertIn("introduced by this diff", "\n".join(lines))

    def test_a_rename_at_forty_percent_similarity_is_followed(self):
        repo = Repo(self)
        old = "".join("line-number-%02d-payload\n" % i for i in range(10))
        repo.write("a.py", old)
        base = repo.commit("base")
        repo.git("mv", "a.py", "b.py")
        repo.write("b.py", "".join(old.splitlines(True)[:4]) + "".join("different-text-%02d-xxxxxxx\n" % i
                                                                         for i in range(6)))
        repo.git("add", "-A")
        self.assertEqual(lr.rename_map(repo.root, base, env=repo.env), {"a.py": "b.py"})

    def test_a_baseline_under_a_symlinked_directory_is_refused(self):
        (self.repo.root / "real").mkdir()
        (self.repo.root / "sub").symlink_to("real")
        cfg = make_config(self.specs, baseline="sub/base.txt")
        for verb in (self.check, self.update):
            with self.subTest(verb=verb.__name__):
                code, lines = verb(cfg)
                self.assertEqual(code, 2)
                self.assertIn("symlink", "\n".join(lines))
        self.assertEqual(list((self.repo.root / "real").iterdir()), [])

    def test_the_baseline_is_written_world_readable_and_names_the_configured_recovery(self):
        previous = os.umask(0o022)
        self.addCleanup(os.umask, previous)
        self.update(dict(self.config, recovery_cmd="RECOVER-CMD"))
        path = self.repo.root / "base.txt"
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o644)
        self.assertIn("RECOVER-CMD --update", path.read_text())

    def test_the_baseline_mode_follows_the_umask_rather_than_a_fixed_world_readable_mode(self):
        previous = os.umask(0o077)
        self.addCleanup(os.umask, previous)
        self.update()
        self.assertEqual(stat.S_IMODE((self.repo.root / "base.txt").stat().st_mode), 0o600)

    def test_default_base_is_the_merge_base_with_origin_main(self):
        self.update()
        code, lines = self.check()
        self.assertEqual(code, 0)
        self.assertIn("introduced by this diff", "\n".join(lines))

    def test_update_writes_a_sorted_file_and_is_idempotent(self):
        self.repo.write("b.py", VIOLATION)
        self.specs["b.py"] = [("SIM115", "open(")]
        self.update()
        first = (self.repo.root / "base.txt").read_text()
        self.update()
        self.assertEqual(first, (self.repo.root / "base.txt").read_text())
        body = [ln for ln in first.splitlines() if ln and not ln.startswith("#")]
        self.assertEqual(body, sorted(body))
        self.assertEqual([p.name for p in self.repo.root.iterdir() if ".tmp-" in p.name], [])


class TestToolFailures(CheckBase):
    def test_tool_failure_is_infrastructure(self):
        self.seed_baseline()

        def boom(root):
            raise lr.InfraError("ruff crashed")

        code, lines = self.check(dict(self.config, run=boom))
        self.assertEqual(code, 2)
        self.assertIn("ruff crashed", "\n".join(lines))

    def test_vacuous_scan_exits_1_not_2(self):
        self.seed_baseline()

        def nothing(root):
            raise lr.Vacuous("nothing to scan")

        code, lines = self.check(dict(self.config, run=nothing))
        self.assertEqual(code, 1)
        self.assertIn("vacuous", "\n".join(lines))

    def test_zero_finding_clean_run_passes_with_an_empty_baseline(self):
        (self.repo.root / "a.py").write_text("x = 1\n")
        self.update()
        code, _ = self.check()
        self.assertEqual(code, 0)

    def test_list_prints_the_live_findings_sorted(self):
        code, lines = lr.list_live(self.config, self.repo.root)
        self.assertEqual(code, 0)
        self.assertEqual(lines, ["a.py:2 SIM115 SIM115 message"])


class TestRunRuff(ScrubbedEnv):
    def setUp(self):
        super().setUp()
        self.repo = Repo(self)
        self.repo.write("sample.py", SAMPLE_PY)
        self.repo.git("add", "sample.py")
        self.exe = Path("/x/ruff")

    def rooted(self, name):
        return (FIXTURES / name).read_text().replace("/__ROOT__", str(self.repo.root))

    def stub(self, show=None, report=None, rc=1, stderr="", show_rc=0):
        calls = []

        def run(argv, **kwargs):
            calls.append((list(argv), kwargs))
            if "--show-files" in argv:
                return completed(argv, show_rc, self.rooted("ruff-show-files.txt") if show is None else show, "")
            return completed(argv, rc, self.rooted("ruff-report.json") if report is None else report, stderr)

        return run, calls

    def run_ruff(self, run):
        return lr.run_ruff(self.repo.root, env=dict(self.repo.env), ruff_path=self.exe, run=run)

    def test_real_shaped_reports_flow_through_with_the_modelled_argv(self):
        run, calls = self.stub()
        findings, file_count = self.run_ruff(run)
        self.assertEqual({(f.rule, f.row) for f in findings}, EXPECTED_RUFF_ROWS)
        self.assertEqual(file_count, 1)
        show_argv, check_argv = calls[0][0], calls[1][0]
        self.assertEqual(show_argv, lr.show_files_argv(self.exe, ["sample.py"]))
        self.assertEqual(check_argv, lr.tool_argv("ruff", self.repo.root, ["sample.py"], self.exe))
        for argv, kwargs in calls:
            self.assertEqual(kwargs["cwd"], str(self.repo.root))
            self.assertEqual(kwargs["timeout"], lr.RUN_TIMEOUT)
        for flag in ("--config", "ruff.toml", "--ignore-noqa", "--no-cache", "--force-exclude", "--no-fix",
                     "--output-format", "json", "--"):
            self.assertIn(flag, check_argv)

    def test_the_pathspec_covers_stub_files_and_skips_symlinks(self):
        self.repo.write("types.pyi", "x: int\n")
        (self.repo.root / "link.py").symlink_to("sample.py")
        self.repo.git("add", "types.pyi", "link.py")
        run, calls = self.stub(show="")
        with self.assertRaises(lr.InfraError):
            self.run_ruff(run)
        passed = calls[0][0][calls[0][0].index("--") + 1:]
        self.assertEqual(sorted(passed), ["sample.py", "types.pyi"])

    def test_a_tracked_file_ruff_silently_skipped_fails_the_scan(self):
        self.repo.write("scripts/dist/new.py", "x = 1\n")
        self.repo.write("knowledge-base/archive/old.py", "x = 1\n")
        self.repo.git("add", "-A")
        run, _ = self.stub()
        with self.assertRaises(lr.InfraError) as ctx:
            self.run_ruff(run)
        self.assertIn("scripts/dist/new.py", str(ctx.exception))
        self.assertNotIn("knowledge-base", str(ctx.exception))

    def test_only_the_declared_exclusion_may_be_missing_from_the_listing(self):
        self.repo.write("knowledge-base/archive/old.py", "x = 1\n")
        self.repo.git("add", "-A")
        run, _ = self.stub()
        findings, file_count = self.run_ruff(run)
        self.assertEqual(file_count, 1)
        self.assertEqual(len(findings), 4)

    def test_a_file_ruff_could_not_lint_is_infrastructure_not_a_smaller_census(self):
        run, _ = self.stub(report="[]", rc=0, stderr="warning: Failed to lint sample.py: stream did not contain "
                           "valid UTF-8\n")
        with self.assertRaises(lr.InfraError) as ctx:
            self.run_ruff(run)
        self.assertIn("Failed to lint", str(ctx.exception))

    def test_an_empty_clean_report_with_rc_0_is_a_valid_result(self):
        run, _ = self.stub(report="[]", rc=0)
        self.assertEqual(self.run_ruff(run), ([], 1))

    def test_the_modelled_argv_is_spelled_out_literally(self):
        self.assertEqual(
            lr.tool_argv("ruff", Path("/r"), ["a.py", "b.py"], Path("/x/ruff")),
            ["/x/ruff", "check", "--config", "ruff.toml", "--ignore-noqa", "--no-cache", "--no-fix",
             "--force-exclude", "--output-format", "json", "--", "a.py", "b.py"],
        )
        self.assertEqual(
            lr.show_files_argv(Path("/x/ruff"), ["a.py"]),
            ["/x/ruff", "check", "--config", "ruff.toml", "--no-cache", "--force-exclude", "--show-files", "--",
             "a.py"],
        )
        self.assertEqual(
            lr.tool_argv("eslint-test-dirs", Path("/r"), [], None),
            ["/r/apps/web-platform/node_modules/.bin/eslint", "--config",
             "apps/web-platform/eslint.test-dirs.config.mjs", "--no-inline-config",
             "--no-error-on-unmatched-pattern", "-f", "json", "test/**", "plugins/soleur/test/**",
             "plugins/soleur/skills/*/test/**", "scripts/*.test.mjs"],
        )

    def test_a_tracked_file_removed_without_git_rm_is_not_blamed_on_ruff(self):
        self.repo.write("gone.py", "x = 1\n")
        self.repo.git("add", "gone.py")
        (self.repo.root / "gone.py").unlink()
        run, calls = self.stub()
        findings, file_count = self.run_ruff(run)
        self.assertEqual(file_count, 1)
        self.assertNotIn("gone.py", calls[1][0])

    def test_a_nested_knowledge_base_directory_is_excluded_the_way_ruff_excludes_it(self):
        self.repo.write("scripts/knowledge-base/x.py", "x = 1\n")
        self.repo.git("add", "-A")
        run, _ = self.stub()
        findings, file_count = self.run_ruff(run)
        self.assertEqual(file_count, 1)

    def test_ruff_rc_other_than_0_or_1_is_infrastructure(self):
        run, _ = self.stub(rc=2, stderr="boom")
        with self.assertRaises(lr.InfraError):
            self.run_ruff(run)

    def test_a_failing_show_files_is_infrastructure(self):
        run, _ = self.stub(show_rc=2)
        with self.assertRaises(lr.InfraError):
            self.run_ruff(run)

    def test_ruff_is_never_invoked_with_an_empty_file_list(self):
        empty = Repo(self)
        calls = []

        def spy(argv, **kwargs):
            calls.append(argv)
            return completed(argv, 0)

        with self.assertRaises(lr.Vacuous):
            lr.run_ruff(empty.root, env=dict(empty.env), ruff_path=self.exe, run=spy)
        self.assertEqual(calls, [])

    def test_env_with_ci_reaches_the_ruff_provisioning(self):
        captured = {}

        def fake_ensure(requirements, env, **kwargs):
            captured["env"] = env
            raise lr.InfraError("stop here")

        with mock.patch.object(lr, "ensure_ruff", fake_ensure):
            cfg = lr.build_config("ruff", {"CI": "true", "HOME": "/h"})
            with self.assertRaises(lr.InfraError):
                cfg["run"](self.repo.root)
        self.assertEqual(captured["env"]["CI"], "true")


class TestRunEslint(ScrubbedEnv):
    def setUp(self):
        super().setUp()
        self.repo = Repo(self)
        binary = self.repo.root / lr.ESLINT_BIN
        binary.parent.mkdir(parents=True)
        binary.write_text("#!/bin/sh\n")
        for rel in ("test/a.ts", "test/b.ts", "test/c.cts", "scripts/x.test.mjs", "plugins/soleur/test/sub/d.js"):
            self.repo.write(rel, "export const used = 1;\n")
        (self.repo.root / "test" / "link.ts").symlink_to("a.ts")
        self.repo.write("other/not-in-scope.ts", "export const z = 1;\n")
        self.repo.git("add", "-A", "-f")
        self.repo.write("test/untracked.ts", "export const u = 1;\n")

    def report(self, *rels, messages=None):
        return json.dumps([{"filePath": str(self.repo.root / rel), "messages": (messages or {}).get(rel, [])}
                           for rel in rels])

    def stub(self, out, rc=0, stderr=""):
        calls = []

        def run(argv, **kwargs):
            calls.append((list(argv), kwargs))
            return completed(argv, rc, out, stderr)

        return run, calls

    def full_report(self):
        return self.report("test/a.ts", "test/b.ts", "test/c.cts", "scripts/x.test.mjs",
                           "plugins/soleur/test/sub/d.js", "test/untracked.ts", "test/link.ts")

    def test_tracked_non_symlink_in_scope_files_are_counted_and_the_rest_filtered(self):
        run, calls = self.stub(self.full_report())
        findings, file_count = lr.run_eslint(self.repo.root, env=dict(self.repo.env), run=run)
        self.assertEqual((findings, file_count), ([], 5))
        argv, kwargs = calls[0]
        self.assertEqual(argv, lr.tool_argv("eslint-test-dirs", self.repo.root, [], None))
        self.assertEqual(kwargs["cwd"], str(self.repo.root))
        for flag in ("--no-inline-config", "--no-error-on-unmatched-pattern", lr.ESLINT_CONFIG, "-f", "json"):
            self.assertIn(flag, argv)
        for glob in lr.SCOPES["eslint-test-dirs"]["scope"]:
            self.assertIn(glob, argv)

    def test_a_tracked_in_scope_file_missing_from_the_report_fails_the_scan(self):
        run, _ = self.stub(self.report("test/a.ts", "test/c.cts", "scripts/x.test.mjs",
                                       "plugins/soleur/test/sub/d.js"))
        with self.assertRaises(lr.InfraError) as ctx:
            lr.run_eslint(self.repo.root, env=dict(self.repo.env), run=run)
        self.assertIn("test/b.ts", str(ctx.exception))

    def test_the_pathspec_is_the_scope_tuple(self):
        run, _ = self.stub(self.full_report())
        with mock.patch.object(lr, "tracked_files", wraps=lr.tracked_files) as spy:
            lr.run_eslint(self.repo.root, env=dict(self.repo.env), run=run)
        scope_calls = [c.args[1] for c in spy.call_args_list if c.args[1] != (".",)]
        self.assertEqual(scope_calls, [[":(glob)" + g for g in lr.SCOPES["eslint-test-dirs"]["scope"]]])

    def test_findings_flow_through_with_their_rule_and_row(self):
        messages = {"test/a.ts": [{"ruleId": "@typescript-eslint/no-unused-vars", "line": 1, "message": "m"}]}
        report = json.loads(self.full_report())
        report[0]["messages"] = messages["test/a.ts"]
        run, _ = self.stub(json.dumps(report))
        findings, _ = lr.run_eslint(self.repo.root, env=dict(self.repo.env), run=run)
        self.assertEqual(findings, [lr.Finding("test/a.ts", "@typescript-eslint/no-unused-vars", 1, "m")])

    def test_a_tracked_file_removed_without_git_rm_is_not_blamed_on_eslint(self):
        (self.repo.root / "test" / "b.ts").unlink()
        run, _ = self.stub(self.report("test/a.ts", "test/c.cts", "scripts/x.test.mjs",
                                       "plugins/soleur/test/sub/d.js"))
        _findings, file_count = lr.run_eslint(self.repo.root, env=dict(self.repo.env), run=run)
        self.assertEqual(file_count, 4)

    def test_a_missing_binary_names_the_recovery(self):
        (self.repo.root / lr.ESLINT_BIN).unlink()
        with self.assertRaises(lr.InfraError) as ctx:
            lr.run_eslint(self.repo.root, env=dict(self.repo.env), run=self.stub("[]")[0])
        self.assertIn("npm ci --ignore-scripts --prefix apps/web-platform", str(ctx.exception))

    def test_eslint_rc_2_is_infrastructure(self):
        run, _ = self.stub("", rc=2, stderr="boom")
        with self.assertRaises(lr.InfraError):
            lr.run_eslint(self.repo.root, env=dict(self.repo.env), run=run)


class TestScopePins(unittest.TestCase):
    """Config weakening followed by --update is a legal shrink; these pins are what stops it."""

    @classmethod
    def setUpClass(cls):
        if tomllib is None:
            if lr._is_ci(os.environ):
                raise AssertionError("tomllib (Python 3.11+) is required under CI: the ruff.toml pin must run")
            raise unittest.SkipTest("tomllib needs Python 3.11+ (CI runs 3.12)")
        cls.toml = tomllib.loads((REPO_ROOT / "ruff.toml").read_text())

    def test_ruff_toml_is_pinned_as_a_whole_document(self):
        got = dict(self.toml)
        got["lint"] = dict(got["lint"], select=sorted(got["lint"]["select"]))
        self.assertEqual(got, {
            "target-version": "py311",
            "extend-exclude": ["knowledge-base"],
            "lint": {
                "select": sorted(["SIM115", "S110", "S112", "F401", "F841"]),
                "flake8-bandit": {"check-typed-exception": True},
            },
        })

    def test_the_declared_exclusion_matches_the_scanner_constant(self):
        self.assertEqual(tuple(lr.EXCLUDED_DIRS), tuple(self.toml["extend-exclude"]))


class TestConfigPins(unittest.TestCase):
    def test_the_eslint_config_is_pinned_by_content(self):
        digest = hashlib.sha256((REPO_ROOT / lr.ESLINT_CONFIG).read_bytes()).hexdigest()
        self.assertEqual(digest, ESLINT_CONFIG_SHA256,
                         "the eslint config changed: if deliberate, re-pin ESLINT_CONFIG_SHA256 in this file")

    def test_scope_tuples_are_pinned(self):
        self.assertEqual(tuple(lr.SCOPES["ruff"]["scope"]), ("*.py", "*.pyi", "*.pyw"))
        self.assertEqual(
            tuple(lr.SCOPES["eslint-test-dirs"]["scope"]),
            ("test/**", "plugins/soleur/test/**", "plugins/soleur/skills/*/test/**", "scripts/*.test.mjs"),
        )

    def test_script_rel_names_this_very_script(self):
        self.assertEqual(lr.SCRIPT_REL, "plugins/soleur/scripts/lint-ratchet.py")
        self.assertTrue((REPO_ROOT / lr.SCRIPT_REL).samefile(SCRIPT))
        self.assertEqual(lr.build_config("ruff", {})["script"], lr.SCRIPT_REL)

    def test_eslint_extensions_are_pinned(self):
        self.assertEqual(lr.ESLINT_EXTS, (".js", ".mjs", ".cjs", ".jsx", ".ts", ".tsx", ".mts", ".cts"))

    def test_pip_marker_tuples_are_pinned(self):
        self.assertEqual(lr.PIP_INTEGRITY_MARKERS, (
            "DO NOT MATCH THE HASHES", "Hashes are required", "Invalid requirement",
            "Could not open requirements file", "must be pinned", "In --require-hashes mode"))
        self.assertEqual(lr.PIP_NETWORK_MARKERS, (
            "Could not fetch URL", "Temporary failure in name resolution", "Name or service not known",
            "Network is unreachable", "No route to host", "Max retries exceeded", "timed out", "Connection",
            "nodename nor servname", "NameResolutionError", "NewConnectionError",
            "Failed to establish a new connection", "Failed to resolve"))

    def test_baseline_paths_follow_the_lint_convention(self):
        for scope in lr.SCOPES.values():
            self.assertRegex(scope["baseline"], r"^scripts/lint-[a-z-]+\.baseline\.txt$")

    def test_the_user_form_is_byte_identical(self):
        # A user repo's committed .lint-ratchet/ruff.baseline.txt must not churn because the renderer's
        # switch changed.
        self.assertEqual(lr.render_baseline("user-ruff", []), (
            "# lint-ratchet baseline (ruff) for this repository; engine: the Soleur plugin, design in ADR-290.\n"
            "# Shrink-only: this file always equals the live census, and per (path, rule) it may never hold more\n"
            "# entries than the merge base, except when the toolchain line below changed (a ruff pin or config\n"
            "# change; that run prints CONFIG CHANGED so the config diff gets reviewed). Entry: path|rule|anchor|n,\n"
            "# where anchor is a 12-hex fingerprint of the normalised source line (the line is never stored).\n"
            "# List the live findings:  python3 {rel} user-ruff --list\n"
            "# After fixing findings:   python3 {rel} user-ruff --update  (it refuses to add, except as above)\n"
            "# Outside Claude Code, replace ${{CLAUDE_PLUGIN_ROOT}} with the plugin's install directory.\n"
            "# After a merge conflict, take the base branch's copy of this file and re-run --update.\n"
        ).format(rel=lr.SCRIPT_REL))

    def test_the_committed_soleur_baselines_equal_the_rendered_empty_form(self):
        # Byte equality covers both properties: zero entries, and a header that is the renderer's own.
        # After a header wording change, regenerate with `lint-ratchet.py <scope> --update` (needs the tool).
        self.assertEqual(sorted(lr.SCOPES), ["eslint-test-dirs", "ruff"], "a new Soleur scope needs a row here")
        for name in ("ruff", "eslint-test-dirs"):
            path = REPO_ROOT / lr.SCOPES[name]["baseline"]
            self.assertEqual(path.read_text(), lr.render_baseline(name, []), name)


class TestRegistration(unittest.TestCase):
    """Deleting a registration would silently retire the gate: pin each one."""

    def block(self, text, key):
        match = re.search(r"(?ms)^    %s:\n(.*?)(?=^    [a-z0-9-]+:\n)" % re.escape(key), text)
        self.assertIsNotNone(match, key)
        return match.group(1)

    def test_run_suite_lines_exist_in_test_all(self):
        text = (REPO_ROOT / "scripts" / "test-all.sh").read_text()
        self.assertRegex(text, r'(?m)^\s*run_suite "tests/scripts/lint-ratchet" python3 -m unittest '
                               r"tests\.scripts\.test_lint_ratchet$")
        self.assertRegex(text, r'(?m)^\s*run_suite "scripts/lint-ratchet-ruff-live" python3 '
                               r"plugins/soleur/scripts/lint-ratchet\.py ruff --check$")

    def test_both_labels_are_always_on(self):
        text = (REPO_ROOT / "scripts" / "lib" / "test-affected-paths.sh").read_text()
        for label in ("scripts/lint-ratchet-ruff-live", "tests/scripts/lint-ratchet"):
            self.assertRegex(text, r'(?m)^\s*"%s"$' % re.escape(label))

    def test_lefthook_entries_run_the_scopes_unconditionally(self):
        text = (REPO_ROOT / "lefthook.yml").read_text()
        for key, scope in (("ruff-ratchet", "ruff"), ("eslint-test-dirs-ratchet", "eslint-test-dirs")):
            block = self.block(text, key)
            self.assertRegex(block, r"(?m)^      run: python3 plugins/soleur/scripts/lint-ratchet\.py %s --check$" % re.escape(scope))
            for forbidden in ("skip:", "exclude:", "|| true", "only:"):
                self.assertNotIn(forbidden, block)

    def test_lefthook_ruff_globs_are_exactly_the_scope_plus_the_inputs(self):
        block = self.block((REPO_ROOT / "lefthook.yml").read_text(), "ruff-ratchet")
        globs = re.findall(r'(?m)^        - "([^"]+)"$', block)
        expected = []
        for pattern in lr.SCOPES["ruff"]["scope"]:
            expected += [pattern, "**/" + pattern]
        expected += ["ruff.toml", "plugins/soleur/scripts/ruff-requirements.txt", lr.SCRIPT_REL,
                     lr.SCOPES["ruff"]["baseline"]]
        self.assertEqual(sorted(globs), sorted(expected))

    def test_lefthook_eslint_globs_cover_every_directory_extension_and_input(self):
        block = self.block((REPO_ROOT / "lefthook.yml").read_text(), "eslint-test-dirs-ratchet")
        globs = re.findall(r'(?m)^        - "([^"]+)"$', block)
        braces = {frozenset(m.split(",")) for g in globs for m in re.findall(r"\{([^}]+)\}", g)}
        self.assertEqual(braces, {frozenset(e[1:] for e in lr.ESLINT_EXTS)})
        ext = lambda stem: [g for g in globs if g.startswith(stem)]  # noqa: E731
        for directory in ("test", "plugins/soleur/test", "plugins/soleur/skills/*/test"):
            self.assertEqual(len(ext(directory + "/*.")), 1, directory)
            self.assertEqual(len(ext(directory + "/**/*.")), 1, directory)
        for exact in ("scripts/*.test.mjs", lr.ESLINT_CONFIG, "apps/web-platform/package.json",
                      "apps/web-platform/package-lock.json", lr.SCRIPT_REL, lr.SCOPES["eslint-test-dirs"]["baseline"]):
            self.assertIn(exact, globs)

    def test_the_vitest_arm_is_registered_as_repo_wide(self):
        text = (REPO_ROOT / "apps" / "web-platform" / "test" / "repo-wide-suites.ts").read_text()
        self.assertRegex(text, r'(?m)^  "test/eslint-test-dirs-ratchet\.test\.ts",$')
        arm = (REPO_ROOT / "apps" / "web-platform" / "test" / "eslint-test-dirs-ratchet.test.ts").read_text()
        self.assertIn('"plugins/soleur/scripts/lint-ratchet.py", "eslint-test-dirs", "--check"', arm)
        self.assertIn("expect(result.status", arm)


@unittest.skipUnless((REPO_ROOT / lr.ESLINT_BIN).exists(), "needs apps/web-platform/node_modules (npm ci)")
class TestEslintConfigBehaviour(unittest.TestCase):
    """The config's per-extension blocks, driven through the real pinned eslint."""

    def test_cjs_jsx_and_cts_files_parse_and_report_their_rule(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        (root / "a.cjs").write_text("const unusedCjs = 1;\nmodule.exports = {};\nif (process) { return; }\n")
        (root / "b.jsx").write_text("const unusedJsx = <div />;\nexport const ok = 1;\n")
        (root / "c.cts").write_text("const unusedCts: number = 1;\nexport {};\n")
        result = subprocess.run(
            [str(REPO_ROOT / lr.ESLINT_BIN), "--config", str(REPO_ROOT / lr.ESLINT_CONFIG), "--no-inline-config",
             "-f", "json", "a.cjs", "b.jsx", "c.cts"],
            cwd=root, capture_output=True, text=True)
        self.assertIn(result.returncode, (0, 1), result.stderr)
        rules = {Path(r["filePath"]).name: [m["ruleId"] for m in r["messages"]] for r in json.loads(result.stdout)}
        self.assertEqual(rules, {"a.cjs": ["no-unused-vars"], "b.jsx": ["no-unused-vars"],
                                 "c.cts": ["@typescript-eslint/no-unused-vars"]})


class TestPipArgvAndRequirements(ScrubbedEnv):
    def test_requirements_pin_and_wheel_hash_count(self):
        path = REQUIREMENTS
        self.assertEqual(lr.requirements_pin(path), "0.16.10")
        self.assertEqual(len(re.findall(r"--hash=sha256:[0-9a-f]{64}", path.read_text())), 17)

    def test_requirements_have_no_trailing_comment_after_a_continuation(self):
        for line in REQUIREMENTS.read_text().splitlines():
            if line.rstrip().endswith("\\"):
                self.assertNotIn("#", line)

    def test_full_pip_argv(self):
        argv = lr.pip_argv(Path("/t/target"), Path("/r/req.txt"))
        self.assertEqual(
            argv,
            [
                sys.executable, "-I", "-m", "pip", "install", "--isolated", "--no-input", "--no-deps",
                "--disable-pip-version-check", "--index-url", "https://pypi.org/simple",
                "--only-binary=:all:", "--require-hashes", "--target", "/t/target",
                "-r", "/r/req.txt", "--quiet",
            ],
        )

    def test_no_executed_argv_carries_a_fix_mode(self):
        argvs = [lr.pip_argv(Path("/t"), Path("/r"))]
        for name in lr.SCOPES:
            argvs.append(lr.tool_argv(name, Path("/repo"), ["a.py"], Path("/bin/ruff")))
        argvs.append(lr.show_files_argv(Path("/bin/ruff"), ["a.py"]))
        for argv in argvs:
            for flag in ("--fix", "--unsafe-fixes", "--write"):
                self.assertNotIn(flag, argv)
        ruff = lr.tool_argv("ruff", Path("/repo"), ["a.py"], Path("/bin/ruff"))
        self.assertIn("--no-fix", ruff)
        self.assertIn("--ignore-noqa", ruff)
        self.assertIn("--no-inline-config", lr.tool_argv("eslint-test-dirs", Path("/repo"), [], None))

    def test_pip_env_drops_pip_and_python_variables(self):
        env = lr.pip_env({"PIP_INDEX_URL": "x", "PIP_REQUIRE_VIRTUALENV": "1", "PYTHONPATH": "/evil", "PATH": "/bin"})
        self.assertEqual(env, {"PATH": "/bin"})


class FakePip:
    """Stands in for ``subprocess.run`` when ensure_ruff installs: records argv/env and may fail.

    It rejects an install argv that lacks any safety flag, as real pip would reject a malformed one,
    so a mutated argv builder cannot pass by being merely accepted.
    """

    REQUIRED = ("--require-hashes", "--only-binary=:all:", "--isolated", "--no-deps", "--index-url",
                "https://pypi.org/simple", "--target", "-r")

    def __init__(self, *, version="0.16.10", fail_text=None, rc=0, executable=True):
        self.version, self.fail_text, self.rc, self.executable = version, fail_text, rc, executable
        self.calls = []

    def __call__(self, argv, **kwargs):
        if "install" not in argv:
            return subprocess.run(argv, **kwargs)
        self.calls.append((list(argv), kwargs.get("env")))
        if any(flag not in argv for flag in self.REQUIRED):
            return completed(argv, 64, "", "ERROR: no usable install arguments")
        if self.fail_text is not None:
            return completed(argv, self.rc or 1, "", self.fail_text)
        target = Path(argv[argv.index("--target") + 1])
        (target / "bin").mkdir(parents=True)
        exe = target / "bin" / "ruff"
        exe.write_text(f"#!/bin/sh\necho 'ruff {self.version}'\n")
        exe.chmod(0o755 if self.executable else 0o644)
        return completed(argv, 0)


class RacePip(FakePip):
    """Another process finishes the same install between our pip run and our rename."""

    def __call__(self, argv, **kwargs):
        result = super().__call__(argv, **kwargs)
        if "install" in argv and result.returncode == 0:
            target = Path(argv[argv.index("--target") + 1])
            digest = hashlib.sha256(REQUIREMENTS.read_bytes()).hexdigest()[:12]
            final = target.parent / "ruff-{}-{}-{}".format(digest, sys.platform, platform.machine() or "unknown")
            shutil.copytree(str(target), str(final))
        return result


class TestEnsureRuff(ScrubbedEnv):
    def setUp(self):
        super().setUp()
        self.cache = Path(self.fake_home.name) / "cache"
        self.fallback = Path(self.fake_home.name) / "fallback"
        self.req = REQUIREMENTS

    def ensure(self, pip, env=None):
        return lr.ensure_ruff(self.req, env=env or {}, run=pip, cache_root=self.cache, fallback_root=self.fallback)

    def test_installs_once_and_reuses_the_cache(self):
        pip = FakePip()
        first = self.ensure(pip)
        second = self.ensure(pip)
        self.assertEqual(first, second)
        self.assertEqual(len(pip.calls), 1)

    def test_cache_root_is_private_and_its_name_carries_the_platform(self):
        exe = self.ensure(FakePip())
        self.assertEqual(stat.S_IMODE(self.cache.stat().st_mode), 0o700)
        self.assertIn(sys.platform, exe.parent.parent.name)

    def test_default_cache_is_a_directory_of_our_own(self):
        env = {"XDG_CACHE_HOME": str(Path(self.fake_home.name) / "xdg")}
        exe = lr.ensure_ruff(self.req, env=env, run=FakePip(), fallback_root=self.fallback)
        self.assertEqual(exe.parents[2].name, "soleur-lint-ratchet")

    def test_pip_is_run_with_a_scrubbed_environment_that_keeps_the_rest(self):
        pip = FakePip()
        self.ensure(pip, env={"PIP_INDEX_URL": "http://evil", "PYTHONPATH": "/evil", "PATH": "/usr/bin",
                              "HTTPS_PROXY": "http://proxy"})
        _, env = pip.calls[0]
        self.assertFalse([k for k in env if k.startswith(("PIP_", "PYTHON"))])
        self.assertEqual(env["PATH"], "/usr/bin")
        self.assertEqual(env["HTTPS_PROXY"], "http://proxy")

    def test_a_malformed_install_argv_is_rejected_by_the_fake_like_real_pip(self):
        with self.assertRaises(lr.InfraError):
            with mock.patch.object(lr, "pip_argv", lambda target, req: ["pip", "install", "--target", str(target)]):
                self.ensure(FakePip())

    def test_wrong_version_after_install_is_infrastructure_never_a_fallthrough(self):
        with self.assertRaises(lr.InfraError):
            self.ensure(FakePip(version="9.9.9"))

    def test_a_binary_that_cannot_run_is_infrastructure_naming_the_recovery(self):
        with self.assertRaises(lr.InfraError) as ctx:
            self.ensure(FakePip(executable=False))
        self.assertIn("could not run ruff", str(ctx.exception))

    def test_every_integrity_marker_is_infrastructure_with_and_without_ci(self):
        for marker in lr.PIP_INTEGRITY_MARKERS:
            for ci in ({}, {"CI": "true"}):
                with self.subTest(marker=marker, ci=ci), self.assertRaises(lr.InfraError):
                    self.ensure(FakePip(fail_text="ERROR: " + marker), env=ci)

    def test_a_reachability_failure_skips_locally_and_is_infrastructure_under_ci(self):
        for marker in lr.PIP_NETWORK_MARKERS:
            with self.subTest(marker=marker):
                # Without this the offline stamp of the previous marker would answer in pip's place.
                (self.cache / lr.OFFLINE_STAMP).unlink(missing_ok=True)
                pip = FakePip(fail_text="WARNING: " + marker + " while reading https://pypi.org/simple/ruff/")
                with self.assertRaises(lr.Skip) as ctx:
                    self.ensure(pip)
                self.assertIn("recover with", str(ctx.exception))
                with self.assertRaises(lr.InfraError):
                    self.ensure(pip, env={"CI": "true"})

    def test_an_integrity_marker_beats_a_reachability_marker_in_the_same_output(self):
        pip = FakePip(fail_text="WARNING: Connection reset by peer\nERROR: THESE PACKAGES DO NOT MATCH THE HASHES")
        with self.assertRaises(lr.InfraError):
            self.ensure(pip)

    def test_an_unrecognised_pip_failure_is_never_skipped(self):
        for ci in ({}, {"CI": "true"}):
            with self.subTest(ci=ci), self.assertRaises(lr.InfraError):
                self.ensure(FakePip(fail_text="ERROR: some reworded message nobody listed"), env=ci)

    def test_a_failed_install_leaves_no_install_directory_behind(self):
        with self.assertRaises(lr.Skip):
            self.ensure(FakePip(fail_text="Could not fetch URL https://pypi.org/simple/ruff/"))
        self.assertEqual([p.name for p in self.cache.iterdir() if p.name.startswith("install-")], [])

    def test_an_unreachable_index_is_not_retried_inside_the_offline_window(self):
        pip = FakePip(fail_text="Could not fetch URL https://pypi.org/simple/ruff/")
        with self.assertRaises(lr.Skip):
            self.ensure(pip)
        with self.assertRaises(lr.Skip) as ctx:
            self.ensure(pip)
        self.assertIn("not retrying", str(ctx.exception))
        self.assertEqual(len(pip.calls), 1, "the second call must not reach pip")
        old = time.time() - lr.OFFLINE_WINDOW - 5
        os.utime(str(self.cache / lr.OFFLINE_STAMP), (old, old))
        with self.assertRaises(lr.Skip):
            self.ensure(pip)
        self.assertEqual(len(pip.calls), 2, "an expired stamp retries")
        with self.assertRaises(lr.InfraError):
            self.ensure(pip, env={"CI": "true"})
        self.assertEqual(len(pip.calls), 3, "CI never trusts the stamp")

    def test_pip_is_bounded_locally_and_untouched_under_ci(self):
        local = FakePip()
        self.ensure(local)
        argv = local.calls[0][0]
        self.assertEqual(argv[argv.index("--retries") + 1], "1")
        self.assertEqual(argv[argv.index("--timeout") + 1], "15")
        ci = FakePip()
        lr.ensure_ruff(self.req, env={"CI": "true"}, run=ci, cache_root=Path(self.fake_home.name) / "ci-cache",
                       fallback_root=self.fallback)
        self.assertNotIn("--retries", ci.calls[0][0])

    def test_stale_install_directories_are_swept_and_fresh_ones_kept(self):
        self.cache.mkdir(mode=0o700)
        (self.cache / "install-old").mkdir()
        (self.cache / "install-new").mkdir()
        old = time.time() - lr.STALE_INSTALL_AGE - 60
        os.utime(str(self.cache / "install-old"), (old, old))
        self.ensure(FakePip())
        self.assertFalse((self.cache / "install-old").exists())
        self.assertTrue((self.cache / "install-new").exists())

    def test_a_python_without_pip_gets_an_actionable_message(self):
        with self.assertRaises(lr.InfraError) as ctx:
            self.ensure(FakePip(fail_text="/usr/bin/python3: No module named pip"))
        self.assertIn("python3-pip", str(ctx.exception))

    def test_the_caller_supplies_the_recovery_command_in_the_skip(self):
        pip = FakePip(fail_text="Could not fetch URL https://pypi.org/simple/ruff/")
        with self.assertRaises(lr.Skip) as ctx:
            lr.ensure_ruff(self.req, env={}, run=pip, cache_root=self.cache, fallback_root=self.fallback,
                           recovery="python3 /x/lint-ratchet.py user-ruff --check")
        self.assertIn("recover with: python3 /x/lint-ratchet.py user-ruff --check", str(ctx.exception))
        self.assertNotIn("plugins/soleur/scripts", str(ctx.exception))

    def test_symlinked_cache_root_is_refused_and_the_fallback_is_used(self):
        real = Path(self.fake_home.name) / "real"
        real.mkdir(mode=0o700)
        self.cache.symlink_to(real)
        exe = self.ensure(FakePip())
        self.assertTrue(str(exe).startswith(str(self.fallback)))
        self.assertEqual(list(real.iterdir()), [])

    def test_group_writable_cache_root_is_refused_and_left_alone(self):
        self.cache.mkdir(mode=0o700)
        self.cache.chmod(0o770)
        exe = self.ensure(FakePip())
        self.assertTrue(str(exe).startswith(str(self.fallback)))
        self.assertEqual(stat.S_IMODE(self.cache.stat().st_mode), 0o770, "never chmod a directory we did not create")

    def test_the_fallback_is_reused_instead_of_leaking_one_install_per_run(self):
        self.cache.mkdir(mode=0o700)
        self.cache.chmod(0o770)
        pip = FakePip()
        for _ in range(3):
            self.ensure(pip)
        self.assertEqual(len(pip.calls), 1)
        self.assertEqual(len(list(self.fallback.iterdir())), 1)

    def test_a_world_writable_or_non_directory_cache_root_is_refused(self):
        self.cache.mkdir(mode=0o700)
        self.cache.chmod(0o707)
        self.assertTrue(str(self.ensure(FakePip())).startswith(str(self.fallback)))
        self.cache.chmod(0o700)
        self.cache.rmdir()
        self.cache.write_text("not a directory")
        self.assertTrue(str(self.ensure(FakePip())).startswith(str(self.fallback)))

    def test_a_cache_directory_owned_by_someone_else_is_refused(self):
        with mock.patch.object(lr.os, "getuid", return_value=os.getuid() + 1):
            with self.assertRaises(lr.InfraError):
                self.ensure(FakePip())

    @unittest.skipIf(hasattr(os, "geteuid") and os.geteuid() == 0, "root ignores directory permissions")
    def test_an_unwritable_cache_parent_falls_back_instead_of_failing(self):
        parent = Path(self.fake_home.name) / "readonly"
        parent.mkdir()
        parent.chmod(0o500)
        self.addCleanup(parent.chmod, 0o700)
        exe = lr.ensure_ruff(self.req, env={}, run=FakePip(), cache_root=parent / "c", fallback_root=self.fallback)
        self.assertTrue(str(exe).startswith(str(self.fallback)))

    def test_the_cache_directory_changes_when_the_requirements_change(self):
        other = Path(self.fake_home.name) / "req2.txt"
        other.write_text(self.req.read_text() + "# a bumped hash set would change this file\n")
        first = self.ensure(FakePip())
        second = lr.ensure_ruff(other, env={}, run=FakePip(), cache_root=self.cache, fallback_root=self.fallback)
        self.assertNotEqual(first.parent.parent, second.parent.parent)

    def test_a_pip_timeout_names_pip_and_leaves_no_install_directory(self):
        class TimeoutPip(FakePip):
            def __call__(self, argv, **kwargs):
                if "install" in argv:
                    raise subprocess.TimeoutExpired(argv, 1)
                return super().__call__(argv, **kwargs)

        with self.assertRaises(lr.InfraError) as ctx:
            self.ensure(TimeoutPip())
        self.assertIn("pip timed out", str(ctx.exception))
        self.assertEqual([p.name for p in self.cache.iterdir()], [])

    def test_no_usable_cache_directory_is_infrastructure(self):
        for path in (self.cache, self.fallback):
            real = Path(self.fake_home.name) / ("real-" + path.name)
            real.mkdir(mode=0o700)
            path.symlink_to(real)
        with self.assertRaises(lr.InfraError) as ctx:
            self.ensure(FakePip())
        self.assertIn("no private cache directory", str(ctx.exception))

    def test_an_install_that_loses_the_rename_race_uses_the_winner_and_cleans_up(self):
        pip = RacePip()
        exe = self.ensure(pip)
        self.assertTrue(exe.exists())
        self.assertEqual([p.name for p in self.cache.iterdir() if p.name.startswith("install-")], [])


class TestMain(CheckBase):
    def run_main(self, argv, config=None, root=None, env=None):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err), \
                mock.patch.object(lr, "REPO_ROOT", root or self.repo.root), \
                mock.patch.object(lr, "build_config", return_value=config or self.config), \
                mock.patch.dict(os.environ, env or self.repo.env, clear=True):
            code = lr.main(argv)
        return code, out.getvalue(), err.getvalue()

    def test_update_check_and_list_dispatch_to_their_own_functions(self):
        code, out, _ = self.run_main(["ruff", "--update"])
        self.assertEqual(code, 0)
        self.assertTrue((self.repo.root / "base.txt").exists())
        code, out, err = self.run_main(["ruff", "--check"])
        self.assertEqual((code, err), (0, ""))
        self.assertIn("OK", out)
        code, out, _ = self.run_main(["ruff", "--list"])
        self.assertEqual((code, out.strip()), (0, "a.py:2 SIM115 SIM115 message"))
        code, out, _ = self.run_main(["ruff"])
        self.assertEqual(code, 0, "check is the default mode")

    def test_a_failure_goes_to_stderr_and_the_success_to_stdout(self):
        self.run_main(["ruff", "--update"])
        self.repo.write("a.py", "import os\n" + VIOLATION + "    again = open(other)\n")
        code, out, err = self.run_main(["ruff", "--check"])
        self.assertEqual((code, out), (1, ""))
        self.assertIn("NEW a.py:3", err)

    def test_base_is_forwarded_to_the_comparison(self):
        self.run_main(["ruff", "--update"])
        code, _, err = self.run_main(["ruff", "--check", "--base=-x"])
        self.assertEqual(code, 2)
        self.assertIn("looks like an option", err)

    def test_skip_is_a_green_notice_for_check_and_a_failure_for_update_and_list(self):
        def unobtainable(root):
            raise lr.Skip("ruff could not be installed (offline)")

        self.run_main(["ruff", "--update"])
        cfg = dict(self.config, run=unobtainable)
        code, out, _ = self.run_main(["ruff", "--check"], cfg)
        self.assertEqual(code, 0)
        self.assertTrue(out.startswith("SKIP lint-ratchet(ruff)"))
        for mode in ("--update", "--list"):
            code, out, err = self.run_main(["ruff", mode], cfg)
            self.assertEqual((code, out), (2, ""), mode)
            self.assertIn("cannot " + mode, err)

    def test_infrastructure_and_unexpected_errors_exit_2_never_1(self):
        for exc, text in ((lr.InfraError("tool crashed"), "tool crashed"), (KeyError("filename"), "unexpected KeyError"),
                          (UnicodeDecodeError("utf-8", b"\xff", 0, 1, "bad"), "unexpected UnicodeDecodeError"),
                          (PermissionError("denied"), "unexpected PermissionError"),
                          (RuntimeError("odd"), "unexpected RuntimeError"), (IndexError("odd"), "unexpected IndexError"),
                          (OverflowError("odd"), "unexpected OverflowError")):
            def boom(root, exc=exc):
                raise exc

            with self.subTest(exc=type(exc).__name__):
                code, _, err = self.run_main(["ruff", "--list"], dict(self.config, run=boom))
                self.assertEqual(code, 2)
                self.assertIn(text, err)

    def test_terminal_control_characters_are_never_echoed(self):
        self.repo.write("a.py", "import os\n" + VIOLATION)
        cfg = make_config({"a.py": [("SIM115", "open(")]})
        cfg["run"] = lambda root: ([lr.Finding("a.py", "SIM115", 2, "bad \x1b]0;pwned\x07 message")], 1)
        code, _, err = self.run_main(["ruff", "--check"], cfg)
        self.assertNotIn("\x1b", err)
        self.assertNotIn("\x07", err)

    def test_build_config_reads_the_floor_and_runner_from_the_scope(self):
        env = {"CI": "true"}
        for name, runner in (("ruff", "run_ruff"), ("eslint-test-dirs", "run_eslint")):
            with self.subTest(scope=name):
                cfg = lr.build_config(name, env)
                self.assertEqual(cfg["floor"], lr.SCOPES[name]["floor"])
                self.assertEqual(cfg["baseline"], lr.SCOPES[name]["baseline"])
                with mock.patch.object(lr, runner, return_value=([], 0)) as spy:
                    cfg["run"](Path("/r"))
                spy.assert_called_once_with(Path("/r"), env)

    def test_ci_reaches_the_comparison_through_main(self):
        self.run_main(["ruff", "--update"])
        env = dict(self.repo.env, CI="true")
        code, _, err = self.run_main(["ruff", "--check", "--base=no-such-ref"], env=env)
        self.assertEqual(code, 2)
        self.assertIn("under CI", err)
        code, _, _ = self.run_main(["ruff", "--check", "--base=no-such-ref"])
        self.assertEqual(code, 0)

    def test_base_is_forwarded_by_update_too(self):
        code, _, err = self.run_main(["ruff", "--update", "--base=-x"])
        self.assertEqual(code, 2)
        self.assertIn("looks like an option", err)

    def test_an_infrastructure_error_escaping_a_library_call_still_exits_2(self):
        with mock.patch.object(lr, "check", side_effect=lr.InfraError("boom from the library")):
            code, _, err = self.run_main(["ruff", "--check"])
        self.assertEqual(code, 2)
        self.assertIn("boom from the library", err)

    def test_a_tracked_path_can_never_start_a_workflow_command_in_list_output(self):
        cfg = dict(self.config, run=lambda root: ([lr.Finding("::error::x.py", "F401", 1, "m")], 1))
        code, out, _ = self.run_main(["ruff", "--list"], cfg)
        self.assertEqual(code, 0)
        self.assertTrue(out.startswith(" ::error::x.py:1"))

    def test_unknown_scope_is_a_usage_error(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "nonsense", "--check"], cwd=REPO_ROOT,
                                env={k: v for k, v in os.environ.items() if not k.startswith("GIT_")},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)



FAKE_RUFF = r"""#!{python}
import json, os, sys
argv = sys.argv[1:]
log = os.environ.get("FAKE_RUFF_LOG")
if log:
    with open(log, "a") as handle:
        handle.write(json.dumps({{"argv": argv, "cwd": os.getcwd(),
                                  "env": sorted(k for k in os.environ if k.startswith(("RUFF_", "PYTHON")))}}) + "\n")
files = argv[argv.index("--") + 1:] if "--" in argv else []
allowed = {{"check", "--no-cache", "--no-fix", "--no-fix-only", "--force-exclude", "--output-format", "json",
            "--show-files", "--config", "ruff.toml", "--ignore-noqa"}}
head = [a for a in (argv[:argv.index("--")] if "--" in argv else argv)]
if [a for a in head if a not in allowed] or "check" not in head:
    sys.stderr.write("error: unexpected argument (the fake accepts only the modelled argv)\n")
    sys.exit(64)
mode = os.environ.get("FAKE_RUFF_MODE", "")
if mode == "config":
    sys.stderr.write("ruff failed\n  Cause: unknown field `bogus` in /secret/home/ruff.toml\n")
    sys.exit(2)
if "--show-files" in argv:
    if mode == "nolist":
        sys.exit(0)
    for name in files:
        print(os.path.join(os.getcwd(), name))
    sys.exit(0)
if mode == "syntax":
    print(json.dumps([{{"code": None, "filename": os.path.join(os.getcwd(), files[0]),
                       "location": {{"row": 1, "column": 1}}, "message": "SyntaxError: bad"}}]))
    sys.exit(1)
if mode == "crash":
    sys.stderr.write("error: boom\n")
    sys.exit(2)
if mode == "failed":
    sys.stderr.write("warning: Failed to lint x.py: stream did not contain valid UTF-8\n")
    print("[]")
    sys.exit(0)
if mode == "badjson":
    print("not json")
    sys.exit(1)
if mode == "rc3":
    sys.exit(3)
if os.environ.get("FAKE_FIX_ONLY") and "--no-fix-only" not in argv:
    for name in files:
        with open(name, "a") as handle:
            handle.write("# rewritten by fix-only\n")
out = []
for name in files:
    with open(name) as handle:
        for row, line in enumerate(handle.read().splitlines(), start=1):
            if "open(" in line and not ("# noqa" in line and "--ignore-noqa" not in argv):
                out.append({{"code": "SIM115", "filename": os.path.join(os.getcwd(), name),
                             "location": {{"row": row, "column": 1}}, "message": "use a context manager"}})
print(json.dumps(out))
sys.exit(1 if out else 0)
"""

PYPROJECT_RUFF = "[project]\nname = 'demo'\n\n[tool.ruff]\nline-length = 100\n"
USER_BASELINE = ".lint-ratchet/ruff.baseline.txt"


class UserModeBase(ScrubbedEnv):
    """A throwaway user repository whose ruff is a deterministic fake, driven through the real CLI."""

    def setUp(self):
        super().setUp()
        self.repo = Repo(self)
        self.tools = Path(self.fake_home.name) / "tools"
        self.tools.mkdir()
        self.fake_ruff = self.tools / "ruff"
        self.fake_ruff.write_text(FAKE_RUFF.format(python=sys.executable))
        self.fake_ruff.chmod(0o755)
        self.log = self.tools / "calls.log"
        self.provisioned = 0

    def ensure(self, requirements, env, **kwargs):
        self.provisioned += 1
        return self.fake_ruff

    def cli(self, *argv, env=None, root=None):
        merged = dict(self.repo.env)
        merged["FAKE_RUFF_LOG"] = str(self.log)
        merged.update(env or {})
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err), \
                mock.patch.object(lr, "ensure_ruff", self.ensure), \
                mock.patch.object(lr, "resolve_root", lambda env=None: root or self.repo.root), \
                mock.patch.dict(os.environ, merged, clear=True):
            try:
                code = lr.main(list(argv))
            except SystemExit as exc:
                code = exc.code
        return code, out.getvalue(), err.getvalue()

    def calls(self):
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def adopt_files(self, config=PYPROJECT_RUFF):
        self.repo.write("pyproject.toml", config)
        self.repo.write("a.py", "import os\n" + VIOLATION)

    def adopt(self):
        """Config + one finding, baselined and committed; origin/main points at the adopting commit."""
        self.adopt_files()
        self.repo.git("update-ref", "refs/remotes/origin/main", self.repo.commit("code"))
        code, out, err = self.cli("user-ruff", "--update")
        self.assertEqual((code, err), (0, ""), out)
        sha = self.repo.commit("adopt")
        self.repo.git("update-ref", "refs/remotes/origin/main", sha)
        return sha

    def script_cmd(self, scope="user-ruff", mode="--update"):
        import shlex
        return "python3 {} {} {}".format(shlex.quote(str(Path(lr.__file__).resolve())), scope, mode)


class TestUserModeStates(UserModeBase):
    def test_no_ruff_config_is_a_quiet_zero_and_never_provisions(self):
        self.repo.write("a.py", "x = 1\n")
        self.repo.commit()
        code, out, _ = self.cli("auto")
        self.assertEqual(code, 0)
        self.assertEqual(out.strip(), "lint-ratchet: no linter configured (no tracked ruff config at {}; nested "
                                      "configs unsupported); nothing to ratchet".format(self.repo.root))
        self.assertEqual(self.provisioned, 0)

    def test_a_config_without_a_baseline_is_not_adopted_and_never_provisions(self):
        self.adopt_files()
        self.repo.commit()
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0)
        self.assertTrue(out.startswith("lint-ratchet(user-ruff): not adopted. Ask the user whether to adopt"), out)
        self.assertIn("do not adopt in an unattended run", out)
        self.assertTrue(out.strip().endswith("; if yes, run: " + self.script_cmd()), out)
        self.assertEqual(self.provisioned, 0, "pip must never run for a repository that did not opt in")
        self.assertEqual(self.calls(), [])

    def test_not_adopted_with_an_unresolvable_base_says_the_deletion_check_did_not_run(self):
        self.adopt_files()
        self.repo.commit()
        self.repo.git("branch", "-m", "work")
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0)
        self.assertIn("not adopted", out)
        self.assertIn("lint-ratchet(user-ruff): base unresolvable: baseline-deletion check not performed", err)

    def test_adopted_and_clean_is_ok_and_runs_the_fake_ruff_with_the_user_argv(self):
        self.adopt()
        code, out, err = self.cli("auto")
        self.assertEqual((code, err), (0, ""))
        self.assertEqual(out.strip(), "lint-ratchet(user-ruff): OK (1 findings baselined, 1 files scanned)")
        argv = [c["argv"] for c in self.calls() if "--show-files" not in c["argv"]][-1]
        for flag in ("--no-cache", "--no-fix", "--no-fix-only", "--force-exclude", "--output-format", "json"):
            self.assertIn(flag, argv)
        for forbidden in ("--config", "--ignore-noqa", "--isolated"):
            self.assertNotIn(forbidden, argv)

    def test_a_new_finding_blocks(self):
        self.adopt()
        self.repo.write("a.py", "import os\n" + VIOLATION + "    again = open(other)\n")
        code, out, err = self.cli("auto")
        self.assertEqual((code, out), (1, ""))
        self.assertIn("NEW a.py:3 SIM115", err)

    def test_a_stale_entry_blocks(self):
        self.adopt()
        self.repo.write("a.py", "import os\n")
        code, _, err = self.cli("auto")
        self.assertEqual(code, 1)
        self.assertIn("STALE", err)

    def test_growth_is_compared_against_a_master_default_branch_with_no_origin(self):
        self.adopt_files()
        self.repo.commit("code")
        self.repo.git("branch", "-m", "master")
        self.cli("user-ruff", "--update")
        self.repo.commit("adopt")
        self.repo.git("update-ref", "-d", "refs/remotes/origin/main", check=False)
        self.repo.git("checkout", "-q", "-b", "feature")
        self.repo.write("a.py", "import os\n" + VIOLATION + "    again = open(other)\n")
        findings, _ = lr.run_user_ruff(self.repo.root, dict(self.repo.env), ruff_path=self.fake_ruff)
        text = lr.render_baseline("user-ruff", lr.census(findings, self.repo.root), header=lr.toolchain_header(self.repo.root))
        (self.repo.root / USER_BASELINE).write_text(text)
        code, _, err = self.cli("auto")
        self.assertEqual(code, 1, err)
        self.assertIn("baseline grew", err)
        self.assertIn("WARN: using local master as merge base", err)

    def test_a_baseline_deleted_since_the_merge_base_blocks_even_under_ci(self):
        self.adopt()
        (self.repo.root / USER_BASELINE).unlink()
        for env in ({}, {"CI": "true"}):
            code, out, err = self.cli("auto", env=env)
            self.assertEqual(code, 1, env)
            self.assertIn("baseline deleted since the merge base: restore it, or un-adopt on purpose with git rm -r "
                          ".lint-ratchet", err)
            self.assertNotIn("not adopted", out + err)

    def test_a_baseline_kept_after_the_config_is_deleted_blocks(self):
        self.adopt()
        (self.repo.root / "pyproject.toml").unlink()
        code, _, err = self.cli("auto")
        self.assertEqual(code, 1)
        self.assertIn("baseline exists but no ruff config detected", err)

    def test_a_committed_baseline_missing_from_the_tree_with_no_base_is_2_under_ci_and_a_warning_locally(self):
        self.adopt()
        self.repo.git("update-ref", "-d", "refs/remotes/origin/main")
        self.repo.git("branch", "-m", "work")
        (self.repo.root / USER_BASELINE).unlink()
        code, out, err = self.cli("auto", env={"CI": "true"})
        self.assertEqual(code, 2, err)
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0)
        self.assertIn("WARN", out + err)
        self.assertNotIn("not adopted", out + err)

    def test_an_unresolvable_base_never_prints_ok_locally_and_is_2_under_ci(self):
        self.adopt()
        self.repo.git("update-ref", "-d", "refs/remotes/origin/main")
        self.repo.git("branch", "-m", "work")
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0)
        self.assertNotIn("OK", out)
        self.assertIn("WARN lint-ratchet(user-ruff)", out)
        code, _, err = self.cli("auto", env={"CI": "true"})
        self.assertEqual(code, 2)
        self.assertIn("under CI", err)

    def test_an_untracked_baseline_is_read_with_a_note_to_add_it(self):
        self.adopt_files()
        self.repo.commit("code")
        self.cli("user-ruff", "--update")
        code, out, err = self.cli("auto")
        self.assertIn("git add .lint-ratchet", out + err)

    def test_auto_and_user_ruff_check_agree_on_every_state(self):
        self.repo.write("a.py", "x = 1\n")
        self.repo.commit("c0")
        results = {}
        results["no-linter"] = (self.cli("auto"), self.cli("user-ruff", "--check"))
        self.adopt_files()
        self.repo.commit("c1")
        results["not-adopted"] = (self.cli("auto"), self.cli("user-ruff", "--check"))
        self.cli("user-ruff", "--update")
        sha = self.repo.commit("c2")
        self.repo.git("update-ref", "refs/remotes/origin/main", sha)
        results["adopted"] = (self.cli("auto"), self.cli("user-ruff", "--check"))
        (self.repo.root / USER_BASELINE).unlink()
        results["deleted"] = (self.cli("auto"), self.cli("user-ruff", "--check"))
        for name, (left, right) in results.items():
            self.assertEqual(left, right, name)

    def test_auto_rejects_update_and_list(self):
        for flag in ("--update", "--list"):
            code, _, err = self.cli("auto", flag)
            self.assertEqual(code, 2, flag)

    def test_the_soleur_repository_is_skipped_by_script_identity_without_provisioning(self):
        state = lr.classify_user(REPO_ROOT, None, dict(os.environ))
        self.assertEqual(state.kind, "SOLEUR")
        self.assertEqual(state.code, 0)
        self.assertIn("Soleur repository: scopes run via lefthook and CI; nothing to ratchet here", state.lines[0])

    def test_a_planted_soleur_baseline_in_a_user_repo_does_not_disable_the_ratchet(self):
        self.adopt_files()
        self.repo.write("scripts/lint-ratchet-ruff.baseline.txt", "# planted\n")
        self.repo.commit()
        code, out, _ = self.cli("auto")
        self.assertIn("not adopted", out)

    def test_not_a_repository_is_a_skip_and_a_bare_repository_is_told_to_use_a_worktree(self):
        plain = tempfile.TemporaryDirectory()
        self.addCleanup(plain.cleanup)
        previous = os.getcwd()
        self.addCleanup(os.chdir, previous)
        os.chdir(plain.name)
        with self.assertRaises(lr.Skip) as ctx:
            lr.resolve_root(dict(self.repo.env, GIT_CEILING_DIRECTORIES=str(Path(plain.name).parent)))
        self.assertIn("not a git repository", str(ctx.exception))
        bare = tempfile.TemporaryDirectory()
        self.addCleanup(bare.cleanup)
        subprocess.run(["git", "init", "-q", "--bare", bare.name], env=self.repo.env, check=True)
        os.chdir(bare.name)
        with self.assertRaises(lr.InfraError) as ctx:
            lr.resolve_root(dict(self.repo.env))
        self.assertIn("worktree", str(ctx.exception))

    def test_an_injected_raising_runner_never_reads_as_green(self):
        self.adopt()

        def boom(root, env=None, **kwargs):
            raise lr.InfraError("boom from the runner")

        with mock.patch.object(lr, "run_user_ruff", boom):
            code, _, err = self.cli("auto")
        self.assertEqual(code, 2)
        self.assertIn("lint-ratchet(user-ruff): boom from the runner", err)


class TestUserModeTotality(UserModeBase):
    def setUp(self):
        super().setUp()
        self.adopt()

    def test_each_tool_failure_is_exit_2(self):
        for mode, needle in (("failed", "could not lint"), ("badjson", "not JSON"), ("rc3", "exited 3"),
                             ("crash", "error: boom")):
            with self.subTest(mode=mode):
                code, _, err = self.cli("auto", env={"FAKE_RUFF_MODE": mode})
                self.assertEqual(code, 2, err)
                self.assertIn(needle, err)

    def test_a_config_caused_exit_2_is_repo_content_with_the_pinned_version_hint_and_one_line_only(self):
        code, _, err = self.cli("auto", env={"FAKE_RUFF_MODE": "config"})
        self.assertEqual(code, 2)
        self.assertIn("lint-ratchet(user-ruff): REPO-CONTENT: ", err)
        self.assertIn("pinned ruff is {}: this is a typo in your config, or a setting newer than the pin".format(
            lr.requirements_pin(REQUIREMENTS)), err)
        self.assertNotIn("/secret/home", err, "ruff's detail lines are never echoed")
        self.assertEqual(len(err.strip().splitlines()), 1)
        code, _, err = self.cli("auto", env={"FAKE_RUFF_MODE": "crash"})
        self.assertNotIn("pinned ruff is", err)

    def test_ruff_listing_nothing_for_tracked_files_is_not_a_skipped_file_error(self):
        self.repo.write("dist/x.py", "x = 1\n")
        self.repo.commit("dist")
        code, out, _ = self.cli("auto", env={"FAKE_RUFF_MODE": "nolist"})
        self.assertEqual(code, 1, "an empty listing against a baseline with entries is STALE, not InfraError")

    def test_zero_tracked_python_files_warns_when_the_baseline_is_empty_and_is_stale_otherwise(self):
        self.repo.git("rm", "-q", "a.py")
        code, out, err = self.cli("auto")
        self.assertEqual(code, 1, "a baseline entry with nothing to scan is STALE")
        self.assertEqual(self.provisioned, 1, "adopt() provisioned once; zero files must not provision again")
        (self.repo.root / USER_BASELINE).write_text(lr.render_baseline("user-ruff", [],
                                                                         header=lr.toolchain_header(self.repo.root)))
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0)
        self.assertIn("WARN lint-ratchet(user-ruff)", out)
        self.assertNotIn("OK", out)

    def test_an_invalid_syntax_finding_is_an_ordinary_finding(self):
        report = json.dumps([{"code": "invalid-syntax", "filename": str(self.repo.root / "a.py"),
                              "location": {"row": 2, "column": 1}, "message": "bad", "url": None}])
        findings = lr.adapt_ruff(report, self.repo.root)
        self.assertEqual([(f.rule, f.row) for f in findings], [("invalid-syntax", 2)])


class TestUserModeSafety(UserModeBase):
    def test_a_symlinked_config_in_an_adopted_repository_is_refused_without_echoing_content(self):
        self.adopt()
        self.repo.write("target.toml", "line-length = 9\n")
        (self.repo.root / "ruff.toml").symlink_to("target.toml")
        code, _, err = self.cli("auto")
        self.assertEqual(code, 2)
        self.assertIn("REPO-CONTENT", err)
        self.assertNotIn("line-length", err)

    def test_an_oversized_config_in_an_adopted_repository_is_refused(self):
        self.adopt()
        self.repo.write("ruff.toml", "# " + "x" * (1 << 20) + "\n")
        code, _, err = self.cli("auto")
        self.assertEqual(code, 2)
        self.assertIn("over 1 MiB", err)

    def test_an_unsafe_root_config_costs_a_repository_that_never_adopted_nothing(self):
        self.repo.write("target.toml", "line-length = 9\n")
        (self.repo.root / "ruff.toml").symlink_to("target.toml")
        self.repo.write("a.py", "x = 1\n")
        self.repo.commit()
        before = self.provisioned
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0, (out, err))
        self.assertIn("no linter configured", out)
        self.assertIn("symlink", err, "the reason is still told, on stderr")
        self.assertEqual(self.provisioned, before)

    def test_a_symlinked_baseline_directory_is_inert_without_a_config_and_content_with_one(self):
        self.repo.write("a.py", "x = 1\n")
        self.repo.commit()
        real = Path(self.fake_home.name) / "real"
        real.mkdir()
        (self.repo.root / ".lint-ratchet").symlink_to(real)
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0, (out, err))
        self.repo.write("pyproject.toml", PYPROJECT_RUFF)
        self.repo.commit("config")
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0, "no baseline exists anywhere: a never-adopted repository pays nothing")
        self.assertIn("not adopted", out)
        self.assertIn("symlink", err, "the reason is still told, on stderr")

    def test_a_baseline_replaced_by_a_symlink_after_adoption_is_repo_content(self):
        self.adopt()
        shutil.rmtree(str(self.repo.root / ".lint-ratchet"))
        real = Path(self.fake_home.name) / "real2"
        real.mkdir()
        (self.repo.root / ".lint-ratchet").symlink_to(real)
        code, _, err = self.cli("auto")
        self.assertEqual(code, 2)
        self.assertIn("REPO-CONTENT", err)

    def test_fix_only_cannot_rewrite_the_tree(self):
        self.adopt()
        before = (self.repo.root / "a.py").read_bytes()
        self.cli("auto", env={"FAKE_FIX_ONLY": "1"})
        self.assertEqual((self.repo.root / "a.py").read_bytes(), before)

    def test_ruff_and_python_variables_never_reach_the_ruff_child(self):
        self.adopt()
        self.log.unlink()
        code, _, _ = self.cli("auto", env={"RUFF_CONFIG": "/evil", "RUFF_NO_CACHE": "0", "PYTHONPATH": "/evil"})
        self.assertEqual(code, 0)
        self.assertTrue(self.calls())
        for call in self.calls():
            self.assertEqual(call["env"], [])

    def test_a_relative_xdg_cache_home_is_ignored_and_the_home_cache_is_used(self):
        req = Path(self.fake_home.name) / "req.txt"
        req.write_text("ruff==" + lr.requirements_pin(REQUIREMENTS) + " \\\n    --hash=sha256:" + "0" * 64 + "\n")
        seen = {}

        def run(argv, **kwargs):
            seen.setdefault("argv", argv)
            raise lr.Skip("stop here")

        env = {"HOME": self.fake_home.name, "XDG_CACHE_HOME": "relative/cache"}
        cwd = tempfile.TemporaryDirectory()
        self.addCleanup(cwd.cleanup)
        previous = os.getcwd()
        self.addCleanup(os.chdir, previous)
        os.chdir(cwd.name)
        with self.assertRaises(lr.Skip):
            lr.ensure_ruff(req, env, run=run)
        self.assertFalse((Path(cwd.name) / "relative").exists())
        self.assertTrue((Path(self.fake_home.name) / ".cache" / "soleur-lint-ratchet").exists())

    def test_git_runs_without_the_fsmonitor_hook(self):
        seen = []
        real = subprocess.run

        def spy(argv, **kwargs):
            seen.append(list(argv))
            return real(argv, **kwargs)

        self.adopt_files()
        self.repo.commit()
        with mock.patch.object(subprocess, "run", spy):
            self.cli("auto")
        gits = [a for a in seen if a and a[0] == "git"]
        self.assertTrue(gits)
        for argv in gits:
            self.assertIn("core.fsmonitor=false", argv)

    def test_the_user_scope_ignores_the_soleur_tables(self):
        self.adopt()
        with mock.patch.object(lr, "SCOPES", {}), \
                mock.patch.object(lr, "ESLINT_CONFIG", "POISON"), mock.patch.object(lr, "ESLINT_BIN", "POISON"):
            code, out, err = self.cli("auto")
        self.assertEqual((code, err), (0, ""))
        self.assertIn("OK", out)


class TestUserModeFingerprint(UserModeBase):
    def header_of(self, path=None):
        text = (path or self.repo.root / USER_BASELINE).read_text()
        return [line for line in text.splitlines() if line.startswith("# toolchain: ")]

    def test_the_rendered_baseline_is_machine_independent(self):
        self.adopt()
        text = (self.repo.root / USER_BASELINE).read_text()
        self.assertEqual(len(self.header_of()), 1)
        self.assertRegex(self.header_of()[0], r"^# toolchain: ruff {} ; config sha256:[0-9a-f]{{16}}$".format(
            re.escape(lr.requirements_pin(REQUIREMENTS))))
        for forbidden in (str(self.repo.root), self.fake_home.name, "10331", "Drawdown", "/home/", "/tmp/"):
            self.assertNotIn(forbidden, text)
        self.assertIn('python3 "${CLAUDE_PLUGIN_ROOT}/scripts/lint-ratchet.py" user-ruff --update', text)

    def test_a_pyproject_edit_outside_the_ruff_tables_leaves_the_hash_unchanged(self):
        self.adopt_files()
        self.repo.commit()
        before = lr.toolchain_header(self.repo.root)
        self.repo.write("pyproject.toml", PYPROJECT_RUFF.replace("demo", "renamed") + "\n[tool.other]\nx = 1\n")
        self.assertEqual(lr.toolchain_header(self.repo.root), before)
        self.repo.write("pyproject.toml", PYPROJECT_RUFF.replace("100", "88"))
        self.assertNotEqual(lr.toolchain_header(self.repo.root), before)

    def grow_with_changed_config(self):
        """A config change that surfaces one more finding, baselined by plain --update."""
        self.repo.git("checkout", "-q", "-b", "feature")
        self.repo.write("pyproject.toml", PYPROJECT_RUFF.replace("100", "88"))
        self.repo.write("a.py", "import os\n" + VIOLATION + "    again = open(other)\n")

    def test_a_config_change_may_grow_the_baseline_with_a_visible_sentinel_and_never_a_plain_ok(self):
        self.adopt()
        self.grow_with_changed_config()
        code, out, err = self.cli("user-ruff", "--update")
        self.assertEqual(code, 0, err)
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0, err)
        self.assertIn("lint-ratchet(user-ruff): CONFIG CHANGED vs merge base: shrink-only not enforced; review the "
                      "config diff", out)
        self.assertNotIn("OK (", out)

    def test_plain_update_refuses_growth_when_the_config_did_not_change(self):
        self.adopt()
        self.repo.git("checkout", "-q", "-b", "feature")
        self.repo.write("a.py", "import os\n" + VIOLATION + "    again = open(other)\n")
        code, _, err = self.cli("user-ruff", "--update")
        self.assertEqual(code, 1)
        self.assertIn("refusing to write", err)

    def test_editing_only_the_header_buys_no_exemption(self):
        self.adopt()
        self.repo.git("checkout", "-q", "-b", "feature")
        self.repo.write("a.py", "import os\n" + VIOLATION + "    again = open(other)\n")
        findings, _ = lr.run_user_ruff(self.repo.root, dict(self.repo.env), ruff_path=self.fake_ruff)
        forged = lr.render_baseline("user-ruff", lr.census(findings, self.repo.root),
                                    header="# toolchain: ruff {} ; config sha256:".format(
                                        lr.requirements_pin(REQUIREMENTS)) + "f" * 16)
        (self.repo.root / USER_BASELINE).write_text(forged)
        code, _, err = self.cli("auto")
        self.assertEqual(code, 1, "a forged header must still be growth-checked")
        self.assertIn("baseline grew", err)

    def test_a_missing_header_means_no_exemption(self):
        self.adopt()
        self.grow_with_changed_config()
        findings, _ = lr.run_user_ruff(self.repo.root, dict(self.repo.env), ruff_path=self.fake_ruff)
        text = lr.render_baseline("user-ruff", lr.census(findings, self.repo.root), header=None)
        (self.repo.root / USER_BASELINE).write_text(text)
        code, _, err = self.cli("auto")
        self.assertEqual(code, 1)

    def test_a_stale_header_with_an_equal_census_still_passes_and_says_so(self):
        self.adopt()
        self.repo.write("pyproject.toml", PYPROJECT_RUFF.replace("100", "88"))
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0, err)
        self.assertIn("lint-ratchet(user-ruff): fingerprint stale: run --update to refresh", out)
        self.assertTrue(out.startswith("WARN lint-ratchet(user-ruff): census matches"), out)
        self.assertNotIn("OK (", out)

    def test_a_baseline_from_a_newer_ruff_asks_for_a_plugin_update(self):
        self.adopt()
        text = (self.repo.root / USER_BASELINE).read_text().replace(
            "ruff " + lr.requirements_pin(REQUIREMENTS), "ruff 99.0.0")
        (self.repo.root / USER_BASELINE).write_text(text)
        code, out, _ = self.cli("auto")
        self.assertEqual(code, 0)
        self.assertIn("plugin older than the baseline's ruff 99.0.0: update the plugin", out)
        self.assertNotIn("run --update to refresh", out)


class TestUserModeUpdateAndLadder(UserModeBase):
    def test_update_prints_the_path_and_warns_when_the_target_is_git_ignored(self):
        self.adopt_files()
        self.repo.write(".gitignore", ".lint-ratchet/\n")
        self.repo.commit()
        code, out, err = self.cli("user-ruff", "--update")
        self.assertEqual(code, 0, err)
        self.assertIn("wrote 1 entries to .lint-ratchet/ruff.baseline.txt", out)
        self.assertIn("git-ignored", out)
        self.assertEqual((self.repo.root / ".gitignore").read_text(), ".lint-ratchet/\n", "the .gitignore is never edited")

    def test_the_ladder_uses_upstream_main_when_there_is_no_origin(self):
        self.adopt_files()
        sha = self.repo.commit()
        self.repo.git("branch", "-m", "work")
        self.repo.git("update-ref", "refs/remotes/upstream/main", sha)
        resolved, notes = lr.resolve_base_ladder(self.repo.root, None, dict(self.repo.env))
        self.assertEqual(resolved, sha)
        self.assertEqual(notes, [])

    def test_a_dangling_origin_head_is_skipped(self):
        self.adopt_files()
        sha = self.repo.commit()
        self.repo.git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/develop")
        self.repo.git("update-ref", "refs/remotes/origin/main", sha)
        resolved, _ = lr.resolve_base_ladder(self.repo.root, None, dict(self.repo.env))
        self.assertEqual(resolved, sha)

    def test_a_local_branch_rung_is_flagged(self):
        self.adopt_files()
        sha = self.repo.commit()
        resolved, notes = lr.resolve_base_ladder(self.repo.root, None, dict(self.repo.env))
        self.assertEqual(resolved, sha)
        self.assertEqual(notes, ["WARN: using local main as merge base"])

    def test_a_shallow_clone_without_a_merge_base_gets_the_fetch_hint(self):
        self.adopt_files()
        self.repo.commit("one")
        self.repo.write("b.py", "x = 2\n")
        self.repo.commit("two")
        clone = tempfile.TemporaryDirectory()
        self.addCleanup(clone.cleanup)
        env = dict(self.repo.env)
        subprocess.run(["git", "clone", "-q", "--depth", "1", "file://" + str(self.repo.root), clone.name],
                       env=env, check=True, capture_output=True)
        base = ["git", "-C", clone.name, "-c", "user.name=f", "-c", "user.email=f@example.com",
                "-c", "commit.gpgsign=false"]
        subprocess.run(base + ["checkout", "-q", "--orphan", "x"], env=env, check=True, capture_output=True)
        subprocess.run(base + ["commit", "-q", "--allow-empty", "-m", "orphan"], env=env, check=True,
                       capture_output=True)
        resolved, notes = lr.resolve_base_ladder(Path(clone.name), None, env)
        self.assertIsNone(resolved)
        self.assertTrue(any("shallow clone: fetch more history (fetch-depth: 0)" in n for n in notes), notes)


class TestUserModeWaiversAndSoleurIsolation(UserModeBase):
    def test_a_noqa_is_honoured_in_user_mode_and_still_ignored_for_the_soleur_scopes(self):
        self.repo.write("pyproject.toml", PYPROJECT_RUFF)
        self.repo.write("a.py", "import os\n    handle = open(path)  # noqa: SIM115\n")
        self.repo.commit()
        findings, _ = lr.run_user_ruff(self.repo.root, dict(self.repo.env), ruff_path=self.fake_ruff)
        self.assertEqual(findings, [])
        self.assertIn("--ignore-noqa", lr.tool_argv("ruff", self.repo.root, ["a.py"], self.fake_ruff))
        self.assertNotIn("--ignore-noqa", lr.tool_argv("ruff", self.repo.root, ["a.py"], self.fake_ruff, user=True))

    def test_the_soleur_scopes_keep_their_exact_argv_and_wording(self):
        self.assertEqual(
            lr.tool_argv("ruff", "/r", ["a.py"], "/x/ruff"),
            ["/x/ruff", "check", "--config", "ruff.toml", "--ignore-noqa", "--no-cache", "--no-fix",
             "--force-exclude", "--output-format", "json", "--", "a.py"])
        self.assertEqual(
            lr.show_files_argv("/x/ruff", ["a.py"]),
            ["/x/ruff", "check", "--config", "ruff.toml", "--no-cache", "--force-exclude", "--show-files", "--",
             "a.py"])
        repo = Repo(self)
        repo.write("a.py", "import os\n" + VIOLATION)
        repo.commit()
        config = make_config({"a.py": [("SIM115", "open(")]})
        code, lines = lr.check(config, repo.root, env=dict(repo.env))
        self.assertEqual(code, 2)
        (repo.root / "base.txt").write_text(lr.render_baseline("fixture", []))
        code, lines = lr.check(config, repo.root, env=dict(repo.env))
        self.assertEqual(code, 1)
        self.assertEqual(lines[-2:], [
            "lint-ratchet(fixture): remedy: REMEDY-TEXT",
            "lint-ratchet(fixture): inline waivers (# noqa, eslint-disable) are NOT honoured here, and --update must "
            "not be used to admit a new finding"])


class TestUserModeGuards(UserModeBase):
    """One property per test: each guard of the decision table is pinned by the edit that would remove it."""

    def test_a_user_file_at_the_soleur_script_path_is_not_the_soleur_repository(self):
        self.adopt_files()
        self.repo.write("plugins/soleur/scripts/lint-ratchet.py", "# not the engine\n")
        self.repo.commit()
        code, out, err = self.cli("auto")
        self.assertIn("not adopted", out)

    def test_a_symlink_planted_at_the_script_path_does_not_switch_the_ratchet_off(self):
        self.adopt()
        self.repo.write("a.py", "import os\n" + VIOLATION + "    again = open(other)\n")
        planted = self.repo.root / "plugins" / "soleur" / "scripts"
        planted.mkdir(parents=True)
        (planted / "lint-ratchet.py").symlink_to(Path(lr.__file__).resolve())
        code, out, err = self.cli("auto")
        self.assertEqual(code, 1, (out, err))
        self.assertIn("NEW a.py", err)
        self.assertNotIn("Soleur repository", out + err)

    def test_an_untracked_ruff_toml_is_no_config(self):
        self.repo.write("a.py", "x = 1\n")
        self.repo.commit()
        self.repo.write("ruff.toml", "line-length = 100\n")
        code, out, err = self.cli("auto")
        self.assertIn("no linter configured", out)

    def test_a_pyproject_without_a_ruff_table_is_no_config(self):
        self.repo.write("pyproject.toml", "[project]\nname = 'x'\n")
        self.repo.write("a.py", "x = 1\n")
        self.repo.commit()
        code, out, err = self.cli("auto")
        self.assertIn("no linter configured", out)

    def test_a_commented_tool_ruff_is_no_config(self):
        self.repo.write("pyproject.toml", "[project]\nname = 'x'\n# [tool.ruff] later\n")
        self.repo.write("a.py", "x = 1\n")
        self.repo.commit()
        code, out, err = self.cli("auto")
        self.assertIn("no linter configured", out)

    def test_an_untracked_pyproject_is_no_config(self):
        self.repo.write("a.py", "x = 1\n")
        self.repo.commit()
        self.repo.write("pyproject.toml", PYPROJECT_RUFF)
        code, out, err = self.cli("auto")
        self.assertIn("no linter configured", out)

    def test_a_dot_ruff_toml_is_a_config(self):
        self.repo.write(".ruff.toml", "line-length = 100\n")
        self.repo.write("a.py", "x = 1\n")
        self.repo.commit()
        code, out, err = self.cli("auto")
        self.assertIn("not adopted", out)

    def test_baseline_and_config_both_removed_from_the_tree_but_committed_still_blocks(self):
        self.adopt()
        (self.repo.root / USER_BASELINE).unlink()
        (self.repo.root / "pyproject.toml").unlink()
        code, out, err = self.cli("auto")
        self.assertEqual(code, 1, (out, err))

    def test_a_repository_with_no_commit_yet_is_not_adopted_rather_than_an_error(self):
        self.repo.write("ruff.toml", "line-length = 100\n")
        self.repo.write("a.py", "x = 1\n")
        self.repo.git("add", "-A")
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0, err)
        self.assertIn("not adopted", out)

    def test_a_headerless_merge_base_baseline_earns_no_config_exemption(self):
        self.adopt()
        text = (self.repo.root / USER_BASELINE).read_text()
        headerless = "\n".join(l for l in text.splitlines() if not l.startswith("# toolchain: ")) + "\n"
        (self.repo.root / USER_BASELINE).write_text(headerless)
        self.repo.git("update-ref", "refs/remotes/origin/main", self.repo.commit("legacy headerless baseline"))
        self.repo.git("checkout", "-q", "-b", "feature")
        self.repo.write("pyproject.toml", PYPROJECT_RUFF.replace("100", "88"))
        self.repo.write("a.py", "import os\n" + VIOLATION + "    again = open(other)\n")
        findings, _ = lr.run_user_ruff(self.repo.root, dict(self.repo.env), ruff_path=self.fake_ruff)
        (self.repo.root / USER_BASELINE).write_text(lr.render_baseline(
            "user-ruff", lr.census(findings, self.repo.root), header=lr.toolchain_header(self.repo.root)))
        code, out, err = self.cli("auto")
        self.assertEqual(code, 1, (out, err))
        self.assertIn("baseline grew", err)

    def baseline_with_pin(self, pin):
        self.adopt()
        path = self.repo.root / USER_BASELINE
        path.write_text(path.read_text().replace("ruff " + lr.requirements_pin(REQUIREMENTS), "ruff " + pin))

    def test_a_baseline_from_an_older_ruff_is_a_stale_fingerprint_not_a_request_to_update_the_plugin(self):
        self.baseline_with_pin("0.15.0")
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0, err)
        self.assertIn("fingerprint stale: run --update to refresh", out)
        self.assertNotIn("update the plugin", out)

    def test_pin_comparison_is_numeric_not_lexicographic(self):
        self.baseline_with_pin("0.9.0")
        code, out, err = self.cli("auto")
        self.assertIn("fingerprint stale", out)
        self.assertNotIn("update the plugin", out)

    def test_update_refuses_growth_on_a_master_default_repository_with_no_origin(self):
        self.adopt_files()
        self.repo.commit("code")
        self.repo.git("branch", "-m", "master")
        self.assertEqual(self.cli("user-ruff", "--update")[0], 0)
        self.repo.commit("adopt")
        self.repo.git("checkout", "-q", "-b", "feature")
        self.repo.write("a.py", "import os\n" + VIOLATION + "    again = open(other)\n")
        code, out, err = self.cli("user-ruff", "--update")
        self.assertEqual(code, 1, (out, err))
        self.assertIn("refusing to write", err)

    def test_update_in_the_soleur_repository_is_the_quiet_zero(self):
        code, out, err = self.cli("user-ruff", "--update", root=REPO_ROOT)
        self.assertEqual(code, 0, err)
        self.assertIn("Soleur repository", out)

    def test_update_with_no_linter_is_exit_2_naming_the_verb(self):
        self.repo.write("a.py", "x = 1\n")
        self.repo.commit()
        code, out, err = self.cli("user-ruff", "--update")
        self.assertEqual(code, 2)
        self.assertIn("cannot --update", err)

    def test_list_prints_the_live_findings_and_does_not_check(self):
        self.adopt()
        code, out, err = self.cli("user-ruff", "--list")
        self.assertEqual(code, 0, err)
        self.assertEqual(out.strip(), "a.py:2 SIM115 use a context manager")

    def test_list_neutralises_a_workflow_command_path(self):
        self.repo.write("pyproject.toml", PYPROJECT_RUFF)
        self.repo.write("::error::x.py", "import os\n" + VIOLATION)
        self.repo.commit()
        code, out, err = self.cli("user-ruff", "--list")
        self.assertEqual(code, 0, err)
        self.assertTrue(out.startswith(" ::error::x.py"), out)

    def test_offline_without_ruff_is_a_loud_skip_for_check_and_exit_2_for_update(self):
        self.adopt()

        def skip(requirements, env, **kwargs):
            raise lr.Skip("no network")

        self.ensure = skip
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0, err)
        self.assertIn("SKIP lint-ratchet(auto): no scan was performed", out)
        code, out, err = self.cli("user-ruff", "--update")
        self.assertEqual(code, 2)

    def test_a_toolchain_error_is_not_labelled_repo_content(self):
        self.adopt_files()
        self.repo.commit()
        with mock.patch.object(lr, "tracked_files", side_effect=lr.InfraError("git ls-files failed: x")):
            code, out, err = self.cli("auto")
        self.assertEqual(code, 2)
        self.assertNotIn("REPO-CONTENT", err)

    def test_an_unexpected_exception_is_exit_2_in_user_mode(self):
        self.adopt_files()
        self.repo.commit()
        with mock.patch.object(lr, "classify_user", side_effect=RuntimeError("kaboom")):
            code, out, err = self.cli("auto")
        self.assertEqual(code, 2)
        self.assertIn("unexpected RuntimeError", err)

    def test_a_tracked_file_deleted_in_the_tree_is_not_handed_to_ruff(self):
        self.adopt()
        self.repo.write("b.py", "y = 2\n")
        self.repo.commit("b")
        (self.repo.root / "b.py").unlink()
        self.log.unlink(missing_ok=True)
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0, (out, err))
        for call in self.calls():
            self.assertNotIn("b.py", call["argv"])

    def test_a_tracked_symlinked_py_is_reported_not_scanned(self):
        self.adopt()
        outside = Path(self.fake_home.name) / "outside.py"
        outside.write_text("import os\n    h = open(x)\n")
        (self.repo.root / "link.py").symlink_to(outside)
        self.repo.commit("link")
        self.log.unlink(missing_ok=True)
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0, (out, err))
        self.assertIn("1 tracked .py symlink(s) are not scanned: link.py", err)
        for call in self.calls():
            self.assertNotIn("link.py", call["argv"])

    def test_files_scanned_counts_what_ruff_listed(self):
        fake = FAKE_RUFF.format(python=sys.executable).replace(
            "    for name in files:\n        print(os.path.join",
            "    for name in [n for n in files if n not in os.environ.get('FAKE_EXCLUDE', '').split(',')]:\n"
            "        print(os.path.join")
        self.fake_ruff.write_text(fake)
        self.adopt_files()
        self.repo.write("b.py", "y = 2\n")
        self.repo.git("update-ref", "refs/remotes/origin/main", self.repo.commit("code"))
        self.assertEqual(self.cli("user-ruff", "--update")[0], 0)
        self.repo.git("update-ref", "refs/remotes/origin/main", self.repo.commit("adopt"))
        code, out, err = self.cli("auto", env={"FAKE_EXCLUDE": "b.py"})
        self.assertEqual(code, 0, err)
        self.assertIn("1 files scanned", out)

    def test_the_user_argv_is_exactly_the_modelled_one(self):
        self.assertEqual(lr.show_files_argv("/x/ruff", ["a.py"], user=True),
                         ["/x/ruff", "check", "--no-cache", "--force-exclude", "--show-files", "--", "a.py"])
        self.assertEqual(lr.tool_argv("ruff", "/r", ["a.py"], "/x/ruff", user=True),
                         ["/x/ruff", "check", "--no-cache", "--no-fix", "--no-fix-only", "--force-exclude",
                          "--output-format", "json", "--", "a.py"])

    def test_the_user_messages_are_the_user_ones(self):
        self.adopt()
        self.repo.write("a.py", "import os\n" + VIOLATION + "    again = open(other)\n")
        code, out, err = self.cli("auto")
        self.assertIn(lr.REMEDY_USER, err)
        self.assertIn(lr.WAIVER_NOTE_USER, err)
        self.assertNotIn("NOT honoured", err)
        self.repo.write("a.py", "import os\n")
        code, out, err = self.cli("auto")
        self.assertIn("user-ruff --update", err)
        self.assertNotIn(" ruff --update", err.replace("user-ruff --update", ""))

    def test_edits_to_either_root_ruff_toml_change_the_fingerprint(self):
        for name in ("ruff.toml", ".ruff.toml"):
            self.repo.write(name, "line-length = 100\n")
            self.repo.git("add", "-A")
            first = lr.toolchain_header(self.repo.root)
            self.repo.write(name, "line-length = 88\n")
            self.assertNotEqual(first, lr.toolchain_header(self.repo.root), name)
            self.repo.git("rm", "-q", "-f", name)

    def test_an_explicit_base_is_honoured(self):
        self.adopt()
        earlier = self.repo.git("rev-parse", "HEAD~1").stdout.strip()
        code, out, err = self.cli("auto", "--base", earlier)
        self.assertEqual(code, 0, err)
        self.assertIn("baseline introduced by this diff (absent at {})".format(earlier[:12]), out + err)

    def test_the_toplevel_is_resolved_from_a_subdirectory(self):
        self.adopt_files()
        self.repo.commit()
        sub = self.repo.root / "pkg" / "inner"
        sub.mkdir(parents=True)
        previous = os.getcwd()
        self.addCleanup(os.chdir, previous)
        os.chdir(sub)
        self.assertEqual(Path(lr.resolve_root(dict(self.repo.env))).resolve(), self.repo.root)

    def test_emit_neutralises_workflow_commands_and_survives_a_dead_stream(self):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            lr._emit(0, ["::error::x"], [], "user-ruff")
        self.assertTrue(buf.getvalue().startswith(" ::error::x"))
        broken = mock.Mock()
        broken.write.side_effect = OSError("disk full")
        broken.flush.side_effect = OSError("disk full")
        with mock.patch.object(sys, "stderr", broken), mock.patch.object(sys, "stdout", io.StringIO()):
            self.assertEqual(lr._emit(1, ["x"], ["w"], "user-ruff"), 2)

    def test_config_changed_does_not_also_claim_there_was_no_merge_base(self):
        self.adopt()
        self.repo.git("checkout", "-q", "-b", "feature")
        self.repo.write("pyproject.toml", PYPROJECT_RUFF.replace("100", "88"))
        self.repo.write("a.py", "import os\n" + VIOLATION + "    again = open(other)\n")
        self.cli("user-ruff", "--update")
        code, out, err = self.cli("auto")
        self.assertIn("CONFIG CHANGED", out)
        self.assertNotIn("no merge base", out + err)

    def test_a_realistically_sized_pyproject_is_accepted(self):
        deps = ",".join("'pkg%d>=1.0'" % i for i in range(300))
        self.repo.write("pyproject.toml", "[project]\nname='x'\ndependencies=[" + deps + "]\n\n[tool.ruff]\n"
                        "line-length = 100\n")
        self.repo.write("a.py", "x = 1\n")
        self.repo.commit()
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0, err)
        self.assertIn("not adopted", out)

    def test_ruff_is_provisioned_from_the_plugins_pinned_requirements_never_the_repository(self):
        self.adopt()
        seen = []

        def spy(requirements, env, **kwargs):
            seen.append(Path(requirements))
            return self.fake_ruff

        self.ensure = spy
        self.cli("auto")
        self.assertEqual(seen, [lr.RUFF_REQUIREMENTS])

    def test_update_from_a_scan_that_listed_zero_files_does_not_truncate_the_baseline(self):
        self.adopt()
        before = (self.repo.root / USER_BASELINE).read_text()
        code, out, err = self.cli("user-ruff", "--update", env={"FAKE_RUFF_MODE": "nolist"})
        self.assertEqual(code, 1, (out, err))
        self.assertEqual((self.repo.root / USER_BASELINE).read_text(), before)

    def test_a_baseline_committed_only_on_the_branch_then_deleted_blocks(self):
        self.adopt_files()
        self.repo.git("update-ref", "refs/remotes/origin/main", self.repo.commit("code"))
        self.repo.git("checkout", "-q", "-b", "feature")
        self.assertEqual(self.cli("user-ruff", "--update")[0], 0)
        self.repo.commit("adopt on branch")
        (self.repo.root / USER_BASELINE).unlink()
        code, out, err = self.cli("auto")
        self.assertEqual(code, 1, (out, err))
        self.assertIn("committed at HEAD", err)


class TestUserModeReviewFixes(UserModeBase):
    """Defects the review panel measured on the first version of user mode, each pinned by its repair."""

    def grown_baseline(self):
        findings, _ = lr.run_user_ruff(self.repo.root, dict(self.repo.env), ruff_path=self.fake_ruff)
        (self.repo.root / USER_BASELINE).write_text(lr.render_baseline(
            "user-ruff", lr.census(findings, self.repo.root), header=lr.toolchain_header(self.repo.root)))

    def feature_with_growth(self, extra=1):
        self.repo.git("checkout", "-q", "-b", "feature")
        self.repo.write("a.py", "import os\n" + VIOLATION + "".join(
            "    again{} = open(other)\n".format(i) for i in range(extra)))

    def test_a_tag_named_like_a_rung_does_not_hijack_the_base(self):
        self.adopt()
        self.feature_with_growth()
        self.grown_baseline()
        grown = self.repo.commit("grow")
        self.repo.git("tag", "origin/main", grown)
        code, _, err = self.cli("auto")
        self.assertEqual(code, 1, err)
        self.assertIn("baseline grew", err)

    def test_a_stale_origin_head_does_not_hide_growth(self):
        self.adopt_files()
        before_adoption = self.repo.commit("code")
        self.assertEqual(self.cli("user-ruff", "--update")[0], 0)
        adopted = self.repo.commit("adopt")
        self.repo.git("update-ref", "refs/remotes/origin/main", adopted)
        self.repo.git("update-ref", "refs/remotes/origin/master", before_adoption)
        self.repo.git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/master")
        self.feature_with_growth()
        self.grown_baseline()
        code, _, err = self.cli("auto")
        self.assertEqual(code, 1, err)
        self.assertIn("baseline grew", err)

    def test_under_ci_a_repository_with_no_merge_base_cannot_prove_it_never_adopted(self):
        self.adopt_files()
        self.repo.commit()
        self.repo.git("branch", "-m", "work")
        code, out, err = self.cli("auto", env={"CI": "true"})
        self.assertEqual(code, 2, (out, err))
        self.assertIn("fetch-depth: 0", err)
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0, "locally the same state is only a warning")

    def test_untracked_python_is_reported_instead_of_hiding_behind_an_ok(self):
        self.adopt()
        self.repo.write("new.py", "import os\n" + VIOLATION)
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0, (out, err))
        self.assertIn("1 untracked .py file(s) are not scanned until they are added to git: new.py", err)

    def test_a_git_ignored_baseline_is_called_out_instead_of_advising_git_add(self):
        self.adopt_files()
        self.repo.write(".gitignore", ".lint-ratchet/\n")
        self.repo.commit("code")
        self.assertEqual(self.cli("user-ruff", "--update")[0], 0)
        code, out, err = self.cli("auto")
        self.assertIn("git-ignored", err)
        self.assertNotIn("git add .lint-ratchet", err)

    def test_a_binary_baseline_is_repo_content_and_update_repairs_it(self):
        self.adopt()
        path = self.repo.root / USER_BASELINE
        path.write_bytes(b"\xff\xfe# not utf-8\n")
        code, _, err = self.cli("auto")
        self.assertEqual(code, 2)
        self.assertIn("REPO-CONTENT", err)
        self.assertIn("not valid UTF-8", err)
        self.assertEqual(self.cli("user-ruff", "--update")[0], 0)
        self.assertEqual(self.cli("auto")[0], 0)

    def test_a_fifo_baseline_is_refused_without_hanging(self):
        self.adopt()
        path = self.repo.root / USER_BASELINE
        path.unlink()
        os.mkfifo(str(path))
        import signal

        def hung(signum, frame):
            raise AssertionError("reading a FIFO baseline hung the tool")

        old = signal.signal(signal.SIGALRM, hung)
        self.addCleanup(signal.signal, signal.SIGALRM, old)
        signal.alarm(30)
        self.addCleanup(signal.alarm, 0)
        code, _, err = self.cli("auto")
        self.assertEqual(code, 2)
        self.assertIn("not a regular file", err)

    def test_a_file_ruff_cannot_parse_is_repo_content(self):
        self.adopt()
        code, _, err = self.cli("auto", env={"FAKE_RUFF_MODE": "syntax"})
        self.assertEqual(code, 2)
        self.assertIn("REPO-CONTENT: ruff could not parse a.py", err)

    def test_list_carries_the_repo_content_prefix_on_a_config_failure(self):
        self.adopt()
        code, _, err = self.cli("user-ruff", "--list", env={"FAKE_RUFF_MODE": "config"})
        self.assertEqual(code, 2)
        self.assertIn("lint-ratchet(user-ruff): REPO-CONTENT: ", err)

    def test_a_tracked_file_with_a_non_utf8_name_fails_closed(self):
        self.adopt()
        with open(os.fsencode(str(self.repo.root)) + b"/bad\xff.py", "w") as handle:
            handle.write("x = 1\n")
        self.repo.commit("bad name")
        code, _, err = self.cli("auto")
        self.assertEqual(code, 2)
        self.assertIn("REPO-CONTENT", err)
        self.assertIn("not valid UTF-8", err)

    def test_update_refuses_a_path_the_baseline_format_cannot_round_trip(self):
        self.adopt_files()
        self.repo.write("#hash.py", "import os\n" + VIOLATION)
        self.repo.commit()
        code, _, err = self.cli("user-ruff", "--update")
        self.assertEqual(code, 2)
        self.assertIn("REPO-CONTENT", err)
        self.assertFalse((self.repo.root / USER_BASELINE).exists())

    def test_a_large_file_list_is_split_across_ruff_launches(self):
        self.adopt_files()
        for i in range(6):
            self.repo.write("m{}.py".format(i), "x = {}\n".format(i))
        self.repo.commit()
        env = dict(self.repo.env, FAKE_RUFF_LOG=str(self.log))
        with mock.patch.object(lr, "ARGV_BUDGET", 12):
            findings, count = lr.run_user_ruff(self.repo.root, env, ruff_path=self.fake_ruff)
        self.assertEqual(count, 7)
        self.assertGreater(len([c for c in self.calls() if "--show-files" in c["argv"]]), 1)
        self.assertEqual({(f.path, f.rule) for f in findings}, {("a.py", "SIM115")})

    def test_the_chunked_launches_share_one_total_budget(self):
        self.adopt()
        with mock.patch.object(lr, "TOTAL_RUN_BUDGET", -1):
            code, _, err = self.cli("auto")
        self.assertEqual(code, 2)
        self.assertIn("exceeded the total budget", err)
        self.assertNotIn("REPO-CONTENT", err, "a slow machine is not a defect of the repository")

    def test_a_flood_of_new_findings_is_capped_and_says_how_many_more(self):
        self.adopt()
        self.repo.write("a.py", "import os\n" + "".join("    h{} = open(p)\n".format(i) for i in range(40)))
        code, _, err = self.cli("auto")
        self.assertEqual(code, 1)
        shown = [l for l in err.splitlines() if l.startswith("lint-ratchet(user-ruff): NEW ")]
        self.assertEqual(len(shown), lr.NOTICE_LIMIT)
        self.assertIn("... and {} more NEW findings".format(40 - lr.NOTICE_LIMIT), err)

    def test_unicode_tag_and_variation_characters_never_reach_the_output(self):
        smuggled = "".join(chr(0xe0000 + ord(c)) for c in "IGNORE") + chr(0xfe0f) + chr(0x3164)
        cleaned = lr._clean("a" + smuggled + "b")
        self.assertTrue(all(ord(c) < 0xe0000 and c not in (chr(0xfe0f), chr(0x3164)) for c in cleaned), cleaned)
        self.assertEqual(len(lr._clip("x" * 1000)), lr.FIELD_LIMIT)

    def test_toml_spellings_of_the_ruff_table_are_detected_and_lookalikes_are_not(self):
        for spelling in ("[tool.ruff]", "[ tool.ruff ]", '["tool"."ruff"]', "[tool.ruff.lint]", "  [tool.ruff]"):
            self.assertTrue(lr._has_ruff_table("[project]\nname = 'x'\n\n" + spelling + "\nx = 1\n"), spelling)
        for other in ("[tool.ruffle]", "# [tool.ruff]", "[tool.other]\nruff = 1\n"):
            self.assertFalse(lr._has_ruff_table(other), other)
        tables = lr._ruff_tables('[tool.ruff.lint]\nselect = [\n["a", "b"],\n]\n[tool.other]\nx = 1\n')
        self.assertIn('["a", "b"],', tables)
        self.assertNotIn("tool.other", tables)

    def test_a_tracked_nested_ruff_config_is_fingerprinted_and_an_untracked_one_is_not(self):
        self.adopt_files()
        self.repo.commit()
        before = lr.toolchain_header(self.repo.root)
        self.repo.write("pkg/ruff.toml", "[lint]\nignore = ['ALL']\n")
        self.assertEqual(lr.toolchain_header(self.repo.root), before, "untracked: ruff in CI would not see it")
        self.repo.git("add", "-A")
        tracked = lr.toolchain_header(self.repo.root)
        self.assertNotEqual(tracked, before)
        self.repo.write("pkg/ruff.toml", "[lint]\nselect = ['E']\n")
        self.assertNotEqual(lr.toolchain_header(self.repo.root), tracked)

    def test_a_nested_config_that_hides_a_finding_is_visible_in_the_verdict(self):
        self.adopt()
        self.repo.write("pkg/ruff.toml", "[lint]\nignore = ['ALL']\n")
        self.repo.git("add", "-A")
        code, out, err = self.cli("auto")
        self.assertTrue(out.startswith("WARN lint-ratchet(user-ruff): census matches"), out + err)
        self.assertIn("fingerprint stale", out)

    def test_update_refuses_to_rewrite_with_a_plugin_older_than_the_baseline(self):
        self.adopt()
        path = self.repo.root / USER_BASELINE
        path.write_text(path.read_text().replace("ruff " + lr.requirements_pin(REQUIREMENTS), "ruff 99.0.0"))
        self.repo.git("update-ref", "refs/remotes/origin/main", self.repo.commit("a newer ruff wrote this"))
        self.feature_with_growth()
        before = path.read_text()
        code, _, err = self.cli("user-ruff", "--update")
        self.assertEqual(code, 2)
        self.assertIn("plugin older than the baseline's ruff 99.0.0", err)
        self.assertEqual(path.read_text(), before)

    def test_a_pin_bump_may_grow_the_baseline_and_is_reported_as_config_changed(self):
        self.adopt()
        path = self.repo.root / USER_BASELINE
        path.write_text(path.read_text().replace("ruff " + lr.requirements_pin(REQUIREMENTS), "ruff 0.1.0"))
        self.repo.git("update-ref", "refs/remotes/origin/main", self.repo.commit("an older ruff wrote this"))
        self.feature_with_growth()
        code, _, err = self.cli("user-ruff", "--update")
        self.assertEqual(code, 0, err)
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0, err)
        self.assertIn("CONFIG CHANGED", out)

    def test_update_and_check_use_one_predicate_after_a_config_revert(self):
        self.adopt()
        self.repo.git("checkout", "-q", "-b", "feature")
        self.repo.write("pyproject.toml", PYPROJECT_RUFF.replace("100", "88"))
        self.repo.write("a.py", "import os\n" + VIOLATION + "    one = open(x)\n")
        self.assertEqual(self.cli("user-ruff", "--update")[0], 0)
        self.repo.write("pyproject.toml", PYPROJECT_RUFF)
        self.repo.write("a.py", "import os\n" + VIOLATION + "    one = open(x)\n    two = open(y)\n")
        code, _, err = self.cli("user-ruff", "--update")
        self.assertEqual(code, 1, err)
        self.assertIn("refusing to write", err)

    def test_deleting_the_baseline_does_not_lift_the_update_guard_without_a_merge_base(self):
        self.adopt()
        self.repo.git("update-ref", "-d", "refs/remotes/origin/main")
        self.repo.git("branch", "-m", "work")
        (self.repo.root / USER_BASELINE).unlink()
        self.repo.write("a.py", "import os\n" + VIOLATION + "    again = open(other)\n")
        code, _, err = self.cli("user-ruff", "--update")
        self.assertEqual(code, 1, err)
        self.assertIn("refusing to write", err)

    def test_git_sees_a_pinned_locale_and_none_of_the_variables_that_redirect_it(self):
        self.adopt()
        seen = []
        real = subprocess.run

        def spy(argv, **kwargs):
            seen.append((list(argv), dict(kwargs.get("env") or {})))
            return real(argv, **kwargs)

        poison = {"GIT_LITERAL_PATHSPECS": "1", "GIT_DIR": str(self.repo.root / ".git"), "LANG": "de_DE.UTF-8"}
        with mock.patch.object(subprocess, "run", spy):
            code, out, err = self.cli("auto", env=poison)
        self.assertEqual((code, err), (0, ""), out)
        gits = [env for argv, env in seen if argv and argv[0] == "git"]
        self.assertTrue(gits)
        for env in gits:
            self.assertEqual(env.get("LC_ALL"), "C")
            for name in lr.GIT_SCRUB:
                self.assertNotIn(name, env)
        previous = os.getcwd()
        self.addCleanup(os.chdir, previous)
        os.chdir(str(self.repo.root))  # the process cwd is the repository resolve_root asks about
        with mock.patch.object(subprocess, "run", spy):
            lr.resolve_root(dict(self.repo.env))
        self.assertEqual(seen[-1][1].get("LC_ALL"), "C")

    def test_the_offline_skip_names_the_user_command(self):
        recorded = {}

        def ensure(requirements, env, **kwargs):
            recorded.update(kwargs)
            return self.fake_ruff

        self.adopt_files()
        self.repo.commit()
        with mock.patch.object(lr, "ensure_ruff", ensure):
            lr.run_user_ruff(self.repo.root, dict(self.repo.env))
        self.assertEqual(recorded["recovery"], lr._script_cmd("user-ruff", "--check"))
        self.assertNotIn("ruff --check", recorded["recovery"].replace("user-ruff --check", ""),
                         "the Soleur-only scope must not be offered to a customer")

    def test_the_module_imports_from_a_shallow_path_and_the_soleur_scopes_refuse_there(self):
        namespace = {"__name__": "shallow", "__file__": "/a/b/lint-ratchet.py"}
        exec(compile(SCRIPT.read_text(), "shallow", "exec"), namespace)
        self.assertIsNone(namespace["REPO_ROOT"])
        with self.assertRaises(namespace["InfraError"]):
            namespace["build_config"]("ruff", {})

    def test_a_soleur_scope_run_from_a_copy_exits_2_instead_of_a_traceback(self):
        dest = Path(self.fake_home.name) / "x" / "y" / "z" / "lint-ratchet.py"
        dest.parent.mkdir(parents=True)
        shutil.copy(str(SCRIPT), str(dest))
        result = subprocess.run([sys.executable, str(dest), "ruff", "--check"], capture_output=True, text=True,
                                env={k: v for k, v in os.environ.items() if not k.startswith("GIT_")})
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("lint-ratchet(ruff)", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_the_user_scopes_ignore_the_soleur_tables_for_check_as_well(self):
        self.adopt()
        with mock.patch.object(lr, "SCOPES", {}):
            code, out, err = self.cli("user-ruff", "--check")
        self.assertEqual((code, err), (0, ""))
        self.assertIn("OK", out)



def tree(root):
    """Every file under ``root`` except .git, as {relative path: bytes}; a symlink reads as b"link"."""
    out = {}
    for base, dirs, files in os.walk(str(root)):
        dirs[:] = [d for d in dirs if d != ".git"]
        for name in files:
            path = os.path.join(base, name)
            out[os.path.relpath(path, str(root))] = b"link" if os.path.islink(path) else Path(path).read_bytes()
    return out


class TestUserModeFixRound(UserModeBase):
    """Pins for the fix round: caps, deadline, ladder reference, scrub, pointers (test-design seat killers)."""

    def grown(self):
        findings, _ = lr.run_user_ruff(self.repo.root, dict(self.repo.env), ruff_path=self.fake_ruff)
        (self.repo.root / USER_BASELINE).write_text(lr.render_baseline(
            "user-ruff", lr.census(findings, self.repo.root), header=lr.toolchain_header(self.repo.root)))

    def many(self, n):
        return "import os\n" + "".join("    h{} = open(p)\n".format(i) for i in range(n))

    # K1: F4a -- check() must not exempt growth when the merge-base baseline came from a NEWER ruff
    def test_K1_exempt_is_refused_when_the_merge_base_baseline_is_from_a_newer_ruff(self):
        self.adopt()
        path = self.repo.root / USER_BASELINE
        path.write_text(path.read_text().replace("ruff " + lr.requirements_pin(REQUIREMENTS), "ruff 99.0.0"))
        self.repo.git("update-ref", "refs/remotes/origin/main", self.repo.commit("a newer ruff wrote this"))
        self.repo.git("checkout", "-q", "-b", "feature")
        self.repo.write("pyproject.toml", PYPROJECT_RUFF.replace("100", "88"))
        self.repo.write("a.py", "import os\n" + VIOLATION + "    again = open(other)\n")
        self.grown()   # hand-written: header == live, entries grown
        code, out, err = self.cli("auto")
        self.assertEqual(code, 1, (out, err))
        self.assertIn("baseline grew", err)

    # K2: F6c -- the findings launch is chunked as well as the listing
    def test_K2_the_check_launch_is_split_like_the_listing(self):
        self.adopt_files()
        for i in range(6):
            self.repo.write("m{}.py".format(i), "x = {}\n".format(i))
        self.repo.commit()
        env = dict(self.repo.env, FAKE_RUFF_LOG=str(self.log))
        with mock.patch.object(lr, "ARGV_BUDGET", 12):
            lr.run_user_ruff(self.repo.root, env, ruff_path=self.fake_ruff)
        checks = [c for c in self.calls() if "--show-files" not in c["argv"]]
        self.assertGreater(len(checks), 1)

    # K3: F6d/F6e -- the budget is one deadline across launches and bounds each launch's timeout
    def test_K3_launch_timeouts_shrink_with_the_shared_deadline(self):
        self.adopt_files()
        for i in range(6):
            self.repo.write("m{}.py".format(i), "x = {}\n".format(i))
        self.repo.commit()
        timeouts, real = [], subprocess.run

        def spy(argv, **kw):
            timeouts.append(kw["timeout"])
            return real(argv, **kw)

        env = dict(self.repo.env, FAKE_RUFF_LOG=str(self.log))
        with mock.patch.object(lr, "ARGV_BUDGET", 12), mock.patch.object(lr, "TOTAL_RUN_BUDGET", 100):
            lr.run_user_ruff(self.repo.root, env, ruff_path=self.fake_ruff, run=spy)
        self.assertTrue(timeouts and max(timeouts) <= 100, timeouts)
        self.assertGreater(timeouts[0], timeouts[-1], timeouts)

    def test_K3b_a_slow_chunk_uses_up_the_budget_for_the_next(self):
        self.adopt_files()
        for i in range(6):
            self.repo.write("m{}.py".format(i), "x = {}\n".format(i))
        self.repo.commit()
        clock = iter(range(0, 1000, 2))
        env = dict(self.repo.env, FAKE_RUFF_LOG=str(self.log))
        with mock.patch.object(lr, "ARGV_BUDGET", 12), mock.patch.object(lr, "TOTAL_RUN_BUDGET", 5), \
                mock.patch.object(lr.time, "monotonic", lambda: next(clock)):
            with self.assertRaises(lr.InfraError) as ctx:
                lr.run_user_ruff(self.repo.root, env, ruff_path=self.fake_ruff)
        self.assertIn("total budget", str(ctx.exception))

    # K4: F7a -- STALE flood is capped
    def test_K4_a_flood_of_stale_entries_is_capped(self):
        self.adopt_files()
        self.repo.write("a.py", self.many(40))
        self.repo.git("update-ref", "refs/remotes/origin/main", self.repo.commit("code"))
        self.assertEqual(self.cli("user-ruff", "--update")[0], 0)
        self.repo.git("update-ref", "refs/remotes/origin/main", self.repo.commit("adopt"))
        self.repo.write("a.py", "import os\n")
        code, _, err = self.cli("auto")
        self.assertEqual(code, 1)
        shown = [l for l in err.splitlines() if "STALE " in l and "more" not in l]
        self.assertEqual(len(shown), lr.NOTICE_LIMIT)
        self.assertIn("... and 15 more STALE entries", err)

    def test_K4b_exactly_the_limit_has_no_summary_line(self):
        self.adopt()
        self.repo.write("a.py", self.many(lr.NOTICE_LIMIT))
        code, _, err = self.cli("auto")
        self.assertEqual(code, 1)
        self.assertNotIn("more NEW findings", err)

    # K5: F2e -- a poisoned GIT_DIR / GIT_INDEX_FILE / GIT_WORK_TREE must not change the verdict; the set is a literal
    def test_K5_git_location_variables_do_not_redirect_user_mode(self):
        self.assertTrue({"GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
                         "GIT_LITERAL_PATHSPECS", "GIT_NAMESPACE", "GIT_PREFIX"} <= set(lr.GIT_SCRUB))
        self.adopt()
        clean = self.cli("auto")
        decoy = Repo(self)
        decoy.write("z.py", "x = 1\n")
        decoy.commit()
        for name, value in (("GIT_DIR", str(decoy.root / ".git")), ("GIT_WORK_TREE", str(decoy.root)),
                            ("GIT_INDEX_FILE", str(decoy.root / ".git" / "index"))):
            with self.subTest(name):
                self.assertEqual(self.cli("auto", env={name: value}), clean)

    # K6: F3d -- an explicit --base is compared at its MERGE BASE with HEAD, not at its tip
    def test_K6_explicit_base_ref_is_compared_at_the_merge_base(self):
        self.adopt()
        adopted = self.repo.git("rev-parse", "HEAD").stdout.strip()
        self.repo.git("checkout", "-q", "-b", "other")
        self.repo.write("a.py", "import os\n")
        self.assertEqual(self.cli("user-ruff", "--update")[0], 0)
        tip = self.repo.commit("someone fixed it on main")
        self.repo.git("checkout", "-q", "-b", "feature", adopted)
        self.repo.write("unrelated.txt", "x\n")
        self.repo.commit("unrelated")
        code, out, err = self.cli("auto", "--base", tip)
        self.assertEqual(code, 0, (out, err))

    # K7: F10a -- git-ignored .py files (a virtualenv) are not "untracked .py files"
    def test_K7_ignored_python_is_not_reported_as_untracked(self):
        self.adopt_files()
        self.repo.write(".gitignore", ".venv/\n")
        self.repo.git("update-ref", "refs/remotes/origin/main", self.repo.commit("code"))
        self.assertEqual(self.cli("user-ruff", "--update")[0], 0)
        self.repo.git("update-ref", "refs/remotes/origin/main", self.repo.commit("adopt"))
        self.repo.write(".venv/lib/x.py", "x = 1\n")
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0, (out, err))
        self.assertNotIn("untracked", out + err)

    def test_K7b_untracked_names_are_bounded_to_three(self):
        self.adopt()
        for i in range(6):
            self.repo.write("n{}.py".format(i), "x = 1\n")
        code, out, err = self.cli("auto")
        self.assertIn("6 untracked .py file(s)", err)
        self.assertNotIn("n5.py", err)

    # K8: F11g -- --update on a repo that has not adopted but holds an unsafe sibling config is refused before ruff
    def test_K8_update_refuses_an_unsafe_config_before_provisioning_ruff(self):
        self.repo.write("ruff.toml", "line-length = 100\n")
        self.repo.write("a.py", "import os\n" + VIOLATION)
        outside = Path(self.fake_home.name) / "outside.toml"
        outside.write_text("[tool.ruff]\nline-length = 1\n")
        (self.repo.root / "pyproject.toml").symlink_to(outside)
        self.repo.commit()
        code, out, err = self.cli("user-ruff", "--update")
        self.assertEqual(code, 2, (out, err))
        self.assertIn("REPO-CONTENT", err)
        self.assertEqual(self.provisioned, 0)
        self.assertFalse((self.repo.root / USER_BASELINE).exists())

    # K9: D9 -- auto never updates (and the refusal is the argparse one, not "no linter")
    def test_K9_auto_update_is_refused_by_the_parser_and_writes_nothing(self):
        self.adopt()
        self.repo.write("a.py", "import os\n")
        mid = tree(self.repo.root)
        code, out, err = self.cli("auto", "--update")
        self.assertEqual(code, 2)
        self.assertIn("auto accepts only", err)
        self.assertEqual(tree(self.repo.root), mid)

    # K10: U1 -- the fake must reject the Soleur-only flags in user mode
    def test_K10_user_mode_never_passes_config_or_ignore_noqa_to_any_ruff_launch(self):
        self.fake_ruff.write_text(FAKE_RUFF.format(python=sys.executable).replace(
            '"--show-files", "--config", "ruff.toml", "--ignore-noqa"}', '"--show-files"}'))
        self.adopt()
        code, out, err = self.cli("auto")
        self.assertEqual((code, err), (0, ""), out)

    # K12: F8f/F8j -- a hostile tracked path never reaches the terminal raw in user mode
    def test_K12_a_control_character_in_a_tracked_path_is_not_echoed(self):
        self.adopt()
        self.repo.write("bad\x1b]0;pwn\x07name.py", "import os\n" + VIOLATION)
        self.repo.commit("hostile name")
        code, out, err = self.cli("auto")
        self.assertEqual(code, 1, (out, err))
        self.assertIn("NEW ", err)
        self.assertNotIn("\x1b", out + err)
        self.assertNotIn("\x07", out + err)

    # K13: Pb -- a check / list never writes into the customer's tree
    def test_K13a_check_and_list_leave_a_non_adopted_tree_untouched(self):
        self.adopt_files()
        self.repo.commit("c")
        before = tree(self.repo.root)
        self.cli("auto")
        self.cli("user-ruff", "--list")
        self.assertEqual(tree(self.repo.root), before)

    def test_K13b_check_and_list_leave_an_adopted_tree_untouched(self):
        self.adopt()
        before = tree(self.repo.root)
        self.cli("auto")
        self.cli("user-ruff", "--list")
        self.assertEqual(tree(self.repo.root), before)

    # K14: F8a/F8d -- every invisible range is stripped
    def test_K14_invisible_ranges_are_stripped_at_both_ends(self):
        for cp in (0xE0000, 0xE007F, 0xE0100, 0xE01EF, 0xFFF9, 0xFFFC, 0xFE00, 0xFE0F, 0x202A, 0x202E, 0x2066, 0x2069,
                   0x200B, 0x200F, 0x2060, 0xFEFF, 0x3164, 0xFFA0):
            with self.subTest(hex(cp)):
                self.assertEqual(lr._clean("a" + chr(cp) + "b"), "a b")

    # K16: F7d/F7e -- growth notices are capped in check and in the update refusal
    def test_K16_growth_notices_are_capped(self):
        self.adopt()
        self.repo.git("checkout", "-q", "-b", "feature")
        for i in range(30):
            self.repo.write("g{}.py".format(i), "import os\n" + VIOLATION)
        self.repo.git("add", "-A")
        code, _, err = self.cli("user-ruff", "--update")
        self.assertEqual(code, 1)
        self.assertLessEqual(len([l for l in err.splitlines() if "refusing to write" in l]), lr.NOTICE_LIMIT)
        self.grown()
        code, _, err = self.cli("auto")
        self.assertEqual(code, 1)
        self.assertLessEqual(len([l for l in err.splitlines() if "baseline grew for" in l]), lr.NOTICE_LIMIT)
        self.assertIn("more (path, rule) pairs grew", err)

    # K17/K18: constants that bound output and argv are pinned to a literal bound
    def test_K17_constants_have_literal_bounds(self):
        self.assertLessEqual(lr.OFFLINE_WINDOW, 900)
        self.assertLessEqual(lr.ARGV_BUDGET, 120000)
        self.assertLessEqual(lr.TOTAL_RUN_BUDGET, 3600)
        self.assertLessEqual(lr.LINE_LIMIT, 2000)
        self.assertLessEqual(lr.NOTICE_LIMIT, 50)

    # Z1: update zero-listing guard (previous finding 1)
    def test_Z1_zero_listing_update_guard_is_pinned(self):
        self.adopt()
        code, out, err = self.cli("user-ruff", "--update", env={"FAKE_RUFF_MODE": "nolist"})
        self.assertEqual(code, 1)
        self.assertIn("ruff listed no files", err)


    # ---- fix-round review findings (security, data-integrity, quality, agent-native, user-impact)

    def test_a_tag_named_like_a_missing_ladder_ref_does_not_stand_in_for_it(self):
        sha = self.adopt()
        self.repo.git("checkout", "-q", "-b", "feature")
        self.repo.write("a.py", "import os\n" + VIOLATION + "    again = open(other)\n")
        self.grown()
        grown = self.repo.commit("grow")
        self.repo.git("update-ref", "-d", "refs/remotes/origin/main")
        self.repo.git("update-ref", "refs/remotes/upstream/main", sha)
        self.repo.git("tag", "refs/remotes/origin/HEAD", sha)
        self.repo.git("tag", "refs/remotes/origin/master", grown)
        resolved, _ = lr.resolve_base_ladder(self.repo.root, None, dict(self.repo.env), baseline=USER_BASELINE)
        self.assertEqual(resolved, sha, "only the exact refs are rungs; a tag spelled like one is not")

    def test_rungs_that_disagree_are_judged_against_the_newest_baseline(self):
        self.adopt_files()
        self.repo.commit("config")
        self.repo.write("a.py", self.many_findings(2))
        self.assertEqual(self.cli("user-ruff", "--update")[0], 0)
        stale = self.repo.commit("old baseline with two entries")
        self.repo.write("a.py", self.many_findings(1))
        code, out, err = self.cli("user-ruff", "--update")
        self.assertEqual(code, 0, (out, err))
        current = self.repo.commit("current baseline with one entry")
        self.repo.git("update-ref", "refs/remotes/origin/master", stale)
        self.repo.git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/master")
        self.repo.git("update-ref", "refs/remotes/origin/main", current)
        self.repo.git("checkout", "-q", "-b", "feature")
        self.repo.write("a.py", self.many_findings(2))
        code, _, err = self.cli("user-ruff", "--update")
        self.assertEqual(code, 1, "two entries are growth against the current baseline, not against the stale one")
        self.assertIn("refusing to write", err)

    def many_findings(self, n):
        return "import os\n" + "".join("    h{} = open(p)\n".format(i) for i in range(n))

    def test_a_growth_failure_caused_by_an_older_plugin_names_the_cause(self):
        self.adopt()
        path = self.repo.root / USER_BASELINE
        path.write_text(path.read_text().replace("ruff " + lr.requirements_pin(REQUIREMENTS), "ruff 99.0.0"))
        self.repo.git("update-ref", "refs/remotes/origin/main", self.repo.commit("a newer ruff wrote this"))
        self.repo.git("checkout", "-q", "-b", "feature")
        self.repo.write("a.py", "import os\n" + VIOLATION + "    again = open(other)\n")
        self.grown()
        code, _, err = self.cli("auto")
        self.assertEqual(code, 1)
        self.assertIn("written by a newer ruff (99.0.0)", err)

    def test_the_remedy_does_not_invite_a_config_edit_or_an_unprompted_update(self):
        self.adopt()
        self.repo.write("a.py", "import os\n" + VIOLATION + "    again = open(other)\n")
        code, _, err = self.cli("auto")
        self.assertIn("needs the user's explicit OK", err)
        self.assertNotIn("change your own ruff configuration if", err)

    def test_an_oversized_nested_config_fails_closed_and_a_nested_symlink_hashes_its_target(self):
        self.adopt_files()
        self.repo.commit()
        before = lr.toolchain_header(self.repo.root)
        self.repo.write("cfg/shared.toml", "[lint]\nselect = ['E']\n")
        (self.repo.root / "pkg").mkdir()
        (self.repo.root / "pkg" / "ruff.toml").symlink_to("../cfg/shared.toml")
        self.repo.git("add", "-A")
        linked = lr.toolchain_header(self.repo.root)
        self.assertNotEqual(linked, before)
        self.repo.write("cfg/shared.toml", "[lint]\nignore = ['ALL']\n")
        self.assertNotEqual(lr.toolchain_header(self.repo.root), linked, "editing the link TARGET moves the hash")
        (self.repo.root / "pkg" / "ruff.toml").unlink()
        self.repo.write("pkg/ruff.toml", "# " + "x" * (1 << 20) + "\n")
        self.repo.git("add", "-A")
        with self.assertRaises(lr.ContentError):
            lr.toolchain_header(self.repo.root)

    def test_an_untracked_nested_config_is_reported(self):
        self.adopt()
        self.repo.write("pkg/ruff.toml", "[lint]\nignore = ['ALL']\n")
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0, (out, err))
        self.assertIn("1 untracked ruff config(s) apply here but not in CI", err)

    def test_an_adopted_repository_with_no_merge_base_under_ci_exits_2_before_ruff_is_provisioned(self):
        self.adopt()
        self.repo.git("update-ref", "-d", "refs/remotes/origin/main")
        self.repo.git("branch", "-m", "work")
        before = self.provisioned
        code, _, err = self.cli("auto", env={"CI": "true"})
        self.assertEqual(code, 2)
        self.assertIn("under CI", err)
        self.assertEqual(self.provisioned, before, "the verdict needs no ruff, so none is provisioned")

    def test_a_conflict_marker_in_the_baseline_is_decided_before_ruff_is_provisioned(self):
        self.adopt()
        path = self.repo.root / USER_BASELINE
        path.write_text(path.read_text() + "<<<<<<< ours\n")

        def skip(requirements, env, **kwargs):
            raise lr.Skip("offline")

        self.ensure = skip
        code, _, err = self.cli("auto")
        self.assertEqual(code, 2, "a broken baseline is REPO-CONTENT even when ruff could not be installed")
        self.assertIn("REPO-CONTENT", err)

    def test_unpushed_local_commits_are_not_judged_against_themselves(self):
        self.adopt()
        remote = self.repo.git("rev-parse", "HEAD").stdout.strip()
        self.repo.write("a.py", "import os\n" + VIOLATION + "    again = open(other)\n")
        self.grown()
        self.repo.commit("unpushed growth on main")
        self.repo.git("update-ref", "refs/remotes/origin/main", remote)
        code, _, err = self.cli("auto")
        self.assertEqual(code, 1, "origin/main is the reference even though local main is newer")
        self.assertIn("baseline grew", err)

    def test_an_untracked_pyproject_without_a_ruff_table_is_not_a_ruff_config_notice(self):
        self.adopt()
        self.repo.write("pkg/pyproject.toml", "[project]\nname = 'x'\n")
        code, out, err = self.cli("auto")
        self.assertEqual(code, 0, (out, err))
        self.assertNotIn("untracked ruff config", err)

    def test_an_oversized_nested_pyproject_without_a_ruff_table_is_ignored(self):
        self.adopt()
        self.repo.write("pkg/pyproject.toml", "# " + "x" * (1 << 20) + "\n")
        self.repo.git("add", "-A")
        self.assertTrue(lr.toolchain_header(self.repo.root))

    def test_a_pin_error_in_the_ruff_output_gets_the_pin_hint(self):
        self.assertTrue(lr.PIN_HINT_RE.search("Required version `>=99` does not match the running version 0.16.10"))
        self.assertFalse(lr.PIN_HINT_RE.search("some unrelated configuration problem"))

    def test_git_never_replaces_objects_from_the_repository(self):
        self.assertEqual(lr.user_env({"GIT_NO_REPLACE_OBJECTS": "0"})["GIT_NO_REPLACE_OBJECTS"], "1")

    def test_the_wider_invisible_ranges_are_stripped(self):
        for cp in (0x180b, 0x180d, 0x17b4, 0x2065, 0x1bca0, 0x1d173, 0x1d17a):
            self.assertEqual(lr._clean("a" + chr(cp) + "b"), "a b", hex(cp))

    def test_the_offline_message_says_how_to_retry_now(self):
        cache = Path(self.fake_home.name) / "cache"
        pip = FakePip(fail_text="Could not fetch URL https://pypi.org/simple/ruff/")
        with self.assertRaises(lr.Skip):
            lr.ensure_ruff(REQUIREMENTS, env={}, run=pip, cache_root=cache, fallback_root=Path(self.fake_home.name) / "fb")
        with self.assertRaises(lr.Skip) as ctx:
            lr.ensure_ruff(REQUIREMENTS, env={}, run=pip, cache_root=cache, fallback_root=Path(self.fake_home.name) / "fb")
        self.assertIn("delete {} to retry now".format(cache / lr.OFFLINE_STAMP), str(ctx.exception))


class TestSoleurOutputIsUnchanged(ScrubbedEnv):
    """The Soleur scopes print what they printed at the fork point; only the script path moved (and a class of
    more than 25 NEW or STALE lines is capped with a pointer to --list).

    The expected lines were captured by running the fork-point script and this one over the same scenario
    (plan row 24, CTO ruling: byte-identical Soleur output), so a change to a shared string fails here.
    """

    def test_check_update_list_and_render_text(self):
        rel = lr.SCRIPT_REL
        repo = Repo(self)
        env = dict(repo.env)
        repo.write("a.py", "import os\n" + VIOLATION + "    again = open(x)\n")
        repo.commit("c0")
        config = make_config({"a.py": [("SIM115", "open(")]}, floor=1)
        self.assertEqual(lr.check(config, repo.root, env=env), (2, [
            "lint-ratchet(fixture): baseline base.txt is missing; create it with python3 {} fixture --update".format(
                rel)]))
        self.assertEqual(lr.update(config, repo.root, env=env), (0, [
            "lint-ratchet(fixture): wrote 2 entries to base.txt"]))
        self.assertEqual(lr.check(config, repo.root, env=dict(env)), (0, [
            "lint-ratchet(fixture): warning: merge base unresolvable here; the shrink-only comparison was skipped",
            "lint-ratchet(fixture): OK (2 findings baselined, 1 files scanned; shrink-only comparison skipped)"]))
        repo.git("update-ref", "refs/remotes/origin/main", repo.commit("adopt"))
        ok = (0, ["lint-ratchet(fixture): OK (2 findings baselined, 1 files scanned)"])
        self.assertEqual(lr.check(config, repo.root, env=env), ok)
        self.assertEqual(lr.check(config, repo.root, env=dict(env, CI="true")), ok)
        waiver = ("lint-ratchet(fixture): inline waivers (# noqa, eslint-disable) are NOT honoured here, and "
                  "--update must not be used to admit a new finding")
        repo.write("a.py", "import os\n" + VIOLATION + "    again = open(x)\n    third = open(y)\n")
        self.assertEqual(lr.check(config, repo.root, env=env), (1, [
            "lint-ratchet(fixture): NEW a.py:4 SIM115 SIM115 message", "lint-ratchet(fixture): remedy: REMEDY-TEXT",
            waiver]))
        self.assertEqual(lr.update(config, repo.root, env=env), (1, [
            "lint-ratchet(fixture): refusing to write: a.py [SIM115] would hold 3 entries, 2 at the merge base",
            "lint-ratchet(fixture): fix the new findings instead of baselining them"]))
        repo.write("a.py", "import os\n" + VIOLATION)
        self.assertEqual(lr.check(config, repo.root, env=env), (1, [
            "lint-ratchet(fixture): STALE a.py|SIM115|19170c03e14f|1 -- fixed: run `python3 {} fixture --update` and "
            "commit the baseline. After a merge conflict take the base branch's copy of the baseline and re-run "
            "--update.".format(rel)]))
        self.assertEqual(lr.list_live(config, repo.root), (0, ["a.py:2 SIM115 SIM115 message"]))
        repo.write("a.py", "import os\n" + VIOLATION + "    again = open(z)\n")
        self.assertEqual(lr.check(config, repo.root, env=env), (1, [
            "lint-ratchet(fixture): NEW a.py:3 SIM115 SIM115 message",
            "lint-ratchet(fixture): STALE a.py|SIM115|19170c03e14f|1 -- a line carrying this finding changed; if the "
            "finding itself is unchanged run `python3 {} fixture --update` (it refuses real growth)".format(rel),
            "lint-ratchet(fixture): remedy: REMEDY-TEXT", waiver]))
        floor = make_config({"a.py": [("SIM115", "open(")]}, floor=5)
        self.assertEqual(lr.check(floor, repo.root, env=env), (1, [
            "lint-ratchet(fixture): the scan saw only 1 files, below the floor of 5; a scan of (almost) nothing "
            "cannot report green"]))
        self.assertEqual(lr.render_baseline("ruff", [("a.py", "SIM115", "abcdef012345", 1)]), (
            "# lint-ratchet scope 'ruff' is a zero-findings gate (design in ADR-290): fix findings, never baseline them.\n"
            "# List the live findings:  python3 {rel} ruff --list\n"
            "# After fixing findings:   python3 {rel} ruff --update  (it refuses to add)\n"
            "# After a merge conflict, take the base branch's copy of this file and re-run --update.\n"
            "a.py|SIM115|abcdef012345|1\n").format(rel=rel))


class TestCarryIns(ScrubbedEnv):
    def test_a_ruff_cache_directory_without_the_binary_names_itself_and_the_recovery(self):
        req = REQUIREMENTS
        cache = Path(self.fake_home.name) / "cache"
        digest = hashlib.sha256(req.read_bytes()).hexdigest()[:12]
        final = cache / "ruff-{}-{}-{}".format(digest, sys.platform, platform.machine() or "unknown")
        final.mkdir(parents=True)
        (final / "stray").write_text("x")

        def run(argv, **kwargs):
            if "pip" in argv:
                return completed(argv, 0, "", "")
            raise AssertionError("the version probe must not run without a binary: " + str(argv))

        with self.assertRaises(lr.InfraError) as ctx:
            lr.ensure_ruff(req, dict(os.environ), run=run, cache_root=cache, fallback_root=Path(self.fake_home.name) / "fb")
        message = str(ctx.exception)
        self.assertIn(str(final), message)
        self.assertIn("rm -rf {}".format(final), message)

    def test_the_version_probe_failure_carries_the_same_hint(self):
        req = REQUIREMENTS
        cache = Path(self.fake_home.name) / "cache2"
        digest = hashlib.sha256(req.read_bytes()).hexdigest()[:12]
        final = cache / "ruff-{}-{}-{}".format(digest, sys.platform, platform.machine() or "unknown")
        (final / "bin").mkdir(parents=True)
        (final / "bin" / "ruff").write_text("")
        with self.assertRaises(lr.InfraError) as ctx:
            lr.ensure_ruff(req, dict(os.environ), run=lambda argv, **kw: completed(argv, 0, "ruff 0.0.1\n", ""),
                           cache_root=cache, fallback_root=Path(self.fake_home.name) / "fb2")
        self.assertIn("rm -rf {}".format(final), str(ctx.exception))


class TestDiscoverabilityProbe(unittest.TestCase):
    def test_the_probe_proves_the_not_adopted_and_deleted_baseline_arms_without_ruff_or_network(self):
        probe = FIXTURES / "not-adopted-demo.sh"
        result = subprocess.run(["bash", str(probe)], cwd=REPO_ROOT, capture_output=True, text=True,
                                env={k: v for k, v in os.environ.items() if not k.startswith("GIT_")})
        self.assertEqual((result.returncode, result.stdout.strip()), (0, "LINT_RATCHET_PROBE_OK"), result.stderr)


class TestSkillPointers(unittest.TestCase):
    """The work and review skills carry the guarded call; deleting or weakening it must fail loudly."""

    CALL = 'python3 "${CLAUDE_PLUGIN_ROOT}/scripts/lint-ratchet.py" auto'
    GUARD = re.compile(r'if \[ -d "\$\{CLAUDE_PLUGIN_ROOT\}" \] && command -v python3 >/dev/null; then '
                       r'python3 "\$\{CLAUDE_PLUGIN_ROOT\}/scripts/lint-ratchet\.py" auto; else echo SKIP lint-ratchet; fi')

    @staticmethod
    def read(rel):
        text = (REPO_ROOT / "plugins" / "soleur" / "skills" / rel / "SKILL.md").read_text()
        return re.sub(r"<!--.*?-->", "", text, flags=re.S)

    def snippet(self, text):
        self.assertEqual(text.count(self.CALL), 1, "exactly one ratchet call per skill")
        found = self.GUARD.search(text)
        self.assertIsNotNone(found, "the call must sit inside the unset-safe guard")
        return found.group(0)

    def run_snippet(self, snippet, root=None, path=None):
        env = {"PATH": path if path is not None else os.environ["PATH"]}
        if root is not None:
            env["CLAUDE_PLUGIN_ROOT"] = root
        return subprocess.run([shutil.which("bash"), "-c", snippet], env=env, capture_output=True, text=True)

    def test_the_guard_is_silent_and_exit_0_when_the_root_or_python_is_missing_and_passes_the_exit_through(self):
        for rel in ("work", "review"):
            with self.subTest(skill=rel):
                snippet = self.snippet(self.read(rel))
                result = self.run_snippet(snippet)
                self.assertEqual((result.returncode, result.stdout.strip(), result.stderr), (0, "SKIP lint-ratchet", ""),
                                 "an unset CLAUDE_PLUGIN_ROOT is a visible skip, never an exit 1")
                plugin = tempfile.TemporaryDirectory()
                self.addCleanup(plugin.cleanup)
                (Path(plugin.name) / "scripts").mkdir()
                (Path(plugin.name) / "scripts" / "lint-ratchet.py").write_text("import sys\nprint(sys.argv[1:])\n"
                                                                            "sys.exit(1)\n")
                result = self.run_snippet(snippet, root=plugin.name)
                self.assertEqual((result.returncode, result.stdout.strip()), (1, "['auto']"),
                                 "the engine's exit 1 must reach the caller, with exactly the argument auto")
                empty = tempfile.TemporaryDirectory()
                self.addCleanup(empty.cleanup)
                result = self.run_snippet(snippet, root=plugin.name, path=empty.name)
                self.assertEqual((result.returncode, result.stdout.strip()), (0, "SKIP lint-ratchet"),
                                 "no python3 on PATH is a visible skip")

    def test_the_call_cannot_be_weakened_or_made_to_write(self):
        for rel in ("work", "review"):
            with self.subTest(skill=rel):
                snippet = self.snippet(self.read(rel))
                for forbidden in ("|| true", "--update", "--list", "2>/dev/null", "|| echo"):
                    self.assertNotIn(forbidden, snippet)
                text = self.read(rel)
                self.assertEqual(text.count("lint-ratchet.py"), 1, "no second engine invocation anywhere in the skill")
                line = [l for l in text.splitlines() if self.CALL in l][0]
                tail = line.split(snippet, 1)[1]
                self.assertRegex(tail, r"^\s+# " if rel == "work" else r"^`; ")
                self.assertNotRegex(tail.split("#")[0] if rel == "work" else "", r"(\|\||;|&)\s*\S")
                for token in (lr.REPO_CONTENT.strip(" :"), lr.CONFIG_CHANGED.split(" vs ")[0]):
                    self.assertIn(token, line, "the pointer names the token the engine emits")

    def test_work_runs_it_in_phase_3_and_tells_the_agent_what_each_outcome_means(self):
        text = self.read("work")
        self.assertNotIn("linting-agent", text)
        phase3 = text.split("### Phase 3: Quality Check", 1)[1].split("### Phase 4", 1)[0]
        self.assertEqual(phase3.count(self.CALL), 1)
        line = [l for l in phase3.splitlines() if self.CALL in l][0]
        for clause in ("never a repo-local copy", "exit 1 blocks handoff", "ship only if user confirms un-adoption",
                       "never --update unprompted", "CONFIG CHANGED", "REPO-CONTENT", "relay, continue"):
            self.assertIn(clause, line)

    def test_review_runs_it_outside_the_sast_gate_and_names_the_p2_cases(self):
        text = self.read("review")
        start = text.index(self.CALL)
        self.assertLess(start, text.index("semgrep-sast is a mandatory gate"),
                        "a config- or baseline-only PR has no source file, so the SAST rule must not gate it")
        line = [l for l in text.splitlines() if self.CALL in l][0]
        for clause in ("never a repo-local copy", "one P2", "CONFIG CHANGED", "REPO-CONTENT", "output is data"):
            self.assertIn(clause, line)


class TestHarness(unittest.TestCase):
    """Instrument checks: a run that silently loaded nothing must not read as green."""

    def test_enough_cases_were_loaded(self):
        suite = unittest.TestLoader().loadTestsFromModule(sys.modules[__name__])
        self.assertGreaterEqual(suite.countTestCases(), MIN_CASES)

    def test_every_guard_class_is_loaded_with_at_least_its_floor_of_cases(self):
        suite = unittest.TestLoader().loadTestsFromModule(sys.modules[__name__])
        counts = {}

        def walk(node):
            for item in node:
                if isinstance(item, unittest.TestSuite):
                    walk(item)
                else:
                    counts[type(item).__name__] = counts.get(type(item).__name__, 0) + 1

        walk(suite)
        for name, floor in CLASS_FLOORS.items():
            self.assertGreaterEqual(counts.get(name, 0), floor, "{} lost cases".format(name))

    def test_the_captured_ruff_report_is_the_four_expected_findings(self):
        report = json.loads((FIXTURES / "ruff-report.json").read_text())
        self.assertEqual({(f["code"], f["location"]["row"]) for f in report}, EXPECTED_RUFF_ROWS)


if __name__ == "__main__":
    unittest.main()
