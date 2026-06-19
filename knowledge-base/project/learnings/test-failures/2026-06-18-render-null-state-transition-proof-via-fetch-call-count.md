---
title: "Proving a render-null state transition in RTL: fetch-call-count anchor + act flush"
date: 2026-06-18
category: test-failures
module: apps/web-platform
issue: 5297
tags: [rtl, vitest, flake, parallel-load, state-machine, act, fetch-mock]
---

# Learning: proving a transition THROUGH a render-null state in RTL

## Problem

`live-repo-badge.test.tsx > "re-arms the interstitial on a fresh fellBackToSolo
transition after dismissal"` flaked under `TEST_GROUP=webplat` forked-worker
load (passed 5/5 in isolation). The test drives one mounted component through
three states via real `fetch` polls + `fireEvent.focus(window)`:
revoked(`solo`) → dismiss → regained(`team`, `fellBackToSolo:false`) →
revoked-again(`solo`). The re-arm is a boolean-dep effect
(`live-repo-badge.tsx:23-25`, dep `[data?.fellBackToSolo]`) that only re-fires
`setDismissed(false)` when the boolean observably transitions `true→false→true`.

The gate before the re-revoke focus anchored on a **body-settle flag**
(`regainCommitted`, flipped in the team payload's `.finally()`). That flag fires
when the fetch JSON body settles — which is a *strictly earlier* microtask than
the hook's `setData(team)` continuation (the `poll` callback in
`use-active-repo.ts`). So the gate proved "the fetch body settled," NOT "the
`false` state rendered." Under CPU starvation the re-revoke focus could
interleave with the still-pending regain continuation; the `false` render was
dropped, the boolean dep never observably changed, the re-arm effect never
re-fired, and the terminal `getByTestId` timed out.

## Solution

Re-anchor on the **fetch-mock call count** (the regain fetch is call #2; its
dispatch is strictly downstream of body-settle), then drain with
`await act(async () => {})`, then reset the coalesce latch, then fire the next
focus. Ordering is load-bearing: **proof → flush → reset → focus** (resetting
`inFlight` before the flush re-opens the continuation-interleave window).

```tsx
await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2), { timeout: 10_000 });
await act(async () => {});            // drains setData(team) + the boolean-dep effect
expect(fetchMock).toHaveBeenCalledTimes(2);  // anti-false-green: regain provably ran
__resetActiveRepoCoalesceForTests();  // AFTER the flush, never before
fireEvent.focus(window);
await vi.waitFor(() => expect(screen.getByTestId(...)).toBeInTheDocument(), { timeout: 10_000 });
expect(fetchMock).toHaveBeenCalledTimes(3);  // re-surfaced via the re-revoke poll, not a stale render
```

## Key Insight

When a component **renders `null` in the state you need to transition THROUGH**
(an interstitial-only / hidden state), there is no positive DOM observable to
anchor on — and a wait-on-absence is vacuous (mount-`solo` is indistinguishable
from re-revoke-`solo`, so a terminal `toBeInTheDocument()` cannot tell "re-armed"
from "never left"). The deterministic in-harness proof of the transition is the
**fetch-mock call count gated before the next action**, paired with an `act`
flush to commit the intermediate render. This extends the settle-anchor
principle of [[2026-06-10-parallel-load-flake-two-mechanisms-and-vacuous-absence-waits]]
to the no-DOM-observable case: anchor on the signal that proves the *commit*
(the downstream `setData` continuation), not the one that proves the *fetch
body settled*.

Corollaries:
- `act(async () => {})` is the correct flush (drains microtasks + React's effect
  queue deterministically); reject `setTimeout`/`vi.advanceTimers*` — they are
  non-deterministic under load and pump the hook's real cloning-poll interval.
- Keep the single-mount + focus harness; do NOT switch to `rerender`
  (see [[2026-05-11-rerender-not-remount-for-in-component-state-machine-tests]]) —
  `rerender` would test a stubbed-hook proxy, not the real focus-revalidation path.
- The issue body's proposed fix (`queryByRole('alert')` + `rerender`) was already
  superseded by prior PRs (#5123/#5239). Issue-body diagnoses for flakes are
  hypotheses — code-read the *current* file before implementing; the proposed fix
  may already be shipped and the real mechanism different.

## Session Errors

1. **Planning subagent's initial `Write` targeted the main checkout path; the
   worktree-guard hook redirected it.** Recovery: re-wrote to the worktree path.
   Prevention: none needed — this is the worktree-guard hook working as designed
   (fail-closed redirect). One-off, not recurring.

## Tags
category: test-failures
module: apps/web-platform
