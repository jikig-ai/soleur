---
title: "fix: de-flake live-repo-badge J5 re-arm interstitial transition under parallel load"
date: 2026-06-18
type: fix
issue: 5297
branch: feat-one-shot-5297-flaky-live-repo-badge-j5-rearm
lane: cross-domain
status: planned
---

# 🐛 fix: de-flake live-repo-badge J5 re-arm interstitial transition under parallel load (#5297)

## Enhancement Summary

**Deepened on:** 2026-06-18
**Agents:** verify-the-negative (claims 1-3 + React-batching mechanism), RTL-flush-precedent (Explore), test-design-reviewer.

### Key corrections from the deepen pass
1. **Root Cause mechanism corrected.** The collapse is NOT React 19 automatic batching (it does not batch across separate awaited microtask continuations). The real defect is the gate anchoring on the **body-settle flag** (`regainCommitted`, which fires before the hook's `setData(team)` continuation) plus a **coalesce-reset/continuation interleave**.
2. **Fix re-anchored.** The interstitial-only component renders `null` in the regain state → no positive DOM observable. The deterministic in-harness proof is the **fetch-mock call count** (`toHaveBeenCalledTimes(2)` before Focus #3) + `await act(async () => {})`, ordered `proof → flush → reset → focus`.
3. **Anti-false-green AC added (AC2b).** Terminal `toBeInTheDocument()` alone cannot distinguish "re-armed" from "never left" (mount-`solo` == re-revoke-`solo`); the call-count gate supplies transition-through-`false` evidence.
4. **Flush idiom pinned** to `await act(async () => {})` (codebase convention — imported in 41 web-platform test files); `setTimeout`/`vi.advanceTimers*` explicitly rejected.

### Verified facts (deepen pass)
- `live-repo-badge.tsx:25` dep array is `[data?.fellBackToSolo]` (boolean) — confirmed.
- All 5 `vi.waitFor(` sites already carry `{ timeout: 10_000 }` (5:5) — confirmed.
- React `^19.1.0`, `@testing-library/react` `^16.3.2` (`apps/web-platform/package.json`).
- `regainCommitted` (`.finally` body-settle) precedes `setData(team)` (post-`await` continuation) in `use-active-repo.ts:59-62` — confirmed.

## Overview

The test `apps/web-platform/test/live-repo-badge.test.tsx > LiveRepoBadge — J5 revocation interstitial > re-arms the interstitial on a fresh fellBackToSolo transition after dismissal (J5 safety)` flakes under full-suite parallel load (`TEST_GROUP=webplat bash scripts/test-all.sh`, forked-worker pool). It passes 5/5 in isolation. This is the documented parallel-load RTL flake class (`knowledge-base/project/learnings/test-failures/2026-06-10-parallel-load-flake-two-mechanisms-and-vacuous-absence-waits.md`).

**This is a test-only race, not a product defect.** The component (`components/dashboard/live-repo-badge.tsx`) and hook (`hooks/use-active-repo.ts`) are correct.

## Research Reconciliation — Issue Premise vs. Codebase

The issue body proposed a specific fix shape. Code-reading the *current* file (post-#5123, post-#5239) shows the premise is **partially stale** — three of its claims do not match the file as it stands today, and its proposed fix is already implemented:

| Issue-body claim | Reality on `origin/main` / current branch | Plan response |
| --- | --- | --- |
| Assertion uses `waitFor(() => expect(queryByRole('alert')).toBeNull())` | The test uses `queryByTestId("revocation-interstitial")`, never `queryByRole('alert')`. The alert role exists on the node but the test keys off the testid. | Target the real selector (`queryByTestId`/`getByTestId`). |
| Fix should "drive the re-arm via `rerender`" | The test deliberately uses **real `fetch` polls + `fireEvent.focus(window)`** to exercise the production focus-revalidation path (`useActiveRepo` polls on `window.focus`). It calls `render()` ONCE (line 109) and drives transitions via focus — in-component `dismissed` state is preserved across transitions (single mount, no remount). | **Do NOT switch to `rerender`.** Per `2026-05-11-rerender-not-remount-for-in-component-state-machine-tests.md`, `rerender` would test a stubbed-hook proxy of the boot path, not the real focus-driven `fellBackToSolo` transition. The current single-mount + focus approach is the *faithful* harness; keep it. |
| "bare `toBeNull()` wait that passes on tick 0 (vacuous)" | Every `vi.waitFor` already carries `{ timeout: 10_000 }`; the dismiss-poll already proves presence first via `findByTestId` (line 110); the regain step is anchored on a `regainCommitted` fetch-body settle flag (line 128). The #5123 + #5239 fixes already closed the vacuous-absence and budget classes. | The remaining race is NOT a vacuous absence wait — it is a **transition-midpoint commit race** (see Root Cause). Fix that, do not re-apply the already-present fix. |

Premise Validation note: issue #5297 is OPEN, title `test: flaky live-repo-badge J5 re-arm interstitial under parallel load` — matches. No blocker issues cited. No open `code-review` issues touch `live-repo-badge.test.tsx`. The cited learning file exists and is the controlling reference. The issue's *symptom* (the re-arm case flakes under load) is real and reproducible-in-principle; only its *diagnosis and proposed fix* are stale.

## Root Cause — the regain-commit gate is anchored on the wrong signal

The re-arm test drives three sequential states through one mounted component:

1. **Mount → revoked** (`solo`, `fellBackToSolo:true`) → interstitial present → user dismisses (`setDismissed(true)`).
2. **Focus #1 → regained** (`team`, `fellBackToSolo:false`) → interstitial stays hidden, no re-arm.
3. **Focus #2 → revoked again** (`solo`, `fellBackToSolo:true`) → interstitial MUST re-surface.

The re-arm mechanism is `live-repo-badge.tsx:23-25` (verified — dep array is the boolean, confirmed in deepen-pass):

```tsx
useEffect(() => {
  if (data?.fellBackToSolo) setDismissed(false);
}, [data?.fellBackToSolo]);   // dep is the BOOLEAN, fires only on value CHANGE
```

The effect re-fires `setDismissed(false)` **only when the boolean `fellBackToSolo` observably transitions value** (`true → false → true`). For the re-arm to fire, React must commit the `false` value (step 2) BEFORE the `true` value (step 3) lands. If the `team` (`false`) render never commits before the re-revoke `solo` (`true`) render, `data?.fellBackToSolo` never observably leaves `true`, the dep-keyed effect never re-runs, `dismissed` stays `true`, and the interstitial never re-appears → step-3 `vi.waitFor(getByTestId(...))` times out.

**The gate before firing Focus #2 anchors on the wrong signal.** The current gate is `await vi.waitFor(() => expect(regainCommitted).toBe(true))` (line 128). `regainCommitted` flips inside the **`team` payload's `.finally()`** (test lines 102-104) — i.e. when the fetch *json body promise* settles. But the hook's `setData(team)` runs in the continuation AFTER `await fetchActiveRepoCoalesced()` (`use-active-repo.ts:59-62`), which is a **strictly later microtask** than the body-settle `.finally`. So `regainCommitted === true` *precedes* `setData(team)`, which precedes React's commit of the `false` render, which precedes the boolean-dep effect. The gate proves the body settled, NOT that the `false` state rendered. Under forked-worker CPU starvation, the third `fireEvent.focus` + its synchronous `poll()` can interleave with the still-pending `setData(team)` continuation → the two `setData` calls (`team`-false and `solo`-true) land close enough that the `false` render is dropped/skipped → no re-arm → timeout.

**Mechanism correction (deepen-pass).** An earlier draft of this plan attributed the collapse to React 19 *automatic batching* merging `false`+`true` into one render. That is inaccurate: React 19.1.0 (`apps/web-platform/package.json`) does NOT batch `setState` calls that land in **separate awaited microtask continuations** — two distinct focus events → two distinct fetches → two separate `.then`/continuation ticks → two separate renders. The real defect is the **wrong anchor** (body-settle flag instead of render-commit) compounded by a **coalesce-reset/continuation interleave**: `__resetActiveRepoCoalesceForTests()` (test line 134) synchronously nulls the module `inFlight` latch (`use-active-repo.ts:52-53`) while the prior poll's `setData(team)` continuation may still be pending, so the new `poll()` is not coalesced and two `setData` continuations are in flight with no ordering guarantee. Both reduce to one fact: **the test never positively proves the `false` regain state committed through the component before driving the re-revoke.** The companion absence assertion `expect(queryByTestId(...)).toBeNull()` at line 131 is *also* satisfied while `dismissed===true` regardless of which value committed — so it proves nothing about the `false` transition either.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing — this is a test harness change with zero runtime/UI effect. A *false-green* (flake masked but the J5 re-arm path silently un-exercised) would be the real risk; the fix is designed to make the re-arm transition MORE deterministically exercised, not less.

**If this leaks, the user's data is exposed via:** N/A — no data path, no secret, no PII, no schema. Test-only `*.test.tsx` edit.

**Brand-survival threshold:** none, reason: test-only de-flake; no production code, data surface, or operator-facing behavior changes (not a sensitive path per preflight Check 6 regex).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1 — fix scope:** Only `apps/web-platform/test/live-repo-badge.test.tsx` is edited. No change to `components/dashboard/live-repo-badge.tsx` or `hooks/use-active-repo.ts` (this is a test-only race; product code is correct). Verify: `git diff --name-only origin/main...HEAD` lists exactly that one file.
- [ ] **AC2 — non-vacuous regain commit (re-anchored on render, not body-settle):** Before the third `fireEvent.focus` (the re-revocation), the test gates on a signal that proves the `fellBackToSolo:false` regain poll's `setData(team)` continuation actually RAN — not merely that the fetch body settled. Because the component renders `null` in the regain state (interstitial-only — there is NO positive DOM observable for the `team`/`false` state), the deterministic in-harness proof is the **fetch-mock call count**: gate Focus #3 on `await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2), { timeout: 10_000 })` (proves the regain `poll()` continuation, which is strictly downstream of `regainCommitted`, was reached) followed by a render/effect flush (`await act(async () => {})`). The bare `regainCommitted`-only gate (current line 128) is insufficient and must be replaced/augmented.
- [ ] **AC2b — positive proof the regain committed before re-revoke (anti-false-green):** The test must prove the interstitial was absent *because the regain poll committed*, not merely absent for any reason. Assert `expect(fetchMock).toHaveBeenCalledTimes(2)` BEFORE Focus #3 (regain poll provably ran), and the terminal re-surface assertion implies call-count 3. This converts "node happens to be absent" into "regain provably committed before re-revoke." Rationale: mount-state `solo` and re-revoke-state `solo` are identical, so the terminal `toBeInTheDocument()` alone cannot distinguish "re-armed" from "never left" — AC2b supplies the missing transition-through-`false` evidence.
- [ ] **AC3 — presence proven, then absence (no new vacuous wait):** Any absence assertion added or retained still follows the file's established pattern — presence proven first (`findByTestId`) OR anchored on a positive settle signal — never a bare `toBeNull()` on a node that was already absent at wait-start. The re-arm assertion at the end remains `getByTestId(...).toBeInTheDocument()` (throws-until-present → non-vacuous). The synchronous `expect(queryByTestId(...)).toBeNull()` at current line 131 is removed or converted (it is satisfied while `dismissed===true` regardless of which value committed → proves nothing).
- [ ] **AC4 — load-tolerant budget on every wait:** Every `vi.waitFor` site in the edited test (including any NEW site introduced by the fix) carries `{ timeout: 10_000 }` with the `#5113`-style comment. Verify: `grep -c "timeout: 10_000" apps/web-platform/test/live-repo-badge.test.tsx` equals the count of `vi.waitFor(` sites — `grep -c "vi.waitFor(" apps/web-platform/test/live-repo-badge.test.tsx`. (A new `vi.waitFor` inherits vitest's 1000 ms default and would re-arm the very flake the file overrides — Insight 6 of the cited learning.)
- [ ] **AC5 — typecheck clean:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [ ] **AC6 — passes in isolation (≥10/10):** `cd apps/web-platform && for i in $(seq 1 10); do ./node_modules/.bin/vitest run test/live-repo-badge.test.tsx || break; done` — all 10 green. (Isolation was already 5/5; the bar rises since the change must not regress isolation.)
- [ ] **AC7 — passes under parallel load (the actual flake repro):** `TEST_GROUP=webplat bash scripts/test-all.sh` green, run **at least 3 times** (the flake is probabilistic; a single green run is not proof). Record the run count in the PR body. Run under the default forks pool that reproduces the contention (NOT `WEBPLAT_TEST_USE_THREADS=1`). **AC7 is necessary but not sufficient** — ≥3 green runs lower the false-negative rate but cannot distinguish "race fixed" from "race masked"; it MUST be paired with AC2/AC2b (the in-flight `false`-commit proof) which is what actually proves the re-arm transition is exercised.

### Post-merge (operator)
- [ ] None. CI on `main` (`test-webplat` shard) exercises the change; no operator step. `gh pr merge --squash --auto` after review per workflow gates.

## Implementation Phases

### Phase 1 — Re-anchor the regain gate on render-commit (call-count + `act` flush) — the only change

Replace the `regainCommitted`-only gate so the `true→false` regain commit is provably reached before the third focus fires. **Prescribed fix (deepen-pass — the call-count + `act` form; do NOT settle for body-settle + bare flush):**

After Focus #1, gate the third focus on the regain poll's continuation having run, then flush React, then reset the latch, then fire:

```tsx
// regain poll (Focus #1) must have COMMITTED before re-revoke — body-settle
// (`regainCommitted`) is too early (fires before the hook's setData continuation).
// Call-count 2 proves poll()'s `setData(team)` continuation was reached.
await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2), {
  timeout: 10_000, // #5113 — tolerate forked-worker CPU starvation
});
await act(async () => {}); // drain the setData(team) commit + boolean-dep fellBackToSolo:false effect
expect(fetchMock).toHaveBeenCalledTimes(2); // AC2b: regain provably ran before re-revoke

// a FRESH revocation (false→true) must re-surface the alert
__resetActiveRepoCoalesceForTests(); // reset AFTER the flush, never before (interleave guard)
fireEvent.focus(window);
await vi.waitFor(
  () => expect(screen.getByTestId("revocation-interstitial")).toBeInTheDocument(),
  { timeout: 10_000 },
);
```

**Ordering is load-bearing — `regain-commit-proof → flush → reset latch → focus`.** The `__resetActiveRepoCoalesceForTests()` MUST come AFTER the `act` flush that drains the `setData(team)` continuation, never before: resetting `inFlight` while the prior poll's `setData(team)` continuation is still pending lets two `setData` continuations (`team`-false and `solo`-true) run concurrently with no ordering guarantee (the interleave hazard in Root Cause). The `act` flush closes that window.

- **Flush idiom — use `await act(async () => {})` (imported from `@testing-library/react`).** It flushes pending microtasks AND React's effect queue (including the boolean-dep `fellBackToSolo` effect) in one deterministic drain, no wall-clock dependency, no interaction with the hook's real cloning-poll `setInterval` (which never arms here — `repoStatus:"ready"`). `act` is the established codebase idiom (imported in 41 web-platform test files). Import it: `import { ..., act } from "@testing-library/react"`.

- **Explicitly rejected — bare `setTimeout` / `vi.advanceTimers*` / `flushPromises`-via-timers flush:** non-deterministic under forked-worker starvation (re-arms the very flake) and `vi.advanceTimers*` would pump the hook's real 2s cloning-poll `setInterval` (`use-active-repo.ts`), the wrong tool. No fake timers are installed in this file.

- **Explicitly rejected — `rerender`:** Do not convert the test to `rerender`-driven transitions. The production re-arm path is focus-revalidation through the real `useActiveRepo` hook + `fetch`; `rerender` with a stubbed hook would exercise the boot/proxy path, not the transition path (see Research Reconciliation row 2 and `2026-05-11-rerender-not-remount-for-in-component-state-machine-tests.md`). The single-mount + focus harness is correct and must be preserved.

Keep the `__resetActiveRepoCoalesceForTests()` latch resets between focus events (they force fresh fetches; removing them would re-coalesce the back-to-back focuses and break determinism — see hook docstring on `inFlight`) — only the *ordering* relative to the flush is corrected above.

### Phase 2 — Verify

Run AC5 (typecheck), AC6 (isolation ≥10×), AC7 (parallel load ≥3×) and confirm AC2/AC2b are encoded (the call-count gate + `act` flush + ordering). If AC7 still flakes after the call-count + `act` fix, the most likely cause is the flush not draining the effect — re-examine the ordering (`proof → flush → reset → focus`) before adding any further machinery; do NOT reach for `setTimeout`. Capture run counts in the PR body.

## Files to Edit
- `apps/web-platform/test/live-repo-badge.test.tsx` — the re-arm test's regain→re-revoke transition gate (lines ~122-142). Test-only.

## Files to Create
- None.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no issue whose body references `live-repo-badge.test.tsx` (checked 2026-06-18).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — test-only de-flake. The only edited file is `apps/web-platform/test/live-repo-badge.test.tsx` (no UI-surface source file, no schema, no infra, no API route). Mechanical UI-surface override did not fire (no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` in Files to Edit — the `*.test.tsx` is a test, not a UI surface).

## Risks & Mitigations

- **Risk: a NEW `vi.waitFor` inherits the 1000 ms default and re-introduces the flake.** Mitigation: AC4 mechanically asserts `timeout: 10_000` count == `vi.waitFor(` count. The new call-count gate (`vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))`) IS a `vi.waitFor` and must carry the budget — AC4 enforces this. The `await act(async () => {})` flush is NOT a `vi.waitFor` and does not affect the count. (Insight 6 of the cited learning — the #5234 trap.)
- **Risk: the fix masks the flake without exercising the re-arm (false-green).** This is the PRIMARY risk — the terminal `getByTestId(...).toBeInTheDocument()` proves end-presence, not transition-through-`false`, and mount-state `solo` is indistinguishable from re-revoke-state `solo`. Mitigation: AC2b's `toHaveBeenCalledTimes(2)`-before-Focus#3 supplies the positive proof that the regain poll committed; AC7's ≥3 contended runs are necessary but NOT sufficient on their own (see AC7).
- **Risk: coalesce-reset / continuation interleave** — resetting `inFlight` before the regain `setData(team)` continuation drains lets two `setData` continuations run concurrently with no ordering guarantee. Mitigation: Phase 1's load-bearing ordering `regain-commit-proof → act flush → reset latch → focus`; the `act` flush drains the regain continuation before the latch reset.
- **Risk: a single green parallel-load run is mistaken for proof.** Mitigation: AC7 mandates ≥3 runs and recording the count; the flake is probabilistic CPU starvation (cited learning Insight 1), so one run proves little.
- **Risk: over-fix — touching product code or switching to `rerender`/`setTimeout`.** Mitigation: AC1 pins the diff to the single test file; Phase 1 "Explicitly rejected" forbids `rerender`, bare `setTimeout`, and `vi.advanceTimers*`.

## Test Strategy

Runner is **vitest 4.1.0** (`apps/web-platform/package.json` `scripts.test: "vitest"`; `bunfig.toml` blocks `bun test` discovery via `pathIgnorePatterns = ["**"]`). Isolated invocation: `cd apps/web-platform && ./node_modules/.bin/vitest run test/live-repo-badge.test.tsx`. The component project (happy-dom) collects `test/**/*.test.tsx` (`vitest.config.ts:64`) — the file is in-scope. Full-suite contended repro: `TEST_GROUP=webplat bash scripts/test-all.sh` (forks pool default; `WEBPLAT_TEST_USE_THREADS=1` opts into threads). No new test file, no new framework, no new dependency.

## References

- `knowledge-base/project/learnings/test-failures/2026-06-10-parallel-load-flake-two-mechanisms-and-vacuous-absence-waits.md` — controlling learning: vacuous-absence-wait class, settle-anchor pattern, timeout-hierarchy nesting (10 s < 16 s testTimeout < 60 s hook), Insight 6 (carry `{ timeout }` to new `vi.waitFor` sites).
- `knowledge-base/project/learnings/test-failures/2026-05-11-rerender-not-remount-for-in-component-state-machine-tests.md` — why this test must NOT use `rerender`; in-component `dismissed` state is preserved across the single-mount focus transitions.
- `knowledge-base/project/learnings/test-failures/2026-04-28-chat-input-xhr-flake-and-negative-space-assertion.md` — replace real-clock waits with explicit triggers between `await waitFor` assertions so intermediate state is provably observed under parallel load; the "prove the transition, don't assume it" lens that motivates AC2b (note: that learning's batching applies to same-tick timer flushes, not the separate-continuation case here — see Mechanism correction).
- `knowledge-base/project/learnings/runtime-errors/2026-04-03-useeffect-race-optimistic-flag-vs-server-ack.md` — await server-acknowledged state before verifying effects downstream of it.
- Prior fixes: #5123 (timeout budgets + first-tick anchors), #5239 (dismiss absence-wait anchors). This PR closes the remaining transition-midpoint gap those left.
- Product code (correct, do not edit): `apps/web-platform/components/dashboard/live-repo-badge.tsx:23-25` (re-arm effect), `apps/web-platform/hooks/use-active-repo.ts` (focus-revalidation + `inFlight` coalescing + `__resetActiveRepoCoalesceForTests`).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This section is filled; threshold = none with a reason.)
- The re-arm `useEffect` dep is the **boolean** `data?.fellBackToSolo`, not the whole `data` object — it fires only on value change. The flake turns on whether the `false` render commits between two `true`s. NOTE: the collapse is NOT React automatic batching (React 19 does not batch across separate awaited microtask continuations — two focus events fire two separate fetches → two separate renders); it is the **wrong gate anchor** (body-settle flag, which precedes the hook's `setData` continuation) plus the **coalesce-reset interleave**. The fix re-anchors on `fetchMock` call-count + an `act` flush, ordered `proof → flush → reset → focus`.
- The terminal `getByTestId().toBeInTheDocument()` is NOT a sufficient anti-vacuity guard on its own: mount-state `solo` and re-revoke-state `solo` are identical, so it cannot tell "re-armed" from "never left." AC2b (`toHaveBeenCalledTimes(2)` before Focus #3) supplies the missing transition-through-`false` evidence. Keep both.
