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

## Root Cause — the transition-midpoint commit race

The re-arm test drives three sequential states through one mounted component:

1. **Mount → revoked** (`solo`, `fellBackToSolo:true`) → interstitial present → user dismisses (`setDismissed(true)`).
2. **Focus #1 → regained** (`team`, `fellBackToSolo:false`) → interstitial stays hidden, no re-arm.
3. **Focus #2 → revoked again** (`solo`, `fellBackToSolo:true`) → interstitial MUST re-surface.

The re-arm mechanism is `live-repo-badge.tsx:23-25`:

```tsx
useEffect(() => {
  if (data?.fellBackToSolo) setDismissed(false);
}, [data?.fellBackToSolo]);   // dep is the BOOLEAN, fires only on value CHANGE
```

The effect re-fires `setDismissed(false)` **only when the boolean `fellBackToSolo` observably transitions value** (`true → false → true`). For the re-arm to fire, React must commit the `false` value (step 2) BEFORE the `true` value (step 3) lands — otherwise React batches `false`+`true` into one render, `data?.fellBackToSolo` never observably leaves `true`, the dep-keyed effect never re-runs, `dismissed` stays `true`, and the interstitial never re-appears → step-3 `vi.waitFor(getByTestId(...))` times out.

The current gate before firing Focus #2 is `await vi.waitFor(() => expect(regainCommitted).toBe(true))` (line 128). **`regainCommitted` only proves the regain fetch BODY settled — NOT that React committed `setData(team)` and ran the `fellBackToSolo:false` effect.** Under forked-worker CPU starvation, the microtask that runs `setData(team)` and the effect can lag behind the next `fireEvent.focus` + its resolving `setData(solo)`. That window is the residual flake. (The companion absence assertion `expect(queryByTestId(...)).toBeNull()` at line 131 is *also* satisfied while `dismissed===true` regardless of which value is committed — so it does not prove the `false` transition committed either.)

## User-Brand Impact

**If this lands broken, the user experiences:** nothing — this is a test harness change with zero runtime/UI effect. A *false-green* (flake masked but the J5 re-arm path silently un-exercised) would be the real risk; the fix is designed to make the re-arm transition MORE deterministically exercised, not less.

**If this leaks, the user's data is exposed via:** N/A — no data path, no secret, no PII, no schema. Test-only `*.test.tsx` edit.

