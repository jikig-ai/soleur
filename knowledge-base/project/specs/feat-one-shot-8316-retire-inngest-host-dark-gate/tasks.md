# Tasks: retire the suite-only inngest_host_dark_gate entry point (Ref #8316)

Plan: `knowledge-base/project/plans/2026-10-14-chore-retire-inngest-host-dark-gate-entry-point-plan.md`
Decisions: `knowledge-base/project/specs/feat-one-shot-8316-retire-inngest-host-dark-gate/decision-challenges.md`
Base: `git merge-base origin/main HEAD` (planning time `b6d745fe78`). Ref #8316 only; never a closing keyword. No merge, no auto-merge.

## Phase 0 — Baseline and kill-set reference (read-only)

- [ ] 0.1 Record the base SHA; confirm the base suite is green (309 passed, `_FLOOR=309`, 37 predicates, tokens 19/19).
- [ ] 0.2 Write the mutant generator (scratch dir, not the repo): one mutant per guard-shaped non-comment line of `_ihdg_graded_row`, its helpers, `_IHDG_*`, `_ihdg_verdict`, `inngest_execute_registry_gate`, `_erg_*`; key by line content + occurrence index; require >= 100 mutants.
- [ ] 0.3 Run the list against a `git archive <base>` copy with the base suite (4-way parallel, ~15 min) -> K_main / S_main.

## Phase 1 — Library

- [ ] 1.1 Delete `inngest_host_dark_gate()` (L725-1059) and its trailing blank line.
- [ ] 1.2 Delete `_ihdg_finished_count` (L387-412 incl. comment block and one trailing blank); keep `_ihdg_decoded_rows`.
- [ ] 1.3 Rewrite the header L1-178 and the execute-gate banner prose L1062-1138 ("SECOND entry point", "BOTH entry points", "recut gate inherits") (one live entry point; retirement note with recovery SHA; G1-G7 = historical E1-E7; G8-G20 retired; positive allowlist; why-not-classify.sh kept; list dangling mentions in kept helper comments). No "kept pending retire-or-keep".
- [ ] 1.4 Confirm `dbsize` on 0 lib lines and the probe marker on 0 non-comment lines.
- [ ] 1.5 Invariance check: kept functions/assignments/comments byte-identical to base (diff of the whole lib minus header and the two deleted ranges).

## Phase 2 — Suite and workflow test (same commit as Phase 1)

- [ ] 2.1 Rewrite suite header; drop `ROWS`/`FIN`/`rows-selftest`; `GATE_FN` defaults to the execute gate; drop dark arms of `_gate_default_args`, `gate()`, `mutate()`.
- [ ] 2.2 Delete 0b, dark BASELINE, sections 1, 2/2a/2c/2b, 3 H-rows, B13, B10 rows G4-G20, section 5.
- [ ] 2.3 Keep B12 trimmed (execute fields, `B12_ERG_MSG`, schema cross-pin); keep Rows 6a/6b, re-word 6c; keep Row 9 (execute-only regex).
- [ ] 2.4 Move 0c (predicate self-test) and the `mutate` cannot-land self-test into section 6, rebound to execute fixtures.
- [ ] 2.5 Section 6/7: rename `mutate_both` -> `mutate_shared` (drop sibling args), remove `-sib` halves, the `[G2] sibling` line, 6.5 recut rows, the `GATE_FN=inngest_host_dark_gate` pair, section 7 recut rows/canary/default-path; reword "sibling"/"recut gate" comments.
- [ ] 2.6 Rebind Row 8/8b (default clock) to the execute gate unconditionally; add section 6.6 ports (E5d, E3b/E3c, M1, Row10, torn, outer, E9d, M5, M7, I1/I2, R2) only where the iterate-until-superset run (Phase 7.2) shows a lost kill.
- [ ] 2.7 Recompute `_PRED_FLOOR`, token floor, exact `_FLOOR` from a measured run; rewrite the itemised floor-history comment.
- [ ] 2.8 `cutover-inngest-workflow.test.sh` L2606-2619: reword comments, strengthen the census assertion (word-boundary strip + widened name family), add mutation rows 1-4 incl. positive control; show the old form passes row 3.

## Phase 3 — Stale prose (line-local)

- [ ] 3.1 `.github/workflows/cutover-inngest.yml` L201-206.
- [ ] 3.2 `scripts/cutover-inngest.sh` L3437.
- [ ] 3.3 `scripts/cutover-inngest.sh` L2659 (the "DOES exist (it shipped in #7695)" sentence and the earlier "inngest-volume-recut apply target" clause); `bash -n`.
- [ ] 3.4 Confirm no edit to `inngest-bootstrap.sh`, `cloud-init-inngest.yml`, `inngest-host.tf`, `vector.toml`, `inngest-cutover-flip.sh`, `inngest-server-flip-guard.sh`.

## Phase 4 — ADR-199 addendum

- [ ] 4.1 Append `## Addendum — 2026-10-14 (#8316)`; supersede by name the Status claim, commitment 1, the Consequences paragraph and the 2026-10-09 "still enforced" sentence; list the predicates with no executable form; state the future-gate requirement; cite the recovery SHA.
- [ ] 4.2 `git diff <base> -- ADR-199 | grep -c '^-[^-]'` is 0.

## Phase 5 — Derived baselines (after the final origin/main sync)

- [ ] 5.1 `bash scripts/test-affected-kb-consumers.test.sh`; `--write-baseline` only on drift.
- [ ] 5.2 `bash plugins/soleur/test/fixture-relative-assert.test.sh`; `--write-baseline` only on drift (rows 463/467).
- [ ] 5.3 `python3 scripts/regenerate-shard-manifest.py --group light --incremental` (dry): expect no change; never hand-edit TSVs; leave `*.tsv.n`.

## Phase 6 — Runbook and residual sweep

- [ ] 6.1 `inngest-server.md` L1481-1483 in-place reword; 6.2 append one dated Update.
- [ ] 6.3 One-time classified sweep of the SUBJECT names; fix live hits; record the rest in the PR body.
- [ ] 6.4 Grep the gate's pinned opaque ids (`106261946`); never touch volume `106443278`.

## Phase 7 — Differential mutation proof

- [ ] 7.1 Re-run the mutant list on the branch -> K_branch / S_branch. 7.2 K_main restricted to surviving lines is a subset of K_branch. 7.3 E1..E14 table with real mutant ids for the PR body.

## Phase 8 — PR hygiene and handoff

- [ ] 8.1 Trailers + closing-keyword scan of commit bodies. 8.2 PR title/body (`Ref #8316`, E-table, sweep, follow-up issue, final robot line); `closingIssuesReferences` is `[]` after each edit.
- [ ] 8.3 File the follow-up issue (unconsumed probe fields + two bootstrap comments, next probe_schema bump).
- [ ] 8.4 No rename in `git diff -M`; no label unless rename-guard trips and the operator agrees.
- [ ] 8.5 Targeted/affected suites only; report `ci-head-verdict.sh verdict 10268`; stop and ask before ready/merge.
- [ ] 8.6 Report #10081 status (re-read PR state/labels; whether any inngest-host-replace ran).
