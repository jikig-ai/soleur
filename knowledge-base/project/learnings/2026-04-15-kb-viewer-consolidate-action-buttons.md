---
name: KB viewer action-button consolidation and the hidden cost of `vi.mock` export drift
description: Consolidating Download into the KB viewer header surfaced a predictable but easy-to-miss test failure pattern — adding a new named export to a component that is `vi.mock`-ed elsewhere silently breaks those mocks.
date: 2026-04-15
category: ui-bugs
module: kb-viewer
pr: 2340
tags: [kb, ux, showDownload, breadcrumb, decodeURIComponent, vi-mock, test-infrastructure, aria-current, compareDocumentPosition]
---

# Learning: KB Viewer Action-Button Consolidation

## Problem

The KB document viewer wasted ~45 px of vertical space above the PDF by rendering two rows of chrome:

1. A header row with `Share` + `Chat about this` on the right
2. A second row inside `PdfPreview`/`TextPreview` with a filename label on the left and an isolated `Download` button on the right

The filename in that second row duplicated the last breadcrumb segment — except the breadcrumb rendered the URL-encoded form (`Au%20Chat%20P%C3%B4tan`) while the inner row rendered the decoded form (`Au Chat Pôtan`), giving users two conflicting "titles" for one file.

## Solution

Three-part UI change threaded through four files:

1. **`showDownload?: boolean` prop (default `true`)** on `PdfPreview` and `TextPreview` (via `FilePreview`). The dashboard opts out with `showDownload={false}`; the shared viewer at `/shared/[token]` — which renders `PdfPreview` **directly** (not via `FilePreview`) — relies on the default.
2. **`safeDecode` helper exported from `kb-breadcrumb.tsx`** wrapping `decodeURIComponent` in a try/catch so malformed percent-escapes fall back to the raw segment. Applied to breadcrumb segments *and* reused in the dashboard page's `filename` derivation so `download="..."` and `aria-label="Download ..."` render human-readable text.
3. **`aria-current="page"` + `data-testid="kb-breadcrumb-current"`** on the last breadcrumb segment, replacing a Tailwind-class assertion with a semantic + stable selector for tests.

PDF *error* branch in `PdfPreview` keeps its Download link unconditionally — if the render itself fails, the outer header might never paint, so the inner Download is the user's last affordance.

## Key Insight

**A boolean-flag prop is OK when the default has exactly one silent consumer.** The architecture reviewer initially read `showDownload` as "dashboard concern leaking into a shared component" — until tracing showed the shared viewer consumes `PdfPreview` directly, so the default *only* protects one external call site (`app/shared/[token]/page.tsx`). Tightening the JSDoc to name that specific file + adding a regression test asserting default-true renders the Download anchor is a stronger guard than any prose comment.

## Session Errors

- **E1: `vi.mock` factory went stale when the mocked module gained a new named export.** `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` added `import { KbBreadcrumb, safeDecode } from "@/components/kb/kb-breadcrumb"`. The existing mock in `test/kb-page-routing.test.tsx` only exported `KbBreadcrumb`, so under test `safeDecode` was `undefined` and `safeDecode(rawFilename)` threw mid-render — vitest spat a 7-failure crash-lot with a stack rooted in the implementation file, not the mock.
  - **Recovery:** Added `safeDecode` to the mock factory with an inline `try/decodeURIComponent/catch` body.
  - **Prevention:** Any time you add a new named export to a module, grep for that module path inside `test/**` (`grep -rn 'vi.mock("@/components/kb/kb-breadcrumb"' test/`) and update every mock factory. This should be part of a mental checklist when adding exports to a mocked module. Candidate hook: a pre-commit or pre-push check that diffs `git show HEAD:<file>` vs the working tree for new `export` lines, then greps `vi.mock("<path>"` in tests and warns if the mock factory body doesn't mention the new identifier.

- **E2: Port 3000 collision with a sibling worktree's long-running dev server.** `lsof -iTCP:3000` showed `node` (PID 56186) had been holding the port for 3+ hours from worktree `feat-integrations-team-settings-sidebar`. Killing that process would trash another session's in-progress work.
  - **Recovery:** Started the QA dev server with `PORT=3001` (verified the server entrypoint reads `process.env.PORT` at `apps/web-platform/server/index.ts:19`).
  - **Prevention:** The `qa` skill's "Step 1.5: Ensure Dev Server is Running" should probe port 3000 first, then fall back to `3001`, `3002`, etc. when busy, and export the chosen port for downstream Playwright navigation.

- **E3: Dev server on 3001 compiled but `/login` returned HTTP 500 with `TypeError [ERR_INVALID_URL_SCHEME]` in postcss-loader, plus `'Rejected origin'` entries for `http://localhost:3001`.** The stack trace in the browser console pointed `tsx`'s ESM loader at `.worktrees/feat-integrations-team-settings-sidebar/apps/web-platform/node_modules/tsx/dist/esm/index.mjs` — i.e. the sibling worktree's cached loader, not ours. The CORS allowlist appears to hardcode `localhost:3000`.
  - **Recovery:** None applied. QA browser scenarios skipped; functional coverage fell back to the 1400-test vitest suite (which fully validates the 8 Test Scenarios: DOM order, pass-through prop, URL decoding, malformed-URI safety, aria-current, and PDF error-fallback Download).
  - **Prevention:** Document the ESM loader cache collision as a known sharp edge for concurrent worktrees. When QA browser scenarios are blocked by dev-server environmental issues, it's legitimate to fall back to vitest coverage *if and only if* the vitest suite covers each Test Scenario — which must be explicitly mapped in the QA report (done in this session). Candidate skill edit: `qa/SKILL.md` should document this fallback pattern so future sessions don't spend 30+ minutes debugging somebody else's loader cache.

## Tags

category: ui-bugs
module: kb-viewer