**Brand-survival threshold:** none, reason: test-only de-flake; no production code, data surface, or operator-facing behavior changes (not a sensitive path per preflight Check 6 regex).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1 — fix scope:** Only `apps/web-platform/test/live-repo-badge.test.tsx` is edited. No change to `components/dashboard/live-repo-badge.tsx` or `hooks/use-active-repo.ts` (this is a test-only race; product code is correct). Verify: `git diff --name-only origin/main...HEAD` lists exactly that one file.
- [ ] **AC2 — non-vacuous regain commit:** Before the third `fireEvent.focus` (the re-revocation), the test gates on a signal that proves the `fellBackToSolo:false` regain state was COMMITTED AND RENDERED, not merely that the fetch body settled. The `regainCommitted`-only gate (current line 128) is replaced/augmented so the `true→false` transition is observably committed before the `false→true` transition is driven. (Mechanism options in Implementation; the work phase picks the simplest that satisfies the post-condition.)
- [ ] **AC3 — presence proven, then absence (no new vacuous wait):** Any absence assertion added or retained still follows the file's established pattern — presence proven first (`findByTestId`) OR anchored on a positive settle signal — never a bare `toBeNull()` on a node that was already absent at wait-start. The re-arm assertion at the end remains `getByTestId(...).toBeInTheDocument()` (throws-until-present → non-vacuous).
- [ ] **AC4 — load-tolerant budget on every wait:** Every `vi.waitFor` site in the edited test (including any NEW site introduced by the fix) carries `{ timeout: 10_000 }` with the `#5113`-style comment. Verify: `grep -c "timeout: 10_000" apps/web-platform/test/live-repo-badge.test.tsx` equals the count of `vi.waitFor(` sites — `grep -c "vi.waitFor(" apps/web-platform/test/live-repo-badge.test.tsx`. (A new `vi.waitFor` inherits vitest's 1000 ms default and would re-arm the very flake the file overrides — Insight 6 of the cited learning.)
- [ ] **AC5 — typecheck clean:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [ ] **AC6 — passes in isolation (≥10/10):** `cd apps/web-platform && for i in $(seq 1 10); do ./node_modules/.bin/vitest run test/live-repo-badge.test.tsx || break; done` — all 10 green. (Isolation was already 5/5; the bar rises since the change must not regress isolation.)
- [ ] **AC7 — passes under parallel load (the actual flake repro):** `TEST_GROUP=webplat bash scripts/test-all.sh` green, run **at least 3 times** (the flake is probabilistic; a single green run is not proof). Record the run count in the PR body. If a worker-pool override exists (`WEBPLAT_TEST_USE_THREADS=1` / forks default), run under the default forks pool that reproduces the contention.

### Post-merge (operator)
- [ ] None. CI on `main` (`test-webplat` shard) exercises the change; no operator step. `gh pr merge --squash --auto` after review per workflow gates.

## Implementation Phases

### Phase 1 — Anchor the regain transition on a committed-and-rendered signal (the only change)

Replace the regain gate so the `true→false` `fellBackToSolo` transition is provably committed before the third focus fires. Pick the **simplest** option that satisfies AC2; the work phase decides at GREEN time, but the recommended order is:

- **Option A (preferred — render-commit flush):** After Focus #1, keep waiting on `regainCommitted` AND ensure a React render/effect flush has occurred before the next focus. Concretely: `await vi.waitFor(() => expect(regainCommitted).toBe(true), { timeout: 10_000 })` followed by an explicit `act`/microtask flush so the `setData(team)` commit + `fellBackToSolo:false` effect drain before `fireEvent.focus` fires the re-revocation. The work phase verifies via AC7 whether the flush alone closes the race.

- **Option B (state-machine-faithful, if Option A is insufficient):** Make the committed `false` state observable to the test via an additional sequencing `await vi.waitFor(...)` that polls a condition only true once the regain render committed — without mutating product code. Do NOT add a `data-testid` to product code (that would be a product change — out of scope per AC1); prefer a test-internal sequencing flush.

- **Explicitly rejected — `rerender`:** Do not convert the test to `rerender`-driven transitions. The production re-arm path is focus-revalidation through the real `useActiveRepo` hook + `fetch`; `rerender` with a stubbed hook would exercise the boot/proxy path, not the transition path (see Research Reconciliation row 2 and `2026-05-11-rerender-not-remount-for-in-component-state-machine-tests.md`). The single-mount + focus harness is correct and must be preserved.

Keep the `__resetActiveRepoCoalesceForTests()` latch resets between focus events (they force fresh fetches; removing them would re-coalesce the back-to-back focuses and break determinism — see hook docstring on `inFlight`).

### Phase 2 — Verify

Run AC5 (typecheck), AC6 (isolation ≥10×), AC7 (parallel load ≥3×). If AC7 still flakes, the gate is insufficient — escalate to Option B before declaring done. Capture run counts in the PR body.

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

- **Risk: a NEW `vi.waitFor` inherits the 1000 ms default and re-introduces the flake.** Mitigation: AC4 mechanically asserts `timeout: 10_000` count == `vi.waitFor(` count. (Insight 6 of the cited learning — exactly the #5234 trap.)
- **Risk: the fix masks the flake without exercising the re-arm (false-green).** Mitigation: the terminal assertion stays `getByTestId(...).toBeInTheDocument()` (throws-until-present → genuinely RED if re-arm fails to fire), and AC7 runs the contended repro ≥3×.
- **Risk: a single green parallel-load run is mistaken for proof.** Mitigation: AC7 mandates ≥3 runs and recording the count; the flake is probabilistic CPU starvation (cited learning Insight 1), so one run proves little.
- **Risk: over-fix — touching product code or switching to `rerender`.** Mitigation: AC1 pins the diff to the single test file; Research Reconciliation row 2 + Phase 1 "Explicitly rejected" forbid `rerender`.

## Test Strategy

Runner is **vitest 4.1.0** (`apps/web-platform/package.json` `scripts.test: "vitest"`; `bunfig.toml` blocks `bun test` discovery via `pathIgnorePatterns = ["**"]`). Isolated invocation: `cd apps/web-platform && ./node_modules/.bin/vitest run test/live-repo-badge.test.tsx`. The component project (happy-dom) collects `test/**/*.test.tsx` (`vitest.config.ts:64`) — the file is in-scope. Full-suite contended repro: `TEST_GROUP=webplat bash scripts/test-all.sh` (forks pool default; `WEBPLAT_TEST_USE_THREADS=1` opts into threads). No new test file, no new framework, no new dependency.

## References

- `knowledge-base/project/learnings/test-failures/2026-06-10-parallel-load-flake-two-mechanisms-and-vacuous-absence-waits.md` — controlling learning: vacuous-absence-wait class, settle-anchor pattern, timeout-hierarchy nesting (10 s < 16 s testTimeout < 60 s hook), Insight 6 (carry `{ timeout }` to new `vi.waitFor` sites).
- `knowledge-base/project/learnings/test-failures/2026-05-11-rerender-not-remount-for-in-component-state-machine-tests.md` — why this test must NOT use `rerender`; in-component `dismissed` state is preserved across the single-mount focus transitions.
- `knowledge-base/project/learnings/test-failures/2026-04-28-chat-input-xhr-flake-and-negative-space-assertion.md` — React automatic batching collapses intermediate state renders under parallel load (the exact `false`/`true` collapse mechanism here); negative-space assertions between transitions.
- `knowledge-base/project/learnings/runtime-errors/2026-04-03-useeffect-race-optimistic-flag-vs-server-ack.md` — await server-acknowledged state before verifying effects downstream of it.
- Prior fixes: #5123 (timeout budgets + first-tick anchors), #5239 (dismiss absence-wait anchors). This PR closes the remaining transition-midpoint gap those left.
- Product code (correct, do not edit): `apps/web-platform/components/dashboard/live-repo-badge.tsx:23-25` (re-arm effect), `apps/web-platform/hooks/use-active-repo.ts` (focus-revalidation + `inFlight` coalescing + `__resetActiveRepoCoalesceForTests`).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This section is filled; threshold = none with a reason.)
- The re-arm `useEffect` dep is the **boolean** `data?.fellBackToSolo`, not the whole `data` object — it fires only on value change. The whole flake turns on whether React commits `false` between two `true`s; any fix that lets React batch `false`+`true` (e.g., firing the third focus before the regain render commits) silently dissolves the re-arm and the test goes green-but-vacuous. The terminal `getByTestId().toBeInTheDocument()` is the guard against that vacuity — keep it.
