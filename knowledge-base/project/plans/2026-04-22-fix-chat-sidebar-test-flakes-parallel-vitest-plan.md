# Fix: chat-surface / kb-chat-sidebar tests flake under vitest parallel execution

**Issues:** Closes #2594 (primary). Closes #2505 (duplicate — same symptom, narrower reproduction window).
**Branch:** `feat-one-shot-fix-chat-sidebar-test-flakes`
**Type:** `fix` (test-infrastructure; no product behavior change)
**Priority:** P3 (operational hygiene — a flaky suite normalizes a red CI).

## Overview

`./node_modules/.bin/vitest run` in `apps/web-platform` intermittently fails 1–8 tests across seven chat-sidebar component test files. `--no-file-parallelism` makes the suite green (2108 pass, 0 fail). The hallmark is **shared mutable module/global state leaking between test files that execute on the same vitest worker thread**.

The fix is **two-layered** and lands in one PR:

1. **Primary — global cleanup harness.** Harden `test/setup-dom.ts` so every component test starts from the same baseline: `sessionStorage`, `localStorage`, `vi.unstubAllGlobals()`, `vi.useRealTimers()`, and (optional) `document.body` reset. This addresses the documented leak surfaces (`kb.chat.sidebarOpen` in `use-kb-layout-state`, `STORAGE_KEY` in `notification-prompt`, ad-hoc `global.fetch`/`vi.stubGlobal` in component tests) without per-file churn.
2. **Secondary — guardrail.** If three consecutive `vitest run` passes are NOT green after the primary fix, scope the `component` vitest project to `isolate: true`. This is documented in the plan but NOT committed up-front — we prefer the diagnosable fix (explicit cleanup) over the blast-radius fix (re-isolate every component test) so the root cause stays visible in the setup file.

