---
title: "Phase 1 diagnosis: test-all-affected cost decomposition and bound-vs-split ruling"
date: 2026-10-29
status: measured
---

# Phase 1 diagnosis — `scripts/test-all-affected` (G1)

Measured from live job logs, not instrumentation. PR run 40936890587 (feat-one-shot-10585),
job `test-scripts (3/8)` id=123671386973: suite ran 19:30:31→20:00:02 = **1771 s, 248 cases**.
merge_group run 40936383604 leg equivalent, job id=123667914103: same 248 cases = **1090 s**.

## Per-row cost decomposition (from GH log line timestamps)

| family | PR s | MG s | n | content |
|---|---|---|---|---|
| th* | 620 | 382 | 85 | glob:`:` corpus census rows (#9813/#9969/#10117), real-tree `git ls-files` walks |
| q* | 242 | 141 | 29 | `--paths`/print-selection; q4 alone = **172 s** (one real-corpus `--print-selection --paths=README.md` over ~690 registrations) |
| tg* | 161 | 96 | 13 | glob hit arm |
| t* | 157 | 97 | 20 | anchored edges (#9307), real-runner invocations |
| v* | 107 | 64 | 2 | lint-orphan census mutations (~53 s each) |
| re* | 105 | 65 | 19 | registration-only classifier rows (scratch repos) |
| m* | 96 | 58 | 14 | classifier mutants |
| p/f/sc/d/s | 196 | 123 | — | remainder tail |

## Ruling: SPLIT (`--rows` label-split), not bound

The plan's decision rule: bound if divergence lives in live-IO (real-repo walk / `gh` surface);
split if it lives in divisible fixture-portable compute.

- **The PR-vs-MG delta is a uniform ~1.6× multiplier across EVERY row family** — including pure
  hermetic rows. Sibling suites on the same leg show the same factor (argv-bearer-sweep 1.58×,
  scratch-residue 1.49×, ci-push-dedupe-soak 1.44×). That is runner/machine noise, not
  diff-size scaling — a diff-scaled cost would concentrate in the real-runner rows.
- **The 337 s "main median" price is stale, not event-lower.** `test-scripts` on a `push` event
  runs as a *skipped* job (verified run 40952456513: job `test-scripts` conclusion=skipped, no
  steps). The suite has grown to 248 cases since it was priced; there is no main run to diverge
  from. The suite IS hermetic (ENV_SCRUB unsets CI; rows run in TESTROOT scratch repos or
  read-only real-repo walks).
- **The cost is ~248 divisible rows** dominated by per-arm overhead of ~5-15 s — fixture-portable
  compute. No boundable live-IO surface dominates (the largest single row, q4 at 172 s, is a
  real-corpus `--print-selection` that deals fine onto one label).

**Decision: `--rows` label-split for `scripts/test-all-affected` too**, same contract as
`ci-pr-affected-replay` — `DECLARED_TOTAL` + `in_range` site sequencing + `_EXPECTED_EXECUTED`
census + `run_suite`/`skip_suite` pairs inside the same gate arm + `_rows_tile_check` coverage
in `scripts-shard-totality.test.sh`.

Split granularity note: `test-all-affected` rows are procedural `cases++` sites (248, some
census-dynamic), not named functions — gate at **row-block level** (~42 `# ---` blocks, blocks
as sites) rather than per-case, unless a cheaper mechanism survives review.
