#!/usr/bin/env python3
"""Tests for scripts/lint-ratchet.py (PR3a of #10331).

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
import unittest
from pathlib import Path
from unittest import mock

try:
    import tomllib
except ModuleNotFoundError:  # Python < 3.11: the ruff.toml pin class below is skipped
    tomllib = None

from tests.scripts._git_fixture_env import git_fixture_env

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "lint-ratchet.py"
FIXTURES = REPO_ROOT / "tests" / "scripts" / "fixtures" / "lint-ratchet"
MIN_CASES = 60

# The synthetic sample and the rule rows its captured report holds (row numbers are 1-based).
SAMPLE_PY = (FIXTURES / "sample.py.txt").read_text()
EXPECTED_RUFF_ROWS = {("F401", 1), ("SIM115", 5), ("S110", 8), ("F841", 10)}

# sha256 of apps/web-platform/eslint.test-dirs.config.mjs. Weakening a rule or an ignore pattern
# there is a legal shrink of the baseline, so the file is pinned: changing it is a two-file edit.
# Re-pin with: sha256sum apps/web-platform/eslint.test-dirs.config.mjs
ESLINT_CONFIG_SHA256 = "f36b6eeb53eb23ce4ee9fbc7f6fdb9df5d3500a0a68419d34e4d44cac5023c29"


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
            "-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid",
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
        "drawdown": "#1",
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
        text = lr.render_baseline("ruff", [], "#1")
        for code in ("SIM115", "S110", "S112", "F401", "F841", "no-unused-vars"):
            self.assertNotIn(code, text)

    def test_rendered_header_documents_the_recovery_path(self):
        text = lr.render_baseline("ruff", [], "#1")
        self.assertIn("--update", text)
        self.assertIn("--list", text)
        self.assertIn("conflict", text)
        self.assertIn("#1", text)

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
        text = lr.render_baseline("fixture", lr.census(findings, self.repo.root), "#1")
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
        (self.repo.root / "base.txt").write_text(lr.render_baseline("fixture", [], "#1"))
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
        (self.repo.root / "base.txt").write_text(lr.render_baseline("fixture", [], "#1"))
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
        (self.repo.root / "base.txt").write_text(lr.render_baseline("fixture", sorted(hand), "#1"))
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
        (self.repo.root / "base.txt").write_text(lr.render_baseline("fixture", sorted(hand), "#1"))
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
        self.update(dict(self.config, recovery_cmd="RECOVER-CMD"))
        path = self.repo.root / "base.txt"
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o644)
        self.assertIn("RECOVER-CMD --update", path.read_text())

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
        self.assertEqual(lr.SCRIPT_REL, "scripts/lint-ratchet.py")
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

    def test_the_drawdown_reference_is_one_constant(self):
        self.assertEqual(lr.build_config("ruff", {})["drawdown"], lr.DRAWDOWN)
        self.assertEqual(lr.build_config("eslint-test-dirs", {})["drawdown"], lr.DRAWDOWN)


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
                               r"scripts/lint-ratchet\.py ruff --check$")

    def test_both_labels_are_always_on(self):
        text = (REPO_ROOT / "scripts" / "lib" / "test-affected-paths.sh").read_text()
        for label in ("scripts/lint-ratchet-ruff-live", "tests/scripts/lint-ratchet"):
            self.assertRegex(text, r'(?m)^\s*"%s"$' % re.escape(label))

    def test_lefthook_entries_run_the_scopes_unconditionally(self):
        text = (REPO_ROOT / "lefthook.yml").read_text()
        for key, scope in (("ruff-ratchet", "ruff"), ("eslint-test-dirs-ratchet", "eslint-test-dirs")):
            block = self.block(text, key)
            self.assertRegex(block, r"(?m)^      run: python3 scripts/lint-ratchet\.py %s --check$" % re.escape(scope))
            for forbidden in ("skip:", "exclude:", "|| true", "only:"):
                self.assertNotIn(forbidden, block)

    def test_lefthook_ruff_globs_are_exactly_the_scope_plus_the_inputs(self):
        block = self.block((REPO_ROOT / "lefthook.yml").read_text(), "ruff-ratchet")
        globs = re.findall(r'(?m)^        - "([^"]+)"$', block)
        expected = []
        for pattern in lr.SCOPES["ruff"]["scope"]:
            expected += [pattern, "**/" + pattern]
        expected += ["ruff.toml", "scripts/ruff-requirements.txt", lr.SCOPES["ruff"]["baseline"]]
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
        self.assertIn('"scripts/lint-ratchet.py", "eslint-test-dirs", "--check"', arm)
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
        path = REPO_ROOT / "scripts" / "ruff-requirements.txt"
        self.assertEqual(lr.requirements_pin(path), "0.16.10")
        self.assertEqual(len(re.findall(r"--hash=sha256:[0-9a-f]{64}", path.read_text())), 17)

    def test_requirements_have_no_trailing_comment_after_a_continuation(self):
        for line in (REPO_ROOT / "scripts" / "ruff-requirements.txt").read_text().splitlines():
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
            digest = hashlib.sha256((REPO_ROOT / "scripts" / "ruff-requirements.txt").read_bytes()).hexdigest()[:12]
            final = target.parent / "ruff-{}-{}-{}".format(digest, sys.platform, platform.machine() or "unknown")
            shutil.copytree(str(target), str(final))
        return result


class TestEnsureRuff(ScrubbedEnv):
    def setUp(self):
        super().setUp()
        self.cache = Path(self.fake_home.name) / "cache"
        self.fallback = Path(self.fake_home.name) / "fallback"
        self.req = REPO_ROOT / "scripts" / "ruff-requirements.txt"

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
        self.assertEqual([p.name for p in self.cache.iterdir()], [])

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


class TestHarness(unittest.TestCase):
    """Instrument checks: a run that silently loaded nothing must not read as green."""

    def test_enough_cases_were_loaded(self):
        suite = unittest.TestLoader().loadTestsFromModule(sys.modules[__name__])
        self.assertGreaterEqual(suite.countTestCases(), MIN_CASES)

    def test_every_guard_class_is_loaded(self):
        suite = unittest.TestLoader().loadTestsFromModule(sys.modules[__name__])
        loaded = set()

        def walk(node):
            for item in node:
                if isinstance(item, unittest.TestSuite):
                    walk(item)
                else:
                    loaded.add(type(item).__name__)

        walk(suite)
        self.assertGreaterEqual(loaded, {
            "TestEntries", "TestAdapters", "TestCheckVerdicts", "TestFloors", "TestMergeBaseDelta", "TestRunRuff",
            "TestRunEslint", "TestScopePins", "TestConfigPins", "TestRegistration", "TestPipArgvAndRequirements",
            "TestEnsureRuff", "TestMain", "TestGrowthArithmetic", "TestToolFailures", "TestHelpers"})

    def test_the_captured_ruff_report_is_the_four_expected_findings(self):
        report = json.loads((FIXTURES / "ruff-report.json").read_text())
        self.assertEqual({(f["code"], f["location"]["row"]) for f in report}, EXPECTED_RUFF_ROWS)


if __name__ == "__main__":
    unittest.main()
