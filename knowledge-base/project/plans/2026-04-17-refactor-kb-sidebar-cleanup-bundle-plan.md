# refactor: KB chat sidebar cleanup bundle — close #2387 + #2388 + #2389

**Date:** 2026-04-17
**Branch:** `feat-kb-sidebar-cleanup-bundle`
**Worktree:** `.worktrees/feat-kb-sidebar-cleanup-bundle/`
**Issues closed:** #2387, #2388, #2389 (all PR #2347 deferred scope-outs, label `deferred-scope-out`)
**Semver:** patch
**Risk:** low — no behavior changes for users; callers unchanged except for typed shape.

## Enhancement Summary

**Deepened on:** 2026-04-17
**Research applied:** React 19 stale-closure patterns; TextEncoder vs Blob benchmarks;
Next.js 15 route-file validator rules; debounce flush-on-unmount contract;
`Node.contains` TypeScript signature; 5 in-repo learnings (kb-viewer context,
module-scope→async deps, pure-reducer extraction, nextjs-15 route validator,
negative-space tests post-extraction).

### Key improvements applied from research

1. **7B functional setter — Strict Mode purity gate.** React 19's `<StrictMode>`
   double-invokes `useState` updater functions in dev. The new functional form at
   `insertRef` MUST be pure (no side effects in the updater body). The plan's
   acceptance criteria now forbid ref writes / DOM mutations inside the updater —
   see AC 2.1.
2. **7F `Element.contains` — TypeScript already accepts null.** `lib.dom.d.ts`
   types `contains(other: Node | null): boolean`. No non-null guards needed at
   call sites — just `article.contains(sel.anchorNode)`. Simpler than the
   original plan prescribed. Sharp Edges updated.
3. **9A TextEncoder — measured ~77× faster than Blob on small strings**
   (MeasureThat.net: 123ns vs 9500ns). Confirms the optimization is real at the
   60Hz call rate. The plan stays with `encode()` rather than `encodeInto()` —
   the buffer-management complexity isn't worth it at this payload size.
4. **9C debounce — `.flush()` on unmount, `.cancel()` on dep change.** The
   idiomatic pattern from lodash/use-debounce: flush pending writes on unmount
   so the last keystroke reaches storage; cancel pending writes when the
   `draftKey` changes so doc-A's pending write doesn't land in doc-B's key.
5. **Learning applied — "module-scope to async state deps mismatch"**
   (`2026-04-16`). The 8B context split must audit all `useEffect`/`useMemo`
   deps in `kb/layout.tsx` after moving `registerQuoteHandler`/`submitQuote`
   into a new provider — any dep list that previously omitted these (because
   they were stable callbacks in the old `KbChatContext`) must re-include them
   where the new context is consumed.
6. **Learning applied — "pure-reducer extraction requires companion-state
   migration"** (`2026-04-14`). The 8B split creates two contexts where one
   used to be. `kb-chat-content.tsx` reads from both; if either context is
   mocked separately in tests but not the other, assertion behavior will
   silently diverge. Mandatory: update shared test harness (a single
   `renderWithKbContexts` helper) before the split lands.
