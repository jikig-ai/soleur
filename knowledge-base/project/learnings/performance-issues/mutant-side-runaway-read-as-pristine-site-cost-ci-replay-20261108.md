---
module: CI Replay Mutation Suite
date: 2026-11-08
problem_type: performance_issue
component: testing_framework
symptoms:
  - "suite-timings ledger reported row_scan_ops site cost 47.3s; measured pristine site cost was ~4.8s"
  - "arm -b merge_group wall ~226s, the slowest gated leg (arm -c ~166s)"
  - "row_scan_ops gated site seconds 105.0 of arm -b's 188.6; row_sym 35.4"
  - "proposed fixture surgery (shrink the corpus/text axis) would have cut coverage to fix a cost the pristine SUT never had"
root_cause: logic_error
resolution_type: test_fix
severity: high
session: feat-one-shot-ci-replay-b-pacer
category: performance-issues
pr: 12419
issue: 12016
synced_to: [plan, work]
tags: [mutation-testing, performance-attribution, measurement-first, ci-replay, suite-cost-ledger]
---

# Learning: a suite's reported "site cost" can be mutant-side runaway, not pristine cost — measure the pristine site before proposing fixture surgery

## Problem

The `ci-pr-affected-replay` arm `-b` leg reported `row_scan_ops` mutant sites costing up to
**47.3 s** each (arm `-b` gated site seconds 188.6; merge_group median ~226 s, slowest of the
three arms). Read naively, the ledger says "the pristine scan is expensive", and the natural
remedy is fixture surgery — shrink the 400k-path corpus, narrow the text axis, drop fixture
sizes. Measured, the **pristine** `row_scan_ops` site runs in **~4.8 s** (post-reshape ~3.3 s).
The 47.3 s was the *mutant-side* runaway: per-start C-call mutants (encode/count/re.search/
replace at the text axis) that run one O(bytes) call per scan, with no bound other than the
line-event cap — and the give_up check only fires between reps.

## What Didn't Work

**Attempted Solution 1:** Plan-time reasoning produced a line-event cap of `12*len+5000`.

- **Why it failed:** The cap was derived, not measured. Pristine `hb` emits **485,001 events
  at 40,000 bytes (12.125/byte)** — one event over the asserted `12*len+5000` cap, which would
  have condemned pristine runs as over-bound. The shipped cap is `16*len+5000` (2x the asserted
  bound, ~1.3x hb's pristine rate). Same defect class as the headline lesson: a bound asserted
  from arithmetic instead of measured against the pristine SUT.

## Solution

1. **Attribution first:** time the pristine site before sizing the remedy. The instrumented
   `/tmp/row_scan_ops_i.py` run showed pristine ~4.8 s vs arm-cost 47.3 s — the gap IS the
   mutant pathology, so the fix targets the mutant path, not the fixture.
2. **Per-scan `give_up` returning over-bound** inside `cpu()`: every abort path returns
   elapsed/reps strictly `> give_up` and therefore `>=` the caller's verdict bound — an abort
   can never read as a pass.
3. **Cheapest-condemner ordering + early exits**: run the cheap axes first so a condemned
   mutant stops paying for the expensive legs.
4. **Text axis 48KB→768KB** (exact 16x window; small-leg pristine ~3.1 ms ≈ 3x FLOOR — blob()
   timings measured: 16384=1.03 ms too close to FLOOR, 32768=2.07, 49152≈3.1 chosen).
5. **Line-event cap** `40*len+20000` → `16*len+5000`, measured against pristine event rates
   (see above — the first draft would have failed pristine `hb`).
6. **`REPLAY_SUT_TIMEOUT` knob** on `run_sut` (default/fallback 30, clamped `>30` so it can
   only shrink the bound); `row_sym` sets 10 s → the read-opens-blocking hang dies at 10 s
   instead of 30 (~20 s/site on site 225). Harness row pins: stub-`timeout` argv log proves
   default 30 / override 2 reaches argv, plus a real 2 s hang → rc 124, plus a declared-setter
   sweep over every `REPLAY_SUT_TIMEOUT=` site.
7. **Result:** arm `-b` local wall 177 s (was ~226 s), 158/158 mutants killed, 0 survived;
   post-merge full run 1130 assertions passed, 484/484 killed. Per-start C-call mutants at the
   text axis die at 6.2–14.1x per-byte over the 3x bound — the dearest (replace) at ~8.5 s vs
   ~30 s at the old 1 MB axis.

## Why This Works

A mutation battery's timing ledger records *arm* cost: pristine run + every mutant rep + the
give_up boundary. When a mutant changes the SUT's asymptotic cost (one O(bytes) call per scan,
per start), the runaway lands inside the site's ledger row and reads as "the site is slow".
Any remedy aimed at the pristine path — smaller fixtures, narrower axes — cuts *coverage* to
treat a cost the pristine SUT never had, and leaves the mutant pathology unbounded. The
discriminating measurement is cheap: run the site once on the pristine SUT, run it once under
the worst mutant, and subtract. If pristine ≈ floor, the remedy is pacing (bounded give_up,
ordering, per-invocation timeouts) — the fixture stays.

