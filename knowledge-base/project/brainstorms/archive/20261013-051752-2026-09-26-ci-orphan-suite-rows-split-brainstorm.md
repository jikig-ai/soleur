---
title: "CI-efficiency arc residual batch — #8864 rows-split + machinery ledger dispositions"
date: 2026-09-26
status: complete
issues: [8864, 8893, 8927, 8923]
lane: cross-domain
---

# Brainstorm: CI-efficiency arc residual batch (#8864, #8893, #8927, #8923)

## What We're Building

The residual surface of the five-item CI-efficiency arc (items 1–5 merged via
#8854, #8891, #8897, #8902, #8919). Four open issues triaged in one batch:

- **#8864** — the `test-scripts` light group's worst leg is one atomic suite,
  `lint-orphan-test-suites-mutations` (588.8 s suite / ~10.2 min wall on run
  36125573947). No matrix leg count can split one suite. Implementation work.
- **#8893 / #8923** — machinery evidence records for the #8891 and #8919 review
  panels (pre-merge gate Signal 3 feeds on `code-review`-labeled issues,
  `--state all` — closed records still count).
- **#8927** — tracking bucket of #8919 duplicate-skip residuals.

Deliverable: disposition decisions for all four + a spec for the #8864
implementation.

## Why This Approach

**#8864 trigger is already fired.** The issue's re-evaluation trigger ("a leg's
suite time exceeds ~9.5 min, or the atomic suite grows past ~9.5 min") was true
at filing — 588.8 s ≈ 9.8 min. The collision constraint cleared when PR #8763
merged 2026-09-25. Nothing is left to wait for except the option choice.

**Rows-split beats move-to-heavy.** Option (b) — relocating the run_suite under
`want_scripts_heavy` — moves the *same* ~9.8 min atomic floor onto a more
expensive toolchain leg (+1 heavy runner, `suite-shard-legs-heavy.tsv` regen).
The worst-leg number does not improve; the suite *is* the floor wherever it
registers. Only splitting the suite lowers it.

**Ledger issues stay open.** CPO and CLO both suggested closing the evidence
records; the operator chose keep-open, matching the standing convention that
recent `review:` machinery records accumulate as the ledger (the gate's
`--state all` means closure wouldn't break evidence — it's a judgment call,
not a constraint).

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Implement #8864 now | Trigger already fired (588.8 s > ~9.5 min at filing); collision PR #8763 merged 2026-09-25 |
| D2 | Approach: `--rows A-B` split of `lint-orphan-test-suites.test.sh` | Copies `scripts-shard-totality-mutations.sh` precedent (DECLARED_TOTAL + range-gate); only option that lowers the floor (~5 min/legs); keeps light toolchain |
| D3 | Two half-suite registrations (`-mutations-a`/`…-b` or equivalent) | `lint-orphan-test-suites.sh` extracts the command token from `run_suite` lines — both halves union-dedupe into the same surface-1 covered set; double-coverage refusal fires only across surfaces |
| D4 | Convert MIN_ROWS=18 → DECLARED_TOTAL + range-scoped executed counter; MIN_ASSERTIONS → range-scoped | A half-run executes ~9–10 rows and would FATAL the literal floor; the precedent asserts declared-rows-reached regardless of range |
| D5 | New tiling guard: assert registered `--rows` ranges tile 1..DECLARED_TOTAL | Row added + constant bumped + range not extended = rows silently execute nowhere — the exact silent-shrink class the suite exists to catch. Anchor on the flag argument, never the label (#7103 lesson) |
| D6 | Fix stale comment at `scripts/test-all.sh:4592` ("six legs" → seven) | From deruelle's #8864 comment; was frozen under the #8763 collision, now unblocked |
| D7 | Keep #8893, #8923, #8927 open | Operator decision (overrides CPO/CLO close recommendation); #8927's items are all conditional/dormant — 2/~10 merges observed, #5780 closed, #6480 open |
| D8 | #8927: no action this batch | Skip-rate window not elapsed; merge-queue re-derivation dormant (#5780 closed); #6480 re-verify gated on an open promotion; secret-scan PR-arm gating stays tracked in #8927 |
| D9 | Registry-gate-mutation-battery split (issue option 3) deferred | Larger, separately tracked; sequence after the rows-split proves the pattern (see Non-Goals) |

## Non-Goals

- **NG1** — Option (b) move-to-heavy: rejected — relocates the floor without
  lowering it, adds a heavy runner and a TSV regen.
- **NG2** — Option (c) `registry-gate-mutation-battery` row-split (14.3–27.9
  min contention ceiling): a separate, larger DECLARED_TOTAL conversion on a
  ~860 s battery; tracked via the open reaper-battery issue, sequenced after
  this split proves the pattern.
- **NG3** — Closing or re-scoping #8893 / #8923 / #8927.
- **NG4** — Any change to the duplicate-skip machinery itself (#8919 shipped;
  residuals tracked in #8927).
- **NG5** — Merge-queue re-adoption work (dormant; #5780 closed).

## User-Brand Impact

- **Artifact:** the `test-scripts` CI shard floor / merge-gate coverage —
  specifically the `lint-orphan-test-suites-mutations` suite's row coverage.
- **Vector:** a rows-split whose ranges don't provably tile 1..DECLARED_TOTAL
  lets mutation rows execute nowhere while CI reports green — silent
  coverage loss on the merge gate every PR passes through.
- **Threshold:** single-user incident.

## Open Questions

- **Q1** — Row-boundary placement: which `--rows` split point balances the two
  halves? Rows have non-uniform cost (sandbox-per-row); plan-time measurement
  picks the boundary. Noted for the plan's measurement phase.
- **Q2** — Tiling-guard home: extend `scripts-shard-totality.test.sh`'s
  gap-detector vs. a new extractor asserting range-tiling from `run_suite`
  flag arguments. Plan decides; D5 fixes the requirement either way.
- **Q3** — Suite naming for the halves (`-mutations-a`/`-mutations-b` vs.
  row-range suffixes). Cosmetic; plan convention check.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** No disposition crosses the single-user-incident threshold — zero
user-facing surface. Option 2 (move-to-heavy) is mechanically safest; option 1
is safe *only if* split coverage is provable — a partial-row split is the one
shape that could silently weaken the merge gate. #8927 must stay open: it owns
the latent duplicate-skip over-skip risk and the open secret-scan item.
(Operator kept all three ledger issues open — broader than CPO's
close-records recommendation.)

### Legal (CLO)

**Summary:** No regulatory exposure — CI machinery, no PII/payments/credentials.
The #8919 duplicate-skip fails open toward running on every ambiguity and
*improves* the forensic trail (logs the merged-sha → PR-head → green-run
binding). Flagged #8927's secret-scan path gating as the only
compliance-weighted residual (skipped jobs must not count as coverage).
(Operator kept evidence records open — see D7.)

### Engineering (CTO)

**Summary:** Rows-split (option a) is architecturally cleanest: extraction is
command-token-anchored and union-dedupes, rows M1–M16 already run as
independent sandboxed workers under a `wait` fan-out (range gate at dispatch
is trivially safe). Mandatory conversions: DECLARED_TOTAL semantics for
MIN_ROWS/MIN_ASSERTIONS and a new tiling guard — the precedent's gap-detector
reads ci.yml matrix rows, so run_suite-carried `--rows` args need an extractor
anchored on the flag argument. Move-to-heavy buys ~nothing (suite *is* the
floor). Option (c) legitimate but bigger — sequence after (a).

## Session Errors

- Local `main` was 93 commits behind `origin/main` at session start (stale pull
  blocked by pre-existing dirty tree). All reads were taken from `origin/main`;
  the worktree was cut from it. The stale-comment line number drifted
  4578 → 4592 between issue filing and this session.
