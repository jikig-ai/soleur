# Learning: a ruling's cited measurements were off, and the ADR prose claimed more than either

**Issue:** #9730 (Ref #10331) · **PR:** #10844 · **Date:** 2026-10-22

## Problem

The CTO agent ruled that the 112 residual code-quality findings stay accepted and supplied an ADR-276
amendment with measured figures. Re-measuring before writing them down found three of them off: 15
tracked `knowledge-base` Python files (16), 26 ruff findings (30), SIM115 21 (20). Four review seats
then found the amendment's prose still claimed more than anyone had measured: "mostly product `.ts`
files" (the audit's only per-file sample is 4 product files against 17 test files), "fails a PR when a
rule's count grows" (the eslint pin is a ceiling with slack: 72 of 74, 179 of 192), "Note and Warning
class" (three Error-severity findings), "every other tracked Python file is under the empty baseline"
(true for ruff's five rules only), and "the type-inference rules need type-aware eslint" (core
`no-useless-assignment` and `no-dupe-keys` are type-free).

## Solution

Re-ran every figure before it entered the ADR (ruff over the 16 files; the pin values in the test file;
the hash pin in `tests/scripts/test_lint_ratchet.py`), then rewrote the amendment so each sentence is
stated at the strength it was checked: ceiling not equality, "approximate guard" not "guarded", the
single-finding rules listed, the untriaged product sites named for the 2026-11-14 re-evaluation.

## Key Insight

A decision-maker's numbers are a lead, like any agent's finding: the accept/reject outcome survived all
of this, but the prose around it was the part nobody had run a command against. Run one command per
sentence the diff adds, and prefer "was not evaluated" over "cannot" for a cost call.

## Session Errors

1. **Subagent-supplied figures were wrong in three places** (file count, finding count, SIM115 count).
   Caught by re-running ruff before writing them. **Prevention:** never copy a measured figure from an
   agent report into a committed record without re-running the command.
2. **Amendment overclaimed in five sentences** (listed above), caught by the history, pattern, security
   and code-quality seats, none of which could be satisfied by a suite. **Prevention:** for a prose-only
   PR, name the falsifying command per added claim before the panel, not after.
3. **A decision row was first classed `operator (scope)`** for what was an engineering mechanism fork,
   which would have filed an issue against the net-issue-flow gate. **Prevention:** ask whether the
   operator's brief already fixed the direction before classing a row operator.
4. **The merge-poll fence in context was stale** (exit 14, no `--fence`), stopping the poll for #10691.
   **Prevention:** extract the poll fence from the on-disk SKILL.md rather than reusing a copy held in
   context.

## Tags

category: workflow-issues
module: knowledge-base/engineering/architecture/decisions/ADR-276
