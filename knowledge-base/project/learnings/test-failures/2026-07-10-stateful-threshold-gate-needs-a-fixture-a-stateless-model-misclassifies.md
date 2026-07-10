---
title: "A stateful/consecutive-threshold gate needs a fixture that a simpler stateless model would misclassify — else the test is vacuous against a refactor"
date: 2026-07-10
category: test-failures
tags: [test-design, vacuous-green, mutation-testing, observability, bash]
issue: 6291
pr: 6298
module: scripts
---

# Learning: a consecutive-climb (stateful) gate needs a single-large-jump fixture to distinguish it from a max-min-delta (stateless) model

## Problem

The zot restart-loop alarm (#6291) fires condition B when `zot_restarts` **strictly increases
across ≥CLIMB_N=3 CONSECUTIVE events** — a *stateful* signal, deliberately NOT a `max-min > tol`
delta (the sibling soak probe's stateless model). The alarm and the soak probe now SHARE a parse
helper and sit right next to each other, so a future refactor could easily swap condition B to the
sibling's `max-min` model.

The unit test had a fixture for "flat" (`5,5,6,6` → GREEN) and "climbing" (`88→120→180` → FIRE).
`test-design` review **mutation-tested** the non-vacuity: it copied the sibling's `max-min > tol`
model into the checker and **the entire 15-case suite still passed**. The two existing fixtures
have delta 92 (fires) and delta 1 (green) under BOTH models, so they cannot tell the models apart.
The consecutive-climb design — the whole point of the gate — was untested.

## Solution

Add a fixture that the two models classify DIFFERENTLY: a **single large jump** `5,5,200` on the
newest boot. Under the (correct) consecutive-climb model the longest strictly-increasing run is 2
(< CLIMB_N=3) → GREEN. Under a `max-min > tol` model, max-min = 195 → FIRE. Asserting GREEN on this
fixture now walls off any refactor to the stateless model.

```
# 5,5,200 → climb run 2 < CLIMB_N=3 → GREEN, but max-min=195 → a max-min model FIRES.
assert_case "S7b single large jump 5,5,200 (max-min high, climb<N)" 0 GREEN
```

## Key Insight

For ANY gate that keys on a **stateful / order-dependent** property (consecutive-run, N-in-a-row,
sliding-window monotonicity, first-wins, streak), the test suite is vacuous against the *obvious
simpler model* unless it contains ≥1 fixture that the simpler model classifies DIFFERENTLY:

- consecutive-climb vs max-min-delta → a single large jump (high delta, short run)
- N-consecutive-failures vs any-failure → an isolated failure surrounded by successes
- sliding-window-rate vs cumulative-count → a burst that clears the window boundary
- first-directive-wins vs last-wins → two directives of the same key in one record

The cheap way to find the gap is exactly what the review agent did: **mutation-test** — mentally (or
literally) substitute the simpler model and check whether any fixture flips. If none flips, the
suite doesn't test the property. This is the stateful sibling of the RED-must-distinguish-gated-from-
ungated rule ([[2026-04-18-red-verification-must-distinguish-gated-from-ungated]]), and it is
especially load-bearing when a stateless sibling implementation lives in the same directory / shares
a helper (a refactor away).

## Session Errors

1. **Branch diverged from main mid-pipeline** (`cron-monitors.tf` + `apply-sentry-infra.yml` changed
   between branch-create and work) — caught at work Phase 0.5, rebased before implementation.
   **Prevention:** the rebase-before-work divergence gate worked as designed; rebase whenever the
   diff's edit-set files changed on main.
2. **Full scripts test-shard hung on a diff-untouched suite** ("skip-sentinel integration tests"),
   killed twice. Intermittent local resource contention (the identical shard completed for a sibling
   PR earlier in the same session; CI-clean). **Prevention:** a full-shard hang on a suite the diff
   does not touch is environmental — verify the changed surface directly (the new suite ran 16/16)
   and defer the full shard to CI's containerized `test-scripts`, don't chase it locally.
3. **`pkill -f 'test-all.sh'` killed my own verification command** (exit 144). **Prevention:** stop a
   background task via TaskStop / a captured PID, never a broad `pkill -f <pattern>` that also matches
   the currently-running shell/command.
