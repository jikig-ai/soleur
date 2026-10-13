# chore(chat-sidebar): drain review backlog #2386 + #2391

**Branch:** `feat-one-shot-drain-review-backlog-2386-2391`
**Worktree:** `.worktrees/feat-one-shot-drain-review-backlog-2386-2391`
**Origin PR:** #2347 (kb-chat-sidebar)
**Closes:** #2386, #2391
**Type:** chore / test refactor + inline code-doc polish
**Severity:** P3 (nice-to-have, no runtime behavior change)

## Enhancement Summary

**Deepened on:** 2026-04-18
**Sections enhanced:** Factory design, behavior hooks, seam pattern, rate-limiter doc pointer, TDD gates, risks
**Research inputs:** Codebase grep (existing `__resetXxxForTest` seams, existing `wrapCode` prop on `MarkdownRenderer`), learnings carry-forward (rule `cq-raf-batching-sweep-test-helpers`, `cq-test-mocked-module-constant-import`, `cq-vite-test-files-esm-only`), PR #2500 post-mortem (rAF + fake timers), PR #2569 post-mortem (constant extraction + mocked-module trap).

### Key Improvements Over Baseline Plan

1. **`data-narrow-wrap` attribute routes through the existing `wrapCode` prop on `MarkdownRenderer`** — no new prop, no widened component surface. One-line edit on line 114 of `components/ui/markdown-renderer.tsx`.
2. **Factory drift-guard tightened.** `ReturnType<typeof useWebSocket>` is confirmed as the canonical hook return; factory must set `satisfies` on the return to get the compile-time drift check even if a consumer supplies stale overrides.
3. **`readSelection` seam uses the established `__resetXxxForTest` export convention** (confirmed via grep: 5+ existing uses in `server/rate-limiter.ts`, `server/share-hash-verdict-cache.ts`, `app/api/analytics/track/throttle.ts`). No new convention introduced.
4. **rAF + fake-timers guard-rails on the `waitFor` replacements** — learnings rule `cq-raf-batching-sweep-test-helpers` (from PR #2500) says `vi.useFakeTimers` does NOT auto-advance rAF under synchronous `act()`. The a11y test is NOT currently using fake timers (confirmed), so `waitFor` is safe; if that ever changes, the acceptance criterion flags it.
5. **Explicit ESM import rule** — per `cq-vite-test-files-esm-only` (PR #2347 learning), the new `test/helpers/dom.ts` and `test/mocks/use-websocket.ts` MUST use top-level `import`, not `require()`.
6. **Pre-emptive constant-import trap callout** — per `cq-test-mocked-module-constant-import` (PR #2569 learning), the new factory lives in `test/mocks/` which is NOT itself `vi.mock()`-ed by any consumer, so the trap does not apply. Documented to prevent a future reviewer from re-raising it.

## Overview

Drain two P3 review-backlog issues filed against the merged kb-chat-sidebar PR (#2347) in a single cleanup PR. Both issues touch the `apps/web-platform` chat-input area and its session/rate-limiter plumbing, so they naturally fold into one PR.

**#2386 — test quality (3 sub-findings + a bonus):**

- **6A.** Extract a `createWebSocketMock(overrides?)` factory so the 15-field `useWebSocket` mock duplicated across 7 chat-sidebar test files stops drifting on every hook-shape change.
- **6B.** Replace Tailwind-class-name assertions (`whitespace-pre-wrap`, `overflow-wrap:anywhere`, `min-w-0`, `ring-(2|amber)`) with behavior-level assertions — `data-state` attributes, `getComputedStyle`, or `getBoundingClientRect()`-derived wrap checks — so refactoring Tailwind → CSS modules or renaming a ring class does not break tests.
- **6C.** Replace three `await new Promise((r) => setTimeout(r, 0))` focus-flushes in `kb-chat-sidebar-a11y.test.tsx` with `await waitFor(...)`. Replace the `Selection.toString` monkey-patch in `selection-toolbar.test.tsx` with a DI-friendly `readSelection()` helper (or Testing Library selection primitive) so the component is no longer coupled to jsdom internals at the test level.
- **Bonus.** Extract the hand-rolled `setControlledValue(el, value, cursor)` helper duplicated across `chat-input-quote.test.tsx`, `chat-input-draft-key.test.tsx`, and `kb-chat-sidebar-quote.test.tsx` into `test/utils/dom.ts`.

**#2391 — session supersession UX + rate-limit scaling note (2 sub-findings, doc-only):**

- **11A.** Document the cross-tab session supersession invariant at the `resumeByContextPath` branch in `server/ws-handler.ts`. Two tabs under the same user share one `sessions.get(userId)` entry; opening tab B evicts tab A silently. Per-doc context_path threads don't change that invariant — add a code comment so the next reader doesn't assume two tabs get two live streams. (The architecture-strategist's other two options — UI supersession banner and rollout QA scenario — are out of scope: shipping a banner is a feature, not a review-backlog drain; the plan.md rollout checklist belongs to a future feature-flag-flip PR, not this one.)
- **11B.** Add a one-line comment at `app/api/analytics/track/throttle.ts` pointing to the existing `Single-instance assumption` / Redis-switch note in `server/rate-limiter.ts` so the new `analyticsTrackThrottle` inherits the caveat by reference rather than silence.

No runtime behavior change. No new dependencies. No migration. No feature flag. This is a test-quality + code-doc cleanup PR.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (from #2386/#2391 bodies) | Reality in worktree | Plan response |
| --- | --- | --- |
| #2386 lists `kb-chat-sidebar-a11y.test.tsx:110` as a `setTimeout(0)` site | `waitFor` landed in a later fix at line 172; three stale `setTimeout(r, 0)` sites remain at lines 125/135/140 | Target those three remaining sites. The fourth case (line 172) is already `waitFor` — do not touch. |
| #2386 prescribes `test/mocks/use-websocket.ts` factory location | `test/mocks/use-team-names.ts` exists as the pattern; `test/mocks/` is the conventional directory | Place new factory at `test/mocks/use-websocket.ts` (matches existing convention). |
| #2386 bonus prescribes `test/utils/dom.ts` | `test/utils/` directory does not exist; `test/helpers/` does. | Create `test/helpers/dom.ts` instead (respect existing convention; adjust issue callers). |
| #2391 prescribes comment at `app/api/analytics/track/route.ts:22` | The throttle is now a sibling module at `throttle.ts` (post-#2347 split per `cq-nextjs-route-files-http-only-exports`). | Add the comment in `throttle.ts` at the throttle construction site; add a one-liner in `route.ts` pointing to it if the field `analyticsTrackThrottle` is still imported there. |

## Open Code-Review Overlap

Two open scope-outs touch `server/ws-handler.ts` and `server/rate-limiter.ts`, but NONE of their concerns overlap with #2391's ask:

- **#2191** `refactor(ws): clearSessionTimers helper + refresh-timer jitter` — structural timer refactor. Different concern. **Defer.** #2391 is a 1-line code comment; #2191 is a timer-semantics refactor with its own test coverage. Folding them in would balloon this PR's blast radius. Leave #2191 open; the drain for it is a separate ws-handler PR.
- **#2196** `refactor(rate-limiter): dedupe prune-interval and compaction, standardize unref` — structural dedupe of rate-limiter internals. Different concern. **Defer.**
- **#2197** `refactor(billing): SubscriptionStatus type + hoist single-instance throttle doc + Sentry breadcrumb UUID policy` — this one is *adjacent* to #2391's 11B (both touch the single-instance doc). **Acknowledge.** #2391 adds a pointer *from* analytics-track *to* rate-limiter's existing caveat; #2197 proposes hoisting the caveat *out of* rate-limiter into a shared location. They are compatible — if #2197 later lands, the one-line pointer in `throttle.ts` can be updated to the new location with a trivial edit. Leave #2197 open.

Files to edit in this PR do NOT overlap with any *same-concern* scope-out.

## Files to edit

### Test quality (#2386)

- `apps/web-platform/test/mocks/use-websocket.ts` — **new.** Factory `createWebSocketMock(overrides?)` returning a complete `ReturnType<typeof useWebSocket>` shape for drift-resistance. Mirrors `test/mocks/use-team-names.ts` structure.
- `apps/web-platform/test/helpers/dom.ts` — **new.** Shared `setControlledValue(el, value, cursor?)` helper plus any companion (`getTextarea()` is cheap enough to keep local — do NOT hoist unless 3+ call sites).
- `apps/web-platform/test/chat-surface-sidebar.test.tsx` — replace inline `wsReturn` with factory; rewrite class-name assertions → behavior assertions.
- `apps/web-platform/test/chat-surface-sidebar-wrap.test.tsx` — same treatment. Rewrite the `min-w-0` ancestor-walk into a `getBoundingClientRect()`-based "no horizontal overflow" check OR a `data-narrow-wrap="true"` attribute on the bubble wrapper that the component exposes. **Preferred:** add `data-narrow-wrap` to the sidebar-variant wrapper in `MarkdownRenderer` (one-line source change in the component, not the test) and assert on that. This is the cleanest behavior-level hook.
- `apps/web-platform/test/kb-chat-sidebar.test.tsx` — factory swap.
- `apps/web-platform/test/kb-chat-sidebar-a11y.test.tsx` — factory swap + replace 3 `setTimeout(r, 0)` sites (lines 125/135/140) with `await waitFor(() => expect(document.activeElement).toBe(...))`.
- `apps/web-platform/test/kb-chat-sidebar-banner-dismiss.test.tsx` — factory swap.
- `apps/web-platform/test/kb-chat-sidebar-close-abort.test.tsx` — factory swap.
- `apps/web-platform/test/kb-chat-sidebar-quote.test.tsx` — factory swap + `setControlledValue` helper import.
- `apps/web-platform/test/chat-input-quote.test.tsx` — `setControlledValue` helper import; rewrite `ring-(2|amber)` assertion → `data-quote-flashing="true"` attribute or a `getComputedStyle` check on the computed `box-shadow` / `outline`. **Preferred:** add `data-quote-flashing` to the textarea in `ChatInput` (one-line source change) and assert on that. The architecture-strategist explicitly called this the "right fix for the flashQuote timer issue" in #2386.
- `apps/web-platform/test/chat-input-draft-key.test.tsx` — `setControlledValue` helper import.
- `apps/web-platform/test/selection-toolbar.test.tsx` — stop monkey-patching `Selection.toString`. Introduce a `readSelection()` injection seam in `components/kb/selection-toolbar.tsx` that defaults to `() => window.getSelection()?.toString() ?? ""`. Tests pass a test-only override. If a prop-level injection widens the component's public API too much, use a module-level `__setReadSelectionForTest` helper exported under `__test__` (pattern already in use in the codebase — grep `__reset` helpers).

### Component attribute hooks (#2386 6B support)

- `apps/web-platform/components/ui/markdown-renderer.tsx` — on line 114, change `<div className="min-w-0 [overflow-wrap:anywhere]">` to emit `data-narrow-wrap={wrapCode ? "true" : undefined}`. The `wrapCode` prop (line 100) is ALREADY the sidebar-variant signal (confirmed via line 97-99 docblock: "Set by sidebar-variant callers where the 380px column makes horizontal scroll unreadable"). Zero new prop, zero widened surface.
- `apps/web-platform/components/chat/chat-input.tsx` — line 571 currently reads `(flashQuote ? " ring-2 ring-amber-400" : "")`. Add `data-quote-flashing={flashQuote ? "true" : undefined}` to the same textarea JSX element. The `flashQuote` state (line 65) is local, 500ms TTL, and already toggled on insert; zero new state.
- `apps/web-platform/components/kb/selection-toolbar.tsx` — extract the two `window.getSelection()` reads (lines 72, 139) into a module-level `readSelection` reference. Default: `() => typeof window !== "undefined" ? (window.getSelection()?.toString() ?? "") : ""`. Export a test helper: `export function __setReadSelectionForTest(fn: () => string): void { readSelection = fn; }`. Mirror the naming of the 5 existing `__resetXxxForTest` exports in the codebase (`__resetShareHashVerdictCacheForTest`, `__resetInvoiceThrottleForTest`, `__resetAnalyticsTrackThrottleForTest`). Reset in `afterEach` to the default.

### Code-doc polish (#2391)

- `apps/web-platform/server/ws-handler.ts` — add a comment block immediately above the `resumeByContextPath` branch (around line 372) explaining the single-session-per-user invariant and the two-tab supersession consequence. Example:

  ```ts
  // Cross-tab session supersession (#2391): `sessions` is keyed by userId,
  // not by (userId, context_path). Opening tab B with a resumeByContextPath
  // will close tab A's socket (see auth success path, ~line 826 — WS_CLOSE
  // code SUPERSEDED). Per-doc context_path resumption does NOT grant two
  // tabs independent live streams; it only resolves the *persisted*
  // conversation row. A UI-level "another tab took over" banner is tracked
  // as a separate feature follow-up.
  ```

- `apps/web-platform/app/api/analytics/track/throttle.ts` — add a one-line reference above the `analyticsTrackThrottle` construction:

  ```ts
  // Single-instance in-memory counter — inherits the Redis-switch caveat
  // documented at server/rate-limiter.ts: see the "Single-instance
  // assumption" note above `invoiceEndpointThrottle` (~line 259). When
  // infra scales to >1 instance, all SlidingWindowCounter instances
  // (invoice, session, analytics-track) must switch to Redis together.
  ```

- `apps/web-platform/app/api/analytics/track/route.ts` — no change required. The import of `analyticsTrackThrottle` from `./throttle` carries the caveat by proximity.

## Non-goals

- **UI banner for supersession.** #2391 11A lists a banner as an *alternative* fix. A banner is a feature PR (design, copy, accessibility review), not a review-backlog drain. Code comment only.
- **Hoisting the single-instance doc into `knowledge-base/engineering/`.** Listed as an alternative in #2391 11B. Leave the canonical doc at the code site; centralization is #2197's concern, not this PR's.
- **Touching #2191 / #2196 / #2197 surface.** Same-file overlap, different concerns. Deferred in the Overlap section above.
- **Rewriting `setControlledValue` call-sites not listed in #2386.** The grep should cover exactly the three sites named in the issue.
- **Removing the `Selection.toString` stub without a component seam.** If the `readSelection` seam is rejected during review, the monkey-patch stays — the fix is the seam, not the test-side cleanup on its own.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `test/mocks/use-websocket.ts` exists, exports `createWebSocketMock(overrides?: Partial<T>): T` where `T = ReturnType<typeof useWebSocket>`.
- [x] All 7 chat-sidebar test files import the factory and none declare a hand-duplicated `wsReturn` literal with 15 fields.
- [x] `kb-chat-sidebar-a11y.test.tsx` contains zero `setTimeout(r, 0)` flushes (grep returns zero hits for `setTimeout.*r.*,\s*0` in that file).
- [x] `selection-toolbar.test.tsx` does NOT call `Object.defineProperty(sel, "toString", ...)`; the component's `readSelection` seam is the only path.
- [x] `chat-surface-sidebar-wrap.test.tsx`, `chat-input-quote.test.tsx` contain no assertions against literal Tailwind class names (`whitespace-pre-wrap`, `overflow-wrap:anywhere`, `min-w-0`, `ring-2`, `ring-amber`). Grep must return zero hits for those strings in those files.
- [x] `test/helpers/dom.ts` exists, exports `setControlledValue`, and the three named test files import from it.
- [x] `server/ws-handler.ts` contains a comment referencing #2391 at the `resumeByContextPath` branch (grep `#2391` in the file).
- [x] `app/api/analytics/track/throttle.ts` contains a comment pointing to the rate-limiter single-instance note (grep for `rate-limiter` or `Single-instance` in that file).
- [x] `node node_modules/vitest/vitest.mjs run` (from `apps/web-platform`) passes with the same or higher count than the pre-change baseline. Expect 1463 pass (no new tests added; assertions reshape, not count-change).
- [x] `tsc --noEmit` from `apps/web-platform`: clean.
- [x] `next build` from `apps/web-platform`: succeeds. (Guards against App Router `route.ts` non-HTTP export regression — `cq-nextjs-route-files-http-only-exports`.)
- [x] PR body contains `Closes #2386` AND `Closes #2391` on separate lines in the body (NOT the title; `wg-use-closes-n-in-pr-body-not-title-to`).

### Post-merge (operator)

- [x] None. No migrations, no Terraform, no infra, no feature flag, no new env var, no deploy-time action.

## Test Scenarios

### TDD gate for #2386 6A (fixture factory)

- **RED (before factory):** No test needs to fail first — this is a pure test-refactor where behavior is already green. The "failing" check is structural: grep for the 15-field `wsReturn` literal across the 7 files must return 7 hits before the change and 0 hits after.
- **GREEN:** After factory extraction, all 7 files import `createWebSocketMock`. Vitest run must pass at the same count.
- **REFACTOR:** TypeScript return-type binding (`ReturnType<typeof useWebSocket>`) guarantees any future hook-shape drift produces a compile error in the factory, not 7 test-runtime errors. Verify by temporarily adding a bogus field to the hook's return type and confirming the factory breaks at compile time.

### TDD gate for #2386 6C (waitFor, readSelection)

- **RED:** Remove the `setTimeout(r, 0)` lines without replacing them → three a11y tests fail deterministically (focus assertions fire before the rAF callback). This is the "pre-existing test characterizing the issue" RED.
- **GREEN:** Insert `await waitFor(() => expect(document.activeElement).toBe(textarea))` → tests pass.
- **selection-toolbar RED:** Remove the `Object.defineProperty(sel, "toString", ...)` stub without adding `readSelection` seam → every selection test fails with `sel.toString() === ""` (jsdom default).
- **selection-toolbar GREEN:** Introduce `readSelection` seam in the component + test-only override → tests pass without monkey-patching jsdom.

### TDD gate for #2386 6B (behavior-over-classnames)

- **RED:** Rename `whitespace-pre-wrap` → `ws-pre-wrap` (throwaway local change) and run tests. Current tests fail (class-name assertion). After the refactor, the same rename must NOT break tests (behavior assertion survives). Revert the throwaway rename before committing.
- **GREEN:** `data-narrow-wrap` attribute + `getBoundingClientRect()` check assert observable behavior; a class-name rename does not affect them.

### Manual verification for #2391 (doc-only)

- Read both comment blocks after editing; confirm they reference the source lines they point to (ws-handler `SUPERSEDED` close path, rate-limiter `invoiceEndpointThrottle` single-instance note). These are the only two files that must be visually checked.

## Implementation Phases

### Phase 1 — Factory + helper scaffolding (setup, no test changes)

1. Create `apps/web-platform/test/mocks/use-websocket.ts`. Use top-level ES imports (rule `cq-vite-test-files-esm-only` — no `require()`). Template:

   ```ts
   import { vi } from "vitest";
   import type { useWebSocket } from "@/lib/ws-client";

   type WebSocketState = ReturnType<typeof useWebSocket>;

   /**
    * Shared factory for mocking `useWebSocket` across chat-sidebar tests.
    * Mirrors `test/mocks/use-team-names.ts`. Drift-resistant via both the
    * return-type annotation AND a `satisfies` check on the literal so a
    * field addition to the hook fails compile here, not at 7 test-runtime
    * errors.
    */
   export function createWebSocketMock(
     overrides: Partial<WebSocketState> = {},
   ): WebSocketState {
     const base = {
       messages: [],
       startSession: vi.fn(),
       resumeSession: vi.fn(),
       sendMessage: vi.fn(),
       sendReviewGateResponse: vi.fn(),
       status: "connected",
       disconnectReason: undefined,
       lastError: null,
       reconnect: vi.fn(),
       routeSource: null,
       activeLeaderIds: [],
       sessionConfirmed: true,
       usageData: null,
       realConversationId: null,
       resumedFrom: null,
     } satisfies WebSocketState;
     return { ...base, ...overrides };
   }
   ```

   Note the `satisfies` keyword (TypeScript 4.9+) — it validates the literal matches the hook return type WITHOUT widening the `base` type, so the spread into `overrides` preserves narrow inference. Confirm TypeScript version via `grep version apps/web-platform/package.json` (should be ≥5.x — safe).

2. Create `apps/web-platform/test/helpers/dom.ts`. Copy `setControlledValue` verbatim from `test/chat-input-quote.test.tsx` lines 76-84 (native value setter + input event dispatch). Template:

   ```ts
   /**
    * Set a controlled input/textarea's value the way React expects, so the
    * component's onChange fires. Uses the native value descriptor to bypass
    * React's synthetic input tracker. Required for tests that rehydrate or
    * prepopulate textareas before asserting downstream behavior.
    */
   export function setControlledValue(
     el: HTMLTextAreaElement | HTMLInputElement,
     value: string,
     cursor?: number,
   ): void {
     const setter = Object.getOwnPropertyDescriptor(
       window.HTMLTextAreaElement.prototype,
       "value",
     )?.set;
     if (!setter) throw new Error("native value setter unavailable");
     setter.call(el, value);
     if (cursor !== undefined) {
       el.selectionStart = cursor;
       el.selectionEnd = cursor;
     }
     el.dispatchEvent(new Event("input", { bubbles: true }));
   }
   ```

3. Run `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. Must pass. (No tests run yet — Phase 1 is scaffolding only.)

### Phase 2 — Rewire 7 chat-sidebar test files to the factory (#2386 6A)

1. Edit each of the 7 test files. Replace the 15-field `wsReturn = { ... }` with `let wsReturn = createWebSocketMock();` and per-test override via `wsReturn = { ...wsReturn, messages: [...] }` as needed.
2. Audit `beforeEach`/`afterEach` reset patterns — the spread-reset bug the review called out can silently leak state. Prefer `wsReturn = createWebSocketMock({ overrides })` over `wsReturn = { ...wsReturn, ... }` at reset boundaries.
3. Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/chat-surface-sidebar test/kb-chat-sidebar` (pattern match). All must pass.

### Phase 3 — waitFor + readSelection + setControlledValue (#2386 6C + bonus)

1. `kb-chat-sidebar-a11y.test.tsx`:
   - Import `waitFor` from `@testing-library/react` (already imported at line 2 — confirmed).
   - Replace three `await new Promise((r) => setTimeout(r, 0))` sites (lines 125, 135, 140) with the appropriate `waitFor` form:

     ```ts
     // line 125 (focus moves to textarea on open):
     const textarea = document.querySelector("textarea") as HTMLTextAreaElement;
     await waitFor(() => expect(document.activeElement).toBe(textarea));

     // line 135 (after trigger click):
     await waitFor(() => expect(document.activeElement).toBe(trigger));
     // — NOTE: this intermediate wait was only needed to let the open
     // flow settle before closing. Replace with a wait on the close
     // button being present: `await screen.findByLabelText(/close panel/i)`
     // then `act(() => { closeBtn.click(); })`.

     // line 140 (after close click):
     await waitFor(() => expect(document.activeElement).toBe(trigger));
     ```

   - Add a file-header comment: `// Uses real timers — focus flush is rAF-driven. Do not add vi.useFakeTimers() here; waitFor relies on real rAF.`
2. `apps/web-platform/components/kb/selection-toolbar.tsx`: extract `readSelection` seam.

   ```ts
   // At module scope (above component):
   let readSelection: () => string = () =>
     (typeof window !== "undefined" ? window.getSelection()?.toString() ?? "" : "");

   /** @internal test-only. Resets via default on next import. */
   export function __setReadSelectionForTest(fn: () => string): void {
     readSelection = fn;
   }
   export function __resetReadSelectionForTest(): void {
     readSelection = () =>
       (typeof window !== "undefined" ? window.getSelection()?.toString() ?? "" : "");
   }
   ```

   Replace both existing `window.getSelection()?.toString()` calls (lines 72 and 139 in the component) with `readSelection()`. Verify with grep after edit: `rg 'getSelection\(\)\.toString' components/kb/selection-toolbar.tsx` returns zero matches.

3. `test/selection-toolbar.test.tsx`:
   - Remove `Object.defineProperty(sel, "toString", ...)` from `setSelection` (line 32). Keep the range + addRange calls — they populate the Selection's anchor/focus nodes which the component also reads.
   - Import `__setReadSelectionForTest, __resetReadSelectionForTest` from `@/components/kb/selection-toolbar`.
   - In `beforeEach`, call `__resetReadSelectionForTest()`. In the per-test selection setter, call `__setReadSelectionForTest(() => text)` where `text` is the argument to `setSelection`.
   - In `afterEach`, call `__resetReadSelectionForTest()` to prevent cross-test leakage.

4. `chat-input-quote.test.tsx`, `chat-input-draft-key.test.tsx`, `kb-chat-sidebar-quote.test.tsx`: import `{ setControlledValue } from "./helpers/dom"` and delete the inline copies (grep each file post-edit: `rg 'nativeInputValueSetter|Object\.getOwnPropertyDescriptor.*HTMLTextAreaElement'` should return zero matches per file).

5. Vitest: `cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-chat-sidebar-a11y test/selection-toolbar test/chat-input-quote test/chat-input-draft-key test/kb-chat-sidebar-quote`. All pass.

### Phase 4 — Behavior-over-classnames (#2386 6B)

1. `apps/web-platform/components/ui/markdown-renderer.tsx` (confirmed path — NOT `components/kb/`): on line 114, change

   ```tsx
   <div className="min-w-0 [overflow-wrap:anywhere]">
   ```

   to

   ```tsx
   <div
     className="min-w-0 [overflow-wrap:anywhere]"
     data-narrow-wrap={wrapCode ? "true" : undefined}
   >
   ```

   The `wrapCode` prop (line 100) is the existing sidebar-variant signal; the attribute just reflects it. `undefined` avoids emitting `data-narrow-wrap="false"` on non-sidebar callers (cleaner DOM).

2. `apps/web-platform/components/chat/chat-input.tsx`: on line 571 (the textarea JSX currently consuming `flashQuote` for class concatenation), add `data-quote-flashing={flashQuote ? "true" : undefined}` as a sibling attribute. Keep the `ring-2 ring-amber-400` class — do NOT remove it; the attribute is additive. Behavior unchanged.

3. `test/chat-surface-sidebar-wrap.test.tsx`:
   - Rewrite the `<pre>` wrap assertion to check the parent `<div>` has `data-narrow-wrap="true"`:

     ```ts
     it("sidebar variant applies narrow-wrap behavior hook", async () => {
       await renderWithMessage("```ts\n" + LONG_CODE + "\n```", "sidebar");
       expect(document.querySelector("[data-narrow-wrap='true']")).not.toBeNull();
     });

     it("full variant does NOT apply narrow-wrap", async () => {
       await renderWithMessage("```ts\n" + LONG_CODE + "\n```", "full");
       expect(document.querySelector("[data-narrow-wrap='true']")).toBeNull();
     });
     ```

   - Delete the `min-w-0` ancestor walk (lines 116-133). It is behavior-by-implementation-detail. The `data-narrow-wrap` hook is the testable behavior.
   - Keep ONE assertion that observable wrapping happens: `const pre = document.querySelector("pre"); expect(pre?.scrollWidth).toBeLessThanOrEqual(pre?.clientWidth ?? Infinity);` — this is a `getBoundingClientRect`-adjacent check that survives a Tailwind-class refactor. Note: jsdom may return 0 for both values; guard with `if (pre && pre.clientWidth > 0)` and treat 0/0 as "assertion skipped in jsdom" to avoid false green.

4. `test/chat-input-quote.test.tsx`:
   - Replace `expect(ta.className).toMatch(/ring-(2|amber)/)` (line 105) with `expect(ta.getAttribute("data-quote-flashing")).toBe("true")`.
   - Replace `expect(ta.className).not.toMatch(/\bring-2\b/)` (line 107) with `expect(ta.getAttribute("data-quote-flashing")).toBeNull()`.
   - Keep `vi.advanceTimersByTime(600)` between the two — the 500ms TTL timer must fire.

5. Vitest: `cd apps/web-platform && ./node_modules/.bin/vitest run test/chat-surface-sidebar-wrap test/chat-input-quote`. All pass.

### Phase 5 — Code-doc polish (#2391)

1. `server/ws-handler.ts`: add the supersession comment block at the `resumeByContextPath` branch (around line 372). Reference #2391 in the comment.
2. `app/api/analytics/track/throttle.ts`: add the one-line Redis-switch pointer above `analyticsTrackThrottle`. Reference `rate-limiter.ts` single-instance note.
3. Vitest (full): `cd apps/web-platform && ./node_modules/.bin/vitest run`. Expect 1463 pass (or current baseline), same as pre-change.

### Phase 6 — Guards + ship

1. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
2. `cd apps/web-platform && npm run build` (check `package.json scripts.build` first; project uses `next build`). `next build` succeeds. This catches any App Router `route.ts` non-HTTP export regressions that vitest + `tsc` miss (rule `cq-nextjs-route-files-http-only-exports`).
3. Grep guards from Acceptance Criteria: run each grep check (see below) and paste output in the PR description as an audit trail.

   ```bash
   # From apps/web-platform/:
   # (a) No hand-duplicated wsReturn literals
   rg -n "let wsReturn = \{" test/ | wc -l  # expect 0
   rg -n "createWebSocketMock" test/ | wc -l  # expect ≥7

   # (b) No setTimeout(r, 0) in a11y file
   rg "setTimeout\(r,\s*0\)" test/kb-chat-sidebar-a11y.test.tsx  # expect zero hits

   # (c) No Selection.toString monkey-patch
   rg "defineProperty.*toString" test/selection-toolbar.test.tsx  # expect zero hits

   # (d) No class-name assertions
   rg "whitespace-pre-wrap|overflow-wrap:anywhere|ring-amber|ring-2" test/chat-surface-sidebar-wrap.test.tsx test/chat-input-quote.test.tsx  # expect zero hits

   # (e) setControlledValue is centralized
   rg "nativeInputValueSetter" test/  # expect zero hits outside helpers/dom.ts

   # (f) #2391 comment references
   rg "#2391" server/ws-handler.ts  # expect ≥1
   rg "rate-limiter|Single-instance" app/api/analytics/track/throttle.ts  # expect ≥1
   ```

4. Run `skill: soleur:compound` before commit (gated by `wg-before-every-commit-run-compound-skill`).
5. Run `skill: soleur:ship` with semver label `patch` (test-only + doc-only, no behavior change, no API change).

## Risks

- **Attribute hooks as test API.** Adding `data-narrow-wrap` / `data-quote-flashing` to components mildly widens the component's stable surface. Mitigation: (a) both attributes have semantic meaning independent of tests — `data-quote-flashing` is a legitimate CSS targeting hook; `data-narrow-wrap` is a direct reflection of the already-public `wrapCode` prop. (b) If the architecture reviewer objects, fall back to `getComputedStyle(el).whiteSpace === "pre-wrap"` for the wrap check, though jsdom's `getComputedStyle` support for Tailwind arbitrary values (`[overflow-wrap:anywhere]`) is incomplete — this is why the attribute approach is preferred. Low risk.
- **`readSelection` seam as internal API.** The `__resetXxxForTest` pattern is already used 5+ times in the codebase (grep confirmed: `server/rate-limiter.ts`, `server/share-hash-verdict-cache.ts`, `app/api/analytics/track/throttle.ts`). Low risk. The naming `__setReadSelectionForTest` matches the established `__<verb><thing>ForTest` convention.
- **Fixture factory mask.** If `createWebSocketMock` defaults drift apart from the actual `useWebSocket` shape, all 7 tests silently green on stale mocks. Mitigation: annotate the factory's return as `ReturnType<typeof useWebSocket>` AND apply `satisfies ReturnType<typeof useWebSocket>` to the returned object literal — `satisfies` catches missing fields at the assignment site, not just at the call site. Any field added to the hook fails compile in the factory file directly. This is the drift-guard.
- **`waitFor` with fake timers.** Per rule `cq-raf-batching-sweep-test-helpers` (PR #2500 post-mortem), `vi.useFakeTimers({ shouldAdvanceTime: true })` does NOT auto-advance rAF inside synchronous `act()`. Currently `kb-chat-sidebar-a11y.test.tsx` does NOT enable fake timers (confirmed via grep — no `useFakeTimers` in that file), so `waitFor(...)` will settle real rAF naturally. **Guard:** if a future edit adds fake timers to that file, the plan's Phase 3 acceptance criterion fails because the `waitFor` assertions will hang. Document this in the file as a header comment: `// Uses real timers — rAF-driven focus flush. Do not add vi.useFakeTimers() here.`
- **`waitFor` timeout flake on CI.** `waitFor` has a 1000ms default timeout which should cover rAF + effect settle. If a11y tests become flaky on CI, bump to `waitFor(..., { timeout: 2000 })` targeting only the a11y file, NOT the whole project (raising global timeout would mask real flakes).
- **Constant-import trap (#2569 class).** Rule `cq-test-mocked-module-constant-import` warns that if a consumer `vi.mock()`s the module that exports a shared constant, the import resolves to the mock factory. Verified-safe: (a) the new factory lives in `test/mocks/use-websocket.ts`, which is itself a test-support module — no consumer will `vi.mock("./mocks/use-websocket")`. (b) The 7 consumers currently `vi.mock("@/lib/ws-client")`, which is the real hook module — the factory is imported from a *different* path. Trap does not apply. Documented for reviewer pre-emption.
- **Selection-toolbar `readSelection` default closes over `window`.** The default lambda reads `window.getSelection()` eagerly on each call — safe because the seam is a function reference, not a captured value. SSR-safe via the `typeof window !== "undefined"` guard that the current component already uses.
- **Pre-existing overlap scope-outs (#2191, #2196, #2197) re-surface.** Acceptable. They are different-concern and pre-date this PR; review bots re-filing them is a no-op. The Overlap section documents the disposition.
- **Next.js App Router route-file non-HTTP export rule.** Per rule `cq-nextjs-route-files-http-only-exports` (PR #2347→#2401 learning), `app/api/analytics/track/route.ts` may only export HTTP handlers. This plan adds a comment to `throttle.ts` (sibling module), NOT to `route.ts`. Verified safe. Vitest + `tsc --noEmit` do NOT catch this class — only `next build` does, which is why Phase 6 explicitly runs `next build`.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
| --- | --- | --- | --- |
| Fold #2191 + #2196 + #2197 into this PR too | "Single cleanup" feels comprehensive | Different concerns (timer refactor, rate-limiter dedupe, type hoisting); balloons blast radius; makes review bisectable harder | Rejected. One-shot PR stays focused on #2386 + #2391 as scoped. Other three remain independently drainable. |
| `getComputedStyle` instead of `data-*` attributes for #2386 6B | No component-surface changes | jsdom does not fully implement `getComputedStyle` for CSS custom properties and Tailwind arbitrary values (`[overflow-wrap:anywhere]`); tests would still be brittle in a different way | Rejected. `data-*` attributes are cleaner and the #2386 body explicitly suggests them. |
| Banner UI for #2391 11A | Actually warns the user | Feature PR, not backlog drain; needs UX copy + a11y + QA; out of review-backlog-drain scope | Rejected for this PR. Code comment only. If a future iteration wants the banner, file as a product feature and milestone it. |
| Hoist single-instance doc into `knowledge-base/engineering/` for #2391 11B | Centralizes the caveat for all throttles | Decoupling docs from code is #2197's explicit concern; duplicating that work here creates a merge conflict | Rejected. Inline pointer only; trust #2197 to handle centralization. |
| Keep the `Selection.toString` monkey-patch, just change the test helper location | Zero component change | Does not address the actual finding (coupling to jsdom internals) | Rejected. The fix IS the component seam. |
| One-off per-issue PRs instead of folding into one | Smaller PRs | Two P3 PRs against identical review origin with overlapping file context is churn; the one-shot skill's whole point is batching | Rejected. The task explicitly requested one PR. |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — test-quality refactor + inline code comments. No user-facing surface change, no copy change, no pricing, no infra, no data model, no flow. CTO-adjacent in the sense that #2391 11A touches server-side invariant documentation, but the change is a comment-only pointer, not an architectural shift. CPO/CMO/COO/etc. have nothing to review.

## Rollout

1. Ship via `skill: soleur:ship` with semver `patch`.
2. Auto-merge on green CI.
3. Post-merge: `skill: soleur:postmerge` verifies deploy + Sentry clean. No production migrations, no feature flag, no DNS change.
4. Both issues close automatically via `Closes #2386` / `Closes #2391` in PR body.

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-04-18-chore-drain-review-backlog-2386-2391-plan.md. Branch: feat-one-shot-drain-review-backlog-2386-2391. Worktree: .worktrees/feat-one-shot-drain-review-backlog-2386-2391/. Issues: #2386 (test quality) + #2391 (session supersession + rate-limit scaling doc). Drain review backlog from PR #2347. Plan written; implementation next (6 phases, test-only + doc-only, no behavior change).
```
