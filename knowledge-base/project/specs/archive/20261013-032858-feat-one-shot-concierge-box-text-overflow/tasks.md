# Tasks — fix Concierge status box text overflow

Plan: `knowledge-base/project/plans/2026-06-03-fix-concierge-status-box-text-overflow-plan.md`
Lane: single-domain · Threshold: aggregate pattern

## 1. Setup / Preconditions (Phase 0)

- [x] 1.1 `grep -n "whitespace-nowrap" apps/web-platform/components/chat/message-bubble.tsx` — confirm 2 sites (line 27 chip, line 193 header). Edit only line 27.
- [x] 1.2 VERIFIED (deepen-plan): Playwright `testDir: ./e2e`, `testMatch: **/*.e2e.ts`; bubble tests need the `authenticated` project (`cc-soleur-go-*` / `start-fresh-*` / `nav-states-*`). New test MUST be `e2e/cc-soleur-go-*.e2e.ts` or extend `e2e/cc-soleur-go-bubbles.e2e.ts`. (NOT `test/*.spec.ts` — silently skipped.)
- [x] 1.3 `grep -n "include" apps/web-platform/vitest.config.ts` — confirm `.test.tsx` collected by `test/**/*.test.tsx`.
- [x] 1.4 Re-read `message-bubble.tsx:24-30, 155-175, 264-269` to confirm line numbers have not drifted.

## 2. Core Implementation (RED → GREEN)

- [x] 2.1 (RED) Update `apps/web-platform/test/message-bubble-tool-status-chip.test.tsx:71-83` — re-point the `whitespace-nowrap` assertion to the wrap-capable mechanism (fails against current code). Keep the other 4 tests intact.
- [x] 2.2 (RED) Extend `apps/web-platform/e2e/cc-soleur-go-bubbles.e2e.ts` (or create `e2e/cc-soleur-go-status-overflow.e2e.ts`) — Playwright via `attachWsInjector`: long label → no horizontal overflow of card (reuse `nav-states-shell.e2e.ts:259,277` `scrollWidth-clientWidth` + empty-band guard); short label → single line. Both `full` and `sidebar` variants. (Fails/overflows against current code.)
- [x] 2.3 (GREEN) Apply Option A to `message-bubble.tsx:27` — swap `whitespace-nowrap` → `[overflow-wrap:anywhere]` (or `break-words`). Do NOT touch line 193.
- [ ] 2.4 (GREEN fallback) If 2.2 short-label single-line assertion fails, switch to Option B: add `w-fit` to bubble card (line 165), keep nowrap on line 27, and update the 2.1 assertion to the `w-fit` mechanism.

## 3. Testing / Verification (Phase 3)

- [x] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/message-bubble-tool-status-chip.test.tsx test/message-bubble-header.test.tsx` — green.
- [ ] 3.2 Run the Playwright e2e (`cc-soleur-go-*`, authenticated project) — both `full` and `sidebar` variants green (no overflow + short-label single-line). Confirm the file matches `testMatch` (`ls e2e/cc-soleur-go-*.e2e.ts`).
- [x] 3.3 `tsc --noEmit` clean for `apps/web-platform`.
- [x] 3.4 Run `cc-routing-panel-concierge-visibility.test.tsx` + remaining `message-bubble-*` suites — green.
