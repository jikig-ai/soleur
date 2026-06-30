---
title: "vi.waitFor floor raise vs a component re-arm effect-race (two mechanisms, one symptom)"
date: 2026-06-30
category: test-failures
module: apps/web-platform
issue: 5796
tags: [vitest, vi-waitfor, flake, react-effects, absence-wait, ci-deploy-gate]
related:
  - 2026-06-10-parallel-load-flake-two-mechanisms-and-vacuous-absence-waits.md
---

# vi.waitFor floor raise vs a component re-arm effect-race

## Problem

The `test-webplat` CI shard intermittently failed RTL/jsdom tests with `vi.waitFor`
timeouts, fail-closing `await-ci` → silently skipping prod `deploy` + `live-verify`
for every PR (#5796). Two **independent** mechanisms hid behind the one symptom:

1. **Bare `vi.waitFor` sites at the 1s default.** vitest's `vi.waitFor` is a
   distinct mechanism from RTL's `asyncUtilTimeout` (raised to 10s by #5113) and
   has **no global config knob**, so ~47 sites stayed at the 1000ms default and
   tripped under forked-worker CPU contention.
2. **A component re-arm effect-race on an EXPLICIT-10s absence-wait.** The cited
   CI failure (`live-repo-badge.test.tsx`) was an absence-wait that *already*
   carried `{ timeout: 10_000 }` — so raising the floor could not touch it, and
   it timed out at the **full 10s** (the condition never settled, ~10% of runs).

## Solution

- **Mechanism 1 — recurrence-proof floor.** Wrap the `vi.waitFor` singleton at
  setup-file top-level (in BOTH `setup-dom.ts` and `setup-node.ts`) to raise its
  default to 10s. Extracted to one shared `test/helpers/install-vi-waitfor-floor.ts`
  (mirrors the `test/helpers/engines-floor.ts` precedent; under `test/helpers/`
  so it dodges the vitest include glob). Explicit per-site timeouts still win
  (resolve the timeout explicitly so `{ timeout: undefined }` falls back to the
  floor, not the 1s default). Approach chosen over a 42-site per-site sweep
  because it is recurrence-proof — a new bare `vi.waitFor` cannot re-arm the flake.
- **Mechanism 2 — root-cause the component, not the test.** `LiveRepoBadge`'s
  re-arm effect fired `setDismissed(false)` on EVERY render where
  `fellBackToSolo` was true, including the initial mount (`undefined→true`).
  React runs that passive effect **after commit**, so ~10% of the time it landed
  *after* the user's dismiss click and undid the dismissal → interstitial
  re-surfaced → absence-wait timed out. Fix: gate the re-arm on a genuine
  `false→true` transition via a `prevValue` ref. Behavior-preserving (the mount
  reset was a no-op on already-false `dismissed`) and a real UX correctness win.

## Key Insight

**An intermittent absence-wait that times out at the FULL (explicit) timeout is a
component/state race, NOT a timeout-floor problem — raising timeouts cannot fix
it.** Discriminator: check whether the failing `vi.waitFor` site already carries
an explicit timeout. If it does, the floor-raise is irrelevant; trace the
component's effect ordering. A passive effect that resets state on *every* render
where a condition holds (rather than on a `prev→curr` transition) races any user
action that should win — gate such effects on the transition, not the current
value.

Corollary: when a test's order-fragile `mockResolvedValueOnce` queue races a
hook that polls on mount/focus, drive responses off a **mutable phase variable
read at `.json()` time** so stray polls are idempotent, and gate phase
transitions on call-count **deltas**, not absolute counts.

## Session Errors

1. **Planning subagent hit a session usage limit mid-Session-Summary.**
   Recovery: one-shot partial-artifact recovery — the plan + `tasks.md` were
   already on disk; resumed without re-running plan. Prevention: existing
   one-shot fallback handled it; no change needed.
2. **Throwaway vitest spike config in `/tmp` failed `Cannot find module 'vitest/config'`.**
   Recovery: place the throwaway config inside the app dir so `node_modules`
   resolves; point `include`/`setupFiles` at the `/tmp` paths. Prevention: spike
   configs that import `vitest/config` must live where the app's `node_modules`
   resolves.
3. **First flake-fix attempt (test-side phase-mock) did not fix the flake.** The
   phase-mock hardened the queue but the dismiss-wait still failed at 10s —
   because the root cause was the component effect-race, not the queue. Recovery:
   read the failure line (explicit-10s site) → realized the floor/queue couldn't
   be it → traced the component effect. Prevention: this learning's Key Insight —
   check the failing site's explicit timeout FIRST.
4. **nav-states Playwright visual gate could not run locally** ("does not support
   chromium on ubuntu26.04-x64"; failure at browser-launch, not assertion).
   Recovery: discriminated as a local-env limitation per the #5009 learning
   (untouched test + launch-layer failure + logic-only diff); CI's containerized
   `e2e` job is authoritative. Prevention: already documented.
5. **Bash summary-parsing grep tripped on ANSI escape codes** (false "FAIL"
   reports). Recovery: `sed 's/\x1b\[[0-9;]*m//g'` + count failed-test markers
   directly. Prevention: strip ANSI before parsing vitest summaries in shell.
