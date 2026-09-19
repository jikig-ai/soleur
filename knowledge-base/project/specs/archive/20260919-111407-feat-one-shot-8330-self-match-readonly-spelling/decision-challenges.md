# Decision challenges — feat-one-shot-8330-self-match-readonly-spelling

Headless plan-review (2026-09-19). Each entry is a Taste or User-Challenge finding that was surfaced, not auto-applied; `ship` Phase 6 renders these into the PR body and files the `action-required` issue.

## 1. Scope the read-only deny to consumed-count shapes (Taste — CTO devex review)

- **Finding:** the incident class is a count feeding a loop or test. Denying bare display pipelines (`ps aux | grep nginx`) buys one noisy output line and costs a deny on the most-typed diagnostic in the repo.
- **Option A (plan as written):** deny every self-matching args-showing `ps` pipeline; the remedy text leads with the one-edit fix for a one-off look (`| grep -v grep`, `pgrep -a <name>`).
- **Option B:** deny only when the pipeline output is consumed (`grep -c`, `| wc -l`, inside `$( )`, `until`/`while`/`[`); allow bare display. Fewer rows (D3 drops), narrower property, one more grammar axis for the parser.
- **Planner's default:** A — the guard is a redirect with a self-explaining reason, and B adds a grammar axis to a hot-path parser to spare one noisy line. Operator may flip to B.

## 2. Mutation-evidence and byte-identity ACs (Taste — DHH review)

- **Finding:** AC8 (one PR-body line per Guard Contract mutation row) is prose nobody re-runs; AC6 (the `-f` reason string byte-identical to `origin/main`) is redundant with the six existing `-f` rows; the 38-row set could be cut to ~19.
- **Planner's default:** keep all three — AC8 is the repo's Guard Contract convention (`scripts/lint-guard-contract.py`, deepen-plan Phase 4.11), AC6 is a verified one-liner, and the extra rows pin fail-open arms so a future tightening is deliberate. Operator may trim.
