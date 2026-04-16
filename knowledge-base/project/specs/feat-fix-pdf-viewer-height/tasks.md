---
title: "fix: PDF viewer height overflow hides pagination controls"
type: fix
date: 2026-04-16
---

# Tasks: fix PDF viewer height overflow

## Phase 1: Fix dashboard PDF viewer height containment

- [ ] 1.1 In `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx`, change the file preview content wrapper (line 145) from `className="flex-1 overflow-y-auto"` to `className="min-h-0 flex-1"`
- [ ] 1.2 Verify the markdown content view (non-file path) is unaffected -- its wrapper on line 178 (`flex-1 overflow-y-auto px-4 py-6 md:px-8`) should remain unchanged

## Phase 2: Fix shared page PDF viewer height

- [ ] 2.1 In `apps/web-platform/app/shared/[token]/page.tsx`, change the PDF container (line 147) from `className="h-[80vh]"` to `className="h-[70vh]"`

## Phase 3: Run existing tests

- [ ] 3.1 Run `node node_modules/vitest/vitest.mjs run apps/web-platform/test/file-preview.test.tsx` to verify existing PDF preview tests still pass
- [ ] 3.2 Run `node node_modules/vitest/vitest.mjs run apps/web-platform/test/shared-page-ui.test.tsx` to verify shared page tests still pass
- [ ] 3.3 Run `node node_modules/vitest/vitest.mjs run apps/web-platform/test/kb-page-routing.test.tsx` to verify KB routing tests still pass

## Phase 4: Visual QA (Playwright)

- [ ] 4.1 Navigate to a multi-page PDF in the dashboard KB viewer and verify pagination controls are visible without scrolling
- [ ] 4.2 Navigate to a shared PDF link and verify pagination controls are visible without scrolling
- [ ] 4.3 Verify image preview, text preview, and download preview are unaffected in the dashboard
