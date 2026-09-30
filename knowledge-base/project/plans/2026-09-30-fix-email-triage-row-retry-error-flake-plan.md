---
title: "fix: de-flake email-triage-row 'a retry after a failure clears the previous error' under suite load"
date: 2026-09-30
slug: email-triage-row-retry-error-flake
branch: feat-one-shot-9126-email-triage-row-flake
issue: 9126
closes: 9126
type: fix
lane: cross-domain
requires_cpo_signoff: false
---

# fix: de-flake email-triage-row retry-clears-error test (#9126)

## Enhancement Summary

**Deepened on:** 2026-09-30
**Sections enhanced:** Root cause (empirical confirmation), Research Insights (deepen gate results)
**Research agents used:** none spawned — proportionate to a one-file test fix; verification done by instrumented probe, React-source read, and gate greps (the plan-review panel — DHH, Kieran, code-simplicity — already ran and its mechanical findings were applied).

### Key Improvements
1. The entanglement/ordering claim is now confirmed by a deterministic instrumented probe (not only by reading React source and a load repro): see "Empirical confirmation" below.
2. AC set trimmed to one deterministic merge gate (AC3 mutation) plus non-gating load evidence (E1, >= 20 runs), per plan-review.

### New Considerations Discovered
- The stale alert is present at `onChanged` time even on an idle machine; the test passes idle only because RTL's post-`waitFor` drain happens to outlast the settle. The flake is a shrinking of that margin, not an intermittent logic path.


Spec lacks valid `lane:` (no spec.md exists for this branch) — defaulted to `cross-domain` (fail-closed).

## Overview

`apps/web-platform/test/components/inbox/email-triage-row.test.tsx` › `EmailTriageRow — action error surfacing (N5)` › `a retry after a failure clears the previous error` fails intermittently under full-suite CPU load with `expected <p role="alert"> to be null`, and passes in isolation. This plan fixes the **test's assertion ordering** (test-only change, one file). It does not touch the component.

The issue's hypothesis ("the retry's re-render hadn't committed before `queryByRole` was evaluated") is directionally right but the mechanism is more specific and **deterministic in code, load-dependent only in timing**. It is confirmed below by reading React source and by reproducing the exact failure signature on demand.

## Root cause (verified, not assumed)

1. `EmailTriageRow` runs its action through `usePendingAction` (`apps/web-platform/hooks/use-pending-action.ts`), which invokes `startTransition(async () => { ... await asyncFn(...) ... })`.
2. `asyncFn` (`components/inbox/email-triage-row.tsx`, the callback passed to `usePendingAction`) begins with `setActionError(null)`, then `await fetch(...)`, then on `res.ok` calls `onChanged?.()`.
3. `setActionError(null)` executes in the **synchronous prefix** of the async transition callback, so React 19 assigns it the **transition lane**, and that lane is *entangled with the in-flight async action*. In `react-dom` 19.2.4, `entangleAsyncAction` / `suspendIfUpdateReadFromEntangledAsyncAction` (`node_modules/react-dom/cjs/react-dom-client.development.js`) make a render that reads an entangled-lane update **suspend until the action's promise settles**. So the stale `<p role="alert">` is *not removed at click time*; it is removed only after `asyncFn` returns.
4. `onChanged()` is called **inside** `asyncFn`, i.e. strictly *before* the action settles. The test's `await waitFor(() => expect(onChanged).toHaveBeenCalledTimes(1))` therefore passes at a moment when, by construction, the stale alert is still in the DOM.
5. Whether the test then observes the cleared alert depends on whether the action promise settles and the entangled transition commits inside RTL's post-`waitFor` drain (`asyncWrapper`'s `setTimeout(0)` wave). Idle machine: yes. CPU-starved worker: no. That is the flake.

**Empirical confirmation (deepen pass, idle machine, 3/3 runs, scratch probe deleted afterwards):** a temporary test recorded `document.querySelector('[role="alert"]') !== null` at three instants of the retry. Results, identical on every run: alert present right after the second `fireEvent.click` (`true`), alert present **inside** `onChanged` (`[true]`), alert absent after the following `waitFor` returned (`false`). This proves the ordering deterministically: `onChanged` strictly precedes the alert's removal, so any un-waited absence assertion depends on a drain margin. Working tree confirmed clean after the probe (`git status --short` empty).

