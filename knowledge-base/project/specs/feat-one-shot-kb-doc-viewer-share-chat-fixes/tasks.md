# Tasks — Fix KB document viewer (share UX + C4 Concierge collapse/reveal)

Plan: `knowledge-base/project/plans/2026-06-04-fix-kb-doc-viewer-share-chat-fixes-plan.md`
Wireframe: `knowledge-base/product/design/kb-viewer/kb-doc-viewer-share-chat-fixes.pen`
Lane: single-domain · Brand-survival threshold: none
Runner: vitest (`./node_modules/.bin/vitest run <path>` from `apps/web-platform`). Tests under `test/**`.

## 1. Setup / Preconditions
- [ ] 1.1 `grep -n "onClose" apps/web-platform/components/chat/kb-chat-content.tsx` — confirm `onClose` only powers the X button (~:161) + passed to `ChatSurface` (~:180).
- [ ] 1.2 `grep -n "setRightTab\|rightTab\|onClose=" apps/web-platform/components/kb/c4-workspace.tsx` — confirm `rightTab` is local state; only `onClose` wiring is :126.
- [ ] 1.3 Confirm markdown viewer callers pass a different `onClose` (`closeSidebar`) — `kb-desktop-layout.tsx:78`, `kb-mobile-layout.tsx:51`.
- [ ] 1.4 `git merge-base --is-ancestor 2ddccc7b HEAD && echo OK` — confirm PR #4922 fix present.

## 2. Item 1a — Share popup error surfacing (TDD)
- [ ] 2.1 RED: add `apps/web-platform/test/share-popover.test.tsx` — open popup, mock POST→500, assert visible error + retry control (NOT silent reset to idle); assert POST→201 happy path still reaches active state.
- [ ] 2.2 GREEN: extend `ShareState.status` with `"error"` (+ optional `errorMessage`); on `!res.ok` and `catch` in `generateLink` set `status:"error"` with a hoisted **generic** message; render error branch with a "Try again" button calling `generateLink`.
- [ ] 2.3 GREEN: apply non-silent handling to the GET-on-open `checkShare` path (do not block generation).
- [ ] 2.4 REFACTOR: hoist error copy to one constant; ensure outside-click + `confirmRevoke` reset clear the error state.

## 3. Item 1b — Server createShare hardening (TDD)
- [ ] 3.1 RED: extend `apps/web-platform/test/kb-share.test.ts` — insert returns `{code:"23503"}` → distinct non-`db-error` result; `{code:"23505"}` → existing 409 `concurrent-retry` preserved.
- [ ] 3.2 GREEN: add a `23503` branch in `server/kb-share.ts` insertError handling (before the generic `db-error` at ~:340) with a new `CreateShareErrorCode`; keep `reportSilentFallback` Sentry mirror (`cq-silent-fallback-must-mirror-to-sentry`).
- [ ] 3.3 GREEN: in `share-popover.tsx`, on POST `409 concurrent-retry` re-run `checkShare` → land on `active` (not error); other 409 → generic error.
- [ ] 3.4 Ensure `app/api/kb/share/route.ts` POST passes `result.code` through in the JSON body; route exports only HTTP verbs (`cq-nextjs-route-files-http-only-exports`).

## 4. Items 2+3 — C4 Concierge collapse/reveal (TDD)
- [ ] 4.1 RED: add `apps/web-platform/test/c4-workspace.test.tsx` (mock `useC4Project`, `KbChatContent`; stub `next/navigation` incl. `useSearchParams`). Assert: default expanded; collapse hides right panel + handle (diagram full width); reveal control appears when collapsed; reveal restores Concierge; thread survives collapse→reveal (component stays mounted).
- [ ] 4.2 GREEN: add `conciergeCollapsed` `useState` in `c4-workspace.tsx`; collapsed → don't render right `<Panel>`+`<ResizeHandle>` (or render at `collapsedSize` keeping it mounted — keep-mounted preferred to preserve thread). Add in-header collapse control (`aria-label="Collapse Concierge"`); repoint `KbChatContent onClose` from `setRightTab("code")` to `() => setConciergeCollapsed(true)`.
- [ ] 4.3 GREEN: add gold-gradient "Open Concierge" reveal pill (top-right of full-width diagram, `aria-label="Open Concierge"`) per wireframe frame 3.
- [ ] 4.4 REFACTOR: leave `page.tsx` / `kb-chat-trigger.tsx` suppression untouched; confirm focus management (reveal → focus chat input).

## 5. Verification
- [ ] 5.1 `tsc --noEmit` clean.
- [ ] 5.2 `./node_modules/.bin/vitest run test/share-popover.test.tsx test/kb-share.test.ts test/c4-workspace.test.tsx` green.
- [ ] 5.3 Existing `test/kb-chat-trigger.test.tsx` + `test/kb-chat-sidebar*.test.tsx` still green (no-regression AC7).
- [ ] 5.4 Manual/Playwright QA on a diagram doc: Generate link succeeds; collapse → full-width diagram; reveal → Concierge thread intact.
