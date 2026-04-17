# Tasks — feat-kb-sidebar-cleanup-bundle

Plan: `knowledge-base/project/plans/2026-04-17-refactor-kb-sidebar-cleanup-bundle-plan.md`
Closes: #2387, #2388, #2389

## Phase 0 — TDD setup (RED)

- 0.1 Create `apps/web-platform/test/safe-session.test.ts` with read/write/clear/undefined-window/throws-silently cases.
- 0.2 Create `apps/web-platform/test/api-conversations.test.ts` with hit/miss/bad-path/unauthenticated/error-fallback cases.
- 0.3 Add Escape-contract cases to `apps/web-platform/test/selection-toolbar.test.tsx` (pill visible + Escape; pill absent + Escape).
- 0.4 Create `apps/web-platform/test/chat-input-draft-debounce.test.tsx` asserting ≤1 sessionStorage write within a 250ms window.
- 0.5 Run vitest — confirm all new tests FAIL (RED).

## Phase 1 — Simplicity bundle (#2387)

- 1.1 (7C) Replace `ChatInputQuoteHandle` interface with `(text: string) => void` callback ref; update imports in `chat-input.tsx`, `chat-surface.tsx`, `kb-chat-content.tsx`.
- 1.2 (7B) Converge `insertRef` effect onto functional `setValue((prev) => ...)` pattern; remove `value` from deps.
- 1.3 (7I) Remove excess `requestAnimationFrame` wraps in `chat-input.tsx` (keep the insertRef one + the `kb-chat-content.tsx:52-58` portal-focus one).
- 1.4 (7H) Create `apps/web-platform/lib/safe-session.ts`; replace 8 call sites in `chat-input.tsx` and `kb/layout.tsx`.
- 1.5 (7A) Drop `SheetSnap`, snap-points, `side` prop, and `onSnapChange` from `components/ui/sheet.tsx`; mobile height = `60vh`; keep drag-to-close. Update `test/sheet.test.tsx`.
- 1.6 (7G) Inline `SIDEBAR_PLACEHOLDER` in `kb-chat-content.tsx`.
- 1.7 (7F) Replace `isDescendant` helper with `Element.contains` in `selection-toolbar.tsx`; non-null-guard Node args.
- 1.8 (7J) Inline `refreshTree` in `kb/layout.tsx`; pass `fetchTree` directly into `ctxValue` `useMemo`.
- 1.9 (7D) Move `?context=` URL-param fetch out of `chat-surface.tsx` and into `app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` (~40 LOC page).
- 1.10 (7E) Delete drain block at `app/api/analytics/track/route.ts:107-114` only (NOT 115-123 catch).
- 1.11 Run vitest — all Phase-0 safeSession + draft-debounce tests still fail (debounce comes in Phase 3); all pre-existing tests green.

## Phase 2 — Architecture refinements (#2388)

- 2.1 (8A) Extract `ChatSurfaceSidebarProps`; group 7 sidebar-only props into `sidebarProps?` on `ChatSurfaceProps`. Update `kb-chat-content.tsx` + `page.tsx` call sites. Update `chat-surface-sidebar*.test.tsx`.
- 2.2 (8B) Create `components/kb/kb-chat-quote-bridge.tsx` with its own context + hook. Mount provider inside `KbLayout`. Move `quoteHandlerRef`, `registerQuoteHandler`, `submitQuote` from `kb-chat-context.tsx`.
- 2.3 (8B cont.) Update `kb-chat-content.tsx` to consume `registerQuoteHandler` from the new context; update any `submitQuote` callers.
- 2.4 (8C) Create `apps/web-platform/server/lookup-conversation-for-path.ts` shared helper.
- 2.5 (8C cont.) Refactor `app/api/chat/thread-info/route.ts` to use the helper (no response-shape change).
- 2.6 (8C cont.) Create `app/api/conversations/route.ts` with `GET` handler returning `{ conversationId, context_path, last_active, message_count } | null`. Use `reportSilentFallback` for error paths.
- 2.7 Make Phase-0 `api-conversations.test.ts` pass (GREEN).
- 2.8 (8D) Write `knowledge-base/engineering/kb-chat-agent-protocol.md` — documents `resumeByContextPath` idempotency and `> ...\n\n` quote convention. Run `npx markdownlint-cli2 --fix` on that file only.

## Phase 3 — Perf + tests (#2389)

- 3.1 (9A) Memoize `TextEncoder` in `selection-toolbar.tsx`; replace `new Blob([...]).size` with `encoder.encode(text).byteLength` (both call sites).
- 3.2 (9A cont.) Wrap `setPill` in `requestAnimationFrame` keyed by `rafRef`; cancel pending frame on re-entry and unmount.
- 3.3 (9B) Phase-0 Escape-contract cases pass (GREEN).
- 3.4 (9C) Debounce `chat-input.tsx` draft persistence — 250ms trailing timer. Cancel on draftKey change; flush on unmount. Keep synchronous rehydrate on draftKey change.
- 3.5 Phase-0 `chat-input-draft-debounce.test.tsx` passes (GREEN).

## Phase 4 — Verification + PR

- 4.1 Run `cd apps/web-platform && ./node_modules/.bin/vitest run` — 100% green (no new failures).
- 4.2 Run `cd apps/web-platform && npm run build` under Doppler — confirm no Next.js 15 route-validator errors on the new `/api/conversations/route.ts`.
- 4.3 Start dev server; execute 7 QA scenarios from plan; capture screenshots.
- 4.4 Draft PR. Body must include `Closes #2387`, `Closes #2388`, `Closes #2389`, the 7 QA screenshots, and a summary of LOC delta. Semver label: `patch`.
- 4.5 Run `/soleur:ship` — review + compound + ship pipeline.