**Reproduction (this session, before any fix):** with 40 busy-loop processes on a 16-core host, `npx vitest run --project component test/components/inbox/email-triage-row.test.tsx -t "retry after"` failed **1 of 5** runs with exactly `AssertionError: expected <p role="alert" …(1)></p> to be null`; the 4 others passed. Idle runs pass. This is the harness AC3 reuses.

**Falsified alternative (H-B):** "the retry click was swallowed because the first episode had not released (`pendingRef` still true / button still `disabled`)". If that were the failure, `onChanged` would never be called and the `waitFor(onChanged)` line would time out — a different error shape from the reported one. It is also unreachable in practice: `setActionError(msg)` and `release()` → `setPending(false)` are both urgent updates queued in the same microtask chain, so they batch into one commit; the alert and the re-enabled button appear together.

## Research Reconciliation — Spec vs. Codebase

| Issue / learning claim | Reality | Plan response |
| --- | --- | --- |
| "retry's re-render hadn't committed before `queryByRole` was evaluated" | True, but the cause is an *entangled-transition hold* on `setActionError(null)`, not generic render latency; `onChanged` is structurally earlier than the clear | Anchor on the effect (alert cleared), not on `onChanged`; document why `onChanged` alone is not a settle signal for the clear |
| Learning 2026-06-10 Insight 3: "wait-on-absence is vacuous — anchor on a positive settle signal" | Applies here in a *different shape*: the absence wait is **not** vacuous because presence is proven first (`findByText` of the error) — Insight 6 of the same learning. The defect is that the *positive signal chosen (`onChanged`) precedes the thing asserted* | Keep `onChanged` as the positive "retry took the success path" anchor, then add a non-vacuous `waitFor` on absence |
| Issue suggests waiting for "onChanged/success state to commit" | `onChanged` firing is NOT the commit of the alert removal (step 4 above) | Use a wait on the alert's absence itself; `onChanged` retained only to prove the retry ran |

## Premise Validation

Checked: #9126 is OPEN with no closing PR; `test/components/inbox/email-triage-row.test.tsx` and `components/inbox/email-triage-row.tsx` exist on the branch (last touched by #5125 and #8904); the cited learning exists; no open `code-review` issue references `email-triage-row`; no ADR is implicated (test-only change, no mechanism proposed beyond an assertion reorder). Held: everything. Stale: nothing.

## Property List and Cut List (Mechanism Minimality)

Properties the fix must buy:

- P1: the absence assertion `queryByRole("alert") === null` can only be evaluated after the retry's clear has committed (no dependence on how fast the worker happens to drain).
- P2: the test still fails if the component regresses to *never* clearing the error on retry (the assertion stays meaningful — presence is proven earlier in the same test).
- P3: the wait budget tolerates full-suite load (nested under the 16 s `testTimeout`).

Existing mechanisms that already buy part of this: RTL `configure({ asyncUtilTimeout: 10_000 })` in `apps/web-platform/test/setup-dom.ts` (`configure({ asyncUtilTimeout: 10_000 })`, grep-verified, gated by `test/setup-dom-leak-guard.test.ts`) covers P3 for every RTL `waitFor` in the component project, so **no per-call `{ timeout }` is added** (the `{ timeout: 10_000 }` rule in the 2026-06-10 learning applies to `vi.waitFor`, which this file does not use — verified: `grep -n "vi.waitFor" test/components/inbox/email-triage-row.test.tsx` returns nothing).

Cut List:

- Settle-flag on the mocked response body (`.finally(() => settled = true)`) from Insight 3 -> buys P1, but a wait on the alert's own absence buys it with zero extra machinery because presence is already proven.
- Pre-click `waitFor(button enabled)` guard against a swallowed retry click (H-B) -> buys nothing observed; H-B is falsified above.
- Component change (move `setActionError(null)` out of the transition, e.g. into the `onClick` before `runAction`) -> would also remove the "stale error visible during in-flight retry" window, but is a product-behavior change to two sibling components (`inbox-item-row.tsx` has the identical pattern), unrequested by the issue, and unnecessary for P1-P3. Rejected, not deferred: the window is sub-second and self-heals on settle; nothing is lost by leaving it.
- Sibling assertion in the 409 case (`409 (row already transitioned elsewhere)…`, `queryByRole("alert")` null after `onChanged`) -> never has an alert to clear (409 branch sets no error), so it cannot flake in this way. Left unchanged.