**Why this shape, not the #2505 hypothesis verbatim.** The #2505 issue recommends per-file `beforeEach`/`afterEach`. That works but requires edits in all 7 flaky files AND any future sibling (`chat-input-*.test.tsx`, `kb-chat-sidebar-quote.test.tsx`, `kb-layout-chat-close-on-switch.test.tsx`), which already share the same worker pool. A single setup-file edit catches the full class and survives new test files without re-visit. This generalizes beyond the named 7 files to every `.test.tsx` in the `component` project.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality | Plan response |
|---|---|---|
| "jsdom state between parallel workers" (#2505 hypothesis) | Actual environment is **happy-dom** (`vitest.config.ts` line 26). | Plan uses happy-dom-accurate guidance; `cq-jsdom-no-layout-gated-assertions` does NOT apply as-is but the *principle* (no layout-engine assertions) still holds. Plan does not add any layout-gated assertions. |
| "sessionStorage, timers, focus, DOM state leakage" | Confirmed: `hooks/use-kb-layout-state.tsx:206` writes `kb.chat.sidebarOpen` to sessionStorage; `components/chat/notification-prompt.tsx:21-37` writes to localStorage; `setup-dom.ts` cleans only `@testing-library/react` DOM — no storage/timer/global reset. | Plan writes explicit per-test cleanup of all four surfaces in `setup-dom.ts`. |
| "WebSocket mock singletons" (#2505 hypothesis) | Each of the 7 files declares module-scope `let wsReturn = createWebSocketMock(...)` + `vi.mock("@/lib/ws-client", () => ({ useWebSocket: () => wsReturn }))`. The `wsReturn` is reset in the file's own `beforeEach`, so intra-file it is fine. BUT: `vi.fn()` instances inside the mock factory are **closures over the file's module scope**, and vitest 3.1 with `pool: 'threads'` shares module graphs across files that land on the same worker. | Plan does not rewrite every `wsReturn` singleton (low-value churn). Instead, adds `vi.restoreAllMocks()` to setup-dom.ts so spies/mocks can't accumulate call-counts across files. This is the real "singleton leak" surface — not the object, the accumulated call history. |
| "Split the flaky files into their own vitest project with `--no-file-parallelism`" (#2594 option 3) | Would shove the suite runtime up for future chat-sidebar tests and set a precedent for "flaky → own project". | Rejected. `isolate: true` on the existing `component` project is the cleaner escape valve if Step 1 is insufficient. |
| "Add `test.isolate: true` or `pool: 'forks'` to vitest.config.ts" (#2594 option 1) | This re-instantiates the module graph for every test file. Fixes the symptom but *hides* the leaks. | Deferred to Phase 4 guardrail only. Shipped only if setup-harness + targeted cleanup do not yield 3/3 green. |

## Hypotheses

H1 (PRIMARY, high confidence): **sessionStorage/localStorage state leaks between files on the same worker.** `use-kb-layout-state` persists `kb.chat.sidebarOpen=1` on any test that interacts with the sidebar-open path. The next file's `render(<KbChatSidebar />)` or `<ChatPage />` then mounts with a stale sidebar-open hint, changing initial DOM structure and breaking queries for "send a message to get started" or "aria-label that includes the filename". `notification-prompt.tsx` does the same via `localStorage`.

H2 (HIGH confidence): **`vi.stubGlobal`/`global.fetch` assignments leak across files.** At least one chat-related test suite (spot-checked in `chat-page.test.tsx` and the sidebar files) uses fetch mocks. Without `vi.unstubAllGlobals()` in `afterEach`, File A's `fetch` mock can answer File B's `thread-info` request (see `use-kb-layout-state.tsx:243` — `/api/chat/thread-info` fetch fired on mount).

H3 (MEDIUM confidence): **Accumulated spy call-history causes assertions to observe events from prior files.** Without `vi.restoreAllMocks()` / `vi.clearAllMocks()` in `afterEach`, `mockStartSession.mock.calls` or `mockTrack.mock.calls` can hold invocations from a prior test file, changing `toHaveBeenCalledTimes(1)` outcomes.

H4 (LOW confidence, watch-only): **Timer leaks.** A few of these files use `setTimeout`/`requestAnimationFrame` debouncing (see `chat-input.tsx` draft debounce). If a test finishes before its 250 ms debounce fires, and the next file's happy-dom DOM is already different, the callback can touch a torn-down tree. `vi.useRealTimers()` in `afterEach` plus explicit `await` of `waitFor` already bounds this. Plan adds `vi.useRealTimers()` as cheap insurance.

Not a network-outage symptom — the **1.4 checklist does not apply**. (No SSH, firewall, DNS, kex, or 5xx language; this is a vitest/happy-dom issue.)

## Files to Edit

- `apps/web-platform/test/setup-dom.ts` — primary fix: add storage/timer/mock cleanup in `afterEach`. **Also add `beforeEach` so state is clean even if prior file skipped afterEach due to thrown assertion.**
- `apps/web-platform/vitest.config.ts` — (Phase 4, conditional) add `isolate: true` to the `component` project only if Phase 3 does not yield 3/3 green.

## Files to Create

- `apps/web-platform/test/setup-dom-leak-guard.test.ts` — meta-test in the `unit` project that asserts `setup-dom.ts` exports a cleanup function covering the four surfaces. This is a drift-guard: a future PR that removes the sessionStorage clear silently re-opens the flake. See sharp edge: drift-resistant cleanup.

## Files NOT to Edit (explicit non-goals)

- The 7 flaky `.test.tsx` files. Per-file beforeEach additions are rejected — setup-harness edit is the whole-class fix. If any single file still flakes after Phase 3, re-open scope.
- `hooks/use-kb-layout-state.tsx`, `components/chat/notification-prompt.tsx`, `components/chat/chat-input.tsx`. These are the **source** of the sessionStorage/localStorage writes, and that behavior is correct product behavior. The tests must tolerate real storage; storage must be reset between tests.
- Other component test files (`chat-input-*.test.tsx`, `dashboard-sidebar-collapse.test.tsx`, etc.). They share the same environment but are currently not flaking. The setup-harness edit will cover them prophylactically at zero additional code cost.

## Open Code-Review Overlap

1 match:

- **#2594** — the flake issue itself (this plan closes it). Listed as its own "overlap" because it IS in `code-review` label set. **Disposition: Fold in** — this plan IS the fix.

No other open `code-review` issue touches the 7 flaky files or `setup-dom.ts`.

## Detail Level: MORE

(More than MINIMAL because the fix is subtle and the exit criterion is statistical — but less than A LOT because there is exactly one surface to edit.)

## Implementation Phases

### Phase 1 — Reproduce the flake deterministically (30 min)

Goal: confirm the failure modes before patching, and capture one known-failing run output as the RED baseline.

1. `cd apps/web-platform`
2. Run `./node_modules/.bin/vitest run 2>&1 | tee /tmp/vitest-baseline-1.log` — record pass/fail counts.
3. Repeat 5x. Tally which tests fail across runs. Expect 1–8 failures each, not always the same tests.
4. Verify serial is green: `./node_modules/.bin/vitest run --no-file-parallelism 2>&1 | tail -20` → expect 2108 pass, 0 fail.
5. (Diagnostic) Run with `--reporter=verbose --poolOptions.threads.singleThread=true` to confirm single-thread is also green. If yes, confirms the leak is **cross-file within a worker**, not timer-driven within a file.

**Exit:** baseline logs saved to `/tmp/vitest-baseline-*.log`. Failure pattern documented in PR description.

### Phase 2 — Harden `setup-dom.ts` (RED → GREEN)

Exempt from TDD gate: this is a test-infrastructure change. The RED signal IS the flake itself, already captured in Phase 1.

Edit `test/setup-dom.ts`:

```ts
import "@testing-library/jest-dom/vitest";
import { afterEach, beforeEach, vi } from "vitest";

// Run in both hooks: beforeEach guarantees a clean slate even if a prior
// test threw out of afterEach; afterEach guarantees nothing leaks forward.
function resetBrowserLikeGlobals() {
  if (typeof sessionStorage !== "undefined") {
    try {
      sessionStorage.clear();
    } catch {
      /* happy-dom with disabled storage — ignore */
    }
  }
  if (typeof localStorage !== "undefined") {
    try {
      localStorage.clear();
    } catch {
      /* ignore */
    }
  }
}

beforeEach(() => {
  resetBrowserLikeGlobals();
});

afterEach(async () => {
  // DOM cleanup (pre-existing behavior — retained)
  if (typeof document !== "undefined") {
    const { cleanup } = await import("@testing-library/react");
    cleanup();
  }

  // 1. Restore spies/mocks so call-history does not accumulate across files.
  //    NOTE: vi.restoreAllMocks() also restores original implementations of
  //    any `vi.spyOn(...)` targets, which is the behavior we want.
  vi.restoreAllMocks();

  // 2. Undo any `vi.stubGlobal(...)` (e.g., `vi.stubGlobal("fetch", fn)`).
  vi.unstubAllGlobals();

  // 3. Undo any `vi.stubEnv(...)` for the same reason.
  vi.unstubAllEnvs();

  // 4. Ensure timers are real — a prior test that forgot to `vi.useRealTimers()`
  //    in its own afterEach would otherwise leak fake timers into the next file.
  vi.useRealTimers();

  // 5. Clear storage again in case the test wrote between beforeEach and now.
  resetBrowserLikeGlobals();
});
```

**Key subtleties.**

- `vi.restoreAllMocks()` is a superset of `vi.clearAllMocks()` + `vi.resetAllMocks()`. Use the strongest form — we want spies unwound.
- `vi.restoreAllMocks()` does **not** undo `vi.mock("@/lib/ws-client", ...)` hoisted-module mocks. Those are module-graph-wide and survive this hook. That is intentional — the tests RELY on those hoisted mocks being stable across their own tests. Cross-file isolation of module mocks is Phase 4's job (isolate).
- `vi.unstubAllGlobals()` is idempotent; safe to call even if no stubs were set.
- `try/catch` around `sessionStorage.clear()` handles the defensive case where happy-dom's storage has been stubbed to throw (some tests do this to simulate Safari private mode).
- The `beforeEach` is DEFENSIVE — if a prior `afterEach` threw (e.g., `cleanup()` raised), the next test still starts clean.

**Do NOT add:** `vi.resetModules()`. It nukes the module graph, which would defeat hoisted `vi.mock()` calls in all test files and break everything. If we decide module isolation IS needed, that is Phase 4 (`isolate: true`), not a manual `resetModules()`.

### Phase 3 — Verify the primary fix (3 consecutive green runs)

1. `./node_modules/.bin/vitest run 2>&1 | tee /tmp/vitest-fix-1.log` — expect 2109 pass, 0 fail.
2. Repeat 2 more times. All 3 must be clean.
3. (Stress) Run with `--pool=threads --poolOptions.threads.maxThreads=8 --pool.isolate=false` to force worst-case concurrency. One green run at max contention is a confidence multiplier.
4. If 3/3 clean → proceed to Phase 5 (drift-guard test). Skip Phase 4.
5. If ANY run fails → proceed to Phase 4.

**Exit criterion:** three consecutive `vitest run` invocations produce `2109 pass, 0 fail`. **This MUST be documented in the PR body with the 3 log tails** so the reviewer can see evidence, not a promise. (Per constitution: the PR body, not the conversation, is the evidence of exit criteria.)

### Phase 4 — Guardrail: scope `isolate: true` to the component project (CONDITIONAL)

Only execute if Phase 3 did NOT achieve 3/3 green.

Edit `apps/web-platform/vitest.config.ts`:

```ts
{
  extends: true,
  test: {
    name: "component",
    environment: "happy-dom",
    include: ["test/**/*.test.tsx"],
    setupFiles: ["test/setup-dom.ts"],
    isolate: true,  // <-- NEW: per-file module-graph isolation
  },
},
```

`isolate: true` causes vitest to create a fresh module graph per test file — the strongest form of cross-file isolation available without switching to `pool: 'forks'` (which would be a larger performance hit).

Trade-off: ~15–25% slower component-project runtime (varies by hardware). This is acceptable for the flake kill. Do NOT change `pool: 'forks'` — threads with `isolate: true` is faster than forks and sufficient.

**Exit criterion:** same as Phase 3 — 3 consecutive green runs.

### Phase 5 — Drift-guard test

Create `apps/web-platform/test/setup-dom-leak-guard.test.ts`:

```ts
import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

// Drift guard: if a future PR removes one of the four cleanup surfaces from
// setup-dom.ts, this test fails with a clear message — cheaper than
// re-debugging another 3-week flake cycle.
//
// See knowledge-base/project/plans/2026-04-22-fix-chat-sidebar-test-flakes-parallel-vitest-plan.md
// for the original 4-surface cleanup rationale.
describe("setup-dom.ts cleanup surfaces", () => {
  const source = readFileSync(
    resolve(__dirname, "setup-dom.ts"),
    "utf8",
  );

  it.each([
    ["sessionStorage clear", "sessionStorage.clear()"],
    ["localStorage clear", "localStorage.clear()"],
    ["restoreAllMocks", "vi.restoreAllMocks()"],
    ["unstubAllGlobals", "vi.unstubAllGlobals()"],
    ["useRealTimers", "vi.useRealTimers()"],
  ])("retains %s", (_label, token) => {
    expect(source).toContain(token);
  });
});
```

This test lives in the **`unit` project** (`.test.ts`, not `.test.tsx`) so it runs fast and with a node environment, and it reads the source text so it is grep-stable across refactors. Deliberate: the assertion is on presence of the literal token, not on behavior, so a reviewer can see exactly what it guards.

**Do NOT** use line numbers — use symbol/token anchors per `cq-code-comments-symbol-anchors-not-line-numbers`.

### Phase 6 — Close duplicate + cross-link

1. PR body: `Closes #2594` and `Closes #2505` (per `wg-use-closes-n-in-pr-body-not-title-to`; qualifiers banned).
2. After merge, add a comment to #2505 linking #2594 and the merged PR, for future searchers.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `./node_modules/.bin/vitest run` (from `apps/web-platform/`) produces `2109 pass, 0 fail` on **three consecutive invocations**. Log tails (not summaries) pasted in PR body.
- [ ] `./node_modules/.bin/vitest run --no-file-parallelism` still produces `2109 pass, 0 fail` (regression check — did not break serial path).
- [ ] `npx tsc --noEmit` (from `apps/web-platform/`) clean.
- [ ] Drift-guard test (`test/setup-dom-leak-guard.test.ts`) exists in the `unit` project and passes.
- [ ] No edits to the 7 flaky component test files (symmetry: same test code, less flake).
- [ ] No edits to `use-kb-layout-state.tsx`, `notification-prompt.tsx`, `chat-input.tsx`, or other product-behavior source files.
- [ ] If `vitest.config.ts` was edited (Phase 4), the `isolate: true` change is scoped to the `component` project only — the `unit` project is untouched.

### Post-merge (operator)

- [ ] Within 48 hours, observe 3 consecutive main-branch CI runs with `apps/web-platform` component tests green. If any CI run flakes, re-open #2594.

## Test Scenarios

| Scenario | Expected | Verification |
|---|---|---|
| Parallel `vitest run`, default config | 2109 pass / 0 fail | Phase 3, 3x |
| Parallel `vitest run`, `--poolOptions.threads.maxThreads=8` | 2109 pass / 0 fail | Phase 3 stress step |
| Serial `vitest run --no-file-parallelism` | 2109 pass / 0 fail | Pre-merge AC regression check |
| `test/setup-dom-leak-guard.test.ts` with stripped cleanup | Fails with "retains sessionStorage clear" etc. | Phase 5 drift-guard intent |
| Drift-guard catches removal of `vi.unstubAllGlobals()` | Specific `it.each` row fails | Verified by manually deleting the line locally, running the guard, then restoring |

## Risks & Mitigations

- **Risk:** happy-dom `sessionStorage.clear()` may throw in some test helpers that stub storage to simulate Safari-private-mode.
  **Mitigation:** `try/catch` around `clear()` calls. Documented in the setup-dom.ts code comment so a reader understands why the `catch` is silent.

- **Risk:** `vi.restoreAllMocks()` restores `vi.spyOn(...)` targets to their originals — if a test file establishes a `spyOn` in a `beforeAll` expecting it to survive across tests in the file, the `afterEach` restore will undo it.
  **Mitigation:** grep for `beforeAll.*spyOn` in `apps/web-platform/test/**/*.test.tsx` during Phase 2. If hits exist, either (a) move those spies into per-test `beforeEach`, or (b) document the collision and use `vi.clearAllMocks()` + explicit `vi.unstubAllGlobals()` instead. **Verification step in Phase 2.**

- **Risk:** Phase 4 (`isolate: true`) slows the component project noticeably on slower CI runners.
  **Mitigation:** Only engage Phase 4 if Phase 3 cannot hit 3/3 green. If engaged, measure the delta (pre/post wall-clock from `/tmp/vitest-baseline-1.log` vs post-fix log) and document in PR body. Acceptable ceiling: +25% component-project runtime.

- **Risk:** The drift-guard test depends on source-text literals. A future reformatter could wrap `sessionStorage.clear()` onto a new line as `sessionStorage\n.clear()`, breaking the `.toContain()`.
  **Mitigation:** The literal tokens chosen (`sessionStorage.clear()`, `vi.restoreAllMocks()`, etc.) are already in their idiomatic one-line form and are not split by any common formatter. If the drift-guard ever fails due to formatter rewriting rather than real drift, update the guard to use regex. Call this out in the code comment above the `it.each`.

- **Risk:** Some other test file (not in the original 7) already relied on leaked `sessionStorage` from the chat-sidebar tests (e.g., implicitly tested that `kb.chat.sidebarOpen=1` persisted after a prior file set it).
  **Mitigation:** extremely unlikely (no test written with that dependency would pass `--no-file-parallelism`, which is currently green). If it surfaces post-fix, the failing test is itself buggy — it should set its own storage in `beforeEach`.

## Non-Goals

- **Rewriting the module-scope `let wsReturn` pattern.** It's fine intra-file; the inter-file leak is covered by `restoreAllMocks()`. Rewriting would churn 7 files for zero leak-reduction benefit.
- **Migrating off happy-dom to jsdom.** happy-dom is faster; the flake is not specific to happy-dom.
- **Moving these 7 tests to a playwright suite.** They test component mount/unmount contracts, not real-browser layout. E2E is the wrong tool.
- **Closing other `code-review`-labeled flakes.** Scope is strictly the chat-sidebar set. A follow-up audit can decide whether to retire other brittle tests.

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| Per-file `beforeEach`/`afterEach` in each of 7 flaky test files | High-churn, doesn't cover future new sibling test files. The setup-harness edit is strictly cleaner and one-shot. |
| `pool: 'forks'` for the whole workspace | Slower than `pool: 'threads' + isolate: true`. Overkill. |
| Split into a dedicated vitest project with `--no-file-parallelism` | Hides the root cause and makes future chat-sidebar tests slower forever. |
| `vi.resetModules()` in afterEach | Destroys hoisted `vi.mock()` calls — would break the tests, not fix them. |
| Switch environment to node + explicit DOM injection per test | Out of scope; requires rewriting all component tests. |

## Research Insights

- **Vitest 3.1 `pool: 'threads'` default behavior:** when `isolate: false` (the default for threads), each worker re-uses its module graph across test files. SessionStorage/localStorage on happy-dom live on the shared worker global. This is documented in vitest's config reference (`isolate` section). **Verified via** `grep -R "isolate" node_modules/vitest/dist/config.d.ts` — field exists on both workspace-level and project-level config.
- **`vi.restoreAllMocks()` vs `vi.resetAllMocks()` vs `vi.clearAllMocks()`:** restore is the superset — it unwinds `vi.spyOn` targets AND clears call history. Per vitest docs: <https://vitest.dev/api/vi.html#vi-restoreallmocks> — source: vitest API reference, still current as of vitest@3.1 (consulted 2026-04-22).
- **`vi.unstubAllGlobals()` is required for `vi.stubGlobal("fetch", …)` cleanup.** `vi.restoreAllMocks()` does NOT undo `stubGlobal` — verified via the vitest source `packages/vitest/src/integrations/vi.ts` (stubs live on a separate map). This is why both are needed in the same `afterEach`.
- **setup-dom.ts is loaded via `setupFiles`, not inline.** `setupFiles` run inside each test file's isolated scope (when `isolate: true`) OR once per worker (when `isolate: false`). Either way, `beforeEach`/`afterEach` hooks declared in a setup file register PER TEST, not per file — so the cleanup fires for every individual test. Verified against vitest setup-files docs.

## Dependencies

- No new dependencies. `vitest@3.1.0` is already present (`devDependencies` in `apps/web-platform/package.json`).
- No terraform, no Doppler, no GitHub Actions — a pure test-infrastructure fix.

## Domain Review

**Domains relevant:** none.

This is a test-infrastructure / CI reliability fix with no product-user-facing surface, no pricing/billing implications, no legal/privacy angle, no marketing artifact, no content change, no ops/security surface. Engineering (CTO) domain is the task topic itself — per `pdr-do-not-route-on-trivial-messages-yes`, no routing.

No cross-domain implications detected — infrastructure/tooling change.

## Sharp Edges (for this plan specifically)

- **The exit criterion is statistical.** "3 consecutive green runs" is not "1 green run." A single green run is not evidence — it could be luck. The PR body MUST show 3 log tails, not 1.
- **Do not `--amend` if the first green-run measurement happens, then later runs flake.** That would silently hide the regression signal. Commit the fix, measure openly, if it flakes back amend the plan (Phase 4), not the measurement.
- **`restoreAllMocks()` runs BEFORE `useRealTimers()` in the order above — keep that order.** If `useRealTimers()` fires first and a fake-timer mock is still registered, the restore step can observe inconsistent state. Tested order: unmount DOM → restore mocks → unstub globals/envs → useRealTimers → final storage clear.
- **Do not extend this plan's scope to `chat-input-*.test.tsx` even if they look similar.** Those tests are NOT currently flaking. The setup-harness edit will cover them prophylactically; touching their files opens unrelated review surface.

## Return Contract (for one-shot pipeline)

- Plan file: `knowledge-base/project/plans/2026-04-22-fix-chat-sidebar-test-flakes-parallel-vitest-plan.md`
- Tasks file: will be written at `knowledge-base/project/specs/feat-one-shot-fix-chat-sidebar-test-flakes/tasks.md`
- Branch: `feat-one-shot-fix-chat-sidebar-test-flakes`
- Issues closed: #2594 (primary), #2505 (duplicate)