## Session Errors

1. **No spawn tool in the planning subagent** — all prescribed fan-outs ran sequential-fallback
   inline; technical rows recorded `pending - assumed:` until the batched CTO gate
   (`cto_spawns=1`, 9 rows, zero dissents).
   - **Recovery:** recorded `Reviewed-Coverage: sequential-fallback` disclosure; batched CTO
     ruling at one spawn.
   - **Prevention:** dispatch context already pins the sequential-fallback disclosure; keep the
     `Reviewed-Coverage:` line in the PR body so the coverage claim is never over-read.
2. **precommit simulation guard blocked two `git commit` invocations.**
   - **Recovery:** separate `git add` call ahead of each commit, per the guard's contract.
   - **Prevention:** run `precommit-guard.sh` before any `git commit` in cloud/hookless shells;
     `git add` is always its own call first.
3. **Plan-ruled cap `12*len+5000` measured wrong** — would have condemned pristine `hb`
   (485,001 events at 40,000 bytes).
   - **Recovery:** re-measured pristine event rate at work time; shipped `16*len+5000`.
   - **Prevention:** same rule as the headline — a bound over a measured quantity must itself
     be measured against the pristine SUT before it is written into a plan ruling.
4. **A previous verify run was killed by a self-imposed 120 s bound** — a timeout kill is not
   a verdict.
   - **Recovery:** re-ran `python3 -I scripts/ci-pr-affected-replay.py ratchet` with no bound.
   - **Prevention:** when a verification's *verdict* is the deliverable, do not bound its wall;
     a kill rc says "unknown", never "pass" or "fail".
5. **FLOOR_ASSERTIONS forecast off by one** — review ruling projected 1129 post-merge; the
   full run measured 1130.
   - **Recovery:** the comment contract already requires re-measure on any merge; committed
     the measured 1130 (1130 passed, 484/484 killed).
   - **Prevention:** treat every forecast floor/count as provisional; the commit message
     carries the *measured* value, not the projected one.

## Key Insight

**Attribute before you amputate.** A suite ledger's per-site cost is arm cost, not pristine
cost. Fixture surgery is the right remedy only after the pristine site itself measures slow;
when pristine is cheap and the arm is expensive, the pathology is in the mutants — bound the
mutant path (per-scan give_up that returns over-bound, cheapest-condemner ordering,
per-invocation timeouts with a shrink-only knob), never the coverage.

## Prevention

- Before proposing fixture changes against a suite-cost reading, run the named site on the
  pristine SUT alone and record the number next to the arm cost in the plan.
- Any numeric bound asserted in a plan ruling (caps, floors, timeouts) gets a pristine-side
  measurement citation, or it is marked `assumed` for the work phase to measure.
- A hang inside a single SUT call emits no line events, so inter-rep give_up cannot fire —
  bound single invocations with `timeout` (here: `REPLAY_SUT_TIMEOUT`), and know the residual:
  that bound is still external, not a line-event guard.

## Related Issues

- See also: [2026-11-08-mutant-killability-and-fixture-key-scoping.md](../workflow-issues/2026-11-08-mutant-killability-and-fixture-key-scoping.md) — sibling slice (PR #12377): mutate-row construction rules for the same battery.
- Refs: epic #11556, residual #12016, adjacency #12412/#12377, stale-price umbrella #11679.
- Residual risk (pre-existing, narrowed not closed): a mutant hanging inside ONE `scan_text`
  call emits no line events → give_up can't fire → bounded only by the CI job timeout.
