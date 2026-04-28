# Fix: chat-input-attachments XHR-progress test flake under vitest parallel execution

## Enhancement Summary

**Deepened on:** 2026-04-28
**Sections enhanced:** 7 (Overview, Hypotheses, Files to Edit, Phase 2, Acceptance Criteria, Risks, Test Scenarios)
**Research applied:** vitest 3.2.4 isolation/pool semantics (verified via `apps/web-platform/node_modules/vitest/package.json` — `^3.1.0` resolves to `3.2.4`), `@testing-library/user-event` v14.6.1 fake-timer compatibility (testing-library issues #1197/#1198/#833 — all confirm the user-event/fake-timer mixing trap), happy-dom `XMLHttpRequest` semantics (the test stubs replace the global entirely, so happy-dom's XHR is bypassed once the stub is active), PR #2819 setup-dom.ts precedent (architecture rationale for `originalFetch` capture), Apr-12 transient-state learning (the same file's "Uploaded" test already uses the manual-trigger pattern — this PR extends the pattern to the five sibling tests).

### Key Improvements After Deepen

1. **The `userEvent` fake-timer trap is ruled out explicitly.** The Apr-26 web research confirmed that `@testing-library/user-event` v14 has documented timeout/hang issues when mixed with `vi.useFakeTimers()` (testing-library/react-testing-library #1197, testing-library/user-event #833). The plan's choice of "manual triggers, no fake timers" is now backed by external evidence, not just preference.
2. **Drift-guard test gets two new assertions, not one.** The original plan called for the `originalXHR` token check. The deepened plan adds a second assertion that `globalThis.XMLHttpRequest = originalXHR` appears in the source — this is the load-bearing line, not just the variable declaration. Mirrors the existing tuple-style `it.each` assertions in `setup-dom-leak-guard.test.ts`.
3. **Phase 2 sequence pinned: setup-dom.ts edit FIRST, drift-guard test SECOND, test-file rewrite THIRD.** Reverse-order edits (rewrite test file first) would leave the suite green for hours while reviewers wait — putting the infra fix first means the drift-guard test fails immediately if `originalXHR` is omitted.
4. **Phase 1 RED falsifiability gap is now explicitly bounded.** If the throwaway test cannot reproduce the race in <100 local runs, the plan documents a structural-evidence justification (the `setTimeout(0/10/20)` triple structurally matches the Apr-12 macrotask-batch race) and proceeds. This makes the TDD exemption auditable, not implicit.
5. **Sibling-test sweep is mandatory, not optional.** The original plan listed three tests to rewrite; deepen-pass extends to all six in the describe block (the three error-state tests use the same `setTimeout(0)` shape). Per `cq-vitest-setup-file-hook-scope` and the `kb-chat-sidebar` precedent, fixing only the actively-failing test invites the same flake to surface in a sibling on the next CI run.
6. **CI verification gate added to Phase 3.** Beyond local 3/3 parallel runs, the plan now requires observation of one CI run on the PR — vitest's CI environment differs from local (different `ulimit -u`, different scheduler, different macrotask cadence) and a green local run does not generalize automatically.
7. **Risks section quantifies the SUT-bug escape hatch.** If 3/3 local runs still flake after Phase 2, the plan now prescribes the exact diagnostic next step (instrument `setAttachments` callback, check React commit ordering) rather than the vague "investigate the SUT" of the original.

### New Considerations Discovered

- **happy-dom 20.8.9 exports `XMLHttpRequest` as a window-level constructor** (verified via `apps/web-platform/node_modules/happy-dom/lib/index.d.ts:218`). Stubbing `globalThis.XMLHttpRequest` shadows the window export but does NOT mutate happy-dom's internal registry — meaning the cross-file leak surface is at `globalThis`, exactly where `originalXHR` capture catches it. No need to dig into happy-dom's window-singleton handling.
- **`userEvent.setup({ delay: null })` is the official escape hatch from user-event's internal `setTimeout` pacing.** The plan does NOT need this because we're not introducing fake timers; but the `Risks` section should note it as the fallback if the manual-trigger pattern hits a `userEvent`-related edge case.
- **vitest 3.2.4 has a documented "Terminating Worker Thread" regression (issue #8133)** that surfaces only on long-running suites. Not load-bearing for this fix, but the post-merge watch in the AC explicitly looks for that signature too — if the chat-input file fails with a worker-thread error rather than the "50%" timeout, that's a different bug class (vitest upgrade) and should not be conflated.

**Issues:** Closes #2524 (CI failure on run 24586094406, "shows incremental progress during XHR upload"). Closes #2470 (duplicate — same file, same flake class, broader symptom: "50% progress text times out in full-suite run").
**Branch:** `feat-one-shot-2524-test-flake-chat-input-attachments`
**Type:** `fix` (test-infrastructure; no product behavior change)
**Priority:** P3 (operational hygiene — a flaky suite normalizes a red CI; recurred on post-merge of unrelated PRs #2516 and #2740).
**Classification:** test-only-no-prod-write (no migrations, no infra, no runtime code change unless QA proves the SUT is racy).

## Overview

`apps/web-platform/test/chat-input-attachments.test.tsx` flakes on CI in two adjacent assertions inside the "send with attachments" describe block:

- `it("shows incremental progress during XHR upload")` — `getByText("50%")` times out (#2524).
- Sibling `it("aborts XHR when attachment is removed during upload")` and `it("calls onSend with attachments after successful upload")` — reported on different runs (#2470 referenced).

The file passes 14/14 in isolation (`./node_modules/.bin/vitest run test/chat-input-attachments.test.tsx`) and intermittently fails 1 test in the full-suite run. This is the **same class** of cross-file leak that PR #2819 (issues #2594, #2505) fixed for the `kb-chat-sidebar` family — but PR #2819's setup-dom.ts harness only restores `fetch`, not `XMLHttpRequest`. Combined with a tight `setTimeout(0)` / `setTimeout(10)` / `setTimeout(20)` race in the test's own mock that React cannot reliably commit between, the file remains flaky after the PR #2819 fixes shipped.

The fix is **two-layered** and lands in one PR:

1. **Primary — stabilize the test's XHR-progress mock.** Rewrite the three race-prone tests in the "send with attachments" describe block so each XHR phase (`onprogress(50%)` → assert "50%" → `onprogress(100%)` → assert "Uploaded" → `onload` → assert send completion) is **explicitly triggered** by the test, not scheduled on a real-clock `setTimeout`. This eliminates the macrotask-batching race where all three timers can fire in the same flush on a slow CI worker before React commits the intermediate state. Pattern is already documented in `knowledge-base/project/learnings/2026-04-12-testing-transient-react-state-in-async-flows.md` (the same file's "Uploaded" test already uses the manual-trigger pattern; we extend it to the "50%" test and the abort/onSend tests).
2. **Secondary — XHR cross-file leak guard.** Mirror PR #2819's `originalFetch` capture-and-restore pattern in `test/setup-dom.ts` for `XMLHttpRequest`: capture the pristine `globalThis.XMLHttpRequest` at setup-file load, restore it in `afterAll`. This closes the leak surface where `test/file-tree-upload.test.tsx` (the only other file that stubs `XMLHttpRequest`) could leave a stale stub on a vitest worker that subsequently runs `chat-input-attachments.test.tsx`. Add a one-line drift-guard assertion to `setup-dom-leak-guard.test.ts` so the restore line cannot be silently removed.

**Why this shape, not "just add fake timers":** `vi.useFakeTimers()` would also work for the timing race, but introduces a new failure mode — `userEvent.type()` and `userEvent.keyboard()` from `@testing-library/user-event` v14 internally call `setTimeout(0)` for keystroke pacing. Mixing fake timers with `userEvent` requires `vi.useFakeTimers({ shouldAdvanceTime: true })` plus manual `vi.advanceTimersByTime()` calls between phases (see `cq-raf-batching-sweep-test-helpers`). The manual-trigger pattern is simpler, already proven on the same file's "Uploaded" test, and removes the only real-clock dependency without forcing a fake-timer / userEvent dance.

### Research Insights — Why Fake Timers Are Off the Table

External evidence (Apr-26 web search) confirms the userEvent v14 / fake-timer interaction is a documented pain point, not an opinion:

- **testing-library/react-testing-library #1197** — "Update to v14 breaks @testing-library/user-event on Vitest" — `await user.click()` no longer resolves under fake timers.
- **testing-library/user-event #833** — "userEvent.click fails due to timeout when used with jest.useFakeTimers" — same pattern in Jest, not specific to vitest.
- **testing-library/react-testing-library #1198** — "Component test with setTimeout and vitest fake timers not working" — vitest-specific reproduction.

The official escape hatch is `userEvent.setup({ advanceTimers: vi.advanceTimersByTime })` plus manual `vi.advanceTimersByTime(N)` between every phase. Three of our six tests have multiple userEvent calls (`type` + `keyboard.{Enter}`); each would need an `advanceTimersByTime` interleave. The manual-trigger pattern keeps real timers everywhere and only controls the XHR mock — strictly simpler.

**Confirming counter-pattern in the same codebase:** `apps/web-platform/test/chat-input-draft-debounce.test.tsx` and `apps/web-platform/test/chat-input-draft-key.test.tsx` both use `vi.useFakeTimers` for the 250ms draft-persist debounce — they work because they exercise SUT-internal `setTimeout`, not external IO. The XHR-progress tests exercise external IO (the mock's setTimeout), which is the wrong layer to control via global fake timers.

Sources:
- [testing-library/react-testing-library #1197](https://github.com/testing-library/react-testing-library/issues/1197)
- [testing-library/user-event #833](https://github.com/testing-library/user-event/issues/833)
- [testing-library/react-testing-library #1198](https://github.com/testing-library/react-testing-library/issues/1198)
- [Vitest Timers guide](https://vitest.dev/guide/mocking/timers)

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality | Plan response |
|---|---|---|
| #2524 hypothesis: "Flaky interaction between the XHR progress-event mock and the happy-dom fetch adapter" | The fetch adapter is not in the call path of the failing assertion. The assertion waits for "50%" text rendered from `att.progress` state set by `onProgress` callback in `lib/upload-with-progress.ts:21`. Fetch is the presign call (resolved before XHR send). | Plan addresses the XHR-progress timing race directly; happy-dom's fetch is not the issue. Captured as plan-level correction so the next reader doesn't chase the wrong layer. |
| #2524 hypothesis: "AggregateError ECONNREFUSED ::1:3000 in log may correlate with GC pressure" | That log line is from a different test exercising network-error paths and is expected stderr. It is unrelated to the failing assertion. | Plan does not gate on GC behavior. |
| #2470 hypothesis: "prior test in the suite leaves XMLHttpRequest / upload progress state or a MSW handler registered" | No MSW in this repo. Confirmed via `grep -r "msw" apps/web-platform/{test,lib,components}` — zero hits. The XHR cross-file leak hypothesis IS valid: `test/file-tree-upload.test.tsx:79-82` stubs `XMLHttpRequest` via `vi.stubGlobal`, and `setup-dom.ts:42` calls `vi.unstubAllGlobals()` only in `afterAll`. Vitest 3.2.4 with `isolate: true` (vitest.config.ts:41) gives per-file module-graph isolation, but the worker-level `globalThis.XMLHttpRequest` write IS scrubbed by `unstubAllGlobals` — UNLESS a future test uses raw assignment (`globalThis.XMLHttpRequest = vi.fn(...)`), which would not be undone. | Plan adds the proactive `originalXHR` capture-and-restore (mirroring `originalFetch` in setup-dom.ts:9-10) so a future raw-assignment leak does not regress. Drift-guard test asserts the line stays. |
| Constitution / `cq-vitest-setup-file-hook-scope` | "Vitest setup-file `afterEach` hooks run per-test, not per-file. Fix cross-file leaks in `afterAll` or via `isolate: true`." | Plan keeps the new XHR restore in `afterAll`, NOT in `afterEach`, consistent with the rule and with the existing `originalFetch` placement. |
| Constitution / `cq-test-mocked-module-constant-import` | Not applicable — no `vi.mock("@/lib/upload-with-progress")` in the affected file. | No action. |
| Constitution / `cq-raf-batching-sweep-test-helpers` | The chat-input component does not use rAF-batching for the progress state (it uses plain `setAttachments` calls inside the `onProgress` callback). | No fake-timer changes needed. The fix is at the test-mock layer, not the component-render layer. |
| #2524: "If the test flakes again in ≥1 of the next 5 main builds, stabilize the test" | Already flaked again on post-merge of PR #2740 (commented on #2470 by Jean on 2026-04-21, run 24732382100). The "≥1 of 5" threshold is already met. | Stabilize NOW; no further wait-and-watch. |

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 \
  | jq -r --arg path "test/chat-input-attachments.test.tsx" \
      '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"'
gh issue list --label code-review --state open --json number,title,body --limit 200 \
  | jq -r --arg path "test/setup-dom.ts" \
      '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"'
gh issue list --label code-review --state open --json number,title,body --limit 200 \
  | jq -r --arg path "lib/upload-with-progress.ts" \
      '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"'
```

None. No open `code-review`-labeled issues touch the planned files. (The only adjacent open issue is #2470, which this PR closes as a duplicate.)

## Hypotheses

H1 (PRIMARY, high confidence): **The test mock's `setTimeout(0)` / `setTimeout(10)` / `setTimeout(20)` race is the proximate cause of the "50%" timeout.** On a slow CI worker the three timers can fire in the same macrotask flush before React commits the intermediate `att.progress = 50` state. React's state-batching then collapses 50→100→cleared into a single render and the "50%" text never appears in the DOM. The Apr-12 learning (`testing-transient-react-state-in-async-flows.md`) already documented this pattern for the sibling "Uploaded" test (which uses a manual-trigger and is NOT flaky). The "50%" test has the same shape but kept the real-clock setTimeouts.

H2 (HIGH confidence, secondary leak surface): **`XMLHttpRequest` global stub is not protected by setup-dom.ts's restore harness.** PR #2819 added `originalFetch = globalThis.fetch` capture in `setup-dom.ts:9-10` and a force-restore in `afterAll`. The same protection was NOT extended to `XMLHttpRequest`. Today the only XHR-stubbing files are `chat-input-attachments.test.tsx` (per-test in `beforeEach`) and `file-tree-upload.test.tsx` (per-test, with explicit `vi.unstubAllGlobals()` in its own `beforeEach`). Both currently use `vi.stubGlobal`, which IS undone by the global `afterAll` `vi.unstubAllGlobals()`. So the leak is **latent**, not active — but the proactive guard prevents future regression (e.g., if any new test uses raw `globalThis.XMLHttpRequest = vi.fn(...)` like the four `kb-layout-*` files do for `fetch` today).

H3 (LOW confidence, watch-only): **`isolate: true` already mitigates module-graph leaks but not happy-dom's internal XHR singleton.** happy-dom's `XMLHttpRequest` implementation is per-window. With `isolate: true`, each test file gets a fresh module graph — but the happy-dom Window instance is reused for the worker thread (vitest doesn't recreate the JSDOM/happy-dom global per file unless `pool: 'forks'` is used). If happy-dom's internal XHR queue/listener registry is corrupted by an earlier file, the chat-input file's stub (which replaces `globalThis.XMLHttpRequest` with a `vi.fn` returning `mockXhr`) bypasses happy-dom entirely — so this hypothesis is unlikely to be load-bearing. We do NOT propose `pool: 'forks'` (high blast radius for a niche failure mode).

## Files to Edit

- `apps/web-platform/test/chat-input-attachments.test.tsx` — Rewrite three tests in the "send with attachments" describe block to use the manual-trigger pattern (already proven on the file's own "Uploaded" test):
  - `"shows incremental progress during XHR upload"` (#2524's failing test) — replace `setTimeout(0/10/20)` triple with three named triggers (`fireProgress50`, `fireProgress100`, `completeUpload`) called explicitly between `await waitFor(...)` assertions.
  - `"aborts XHR when attachment is removed during upload"` — replace `setTimeout(0)` with a single `fireProgress25` trigger called explicitly before the remove-button click.
  - `"calls onSend with attachments after successful upload"` — replace `setTimeout(() => mockXhr.onload?.(), 0)` with explicit trigger called after the `userEvent.keyboard("{Enter}")` so `onSend` resolution is deterministic.
  - Sibling tests (`"shows error state on XHR upload failure"`, `"shows error on non-2xx XHR status"`, `"preserves errored attachments after send while clearing successful ones"`) — same `setTimeout(0)` pattern; rewrite to manual triggers for consistency and to prevent the same flake class in a future "fix only the failing test" PR.

- `apps/web-platform/test/setup-dom.ts` — Add proactive `originalXHR` capture-and-restore mirroring `originalFetch` (lines 9-10, 38-44):
  ```ts
  const originalXHR: typeof XMLHttpRequest | undefined =
    typeof globalThis !== "undefined" ? globalThis.XMLHttpRequest : undefined;
  // ...
  afterAll(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    if (originalFetch && typeof globalThis !== "undefined") {
      globalThis.fetch = originalFetch;
    }
    if (originalXHR && typeof globalThis !== "undefined") {
      globalThis.XMLHttpRequest = originalXHR;
    }
    vi.useRealTimers();
    resetBrowserLikeGlobals();
  });
  ```
  Comment block above the new lines should reference: "PR #2819 fixed the same leak class for `fetch`. XMLHttpRequest is currently only `vi.stubGlobal`-stubbed in two files (chat-input-attachments, file-tree-upload), but the proactive capture prevents a future raw-assignment leak from regressing the same class." Symbol-anchor the cross-reference per `cq-code-comments-symbol-anchors-not-line-numbers` — refer to `originalFetch` by name, not by line number.

- `apps/web-platform/test/setup-dom-leak-guard.test.ts` — Add an assertion that `setup-dom.ts` contains the literal token `originalXHR` and the `globalThis.XMLHttpRequest = originalXHR` restore. Mirror the existing assertion pattern for `originalFetch`.

## Files to Create

None.

## Implementation Phases

### Phase 1 — RED (failing test that proves the fix is real, not a no-op)

Write a test that simulates the macrotask-batch race condition and PROVES it produces the symptom on the unmodified mock. Approach:

1. In a **new throwaway test** inside `chat-input-attachments.test.tsx` (deleted after Phase 3), set `mockXhr.send` to fire all three timers synchronously inside a `Promise.resolve().then(...)` chain (the post-fix code MUST handle that case). Assert "50%" text appears.
2. Run the throwaway test under the unmodified mock structure to confirm it fails with the same `Unable to find an element with the text: 50%` symptom.

If Phase 1 cannot reproduce the race deterministically (the original failure is timing-dependent and may not reproduce in <100 runs locally), document the falsifiability gap in the PR description and proceed to Phase 2 with **structural** evidence: the existing `setTimeout(0/10/20)` triple matches the macrotask-batch race shape documented in the Apr-12 learning. Per `cq-write-failing-tests-before` (`Infrastructure-only tasks (config, CI, scaffolding) are exempt`), test-infrastructure fixes that cannot deterministically produce the bug locally are exempt.

**Acceptance gate:** Phase 1 completes when EITHER (a) a deterministic RED test exists and fails on the unmodified code, OR (b) the falsifiability gap is documented in the PR body with the structural-evidence justification.

### Phase 2 — GREEN (apply the fix)

**Sequence pinned (deepen-pass insight):** Apply the setup-dom.ts edit FIRST so the drift-guard test fails immediately if `originalXHR` is omitted. Apply the drift-guard assertion SECOND. Rewrite the test file THIRD. Reverse-order edits (test file first) would leave the drift-guard surface untested for hours while reviewers wait on the rewrite.

1. **First — `apps/web-platform/test/setup-dom.ts`:** Add the `originalXHR` capture and restore.
2. **Second — `apps/web-platform/test/setup-dom-leak-guard.test.ts`:** Add the two assertions (token + restore line). Run `./node_modules/.bin/vitest run test/setup-dom-leak-guard.test.ts` — must pass.
3. **Third — Rewrite the six tests** in the "send with attachments" describe block per the file-edit list above. Pattern (extracted from the file's own already-passing "Uploaded" test):
   ```ts
   let fireProgress50: () => void;
   let fireProgress100: () => void;
   let completeUpload: () => void;
   mockXhr.send.mockImplementation(() => {
     fireProgress50 = () => mockXhr.upload.onprogress?.({ lengthComputable: true, loaded: 50, total: 100 });
     fireProgress100 = () => mockXhr.upload.onprogress?.({ lengthComputable: true, loaded: 100, total: 100 });
     completeUpload = () => mockXhr.onload?.();
   });
   // ... userEvent send to trigger upload ...
   fireProgress50!();
   await waitFor(() => expect(screen.getByText("50%")).toBeInTheDocument());
   fireProgress100!();
   await waitFor(() => expect(screen.getByText("Uploaded")).toBeInTheDocument());
   completeUpload!();
   ```
4. Run the throwaway RED test from Phase 1 — it MUST now pass.
5. Delete the throwaway RED test (it served its purpose).

### Research Insights — Phase 2 Implementation Detail

**Manual-trigger pattern, exact shape (confirmed against the file's existing `it("shows 'Uploaded' text when progress reaches 100%")` test):**

```ts
let fireProgress50: () => void;
let fireProgress100: () => void;
let completeUpload: () => void;

mockXhr.send.mockImplementation(() => {
  fireProgress50 = () => mockXhr.upload.onprogress?.({ lengthComputable: true, loaded: 50, total: 100 });
  fireProgress100 = () => mockXhr.upload.onprogress?.({ lengthComputable: true, loaded: 100, total: 100 });
  completeUpload = () => mockXhr.onload?.();
});

// ... setup attachment, type message, press Enter ...

fireProgress50!();
await waitFor(() => expect(screen.getByText("50%")).toBeInTheDocument());
fireProgress100!();
await waitFor(() => expect(screen.getByText("Uploaded")).toBeInTheDocument());
completeUpload!();
```

**Why the non-null assertion (`!`) is acceptable here:** the trigger functions are assigned inside `mockXhr.send.mockImplementation`, which fires synchronously when `uploadAttachments()` calls `xhr.send(file)` (see `xhr.send(file)` at the bottom of `uploadWithProgress` in `lib/upload-with-progress.ts`). By the time the assertion `fireProgress50!()` runs, `userEvent.keyboard("{Enter}")` has already awaited `handleSubmit` past the `xhr.send` call. TypeScript can't prove this control-flow ordering, so `!` is the correct narrow.

**Why `setAttachments` callback ordering is safe:** the SUT's progress callback (the `onProgress` arg passed to `uploadWithProgress` inside `uploadAttachments` in `chat-input.tsx`) does `setAttachments((prev) => prev.map((a) => (a.id === att.id ? { ...a, progress: percent } : a)))`. Each `fireProgress*()` call schedules exactly one React state update; React batches inside a single microtask but `await waitFor(...)` between triggers gives React a full microtask flush window to commit the intermediate state. This is structurally identical to how the existing `it("shows 'Uploaded' text when progress reaches 100%")` test works.

### Phase 3 — REFACTOR & verify (3 consecutive parallel passes)

1. Run the affected file in isolation: `cd apps/web-platform && ./node_modules/.bin/vitest run test/chat-input-attachments.test.tsx`. Must pass 14/14.
2. Run the full component project, three times back-to-back: `for i in 1 2 3; do cd apps/web-platform && ./node_modules/.bin/vitest run; done`. All three runs must be green for the chat-input file. Per the existing `kb-chat-sidebar` pattern in PR #2819, "3/3 green parallel runs" is the standing bar for declaring a flake fixed.
3. Push branch, observe one full CI run on the PR. CI must be green.

If any of the three local parallel runs fails for the chat-input file, escalate per the H3 fallback: investigate happy-dom's window-singleton XHR registry and consider scoping the chat-input file to its own vitest project. Do NOT default to that escalation — it is heavyweight and was rejected in PR #2819's deliberation.

### Phase 4 — Documentation

1. Append a session learning to `knowledge-base/project/learnings/test-failures/` with topic `chat-input-attachments-xhr-progress-flake`. Date filled at write-time per the plan-skill sharp-edge "Do not prescribe exact learning filenames with dates in `tasks.md`".
2. The learning MUST cross-reference: PR #2819 (the precedent fix), the Apr-12 transient-state learning (the manual-trigger pattern source), and the Apr-22 cross-file-leaks learning (the `originalFetch` precedent the new `originalXHR` mirrors).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/chat-input-attachments.test.tsx` passes 14/14 in isolation.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run` passes the chat-input file in 3/3 consecutive parallel runs.
- [ ] `setup-dom-leak-guard.test.ts` includes the new `originalXHR` and `globalThis.XMLHttpRequest = originalXHR` assertions, and passes.
- [ ] PR body contains `Closes #2524` and `Closes #2470` (per `wg-use-closes-n-in-pr-body-not-title-to`; both are pre-merge resolvable because the fix is the test-stabilization itself, not an operator action).
- [ ] No `setTimeout(...)` calls remain in the "send with attachments" describe block of `chat-input-attachments.test.tsx` (grep verification: `rg "setTimeout" apps/web-platform/test/chat-input-attachments.test.tsx` returns zero).
- [ ] No `apps/*/components/**/*.tsx`, `apps/*/lib/**/*.ts`, `supabase/migrations/**`, or `apps/*/infra/**` files touched (this is test-only). Verify with `git diff --name-only main...HEAD`.

### Post-merge (operator)

- [ ] Watch the next 5 CI runs on `main` for any recurrence of `chat-input-attachments.test.tsx` failure. If zero failures, close #2524 and #2470 (already auto-closed by `Closes` in PR body — verify they didn't reopen on a recurrence).
- [ ] If a recurrence happens within 5 runs, reopen the issue, file the symptom, and escalate to H3 (happy-dom singleton scope investigation).

## Test Scenarios

The six rewritten tests in `chat-input-attachments.test.tsx > "send with attachments"` describe block, in their post-fix shape, ARE the test scenarios. No additional integration coverage needed — this is purely a test-stabilization change.

The drift-guard assertions in `setup-dom-leak-guard.test.ts` are the regression coverage for the secondary fix.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — test-infrastructure-only change. CTO involvement is implicit (test infrastructure IS the engineering domain), but this is mechanical hygiene work that does not warrant the domain-leader gate (the change touches only test files; the SUT is unchanged).

## Network-Outage Deep-Dive Check (Phase 4.5)

**Status:** Evaluated, not applied.

Trigger keywords searched: `SSH`, `connection reset`, `kex`, `firewall`, `unreachable`, `EHOSTUNREACH`, `ECONNRESET`, `502`, `503`, `504`, `handshake`. None appear in the Overview, Hypotheses, or Risks sections in a network-connectivity context. The word "timeout" appears 11 times but every occurrence refers to test-runner timeouts (`waitFor` timeout, `userEvent` hang, vitest 5000ms default), not network or SSH timeouts. Per `hr-ssh-diagnosis-verify-firewall`'s scope ("plans that address an SSH/network-connectivity symptom"), this plan is out of scope and the L3-firewall verification gate does not apply.

## Risks

- **Risk: the bug is in the SUT (`uploadWithProgress` or `chat-input.tsx`'s `uploadAttachments`), not the test.** If after Phase 3, three parallel runs are still flaky, the test stabilization will mask a real production bug (e.g., a React state-batching issue where rapid `onProgress` calls collapse before a render commit). **Mitigation:** Phase 3's 3/3 parallel-run gate. If the gate fails after the test rewrite, do NOT ship — escalate to investigate the SUT. Specifically:
  1. Instrument the `setAttachments((prev) => ...)` callback inside `uploadAttachments` (the `onProgress` callback passed to `uploadWithProgress`) to log `[ts, attachId, percent]` on each invocation.
  2. Run the failing test in a tight loop (`for i in $(seq 50); do ./node_modules/.bin/vitest run test/chat-input-attachments.test.tsx -t "incremental progress"; done`) and capture logs from the failing run.
  3. If the logs show `progress=50` arrived but `progress=100` arrived in the same microtask before React committed, the SUT needs throttling — wrap the `onProgress` callback in a `requestAnimationFrame` debounce, or replace `setAttachments` with a `useReducer` that coalesces by `attachId`. Per `cq-raf-batching-sweep-test-helpers`, any rAF batching in the SUT requires a corresponding test-helper sweep — that change extends the PR scope and warrants a fresh review pass.
  4. If the SUT logs show two distinct microtasks but React still didn't commit, suspect React's automatic-batching window (React 18+ batches across microtasks within the same callback) — `flushSync(() => setAttachments(...))` is the targeted fix. This is heavier than the test-only fix and should not ship without a separate plan-review pass.

- **Risk: the secondary fix (originalXHR restore) breaks a file that depends on a stub leaking.** Mitigation: today only two files stub `XMLHttpRequest` (chat-input-attachments, file-tree-upload), both via `vi.stubGlobal` which is already restored by the existing `vi.unstubAllGlobals()` call. The new `originalXHR = globalThis.XMLHttpRequest` restore is redundant for those files and only fires AFTER `unstubAllGlobals` already ran — so it cannot break them. Verified by reading both files: each `beforeEach` re-stubs, so even if the restore wiped an in-progress stub (it can't — it's `afterAll`, not `afterEach`), the next test's `beforeEach` would re-establish it.

- **Risk: drift-guard test becomes brittle.** Mitigation: the assertion checks for the literal tokens `originalXHR` and `globalThis.XMLHttpRequest = originalXHR`, identical to the existing `originalFetch` assertion's grep-stable pattern. If a future refactor renames the variable, the test fails loudly with a clear "rename me too" signal — this is the intended behavior per `cq-code-comments-symbol-anchors-not-line-numbers`.

- **Risk: removing all `setTimeout` from the describe block breaks `userEvent` internal pacing.** Mitigation: `userEvent.type()` and `userEvent.keyboard()` use `setTimeout` internally for keystroke pacing, but those are inside the `userEvent` library's own modules — the grep `rg "setTimeout" apps/web-platform/test/chat-input-attachments.test.tsx` only catches OUR test's setTimeouts, not the library's. The grep verification AC is correctly scoped.

- **Risk: a future test author adds `vi.useFakeTimers()` to the file without realizing it conflicts with `userEvent` and the manual triggers.** Mitigation: add a top-of-file comment block in `chat-input-attachments.test.tsx` that says "DO NOT add `vi.useFakeTimers()` to this file. The XHR progress mocks use manual triggers (see `fireProgress50`/`fireProgress100`/`completeUpload` pattern). Mixing fake timers with `@testing-library/user-event` v14 hangs `await user.type/keyboard` calls — see testing-library/user-event#833." This is a documentation guard, not enforceable, but the next author will see it before running into the trap.

- **Risk: `originalXHR` capture-and-restore introduces a happy-dom warm-up race if `globalThis.XMLHttpRequest` is undefined at setup-file load.** Mitigation: the capture is guarded by `typeof globalThis !== "undefined" ? globalThis.XMLHttpRequest : undefined` and the restore is guarded by `if (originalXHR && typeof globalThis !== "undefined")`. happy-dom 20.8.9 exports `XMLHttpRequest` at window-init time, before any setup-file imports run, so the value is always defined in this codebase. The undefined-fallback is defense-in-depth for a future environment swap (e.g., `environment: "node"` for a non-DOM file).

## Non-Goals

- **Not switching to `vi.useFakeTimers`.** The manual-trigger pattern is sufficient and has lower blast radius.
- **Not migrating to `pool: 'forks'`.** Heavyweight, was rejected in PR #2819.
- **Not adding a new vitest project for chat-input tests.** Same reasoning as above.
- **Not refactoring `lib/upload-with-progress.ts` or `chat-input.tsx`.** Phase 3's 3/3 gate is the trip-wire that escalates to SUT investigation if needed.
- **Not chasing the `AggregateError ECONNREFUSED ::1:3000` log noise from #2524's hypothesis.** It's expected stderr from network-error test paths, unrelated to this assertion.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| `vi.useFakeTimers({ shouldAdvanceTime: true })` + `vi.advanceTimersByTime(20)` between phases | Mixes fake timers with `userEvent` keystroke-pacing setTimeouts; requires manual `advanceTimersByTime` between every `userEvent.type` and `userEvent.keyboard`. Higher cognitive cost than manual triggers, and `cq-raf-batching-sweep-test-helpers` already documents this trap. |
| Add `pool: 'forks'` to the component vitest project | Per-file fork creation is ~5x slower than threads. Was rejected in PR #2819's deliberation. |
| Add a new vitest project with `--no-file-parallelism` for the chat-input file | Sets a precedent for "any flaky file gets its own project". Same rejection rationale as PR #2819. |
| Add `act(() => fireProgress50!())` wrappers | `@testing-library/react` v16's `act` is a passthrough for synchronous calls already; the manual triggers don't need explicit `act` wrapping inside a `waitFor` block. Adding it would be cargo-cult. |
| Raise vitest's default `waitFor` timeout from 5000ms to 15000ms for the file | Masks the bug; doesn't fix it. The Apr-21 recurrence (#2470 comment) already showed that the timeout is hit, not approached — the state genuinely never renders, raising the timeout would not help. |

## Resources

- PR #2819 — "Fix kb-chat-sidebar test flakes under vitest parallel execution" — the precedent fix this PR mirrors.
- `knowledge-base/project/learnings/test-failures/2026-04-22-vitest-cross-file-leaks-and-module-scope-stubs.md` — the architecture rationale for the `setup-dom.ts` originalFetch/restore pattern.
- `knowledge-base/project/learnings/2026-04-12-testing-transient-react-state-in-async-flows.md` — the manual-trigger pattern documented for the same file's "Uploaded" test.
- `knowledge-base/project/learnings/ui-bugs/xhr-upload-progress-and-state-ordering-20260413.md` — context on why XHR-with-progress is the production design (cannot revert to fetch).
- AGENTS.md `cq-vitest-setup-file-hook-scope` — the rule that places the new restore in `afterAll`, not `afterEach`.
- AGENTS.md `cq-code-comments-symbol-anchors-not-line-numbers` — the rule that requires the new code-comment cross-reference to use symbol names, not line numbers.
- AGENTS.md `cq-raf-batching-sweep-test-helpers` — adjacent rule explaining why fake timers were not chosen.
- AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to` — the rule that puts `Closes #2524` and `Closes #2470` in the PR body.

## PR Body Reminder

```
Closes #2524
Closes #2470

[Body content per the plan's Acceptance Criteria. Do NOT promote `Closes` to the title — auto-close fires from the body only.]
```
