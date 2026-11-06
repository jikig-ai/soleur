---
date: 2026-11-03
category: workflow-patterns
issue: 11810
pr: 11955
---

# Verdict-input edges, and the ~442-pair myth that blocked them for a week

**What happened.** A `.gitignore` edge declaration for `grep-q-pipe-guard.test.sh` was reverted pre-merge at #11779 on the premise that declaring it "makes the audit READ each `.gitignore`, minting ~442 accept-required pairs across 22 files." A CTO ruling on #11810 measured that the premise is mechanistically impossible: `code_pats_of` (scripts/ci-pr-affected-replay.py) admits a `^file` pattern into the naming walk only when `os.path.splitext(e)[1]` is in `CODE_EXT` — `.gitignore` has no extension, is never `pats[0]`, and can't be a `.sh|.bash` source hop. Live corroboration: `.gitignore` edges already existed on main in two other arrays (`AFFECTED_SCRIPTS_AUDIT_SUITE_READS_PATHS`, `AFFECTED_TESTS_SCRIPTS_TRIO_BASELINE_CENSUS_PATHS`) with a green ratchet — zero pairs minted. Only 7 `.gitignore` files are tracked, not 22.

**The real defect was a doctrine gap, not a pair storm.** The edge grammar's criterion ("the suite's verdict is a property of specific files") covers verdict-inputs; the audit's drain-reveal/remedy text said "declare an edge only when the suite really reads or executes the file" — which steered reviewers to accept rows for a file whose *state* feeds the verdict (`--exclude-standard` consults it instrumentally). PR #11955 widened all four statement sites (docstring, two `RATCHET_REMEDY_NEW` strings, the activation runbook) to "reads or executes, or whose state feeds its verdict".

**Two `glob:**` spellings, two different failure modes.** `glob:**/.gitignore` (slash-bearing tail) → `root-tail-slash` malformed → always-match degrade (fail-wide). `glob:**.gitignore` (no slash) → *well-formed* `root` class matching only dir-less lines — silently under-covers while looking like coverage (the worse failure). Both prohibited, for opposite reasons — three review seats converged on this when a comment attributed one mechanism to both.

**Takeaway:** when a revert cites a measured number you can't reproduce, re-derive it from the mechanism before accepting it — the number survived because the premise (edges are read) was plausible-sounding and the check (audit output diff) was never run. Squash-merges erase the evidence; the machinery's own invariants (CODE_EXT admission, live examples on main) are the reproducible record.
