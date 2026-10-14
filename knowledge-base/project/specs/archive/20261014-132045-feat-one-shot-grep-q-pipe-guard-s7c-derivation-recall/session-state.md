# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-12-chore-grep-q-wave-b-s7c-derivation-recall-plan.md
- Status: complete (plan, plan-review four-seat round and deepen-plan halts done)
- Plan artifact: complete (selector=branch)

### Errors
None blocking. Host has gawk only (mawk unmeasured locally); markdownlint scope excludes knowledge-base/project.

### Decisions
- J0 is a committed port of the guard derivation that reproduces 66 pairs and 120 triples before it measures any arm: U1 (the brief's list without any-producer) +57 pairs, U2 (with it, quote parity included) +90.
- J0 found a defect the brief did not list: a stub written `> "$d/jq"; chmod` is recorded as `jq";` and never matches (7 pairs).
- Late #10074 findings were re-measured at the merged head: window crossing and unneutered verdicts are open, one fail-open spelling is already fixed, the annotation finding is real for a pipe after the annotation string.
- Any-producer arm kept last and cuttable; reach classification precedes the awk arms.

### Components Invoked
soleur:plan, learnings-researcher, scoped advisor consult, soleur:plan-review (dhh, kieran, code-simplicity, cto), soleur:deepen-plan (mechanical halts and live citation verification; all-agent fan-out not run).

## Review round (2026-10-12; appended)

- The window-crossing control and the verdict controls (Guards 2 and 3) are closed on the head: the two findings that Phase 0.6 recorded as OPEN are fixed and have fixtures and neutered-verdict rows; the 0.6 table is the plan-time reading.
- The review round is in progress: fix round A (guard code) is pushed at `e8e91ca13b` (153 pairs, 263 triples, 154 rows); fix round B (three suite edits and these documents) follows. The figures in the Decisions block above are plan-time (66 pairs, 120 triples); see decision-challenges items 59 and 60 for the reconciliation.

## Fix round C (2026-10-12; appended)

- Review round done: seven seats read `0a8d2bd5e5..e737ea0814` plus the merge `8b43c9df5d`; twelve P2 findings, all fixed in the guard and the documents (evidence: "Post-merge and fix round C"; decisions 62 to 74). The guard is pushed on this branch; the three suites were not touched this round.
- Numbers at this head (derived on the tree): 149 pairs, 258 triples, 150 rows (21 drains, 129 exempt, 2 fenced), `SWEEP_PROBE_CHECKS=54`, 102 derivation cases, `j0-derive.py` U2 equal to the awk. Every earlier "final" figure in this directory (153 / 263 / 154, 133 exempt, BASE 67 / 126) is the `e737ea0814` state, before the merge of main retired three suites.
- The Decisions block above reads 66 pairs and 120 triples: that is the plan-time base (`0aae3f8680`), not a head.

## Fix round D (2026-10-12; appended)

- Verifier findings fixed (decision-challenges items 75 to 82; evidence "Fix round D"). Correction of the block above: "twelve P2 findings" should read fourteen (the evidence's review table sums per seat); the twelve counted distinct ones.
- Numbers at this head: see the evidence section (149 pairs, 258 triples, 150 rows, 109 derivation cases, 17 `pj_floor` floors, `SWEEP_PROBE_CHECKS=54`).