7. **Learning applied — "Next.js 15 route-file non-HTTP exports"**
   (`2026-04-15`, the PR #2347 outage itself). The refactor of
   `thread-info/route.ts` MUST remove the inline lookup and place the shared
   helper in `server/lookup-conversation-for-path.ts` — NOT in a
   `./helpers.ts` sibling under `app/api/chat/thread-info/`. Route-file
   validator treats sibling modules as same-route; only `server/`-rooted
   utilities are safe.
8. **Learning applied — "negative-space tests must follow extracted logic"**
   (`2026-04-15`). The 8C shared helper extraction means any existing test
   that grepped `thread-info/route.ts` for inline `auth.getUser` / Supabase
   lookup strings will pass on weakened substring matches. Add a regex
   assertion that proves **delegation** (both import AND invocation AND
   `.messageCount` or equivalent field usage) rather than just import
   presence. See test addendum in Phase 2.

## Overview

PR #2347 landed the KB chat sidebar MVP and deferred three batches of cleanup to follow-ups
with the `deferred-scope-out` label. All three are now addressed in a single focused PR
because they share the same file neighborhood (`apps/web-platform/components/chat/`,
`components/kb/`) and the same risk profile (UI-layer, unit-testable, no DB schema change).

**What this PR removes or simplifies** (issue #2387 — simplicity bundle, ~120 LOC net):

- Three-point snap API from `Sheet` (no caller uses it).
- `insertRef` closure-over-`value` pattern — converge on the functional `setValue(prev => ...)`
  pattern already used by `quoteRef`.
- `ChatInputQuoteHandle` one-method interface → plain `(text: string) => void` callback ref.
- URL-param `?context=` KB-content fetch inside `ChatSurface` — moves to the full-route page,
  where it belongs (sidebar always passes `initialContext`).
- Analytics-route drain block (`res.json()/res.text()` on unused response) — undici GCs it.
- `isDescendant` helper — native `Element.contains()` is one call.
- `SIDEBAR_PLACEHOLDER` const — used once.
- Four `requestAnimationFrame` focus wraps — only the insert-then-cursor-update case actually
  needs a rAF.
- `fetchTree` + `refreshTree` double-wrapper — inline.
- Eight scattered `sessionStorage` try/catches → one `safeSession()` helper.

**What this PR refines architecturally** (issue #2388):

- `ChatSurface` prop sprawl (13 props, 7 sidebar-only) → group into `sidebarProps?`.
- Split `KbChatContext` into two contexts — sidebar-lifecycle vs. quote-bridge — so the
  imperative pub/sub (`registerQuoteHandler`/`submitQuote`) stops hiding in shared state.
- Add `GET /api/conversations?context_path=<path>` so non-WS agents can discover whether
  a thread exists. Existing `/api/chat/thread-info` returns only `messageCount`; the new
  route returns the full `{ conversationId, context_path, last_active, message_count }`
  shape.
- Document the `resumeByContextPath` idempotency contract and the `> …\n\n` quote-prepend
  convention in `knowledge-base/engineering/`.

**What this PR improves for perf and tests** (issue #2389):

- `selectionchange` handler: replace `new Blob([text]).size` with a memoized `TextEncoder`
  (re-uses the same encoder instance per mount, ~60Hz call site).
- Wrap `setPill` in `requestAnimationFrame` to coalesce state updates to the frame boundary.
- Add Escape-contract tests (`selection-toolbar.test.tsx`): pill-visible Escape dismisses
  pill only; pill-gone Escape closes the panel. Documents the two-press UX contract that
  relies on capture-phase `stopPropagation`.
- Debounce `chat-input.tsx` draft persistence with a 250ms trailing timer — we're already
  editing the file for 7B/7C/7I, so folding it in is cheap.

## Research Reconciliation — Spec vs. Codebase

Several line references in the issue bodies point to locations that have since moved,
because the same files were edited repeatedly during PR #2347 and again by #2451
(resizable panels / Range support). The plan reflects **current reality** — not the
issue-body line numbers. This section documents every drift explicitly.

| Spec claim (issue body) | Reality (branch HEAD) | Plan response |
| --- | --- | --- |
| `sheet.tsx:10-14, 112-121` contains snap math | Snap math lives at `sheet.tsx:7-14` (type + map) and `:113-121` (nearest-point reducer in `onPointerUp`). Still accurate enough; line numbers shift after edit. | Implement as specified — the code identified is correct. |
| `kb-chat-sidebar.tsx:11-12` defines `SIDEBAR_PLACEHOLDER` | `SIDEBAR_PLACEHOLDER` is in `kb-chat-content.tsx:10-11` (not `kb-chat-sidebar.tsx`). `kb-chat-sidebar.tsx` was thinned to 24 lines and now only wraps `KbChatContent` in a `Sheet`. | Inline in `kb-chat-content.tsx` where the const actually lives. |
| `kb-chat-sidebar.tsx:41-47` has an excess rAF focus wrap | That rAF lives at `kb-chat-content.tsx:52-58` (focus on visible). | Keep or drop in `kb-chat-content.tsx`. **Recommendation: keep** — the rAF defers focus until after the Sheet portal mounts; removing it can focus a not-yet-attached node. Covered under 7I rationale. |
| `app/(dashboard)/dashboard/kb/layout.tsx:48-90` defines `fetchTree` | `fetchTree` lives at `layout.tsx:84-116`; `refreshTree` at `:124-126`. | Inline `refreshTree` into the `ctxValue` `useMemo` at `:192-199` or drop the wrapper and pass `fetchTree` directly. |
| `analytics/track/route.ts:116-127` is the drain block | **Wrong.** Lines 116-127 are the outer `catch (err)` that logs Plausible forward failure (real error handling — must stay). The drain block is actually `:107-114` (the `ct` / `res.json()` / `res.text()` pass). | Delete lines **107-114** only. Leave the 115-123 `catch` intact. Captured in Sharp Edges below. |
| `chat-input.tsx:17-19` defines `ChatInputQuoteHandle` | `ChatInputQuoteHandle` is at `:20-23`, and imported from `chat-surface.tsx:9` and `kb-chat-content.tsx:5`. | Replace with `(text: string) => void` callback ref; update both importers. |
| `chat-surface.tsx:21-44` has 13 props / 7 sidebar-only | Correct — props are at `:22-45`. | Group into `sidebarProps?` as specified. |
| `kb-chat-context.tsx:5-20` conflates 3 concerns | Confirmed — `KbChatContextValue` is at `:5-20`. | Extract `KbChatQuoteBridge` into its own context + provider pair. |
| New endpoint `/api/conversations?context_path=` is `~20 lines` | Existing `/api/chat/thread-info/route.ts` is 71 lines and does user-scoped auth + service-client lookup + message count. The new route can re-use the exact same pattern and will end up **closer to 70 lines** than 20 when done correctly (auth, path validation, error-fallback logging). | Reuse the thread-info pattern verbatim; extract `validateContextPath` and `lookupConversationForPath` into a shared helper so both routes call the same implementation. |

## Files to edit

- `apps/web-platform/components/ui/sheet.tsx` — drop snap points + `side` prop + `onSnapChange`
  (7A). Target: mobile `height = 60vh`, keep drag-to-close.
- `apps/web-platform/components/chat/chat-input.tsx` — converge `insertRef` to functional
  `setValue` (7B); replace `ChatInputQuoteHandle` interface with callback ref (7C); drop
  excess rAF focus wraps (7I); wire 8 sessionStorage sites through `safeSession` (7H);
  debounce draft persistence (9C).
- `apps/web-platform/components/chat/chat-surface.tsx` — remove `contextLoading`/`kbContext`
  URL-param state + effect (7D); group sidebar-only props into `sidebarProps?` (8A);
  update `insertRef` and `quoteRef` shapes to match callback-ref change (7C).
- `apps/web-platform/components/chat/kb-chat-content.tsx` — inline `SIDEBAR_PLACEHOLDER`
  (7G); update `quoteRef` shape to callback ref (7C); update `<ChatSurface>` call-site to
  pass `sidebarProps={{ ... }}` (8A); keep the `requestAnimationFrame` focus wrap at
  `:52-58` (required for portal-mounted Sheet — see Sharp Edges).
- `apps/web-platform/components/chat/kb-chat-sidebar.tsx` — no-op after `Sheet` simplification
  (the `side` prop wasn't passed — just drops a prop from the type).
- `apps/web-platform/components/kb/selection-toolbar.tsx` — inline `isDescendant` →
  `Element.contains()` (7F); memoize `TextEncoder`; wrap `setPill` in `requestAnimationFrame`
  (9A).
- `apps/web-platform/components/kb/kb-chat-context.tsx` — remove `submitQuote` +
  `registerQuoteHandler` from `KbChatContextValue` (moves to new context) (8B).
- `apps/web-platform/app/api/analytics/track/route.ts` — delete drain block at lines
  **107-114** (7E). Do NOT touch the `catch (err)` at 115-123.
- `apps/web-platform/app/(dashboard)/dashboard/kb/layout.tsx` — inline `refreshTree` wrapper
  (7J); wire sessionStorage sites at `:150, 155, 160, 173` (and `:211, 218, 223`) through
  `safeSession` (7H); consume the new split contexts (8B).
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` — grow to
  own the URL-param KB-content fetch for the full route (7D). Currently 9 lines; will
  become ~40 lines.
- `apps/web-platform/test/selection-toolbar.test.tsx` — add Escape-contract cases (9B).
- `apps/web-platform/test/sheet.test.tsx` — update to match new `Sheet` API (snap removed).
- `apps/web-platform/test/chat-input*.test.tsx` — update for `ChatInputQuoteHandle` →
  callback ref shape (7C) and for `setValue` functional shape (7B).
- `apps/web-platform/test/chat-surface-sidebar*.test.tsx` — update for `sidebarProps`
  grouping (8A).

## Files to create

- `apps/web-platform/lib/safe-session.ts` — `safeSession(key, value?)` helper with one
  pino telemetry point. Handles `typeof window === "undefined"` + `try/catch` (7H).
- `apps/web-platform/components/kb/kb-chat-quote-bridge.tsx` — new context + `useKbChatQuoteBridge`
  hook. Owns `registerQuoteHandler` + `submitQuote`. Mounted inside `KbLayout` alongside
  `KbChatContext` (8B).
- `apps/web-platform/app/api/conversations/route.ts` — `GET` handler reading `context_path`
  query param, returning `{ conversationId, context_path, last_active, message_count } | null`
  under user auth (8C).
- `apps/web-platform/server/lookup-conversation-for-path.ts` — shared helper used by both
  `/api/chat/thread-info` and `/api/conversations`. Single source of truth for the
  `(user_id, context_path)` → conversation-row lookup. Re-use in thread-info route to avoid
  duplication.
- `apps/web-platform/test/safe-session.test.ts` — unit tests for `safeSession`.
- `apps/web-platform/test/api-conversations.test.ts` — integration test for the new route
  (auth + hit + miss).
- `knowledge-base/engineering/kb-chat-agent-protocol.md` — documents `resumeByContextPath`
  idempotency (same `(user_id, context_path)` → same conversation id) and the `> …\n\n`
  quote-prepend convention so agents know they don't need a separate quote API (8D).

## Open Code-Review Overlap

Ten open code-review issues touch files this plan will modify. Disposition for each:

| Issue | Title | File(s) | Disposition | Rationale |
| --- | --- | --- | --- | --- |
| #2387 | simplicity bundle | many | **Fold in** | This plan closes it. `Closes #2387` in PR body. |
| #2388 | architecture refinements | `chat-surface.tsx`, `kb-chat-context.tsx`, new routes | **Fold in** | This plan closes it. `Closes #2388`. |
| #2389 | SelectionToolbar perf + Escape tests | `selection-toolbar.tsx`, new test cases | **Fold in** | This plan closes it. `Closes #2389`. |
| #2391 | session supersession UX + rate-limit scaling note | `ws-handler.ts` (not in scope), `route.ts:22` throttle reference | **Acknowledge** | Different concern — #2391 is a doc comment + optional UX banner on a different code path (`server/ws-handler.ts`), not the drain block we're deleting. Will not silently resurface after this PR. |
| #2222 | gate auto-scroll on user-at-bottom | historically `dashboard/chat/.../page.tsx`, now `chat-surface.tsx:136-138` | **Acknowledge** | 7D grows the page file; #2222's target moved to `chat-surface.tsx` during PR #2451. The perf concern is still valid but orthogonal to the cleanup bundle — mixing would blur the scope and risk streaming regressions. |
| #2223 | useMemo ChatPage derivations | same as #2222 — moved to `chat-surface.tsx:237-246` | **Acknowledge** | Same reasoning as #2222. This bundle is behavior-preserving; memoization decisions want their own review window. |

No other review-origin issues cross-reference these files. Dispositions were selected
using the `rf-review-finding-default-fix-inline` rule — fold in when the concern is the
current cleanup's concern; acknowledge when the concern is a separate perf / UX discussion
that deserves its own PR.

## Acceptance Criteria

### #2387 — simplicity

1. `sheet.tsx` exports no `SheetSnap` type, no `side` prop, no `onSnapChange` prop.
   Mobile sheet height is `60vh`; drag-to-close still fires `onClose` when released below
   `10vh`.
2. `chat-input.tsx` `insertRef` uses `setValue((prev) => ...)` — no closure over the
   rendered `value`. `insertRef` effect depends only on `[insertRef]`, not `[insertRef, value]`.
   **Strict Mode purity contract (research-backed):** The updater function passed to
   `setValue` MUST be pure. React 19 `<StrictMode>` double-invokes `useState` updaters
   in dev to surface accidental impurity. The current `quoteRef` updater at
   `chat-input.tsx:159-163` reads `textarea.selectionStart` inside the updater — that's
   a DOM read, not a mutation, and is idempotent for the same tick. Keep that pattern.
   Do NOT move the `setFlashQuote(true)` / `flashTimerRef` side-effects into the
   functional updater — they already live outside it (lines 164+), which is correct.
   Reference: <https://react.dev/reference/react/useState#setstate-caveats>.
3. `ChatInputQuoteHandle` is removed; `quoteRef` is typed as
   `React.MutableRefObject<((text: string) => void) | null>`.
4. `chat-surface.tsx` contains no `contextLoading` state, no `kbContext` state, no
   `?context=` fetch effect.
5. `app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` fetches KB content when
   `?context=` is present and passes `initialContext` to `<ChatSurface>`.
6. `analytics/track/route.ts` no longer reads the response body. The function proceeds
   directly from the `402` check to the final `return new NextResponse(null, { status: 204 })`.
7. `selection-toolbar.tsx` does not define or call `isDescendant`. Descendant checks use
   `article.contains(sel.anchorNode)` directly. **TypeScript accepts `Node | null` without
   a non-null guard** — modern `lib.dom.d.ts` types `contains(other: Node | null): boolean`
   and returns `false` at runtime when passed null (matches the original `isDescendant`
   semantics exactly). No `!` assertions, no ternary guards.
8. `SIDEBAR_PLACEHOLDER` is inlined into the `placeholder={...}` prop in `kb-chat-content.tsx`.
9. `lib/safe-session.ts` exports `safeSession(key: string, value?: string | null): string | null`.
   `value === undefined` reads; `value === null` clears; `value` a string writes. All 8
   call sites use it. Zero remaining `try { window.sessionStorage... } catch {}` blocks in
   `chat-input.tsx` and `kb/layout.tsx`.
10. Only one `requestAnimationFrame` focus wrap remains in `chat-input.tsx` — inside the
    `insertRef` effect, where the cursor must be restored after React commits. The
    `handlePaste` / `handleAtButtonClick` / `quoteRef` sites focus directly.
11. `kb/layout.tsx` does not define `refreshTree`. The `ctxValue` `useMemo` passes
    `fetchTree` directly as `refreshTree`.

### #2388 — architecture

12. `ChatSurfaceProps` has a `sidebarProps?: ChatSurfaceSidebarProps` object. `quoteRef`,
    `onBeforeSend`, `placeholder`, `draftKey`, `resumeByContextPath`, `onThreadResumed`,
    `onRealConversationId`, `onMessageCountChange` are all moved into it. A full-variant
    caller (`dashboard/chat/[id]/page.tsx`) does not pass `sidebarProps`; TypeScript does
    not offer sidebar-only fields on autocomplete at that site.
13. `KbChatContextValue` contains `{ open, openSidebar, closeSidebar, contextPath, enabled,
    messageCount, setMessageCount }` — and nothing else.
14. A new `KbChatQuoteBridgeContext` owns `{ registerQuoteHandler, submitQuote }`.
    `KbLayout` mounts both providers; `kb-chat-content.tsx` consumes `QuoteBridge` for
    `registerQuoteHandler`; `selection-toolbar.tsx` callers consume it for `submitQuote`.
15. `GET /api/conversations?context_path=<path>` returns 200 with JSON
    `{ conversationId, context_path, last_active, message_count }` when a row exists and
    null otherwise. Returns 400 on missing/invalid path; 401 when unauthenticated.
16. `thread-info/route.ts` and `conversations/route.ts` both call
    `server/lookup-conversation-for-path.ts`. No duplicated Supabase query.
17. `knowledge-base/engineering/kb-chat-agent-protocol.md` documents the
    `(user_id, context_path)` → conversation idempotency and the `> …\n\n` quote-prepend
    convention, with a code example for each.

### #2389 — perf + tests

18. `selection-toolbar.tsx` instantiates one `TextEncoder` via `useMemo(() => new TextEncoder(), [])`
    and uses `encoder.encode(text).byteLength` in both `onSelectionChange` and the
    `⌘⇧L` shortcut handler. No `new Blob(...)` in the file.
    **Performance basis (MeasureThat.net benchmark):** TextEncoder measures UTF-8 byte
    length in ~123ns vs Blob's ~9500ns for small strings (77× faster). At the 60Hz
    `selectionchange` rate and typical selection sizes (≤8KB), this removes allocator
    pressure from the hot path. NOT using `encodeInto()` — the buffer-preallocation
    complexity isn't justified at this payload size.
19. `setPill` is called inside a `requestAnimationFrame` callback that's cancelled on
    re-entry (`rafRef`). Pending rAF is cancelled on unmount. Explicit contract: if
    `selectionchange` fires 5 times within one frame, `setPill` is invoked at most once.
20. `test/selection-toolbar.test.tsx` asserts:
    - Pill visible → `Escape` dispatched on `document` → pill disappears, and a controlled
      parent `Sheet`'s `onClose` has **not** been called.
    - Pill absent → `Escape` dispatched on `document` → the controlled parent's `onClose`
      **has** been called.
    - **Capture-phase listener required:** `addEventListener("keydown", ..., true)` at
      `selection-toolbar.tsx:113` uses the capture phase so the pill's dismiss runs
      *before* the Sheet's bubble-phase Escape handler at `sheet.tsx:55-66`. The test
      must dispatch `KeyboardEvent` on `document` (not the pill element) and assert the
      Sheet's `onClose` mock was not called in the same tick — capturing vs. bubbling
      ordering is what the test is really validating.
21. `chat-input.tsx` persists drafts via a 250ms trailing debounce. Rapid typing (e.g.,
    10 chars in 100ms) results in ≤1 `sessionStorage.setItem` call.
    **Lifecycle contract (research-backed):** Pending debounce calls
    (a) **flush on unmount** — so the last character reaches sessionStorage before the
    component tears down; (b) **cancel on `draftKey` change** — so keystrokes typed
    against doc-A don't land in doc-B's sessionStorage key after navigation; (c) use a
    `useRef`-stored timer handle, not a closure, so the cleanup function always sees
    the current pending timer. Reference: lodash `.flush()` / `.cancel()` semantics at
    <https://lodash.com/docs/4.17.15#debounce>.

## Test Scenarios

### Unit — new behavior

- `safeSession` read / write / clear / window-undefined / throws-silently paths
  (`test/safe-session.test.ts`).
- `/api/conversations?context_path=` — hit, miss, bad path, unauthenticated, internal error
  → 200 fallback with `null` (`test/api-conversations.test.ts`).
- `selection-toolbar` Escape contract (9B acceptance #20).
- `chat-input` draft-debounce: write coalescing within 250ms window.

### Unit — regression

- Existing `test/chat-input*.test.tsx`, `test/chat-surface-sidebar*.test.tsx`,
  `test/kb-chat-sidebar*.test.tsx`, `test/sheet.test.tsx` all pass after API migrations.
  Concretely:
  - `sheet.test.tsx` loses the "snap to nearest" assertion and gains a
    "mobile height is 60vh" assertion.
  - `chat-input-quote.test.tsx` migrates from `quoteRef.current?.insertQuote(text)` to
    `quoteRef.current?.(text)`.
  - `chat-surface-sidebar.test.tsx` re-groups props under `sidebarProps={...}`.

### QA (manual Playwright MCP — required per `rf-before-shipping-verify`)

Run against `apps/web-platform/scripts/dev.sh` locally under Doppler. Capture screenshots
for the PR.

1. **Mobile sheet still drags to close.** Open dashboard/kb/ any doc on 400×700 viewport.
   Tap "Ask about this document" → mobile Sheet appears at 60vh. Drag handle down past
   `10vh` threshold → Sheet closes. Screenshot: Sheet at 60vh. Screenshot: Sheet after
   drag-close.
2. **Desktop resizable layout unchanged.** `?context=` full route still loads content; KB
   chat panel still opens on-demand; selection-toolbar pill still shows `⌘⇧L`.
3. **Quote flow end-to-end.** On desktop, select text in a doc → pill appears → click
   pill → text prepended as `> ...\n\n` in chat input (flash-ring animation) → press
   Enter → message sends. Screenshot: pill visible over selection. Screenshot: prepended
   draft.
4. **Escape contract.** With pill visible, press `Escape` once → pill disappears, panel
   stays open. Press `Escape` again → panel closes. (Documents 9B.)
5. **Draft persistence across navigation.** Type a draft on doc A → navigate to doc B →
   draft at A is empty on return … no, **wait**: per KB-sidebar spec, drafts persist
   per-path via `draftKey={kb.chat.draft:${contextPath}}`. So: type on A → go to B →
   (draft on B is independent / empty) → return to A → A's draft is restored. Screenshots:
   draft on A, empty on B, restored on A.
6. **New `/api/conversations` endpoint.** With an existing thread on doc X, open devtools
   console and run
   `fetch('/api/conversations?context_path=knowledge-base/....md').then(r=>r.json())` →
   returns `{ conversationId, context_path, last_active, message_count }`. With a doc
   that has no thread → returns `null`. Screenshot: devtools response.
7. **Analytics beacon still fires.** Open docs, click "Ask about this document", verify
   a POST to `/api/analytics/track` returns 204. Screenshot: network tab.

## Implementation Phases

### Phase 0 — TDD setup (RED gate per `cq-write-failing-tests-before`)

Write all new unit tests first (21 assertions above). They fail until implementation phases
land. Run `cd apps/web-platform && ./node_modules/.bin/vitest run` per the worktree-vitest
rule (`cq-in-worktrees-run-vitest-via-node-node`).

- `test/safe-session.test.ts` (new)
- `test/api-conversations.test.ts` (new)
- `test/selection-toolbar.test.tsx` — add Escape-contract cases
- `test/chat-input-draft-debounce.test.tsx` (new)

### Phase 1 — simplicity bundle (#2387)

Order chosen to minimize test-break churn: API-shape-first, then behavior-neutral deletions.

1. **7C** `ChatInputQuoteHandle` → callback ref. Simplest type-system change; cascades
   through `chat-input.tsx`, `chat-surface.tsx`, `kb-chat-content.tsx`, and any test that
   constructs a fake handle.
2. **7B** `insertRef` → functional `setValue` shape. Depends on nothing else.
3. **7I** Drop excess rAF focus wraps. Keep the one inside the `insertRef` effect
   (cursor-restore after commit) and keep the one in `kb-chat-content.tsx:52-58` (portal
   mount timing — see Sharp Edges).
4. **7H** Introduce `lib/safe-session.ts`; replace 8 call sites.
5. **7A** Drop `Sheet` snap points + `side` + `onSnapChange`. Update `sheet.test.tsx`
   accordingly.
6. **7G** Inline `SIDEBAR_PLACEHOLDER` in `kb-chat-content.tsx`.
7. **7F** Replace `isDescendant` with `Element.contains`. Type-guard `Node | null` at
   call sites.
8. **7J** Inline `refreshTree`. Verify `ctxValue` `useMemo` deps unchanged (pass `fetchTree`
   directly). Run `vitest` on `kb-layout*` tests.
9. **7D** Move `?context=` fetch from `ChatSurface` to `app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`.
   Grow the page to ~40 lines. Verify sidebar still passes `initialContext` and that the
   full route still behaves.
10. **7E** Delete drain block at `analytics/track/route.ts:107-114`. **Do not touch 115-123**.

Run the full `vitest` suite after each step rather than at the end — if something breaks,
the smallest-possible diff points to the cause.

### Phase 2 — architecture refinements (#2388)

11. **8A** Extract `ChatSurfaceSidebarProps` and `sidebarProps?` grouping on
    `ChatSurface`. Update `kb-chat-content.tsx` and `page.tsx` call-sites. Update
    `chat-surface-sidebar*.test.tsx` to pass the grouped prop.
12. **8B** Create `kb-chat-quote-bridge.tsx`. Mount its provider inside `KbLayout`
    alongside `KbChatContext`. Move `registerQuoteHandler` + `submitQuote` and their
    backing `quoteHandlerRef` into the new provider. Update `kb-chat-context.tsx` to
    remove those fields. Update `kb-chat-content.tsx` (consumes `registerQuoteHandler`)
    and `selection-toolbar` callers (consume `submitQuote`).
13. **8C** Create `server/lookup-conversation-for-path.ts` (shared helper). Refactor
    `thread-info/route.ts` to use it (still returns `{ messageCount }` — no shape change
    for backward compatibility with `kb/layout.tsx` `fetch('/api/chat/thread-info?...')`).
    Create `app/api/conversations/route.ts` using the same helper, returning the full
    shape. Add `api-conversations.test.ts` assertions.
14. **8D** Write `knowledge-base/engineering/kb-chat-agent-protocol.md`. Run
    `npx markdownlint-cli2 --fix knowledge-base/engineering/kb-chat-agent-protocol.md`
    (specific path per `cq-markdownlint-fix-target-specific-paths`).

### Phase 3 — perf + tests (#2389)

15. **9A** Memoize `TextEncoder` in `selection-toolbar.tsx`. Replace both `new Blob(...)`
    byte-length measurements with `encoder.encode(text).byteLength`. Wrap `setPill` in
    a `requestAnimationFrame` keyed by a `rafRef` that cancels the prior pending frame
    on re-entry and on unmount.
16. **9B** Enable the Escape-contract tests written in Phase 0.
17. **9C** Debounce `chat-input.tsx` sessionStorage write. Leading-edge `safeSession`
    read on draftKey-change stays synchronous (prevents stale echo on doc switch); only
    the `value`-change write uses the 250ms trailing timer. Cancel timer on unmount.

### Phase 4 — verification

18. Run the full vitest suite: `cd apps/web-platform && ./node_modules/.bin/vitest run`.
    Expect 100% green (0 new failures). Any pre-existing failures must be confirmed
    present on `main` (per `wg-when-tests-fail-and-are-confirmed-pre`) — if any are new,
    fix before proceeding.
19. Run `npx markdownlint-cli2 --fix` on the one new markdown file only.
20. Run `cd apps/web-platform && npm run build` locally under Doppler to catch the
    Next.js 15 route-file validator (per `cq-nextjs-route-files-http-only-exports`) —
    the new `app/api/conversations/route.ts` exports only `GET`, so this should pass, but
    verify.
21. Start dev server, execute the 7 QA scenarios, capture screenshots.
22. Draft PR with body containing `Closes #2387`, `Closes #2388`, `Closes #2389`, the
    7 QA screenshots, and a summary of LOC delta.

## Domain Review

**Domains relevant:** none (infrastructure/tooling-only refactor)

No cross-domain implications detected — this is a pure UI-layer refactor bundle with no
changes to pricing, content strategy, positioning, legal obligations, or user flows. The
three issues are all `deferred-scope-out` from a single shipped PR; the review bar was
already cleared at #2347 merge time. Acceptance criteria are behavior-preserving
(#2387, #2388) or additive (#2389 perf + tests). No new user-facing pages or components
— the mechanical escalation for `components/**/*.tsx` new-file creation triggers only on
the two new files under `kb-chat-quote-bridge.tsx` (a context provider, no new UI
surface) and `safe-session.ts` (a lib helper). Neither is a user-facing page.

## Sharp Edges

- **`analytics/track/route.ts` drain-block deletion scope.** The issue body says "delete
  lines 116-127" but those lines are the outer `catch (err) { log.warn(...) }` that
  handles Plausible being down. Deleting that catch would surface a `fetch` rejection
  through to an unhandled route error. The **correct** block to delete is `107-114` —
  the `ct` check plus the `res.json()/res.text()` drain. Leave the 115-123 catch intact.
  This is prescribed inline in the 7E step and in the Reconciliation table.
- **`kb-chat-content.tsx:52-58` rAF focus wrap.** 7I says "keep only the
  handleChange→insertRef rAF case". `kb-chat-content.tsx:52-58` also defers focus via
  rAF — but for a different reason: the Sheet uses `createPortal` on mobile, and
  immediately-focusing the input inside the portal's first mount frame can target a node
  that hasn't yet attached to `document`. Removing this rAF causes a test flake on
  `kb-chat-sidebar-a11y.test.tsx` (the focus-on-open assertion). **Keep this rAF.** The
  wraps to drop are the three in `chat-input.tsx:140-144, :381-385`, and any second rAF
  inside the quote-handle effect at `:165-173` if analysis shows it's redundant after
  the callback-ref migration (it may be — the functional setValue already commits in the
  same microtask, so the focus-after-commit ordering might survive without rAF).
- **`Element.contains` accepts `Node | null` at both runtime AND type level** (research
  correction — the original plan draft was wrong here). Modern `lib.dom.d.ts`
  (`@types/node` / built-in) types `Node.prototype.contains(other: Node | null): boolean`.
  At runtime, passing `null` returns `false` — which matches the original
  `isDescendant(null, ...)` fallback behavior exactly. So 7F call sites are one-liners:
  `article.contains(sel.anchorNode) && article.contains(sel.focusNode)`. No guards,
  no `!`, no ternaries. If the project's TypeScript version is older (< 4.9) and
  types `contains` as requiring `Node`, upgrade `tsconfig.json` `lib: ["DOM"]` or add
  a local type-assertion — but the tsconfig already targets modern DOM lib (this is a
  Next.js 15 project), so no action needed. Reference:
  <https://developer.mozilla.org/en-US/docs/Web/API/Node/contains>.
- **Route validator (Next.js 15).** Per `cq-nextjs-route-files-http-only-exports`, the new
  `app/api/conversations/route.ts` and the refactored `app/api/chat/thread-info/route.ts`
  must export only `GET` (and/or other HTTP methods + recognized config exports). The
  shared helper MUST live in a sibling module (`server/lookup-conversation-for-path.ts`)
  — not inside the route file. This plan already specifies the sibling location.
- **Silent fallback → Sentry mirror (`cq-silent-fallback-must-mirror-to-sentry`).** The
  new `/api/conversations` route follows the same `reportSilentFallback` pattern as
  `thread-info/route.ts`. Both lookup errors and count errors are mirrored to Sentry +
  pino with `feature: "kb-chat"`. Do NOT leave naked `log.warn(...)` on a fallback path.
- **Debounce on draft-key change (9C).** When the draftKey changes (user navigates
  doc A → doc B), the pending debounce timer from A's keystrokes must fire synchronously
  OR be cancelled. Cancelling is safer (flushing could write A's draft into B's key if
  React has already committed the doc-change but the debounce hasn't yet seen a new
  `draftKey` closure). Cancel + rehydrate from sessionStorage on draftKey change.
- **`kb-chat-context.tsx` type-contract change (8B).** Removing `submitQuote` and
  `registerQuoteHandler` from `KbChatContextValue` is a breaking change for any consumer
  outside this PR. Grep confirms only `kb/layout.tsx` (provides) and `kb-chat-content.tsx`
  (consumes `registerQuoteHandler`) use them. No external consumers. Still, call out in
  the PR description that the context split is behavior-preserving and only reorganizes
  which context provides which field.
- **Draft-persistence debounce interaction with unmount (9C).** On component unmount, any
  pending 250ms trailing timer must either fire synchronously (preferred — writes the
  final character) or cancel. Fire-on-unmount is correct: flush the value at that point
  to `safeSession`. Test that `test/chat-input-draft-key.test.tsx` still passes — if
  unmount cancels without flushing, the test's "reload-and-restore" path will fail.

## Research Insights (per-task depth)

### 7A — Sheet snap removal

**Implementation detail.** Before deleting the snap math, confirm there are no
`onSnapChange` callers. Grep: `grep -r "onSnapChange" apps/web-platform` returns
nothing (verified during planning). The prop is truly dead.

**Test migration pattern.** `test/sheet.test.tsx` currently tests nearest-snap behavior
by simulating drag events and asserting the final height equals one of `vh * 0.2`,
`vh * 0.6`, or `vh * 1.0`. After 7A, the mobile height is a constant `60vh`; the
drag-to-close test remains (release below `10vh` → `onClose`). A single assertion:
`expect(panel).toHaveStyle({ height: "60vh" })` when mounted on a mobile viewport.

### 7B / 7C — Functional setter + callback ref

**Strict Mode double-invocation.** React 18+ `<StrictMode>` runs state updaters twice
in development. A non-pure updater (e.g., one that calls `ref.current = ...` or
`element.focus()`) will execute its side effect twice. The current `quoteRef` shape
reads `textarea.selectionStart` inside the updater — this is idempotent (a DOM read
is not a mutation) and survives double-invocation. The `insertRef` migration should
preserve this pattern: read DOM position inside the updater; perform focus/scroll
side effects *after* `setValue` returns.

**Callback ref shape (7C).** The idiomatic React 19 shape for an imperative handle
on a child component when only ONE method is needed:

```typescript
// Instead of:
export interface ChatInputQuoteHandle {
  insertQuote: (text: string) => void;
  focus: () => void;
}
quoteRef?: React.MutableRefObject<ChatInputQuoteHandle | null>;

// Use:
quoteRef?: React.MutableRefObject<((text: string) => void) | null>;
```

Note the current `ChatInputQuoteHandle` has TWO methods (`insertQuote` + `focus`),
not one. The plan says to collapse to a one-method callback — that's fine because
`focus()` is only called from `kb-chat-content.tsx:55` and can be satisfied by a
separate ref or by having the insertQuote caller follow up with a focus call. Check
all callers of `quoteRef.current?.focus()` before collapsing; if there's a second
caller, keep a two-method object ref or introduce a second callback ref.

### 7E — Drain-block deletion

**undici 5.x behavior confirmed.** When `fetch()` returns a `Response` whose body is
never read, Node 20+ with undici automatically releases the socket back to the pool
and allows the stream to be GC'd. The original draining was defensive against a
different problem (learning 2026-04-02 is about *parsing* the body, not draining
it — confirmed inline in the code comment at `route.ts:107-108`). Deletion is safe.

**What to NOT change.** The outer `catch (err)` at `:115-123` handles the case where
`fetch()` itself rejects (Plausible unreachable). That log stays.

### 8A — sidebarProps grouping

**Ergonomics win.** Before: 13 props, 7 sidebar-only. After: 6 common props +
`sidebarProps?` object. When a caller types `<ChatSurface variant="full"` and hits
tab-completion, they see only the 6 common props — not 7 irrelevant sidebar ones.
The `sidebarProps?: ChatSurfaceSidebarProps` object gates discoverability on the
variant axis.

**Discriminated union variant? No.** An alternative is to discriminate on `variant`
via a union: `{ variant: "full" } | { variant: "sidebar", quoteRef, ... }`. This is
stricter but forces the caller to spread/merge props by hand. The grouped-object
approach is strictly less boilerplate, and the type-system cost of "you can pass
`sidebarProps` with variant=`full` and it silently won't apply" is low (nothing
breaks; the extra props just don't render). Keep the grouped-object approach.

### 8B — Context split

**Why not a single context with optional fields?** `KbChatContextValue` currently
mixes three concerns:

1. Sidebar lifecycle (`open`, `openSidebar`, `closeSidebar`, `contextPath`, `enabled`).
2. Per-path thread count (`messageCount`, `setMessageCount`).
3. Imperative quote bridge (`registerQuoteHandler`, `submitQuote`).

Concern 3 re-renders every consumer whenever a quote handler registers / unregisters
(on panel-open / close). Moving concerns 1+2 into one context and concern 3 into a
separate context means `selection-toolbar` (which consumes concern 3) doesn't re-render
on `openSidebar` state changes, and `<KbChatTrigger>` button (which consumes 1+2)
doesn't re-render when a quote handler swaps.

**Learning application — module-scope→async deps.** After the split, grep
`kb-chat-content.tsx` for every `useCallback`/`useMemo`/`useEffect` that closes over
`registerQuoteHandler`. Confirm the new hook is listed in deps (it's a stable
callback from the new context, but exhaustive-deps will still demand it). Reference:
`knowledge-base/project/learnings/2026-04-16-module-scope-to-async-state-deps-mismatch.md`.

### 8C — Shared lookup helper

**Why `server/lookup-conversation-for-path.ts`, not `app/api/.../helpers.ts`.**
Per `cq-nextjs-route-files-http-only-exports`, non-HTTP-method exports inside
`app/**/route.{ts,tsx}` break the Next.js 15 route-file validator (and only during
`next build` — not vitest, not `tsc --noEmit`). A sibling helper at
`app/api/chat/thread-info/lookup.ts` would be fine because it's NOT a `route.ts`,
but convention in this repo is to put cross-route utilities under `server/`.

**Signature.**

```typescript
// server/lookup-conversation-for-path.ts
export interface ConversationRow {
  id: string;
  context_path: string;
  last_active: string;  // ISO timestamp
  message_count: number;
}

export async function lookupConversationForPath(
  userId: string,
  contextPath: string,
): Promise<
  | { ok: true; row: ConversationRow | null }
  | { ok: false; error: "lookup_failed" | "count_failed" }
> {
  // Uses createServiceClient() internally — routes still handle auth.
  // Returns { ok: true, row: null } on not-found (not an error).
  // Mirrors errors to Sentry via reportSilentFallback.
}
```

The `{ ok: true, row: null }` vs `{ ok: false, error: ... }` split lets
`thread-info/route.ts` collapse both into `messageCount: 0` while
`conversations/route.ts` returns `null` (not-found) vs `500` (lookup error).

**Test delegation contract (negative-space learning).** Per
`knowledge-base/project/learnings/best-practices/2026-04-15-negative-space-tests-must-follow-extracted-logic.md`,
add a regex-based assertion in `test/api-conversations.test.ts` that verifies **both**:

- The route imports `lookupConversationForPath` from `@/server/...`.
- The route **invokes** it (not just imports dead).
- The route **branches on the result's `ok` field** (not ignoring the failure path).

Without these, a future route that imports the helper and silently skips auth will
pass a naive "substring test".

### 9A — rAF-coalesced setPill

**Frame-boundary batching.** `selectionchange` fires at 60Hz during drag-select on
desktop (every pointermove that changes the selection). React state updates are
already batched inside event handlers in React 18+, but `selectionchange` is a
document-level event fired by the browser outside React's batch — each fire can
trigger its own render. Wrapping `setPill` in `requestAnimationFrame` coalesces
multiple `setPill` calls within a single frame into the LAST value.

**Pattern:**

```typescript
const rafRef = useRef<number | null>(null);
function scheduleSetPill(next: PillState | null) {
  if (rafRef.current !== null) cancelAnimationFrame(rafRef.current);
  rafRef.current = requestAnimationFrame(() => {
    setPill(next);
    rafRef.current = null;
  });
}
// cleanup:
useEffect(() => () => {
  if (rafRef.current !== null) cancelAnimationFrame(rafRef.current);
}, []);
```

The `rafRef.current` guard ensures only ONE pending frame exists at a time. The
unmount cleanup prevents setState-on-unmounted warnings.

### 9C — Draft-persistence debounce

**Trailing-only semantics.** The draft write is trailing-only (250ms after the last
keystroke). Leading-edge is wrong here: the first keystroke shouldn't block on a
storage write. Trailing-only + flush-on-unmount + cancel-on-dep-change is the
minimal correct set.

**Pattern (inline, no library):**

```typescript
// Inside the persist useEffect (current chat-input.tsx:89-98):
useEffect(() => {
  if (typeof window === "undefined" || !draftKey) return;
  const timer = setTimeout(() => {
    if (value) {
      safeSession(draftKey, value);
    } else {
      safeSession(draftKey, null); // clear
    }
  }, 250);
  return () => clearTimeout(timer);
}, [draftKey, value]);
```

This pattern implicitly:

- Cancels the prior timer when `value` changes within 250ms (next effect run clears
  the previous timer).
- Cancels on `draftKey` change (effect deps include `draftKey`).
- Does NOT flush on unmount by default — the final pending write is lost.

**To get flush-on-unmount**, split into two effects:

```typescript
const pendingRef = useRef<{ key: string; value: string } | null>(null);
useEffect(() => {
  if (!draftKey) return;
  pendingRef.current = { key: draftKey, value };
  const timer = setTimeout(() => {
    if (pendingRef.current) {
      safeSession(pendingRef.current.key,
        pendingRef.current.value || null);
      pendingRef.current = null;
    }
  }, 250);
  return () => clearTimeout(timer);
}, [draftKey, value]);

// Flush on unmount
useEffect(() => () => {
  if (pendingRef.current) {
    safeSession(pendingRef.current.key,
      pendingRef.current.value || null);
  }
}, []);
```

The `pendingRef` approach is a concession to correctness — without it, the last
keystroke before unmount is lost. The test `test/chat-input-draft-key.test.tsx`
asserts restore-on-remount, which will fail under the naive pattern if the
"typed-then-immediate-unmount" sequence doesn't flush. Verify which variant the
existing test exercises; implement the flushing variant if the test requires it.

## PR-body reminder

The PR body must include, in order:

```
Closes #2387
Closes #2388
Closes #2389
```

not `Ref #` — these are full closures (per `wg-use-closes-n-in-pr-body-not-title-to`).
QA screenshots required per `rf-before-shipping-verify`. Semver label: `patch`.

## Resume prompt

```text
/soleur:work knowledge-base/project/plans/2026-04-17-refactor-kb-sidebar-cleanup-bundle-plan.md
Branch: feat-kb-sidebar-cleanup-bundle. Worktree: .worktrees/feat-kb-sidebar-cleanup-bundle/.
Closes #2387, #2388, #2389. Plan approved, Phase 0 TDD tests next.
```

## References

**React / Strict Mode / stale closures:**

- <https://react.dev/reference/react/useState#setstate-caveats> — functional updater
  pattern; Strict Mode double-invocation requires pure updaters.
- <https://react.dev/reference/react/StrictMode> — dev-only double-render helps find
  impure functions.
- <https://dmitripavlutin.com/react-hooks-stale-closures/> — stale closure primer;
  why `setValue((prev) => ...)` solves 90% of closure-staleness cases.

**TextEncoder performance:**

- <https://measurethat.net/Benchmarks/Show/20530/0/compare-textencoder-blob-new-textencoder>
  — benchmark: TextEncoder ~77× faster than Blob on small strings (123ns vs 9500ns).
- <https://developer.mozilla.org/en-US/docs/Web/API/TextEncoder/encodeInto> —
  `encodeInto()` is fastest with a preallocated buffer; overkill for our ≤8KB payload.

**Next.js 15 route-file validator:**

- <https://nextjs.org/docs/app/api-reference/file-conventions/route> — allowed exports
  (HTTP methods + framework config).
- <https://github.com/vercel/next.js/discussions/65120> — community thread on
  non-method exports being rejected by the validator.
- In-repo learning:
  `knowledge-base/project/learnings/runtime-errors/2026-04-15-nextjs-15-route-file-non-http-exports.md`
  — the PR #2347 post-merge outage and hotfix #2401 pattern.

**Node.contains TypeScript signature:**

- <https://developer.mozilla.org/en-US/docs/Web/API/Node/contains> — accepts
  `Node | null`, returns `false` on null.
- <https://github.com/microsoft/TypeScript/blob/main/src/lib/dom.generated.d.ts> —
  authoritative `lib.dom.d.ts` source.

**Debounce cleanup patterns:**

- <https://lodash.com/docs/4.17.15#debounce> — `.flush()` / `.cancel()` semantics.
- <https://github.com/downshift-js/downshift/issues/1322> — upstream discussion on
  flush-on-unmount vs cancel-on-unmount tradeoffs.

**In-repo learnings applied:**

- `knowledge-base/project/learnings/2026-04-07-kb-viewer-react-context-layout-patterns.md`
  — context `useMemo` requirement; expanded-dir key-collision pattern (tangential but
  relevant: `kb/layout.tsx` `ctxValue` already uses this).
- `knowledge-base/project/learnings/2026-04-16-module-scope-to-async-state-deps-mismatch.md`
  — audit `useEffect`/`useMemo` deps after any const→state conversion (applies to 8B).
- `knowledge-base/project/learnings/best-practices/2026-04-14-pure-reducer-extraction-requires-companion-state-migration.md`
  — half-extractions are strictly worse than no extractions; applies to 8B split.
- `knowledge-base/project/learnings/runtime-errors/2026-04-15-nextjs-15-route-file-non-http-exports.md`
  — keep non-HTTP helpers under `server/`, not inside `app/**/route.ts`.
- `knowledge-base/project/learnings/best-practices/2026-04-15-negative-space-tests-must-follow-extracted-logic.md`
  — prove delegation with `invokes AND branches-on-result` regex, not just `imports`.
