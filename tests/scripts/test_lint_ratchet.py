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

import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

from tests.scripts._git_fixture_env import git_fixture_env

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "lint-ratchet.py"
FIXTURES = REPO_ROOT / "tests" / "scripts" / "fixtures" / "lint-ratchet"
MIN_CASES = 60

# The synthetic sample and the rule rows its captured report holds (row numbers are 1-based).
SAMPLE_PY = (FIXTURES / "sample.py.txt").read_text()
EXPECTED_RUFF_ROWS = {("F401", 1), ("SIM115", 5), ("S110", 8), ("F841", 10)}


def load_module():
    spec = importlib.util.spec_from_file_location("lint_ratchet", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules["lint_ratchet"] = module
    spec.loader.exec_module(module)
    return module


lr = load_module()

VIOLATION = "    handle = open(path)\n"  # a SIM115 finding when ruff sees it


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


def make_config(findings_by_path, floor=0, file_count=None, baseline="base.txt"):
    """A scope config whose tool is a function of the repo's files.

    ``findings_by_path`` maps a relative path to a list of (rule, needle) pairs: a finding is
    produced for every line of that file containing ``needle``.
    """

    def run(root):
        out = []
        for rel, specs in findings_by_path(root).items() if callable(findings_by_path) else findings_by_path.items():
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


class TestAdapters(ScrubbedEnv):
    def _fixture_root(self):
        repo = Repo(self)
        repo.write("sample.py", SAMPLE_PY)
        repo.write("test/sample.ts", (FIXTURES / "sample.ts.txt").read_text())
        repo.write("test/sample.mjs", (FIXTURES / "sample.mjs.txt").read_text())
        return repo

    def _report(self, name, root):
        return (FIXTURES / name).read_text().replace("/__ROOT__", str(root))

    def test_ruff_adapter_reads_the_captured_report(self):
        repo = self._fixture_root()
        findings = lr.adapt_ruff(self._report("ruff-report.json", repo.root), repo.root)
        self.assertEqual({(f.rule, f.row) for f in findings}, EXPECTED_RUFF_ROWS)
        self.assertTrue(all(f.path == "sample.py" for f in findings))

    def test_ruff_adapter_keeps_the_tool_message_for_the_console(self):
        repo = self._fixture_root()
        findings = lr.adapt_ruff(self._report("ruff-report.json", repo.root), repo.root)
        self.assertTrue(all(f.message for f in findings))

    def test_ruff_adapter_rejects_garbage_and_non_lists(self):
        with self.assertRaises(lr.InfraError):
            lr.adapt_ruff("not json", Path("/x"))
        with self.assertRaises(lr.InfraError):
            lr.adapt_ruff('{"a": 1}', Path("/x"))

    def test_ruff_adapter_accepts_a_clean_empty_report(self):
        self.assertEqual(lr.adapt_ruff("[]", Path("/x")), [])

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

    def test_eslint_adapter_treats_a_fatal_parse_error_as_infrastructure(self):
        report = json.dumps([{
            "filePath": "/r/a.ts", "fatalErrorCount": 1,
            "messages": [{"ruleId": None, "fatal": True, "line": 1, "message": "Parsing error"}],
        }])
        with self.assertRaises(lr.InfraError):
            lr.adapt_eslint(report, Path("/r"))

    def test_eslint_adapter_rejects_garbage(self):
        with self.assertRaises(lr.InfraError):
            lr.adapt_eslint("{", Path("/r"))

    def test_captured_rows_hash_to_the_committed_anchor(self):
        repo = self._fixture_root()
        findings = lr.adapt_ruff(self._report("ruff-report.json", repo.root), repo.root)
        lines = SAMPLE_PY.splitlines()
        for entry, finding in zip(lr.census(findings, repo.root), sorted(findings, key=lambda f: (f.rule, f.row))):
            self.assertEqual(entry[2], lr.anchor_of(lines[finding.row - 1]))


class CheckBase(ScrubbedEnv):
    """A repository with one ruff-style file whose findings are the baseline."""

    def setUp(self):
        super().setUp()
        self.repo = Repo(self)
        self.repo.write("a.py", "import os\n" + VIOLATION)
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

    def test_failure_text_says_waivers_are_not_honoured_and_update_must_not_admit(self):
        self.seed_baseline()
        self.repo.write("a.py", "import os\n" + VIOLATION + "    other = open(path2)\n")
        _, lines = self.check()
        out = "\n".join(lines)
        self.assertIn("noqa", out)
        self.assertIn("--update", out)

    def test_empty_tool_output_makes_every_baseline_entry_stale(self):
        self.seed_baseline()
        self.repo.write("a.py", "import os\n")
        code, lines = self.check()
        out = "\n".join(lines)
        self.assertEqual(code, 1)
        self.assertIn("fixed: run", out)
        self.assertIn("--update", out)
        self.assertIn("conflict", out)

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

    def test_two_pr_duplicate_delete_leaves_a_stale_entry(self):
        # Two identical lines baselined as n=1 and n=2; after both are fixed the baseline still
        # holds n=1, which the stale message tells the contributor to regenerate.
        self.repo.write("a.py", VIOLATION + VIOLATION)
        self.seed_baseline()
        (self.repo.root / "a.py").write_text("x = 1\n")
        code, lines = self.check()
        self.assertEqual(code, 1)
        self.assertIn("fixed: run", "\n".join(lines))


class TestFloors(CheckBase):
    def _floor_config(self, floor, file_count):
        cfg = make_config(self.specs, floor=floor, file_count=file_count)
        return cfg

    def test_ruff_floor_boundary(self):
        floor = lr.SCOPES["ruff"]["floor"]
        self.assertEqual(floor, 55)
        for count, expected in ((floor - 1, 1), (floor, 0)):
            with self.subTest(count=count):
                cfg = self._floor_config(floor, count)
                self.update(cfg)
                code, _ = self.check(cfg)
                self.assertEqual(code, expected)

    def test_eslint_floor_boundary(self):
        floor = lr.SCOPES["eslint-test-dirs"]["floor"]
        self.assertEqual(floor, 105)
        for count, expected in ((floor - 1, 1), (floor, 0)):
            with self.subTest(count=count):
                cfg = self._floor_config(floor, count)
                self.update(cfg)
                code, _ = self.check(cfg)
                self.assertEqual(code, expected)

    def test_an_empty_scan_never_reports_green(self):
        cfg = make_config({}, floor=1, file_count=0)
        (self.repo.root / "base.txt").write_text(lr.render_baseline("fixture", [], "#1"))
        code, lines = self.check(cfg)
        self.assertEqual(code, 1)
        self.assertIn("scan", "\n".join(lines))

    def test_removing_finding_free_files_above_the_floor_still_passes(self):
        cfg = self._floor_config(105, 113)
        self.update(cfg)
        code, _ = self.check(cfg)
        self.assertEqual(code, 0)


class TestMergeBaseDelta(CheckBase):
    def test_baseline_absent_at_the_base_is_introduced_by_this_diff(self):
        base = self.repo.commit("no baseline yet")
        self.update()
        code, lines = self.check(base=base)
        self.assertEqual(code, 0)
        self.assertIn("introduced by this diff", "\n".join(lines))

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
            with self.subTest(ref=ref):
                code, _ = self.check(base=ref)
                self.assertEqual(code, 2)

    def test_unresolvable_base_warns_locally_and_exits_2_under_ci(self):
        self.seed_baseline()
        code, lines = self.check(base="no-such-ref-anywhere")
        self.assertEqual(code, 0)
        self.assertIn("warning", "\n".join(lines).lower())
        code, _ = self.check(base="no-such-ref-anywhere", extra_env={"CI": "true"})
        self.assertEqual(code, 2)

    def test_default_base_is_the_merge_base_with_origin_main(self):
        self.repo.git("update-ref", "refs/remotes/origin/main", self.repo.commit("root"))
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


class TestToolFailures(CheckBase):
    def test_tool_failure_is_infrastructure(self):
        self.seed_baseline()

        def boom(root):
            raise lr.InfraError("ruff crashed")

        cfg = dict(self.config, run=boom)
        code, lines = self.check(cfg)
        self.assertEqual(code, 2)
        self.assertIn("ruff crashed", "\n".join(lines))

    def test_vacuous_scan_exits_1_not_2(self):
        self.seed_baseline()

        def nothing(root):
            raise lr.Vacuous("nothing to scan")

        code, lines = self.check(dict(self.config, run=nothing))
        self.assertEqual(code, 1)
        self.assertIn("vacuous", "\n".join(lines))

    def test_ruff_is_never_invoked_with_an_empty_file_list(self):
        calls = []

        def spy(argv, **kwargs):
            calls.append(argv)
            return subprocess.CompletedProcess(argv, 0, "", "")

        with self.assertRaises(lr.Vacuous):
            lr.run_ruff(self.repo.root, env=dict(self.repo.env), ruff_path=Path("/nonexistent/ruff"), run=spy)
        self.assertEqual(calls, [])

    def test_ruff_rc_other_than_0_or_1_is_infrastructure(self):
        self.repo.write("a.py", "x = 1\n")
        self.repo.git("add", "a.py")

        def crash(argv, **kwargs):
            rc = 0 if "--show-files" in argv else 2
            return subprocess.CompletedProcess(argv, rc, "a.py\n", "boom")

        with self.assertRaises(lr.InfraError):
            lr.run_ruff(self.repo.root, env=dict(self.repo.env), ruff_path=Path("/x/ruff"), run=crash)

    def test_zero_finding_clean_run_passes_with_an_empty_baseline(self):
        (self.repo.root / "a.py").write_text("x = 1\n")
        self.update()
        code, _ = self.check()
        self.assertEqual(code, 0)


class TestScopePins(unittest.TestCase):
    """Config weakening followed by --update is a legal shrink; these pins are what stops it."""

    @classmethod
    def setUpClass(cls):
        cls.toml = tomllib.loads((REPO_ROOT / "ruff.toml").read_text())

    def test_ruff_rule_set_is_pinned(self):
        self.assertEqual(set(self.toml["lint"]["select"]), {"SIM115", "S110", "S112", "F401", "F841"})

    def test_typed_except_handlers_are_checked(self):
        self.assertIs(self.toml["lint"]["flake8-bandit"]["check-typed-exception"], True)

    def test_ruff_exclusion_is_knowledge_base_only(self):
        self.assertEqual(self.toml["extend-exclude"], ["knowledge-base"])

    def test_eslint_scope_tuple_is_pinned(self):
        self.assertEqual(
            tuple(lr.SCOPES["eslint-test-dirs"]["scope"]),
            ("test/**", "plugins/soleur/test/**", "plugins/soleur/skills/*/test/**", "scripts/*.test.mjs"),
        )

    def test_floors_are_pinned(self):
        self.assertEqual(lr.SCOPES["ruff"]["floor"], 55)
        self.assertEqual(lr.SCOPES["eslint-test-dirs"]["floor"], 105)

    def test_baseline_paths_follow_the_lint_convention(self):
        for scope in lr.SCOPES.values():
            self.assertRegex(scope["baseline"], r"^scripts/lint-[a-z-]+\.baseline\.txt$")


class TestPipArgvAndRequirements(ScrubbedEnv):
    def test_requirements_pin_and_wheel_hash_count(self):
        version, hashes = lr.requirements_pin(REPO_ROOT / "scripts" / "ruff-requirements.txt")
        self.assertEqual(version, "0.16.10")
        self.assertEqual(hashes, 17)

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
    """Stands in for ``subprocess.run`` when ensure_ruff installs: records argv/env and may fail."""

    def __init__(self, test, *, version="0.16.10", fail_text=None, rc=0):
        self.test, self.version, self.fail_text, self.rc = test, version, fail_text, rc
        self.calls = []

    def __call__(self, argv, **kwargs):
        self.calls.append((list(argv), kwargs.get("env")))
        if self.fail_text is not None:
            return subprocess.CompletedProcess(argv, self.rc or 1, "", self.fail_text)
        target = Path(argv[argv.index("--target") + 1])
        (target / "bin").mkdir(parents=True)
        exe = target / "bin" / "ruff"
        exe.write_text(f"#!/bin/sh\necho 'ruff {self.version}'\n")
        exe.chmod(0o755)
        return subprocess.CompletedProcess(argv, 0, "", "")


class TestEnsureRuff(ScrubbedEnv):
    def setUp(self):
        super().setUp()
        self.cache = Path(self.fake_home.name) / "cache"
        self.req = REPO_ROOT / "scripts" / "ruff-requirements.txt"

    def ensure(self, pip, env=None):
        return lr.ensure_ruff(self.req, env=env or {}, run=pip, cache_root=self.cache)

    def test_installs_once_and_reuses_the_cache(self):
        pip = FakePip(self)
        first = self.ensure(pip)
        second = self.ensure(pip)
        self.assertEqual(first, second)
        self.assertEqual(len(pip.calls), 1)

    def test_cache_root_is_private(self):
        self.ensure(FakePip(self))
        self.assertEqual(stat.S_IMODE(self.cache.stat().st_mode), 0o700)

    def test_pip_is_run_with_a_scrubbed_environment(self):
        pip = FakePip(self)
        self.ensure(pip, env={"PIP_INDEX_URL": "http://evil", "PYTHONPATH": "/evil", "PATH": "/usr/bin"})
        _, env = pip.calls[0]
        self.assertFalse([k for k in env if k.startswith(("PIP_", "PYTHON"))])

    def test_wrong_version_after_install_is_infrastructure_never_a_fallthrough(self):
        with self.assertRaises(lr.InfraError):
            self.ensure(FakePip(self, version="9.9.9"))

    def test_hash_mismatch_is_never_a_skip(self):
        pip = FakePip(self, fail_text="THESE PACKAGES DO NOT MATCH THE HASHES FROM THE REQUIREMENTS FILE")
        for ci in ({}, {"CI": "true"}):
            with self.subTest(ci=ci), self.assertRaises(lr.InfraError):
                self.ensure(pip, env=ci)

    def test_network_failure_skips_locally_and_is_infrastructure_under_ci(self):
        pip = FakePip(self, fail_text="Could not fetch URL https://pypi.org/simple/ruff/: connection error")
        with self.assertRaises(lr.Skip) as ctx:
            self.ensure(pip)
        self.assertIn("recover with", str(ctx.exception))
        with self.assertRaises(lr.InfraError):
            self.ensure(pip, env={"CI": "true"})

    def test_symlinked_cache_root_is_refused_and_a_fresh_directory_used(self):
        real = Path(self.fake_home.name) / "real"
        real.mkdir(mode=0o700)
        self.cache.symlink_to(real)
        exe = self.ensure(FakePip(self))
        self.assertFalse(str(exe).startswith(str(real)))
        self.assertFalse(str(exe).startswith(str(self.cache)))

    def test_group_writable_cache_root_is_refused(self):
        self.cache.mkdir(mode=0o700)
        self.cache.chmod(0o770)
        exe = self.ensure(FakePip(self))
        self.assertFalse(str(exe).startswith(str(self.cache)))
        self.assertEqual(stat.S_IMODE(self.cache.stat().st_mode), 0o770, "never chmod a directory we did not create")

    def test_concurrent_install_that_already_landed_is_used(self):
        pip = FakePip(self)
        first = self.ensure(pip)
        # A second process installing into a fresh temp dir finds the final directory present.
        self.assertEqual(self.ensure(pip), first)


class TestCli(ScrubbedEnv):
    def _run(self, *args):
        env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args], cwd=REPO_ROOT, env=env, capture_output=True, text=True
        )

    def test_unknown_scope_is_a_usage_error(self):
        result = self._run("nonsense", "--check")
        self.assertEqual(result.returncode, 2)

    def test_scopes_are_the_documented_two(self):
        self.assertEqual(set(lr.SCOPES), {"ruff", "eslint-test-dirs"})

    def test_help_mentions_every_mode(self):
        result = self._run("--help")
        self.assertEqual(result.returncode, 0)
        for mode in ("--check", "--update", "--list", "--base"):
            self.assertIn(mode, result.stdout)


class TestHarness(unittest.TestCase):
    """Instrument checks: a run that silently loaded nothing must not read as green."""

    def test_enough_cases_were_loaded(self):
        suite = unittest.TestLoader().loadTestsFromModule(sys.modules[__name__])
        self.assertGreaterEqual(suite.countTestCases(), MIN_CASES)

    def test_the_captured_ruff_report_is_the_four_expected_findings(self):
        report = json.loads((FIXTURES / "ruff-report.json").read_text())
        self.assertEqual({(f["code"], f["location"]["row"]) for f in report}, EXPECTED_RUFF_ROWS)


if __name__ == "__main__":
    unittest.main()