## Open Code-Review Overlap

None (`gh issue list --label code-review --state open` scanned for `email-triage-row`: no matches).

## Files to Edit

- `apps/web-platform/test/components/inbox/email-triage-row.test.tsx` — rewrite the tail of the `a retry after a failure clears the previous error` case (from the `// Default mock (200) takes over for the retry.` comment to the end of the case) and its comment.

## Files to Create

- None (plan/tasks artifacts under `knowledge-base/project/{plans,specs}/` aside).

## Implementation Phases

### Phase 1 — Reproduce (RED, pre-fix)

1. Run the load harness (see Test Scenarios) against the unmodified test and record the failure rate. Baseline already observed: 1/5. If a session's baseline shows 0 failures in 5 runs, raise the burner count or run more iterations before concluding — do not proceed to Phase 2 on a non-reproducing baseline (a fix validated against a non-reproducing baseline proves nothing).

### Phase 2 — Fix the assertion (GREEN)

Replace the tail of the test with:

```tsx
    // Default mock (200) takes over for the retry.
    fireEvent.click(screen.getByLabelText("Acknowledge email"));

    // Positive anchor: the retry reached the success path.
    await waitFor(() => expect(onChanged).toHaveBeenCalledTimes(1));

    // onChanged fires before the transition that clears the alert commits
    // (setActionError(null) is in the async transition's sync prefix), so wait
    // on the effect. Non-vacuous: the alert was proven present above (#9126).
    await waitFor(() => expect(screen.queryByRole("alert")).toBeNull());
```

- No `{ timeout }` option: RTL's global `asyncUtilTimeout` (`test/setup-dom.ts`) already applies; adding a literal would duplicate a drifting number.
- Keep the earlier `findByText` (presence proof) untouched — it is what makes the absence wait non-vacuous.
- Do not merge the two `waitFor`s into one callback: separate calls keep the failure message attributable (retry never ran vs. alert never cleared).

### Phase 3 — Verify (see Acceptance Criteria)

Run the isolated file, the scratch mutation (AC3), then the load harness pre/post comparison (E1).

### Phase 4 — Capture the learning

Append an "Insight 7" to `knowledge-base/project/learnings/test-failures/2026-06-10-parallel-load-flake-two-mechanisms-and-vacuous-absence-waits.md` (in the work/ship phase, not now): *a positive settle signal must come strictly AFTER the state change asserted; a callback invoked from inside an async transition (`onChanged`) precedes the transition's own entangled updates committing, so it is the wrong anchor for asserting an update made in that same transition's sync prefix.* Include the 1-in-5 reproduction recipe.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: the retry test in `apps/web-platform/test/components/inbox/email-triage-row.test.tsx` contains, after the second click, a `waitFor` on `onChanged` (called once) followed by a **separate** `waitFor(() => expect(screen.queryByRole("alert")).toBeNull())`; the un-waited `expect(screen.queryByRole("alert")).toBeNull()` at the end of that case is gone. The working-tree diff (`git diff --stat origin/main -- apps/web-platform`) lists only the test file.
- [ ] AC2: the isolated file passes: `cd apps/web-platform && npx vitest run --project component test/components/inbox/email-triage-row.test.tsx` -> all tests pass.
- [ ] AC3 (deterministic gate, P2): a scratch mutation that removes `setActionError(null)` from `asyncFn` in `components/inbox/email-triage-row.tsx` makes the retry test FAIL (absence wait times out showing the `<p role="alert">`); after reverting, `git diff -- apps/web-platform/components` is empty. This is the merge-gating proof that the assertion still guards the behavior.

### Verification evidence (non-gating, recorded in the PR body)

- [ ] E1: Phase 1 baseline and post-fix results from the CPU-burner harness: 40 busy-loop `sh -c 'while :; do :; done'` burners under `timeout`, PIDs captured from `$!` and killed individually (a PreToolUse hook blocks the full-command-line form of pkill), looping `npx vitest run --project component <file> -t "retry after"`. Report pre-fix failures/runs and post-fix failures/runs with **>= 20 post-fix runs** (at a ~20% pre-fix rate, 20 clean runs leave ~1% odds of a still-broken test passing). Host- and load-dependent, hence evidence and not a merge gate; the deterministic gate is AC3 plus the source-level root cause.
- [ ] E2: PR body contains `Closes #9126` (ship-phase concern).

### Post-merge (operator)

- None. (No deploy surface; #9126 auto-closes via the PR.)

## Test Scenarios

1. **Idle, isolated** — retry test passes (regression baseline).
2. **CPU-starved** — burner harness (E1) -> 0 post-fix failures.
3. **Mutation: component never clears on retry** (scratch) -> retry test fails on the absence wait (AC3).
4. **Sibling** — the other three N5 cases (500 acknowledge, 500 archive, 409) pass unchanged.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — a test-only file changes; the worst outcome is the flake persists and CI reruns cost engineer time.
**If this leaks, the user's data is exposed via:** no exposure vector — no runtime code, data, or config changes.
**Brand-survival threshold:** none

threshold: none, reason: the diff is confined to a single component test file under `apps/web-platform/test/`; no sensitive path (auth, payments, migrations, server routes) is touched.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — test-only flake fix in an existing test file (no product surface, no new component, no copy).

## Observability

Skipped: pure test-file change (Files to Edit contains no path under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`, and introduces no infrastructure surface).

## Risks and Sharp Edges

- The absence wait is non-vacuous **only because** the earlier `findByText("Couldn't acknowledge — try again.")` proves the alert exists first. If a future edit removes that line or moves the second click before it, the wait becomes vacuous (passes on tick 1). Keep the comment that says so.
- `onChanged` firing must never be used as the settle anchor for asserting removal of state cleared by `asyncFn`'s leading `setActionError(null)` — it precedes the entangled commit by construction.
- React internals are cited by function name (`entangleAsyncAction`, `suspendIfUpdateReadFromEntangledAsyncAction`) against a pinned `react-dom` 19.2.4 build, never by line number.
- The commit-timing window is small (settle follows `onChanged` within a couple of microtasks; the entangled commit is then scheduled as a macrotask). The ORDERING (onChanged before the clear) is deterministic; only the race margin is load-dependent. The fix does not depend on the exact internals: it waits on the effect itself.
- A plan whose `## User-Brand Impact` section is empty or placeholder text fails `deepen-plan` Phase 4.6; this one is filled (threshold `none`, non-sensitive path).
- Phase 1's baseline is load- and host-dependent. Report the observed rate; do not hard-code "1/5" as an invariant.

## Research Insights

- Learning applied: `knowledge-base/project/learnings/test-failures/2026-06-10-parallel-load-flake-two-mechanisms-and-vacuous-absence-waits.md` (Insights 2, 3, 5, 6). RTL `waitFor` and `vi.waitFor` are independent mechanisms; file uses only RTL `waitFor`, whose 10 s ceiling is set globally in `apps/web-platform/test/setup-dom.ts`.
- Component: `apps/web-platform/components/inbox/email-triage-row.tsx` (`usePendingAction` callback: `setActionError(null)` -> `fetch` -> `onChanged`). Hook: `apps/web-platform/hooks/use-pending-action.ts` (`startTransition(async …)`, `release()` after `await`).
- Sibling with identical pattern and no equivalent assertion: `apps/web-platform/components/inbox/inbox-item-row.tsx` (no change needed).
- Stack: react/react-dom 19.2.4, @testing-library/react 16.3.2, vitest 4.1.11; `component` project uses `test/setup-dom.ts` (`vitest.config.ts` projects block).
- No external research needed (strong local context; no security/payments/API surface).
- Deepen-plan gates: `## User-Brand Impact` present (threshold `none`, scope-out reason present, no sensitive path); PAT-shaped-variable grep: no matches; cited PRs #5125 and #8904 verified MERGED via `gh pr view`; no AGENTS rule IDs cited in the plan body; UI-wireframe halt not applicable (no UI-surface file in Files to Edit; the file edited is under `apps/web-platform/test/`); Observability halt: the sole edited file is a test file outside the plan Phase 2.9 code/infra trigger set, so no `## Observability` section is required (matches the skip recorded above); no `## Guard Contract` required (the deliverable is an assertion reorder in an existing test, not a new guard/lint/gate); no Encryption Posture / Downtime triggers.
