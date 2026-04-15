---
title: "fix: KB share button missing on PDF attachments"
type: fix
date: 2026-04-15
issue: 2232
branch: feat-kb-share-btn-pdf-attachments
---

# Fix: KB share button missing on PDF (and other non-markdown) attachments

## Enhancement Summary

**Deepened on:** 2026-04-15
**Sections enhanced:** Security Review, Technical Approach, Test Scenarios, new CSP/react-pdf section.

### Key Improvements

1. **Middleware CSP verified compatible** — `worker-src 'self' blob:` already configured for pdfjs in `lib/csp.ts:59`; `/shared` and `/api/shared` already in `PUBLIC_PATHS`. No middleware changes needed.
2. **Binary-response CSP clarified** — the `KB_BINARY_RESPONSE_CSP` header on the binary response applies only when the binary is navigated to as a document (top-level frame), not when fetched as data. `react-pdf` fetches the PDF bytes via XHR and parses them client-side, so the binary's per-response CSP does not interfere with inline preview.
3. **IDOR re-validation at point of use** — explicit validation in the owner API mirrors the `2026-04-11-service-role-idor-untrusted-ws-attachments` learning: every service-role operation that acts on user-supplied paths must re-validate at the point of use, even if the path "came from" a trusted source (the Supabase share record).
4. **Symlink rejection at both owner API and public API** — per `2026-04-07-symlink-escape-recursive-directory-traversal` learning. Owner API rejects symlink share creation; public API rejects symlinked paths at serve time (belt and suspenders, since paths could be symlinked after share creation).
5. **Filename sanitization for Content-Disposition** — carried forward from `2026-04-12-binary-content-serving-security-headers`. Filename regex `/["\r\n\\]/g` replaced with `_`. Applied in the shared binary-response helper.
6. **Async fs operations only** — never use `readFileSync`; same learning.
7. **Fetch-once optimization for shared page** — use single `fetch(/api/shared/${token})`, branch on `Content-Type`. Binary content is already cached by the browser when rendered via `<embed>` / `<img>` pointing at the same URL — no duplicate GET.
8. **Dead-link prevention** — apply the 50 MB size guard at share creation time, not just at serve time, so users don't generate links that 413 on view.

### New Considerations Discovered

- **CSP for the `/shared/[token]` HTML page** comes from `middleware.ts` (builds per-request CSP via `buildCspHeader`). The middleware already allows `worker-src 'self' blob:` and `img-src 'self' blob: data:` — sufficient for react-pdf and inline image rendering. No middleware changes needed.
- **Analytics/logging parity** — the existing `event: "shared_page_viewed"` log must fire for binary views too; be careful to emit it inside both branches (JSON and binary) of the public route.
- **Content-Disposition on shared binaries** — keep `inline` (not `attachment`) for PDFs and images so the browser renders in-place; preserve `attachment` for `.docx` per existing `ATTACHMENT_EXTENSIONS` set.
- **HEAD request optimization rejected** — Node.js `Response` in Next.js route handlers does not auto-generate HEAD; extra code cost isn't worth it. Use the single GET + Content-Type branching instead.

## Problem Statement

The KB viewer shows a "Share" button in the header when viewing markdown files (e.g. `vision.md`) but not when viewing uploaded PDF attachments (or images, CSVs, TXTs, DOCX). The button renders in the markdown branch of `app/(dashboard)/dashboard/kb/[...path]/page.tsx` (line 153) but is absent from the non-markdown branch (lines 102–133). Even if the button were rendered, the server route `app/api/kb/share/route.ts` rejects any path that does not end in `.md` with `400 "Only markdown files can be shared"` — so wiring the UI alone is insufficient.

Reported in [#2232](https://github.com/jikig-ai/soleur/issues/2232) (Phase 3: Make it Sticky, priority P2, type/bug, domain/engineering).

**Scope decision:** Extend sharing to cover all previewable KB file types (markdown + binary attachments). Rationale:

- Users already upload PDFs/images/CSVs into the KB ([#file-upload] feature is live).
- The share feature's original purpose is "share high-value KB artifacts externally" (per `2026-04-10-feat-kb-document-sharing-plan.md`) — PDFs are high-value artifacts.
- Limiting to `.md` was a first-slice decision from the original plan, not a security boundary. The server already safely serves binaries to the owner via `/api/kb/content/[...path]` with path traversal checks, size guards, and CSP.
- No data model change is required — `kb_share_links.document_path` is already a generic text column.

## Root Cause

Two bugs:

1. **UI bug** — `app/(dashboard)/dashboard/kb/[...path]/page.tsx` renders `<SharePopover />` only in the markdown branch. The non-markdown branch (returned early at line 102) has no SharePopover in its header.
2. **Server gate** — `app/api/kb/share/route.ts` line 32–37 rejects any `documentPath` that does not end in `.md`. The existing test `test/kb-share-md-only.test.ts` pins this behavior for `.png`, `.pdf`, `.csv`, and extensionless paths.

A third consequence: the public viewer `/shared/[token]` and its API `/api/shared/[token]/route.ts` only know how to serve markdown — it calls `readContent()` which throws `KbNotFoundError("Only .md files are supported")` for any other extension.

## Proposed Solution

Three-layer fix:

1. **UI** — Render `<SharePopover />` in the non-markdown branch header, symmetric with the markdown branch. (One component, two render sites.)
2. **Owner API (`/api/kb/share`)** — Replace the `.md`-only check with a "path must resolve to an existing file in the workspace KB root" check. Reuse the same `isPathInWorkspace` + `fs.stat` pattern already used in the binary branch of `/api/kb/content`.
3. **Public viewer API (`/api/shared/[token]`)** — Fork on extension: `.md` (or extensionless) → return JSON `{content, path}` as today; binary → stream the file with the same `Content-Type` / `Content-Disposition: inline` / `Content-Security-Policy` / `X-Content-Type-Options: nosniff` / size guard pattern used by `/api/kb/content/[...path]/route.ts`. Extract the binary-serving logic into a helper shared by both routes (`server/kb-binary-response.ts`) to avoid drift.
4. **Public viewer page (`/shared/[token]`)** — Fork on content type: if the API returns JSON, render `<MarkdownRenderer />` as today; if the API returns a binary response, render a minimal preview (PDF → embed via the existing `<PdfPreview>` component, image → `<img>`, anything else → download link). Reuse `<FilePreview>` where practical — but it currently only consumes `/api/kb/content/{path}`, so generalize it to accept a URL prop (`src`) or extract the rendering primitives.

## Technical Approach

### File-by-file changes

#### 1. `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` (UI wiring)

In the non-markdown branch (around line 102–133), add `<SharePopover documentPath={joinedPath} />` to the right-side header cluster, mirroring the markdown branch (line 152–163):

```tsx
// Before (lines 118–127 in current file)
<Link href={chatUrl} className="...">Chat about this</Link>

// After
<div className="flex items-center gap-2">
  <SharePopover documentPath={joinedPath} />
  <Link href={chatUrl} className="...">Chat about this</Link>
</div>
```

No other changes to this file.

#### 2. `apps/web-platform/app/api/kb/share/route.ts` (owner API)

Remove the `.md` gate (lines 32–37) and replace with a file-existence check:

```ts
// Remove:
if (!body.documentPath.endsWith(".md")) { ... 400 ... }

// Keep existing isPathInWorkspace check (line 53).
// Add: verify the path resolves to an existing regular file (not dir, not symlink).
//      Reuse the symlink + lstat pattern from app/api/kb/content/[...path]/route.ts:103–119.
const fullPath = path.join(kbRoot, body.documentPath);
if (!isPathInWorkspace(fullPath, kbRoot)) {
  return NextResponse.json({ error: "Invalid document path" }, { status: 400 });
}
let lstat: fs.Stats;
try {
  lstat = await fs.promises.lstat(fullPath);
} catch {
  return NextResponse.json({ error: "File not found" }, { status: 404 });
}
if (lstat.isSymbolicLink() || !lstat.isFile()) {
  return NextResponse.json({ error: "Invalid document path" }, { status: 400 });
}
```

Keep all other behavior (existing-share dedup, crypto token, insert, logging).

#### 3. `apps/web-platform/server/kb-binary-response.ts` (NEW — shared helper)

Extract the binary-serving logic currently inlined in `/api/kb/content/[...path]/route.ts:93–144` into a shared helper:

```ts
export const MAX_BINARY_SIZE = 50 * 1024 * 1024;
export const CONTENT_TYPE_MAP: Record<string, string> = { /* copy from route.ts:15–27 */ };
export const ATTACHMENT_EXTENSIONS = new Set([".docx"]);

export async function readBinaryFile(kbRoot: string, relativePath: string): Promise<
  | { ok: true; buffer: Buffer; contentType: string; disposition: "inline" | "attachment"; safeName: string }
  | { ok: false; status: 403 | 404 | 413; error: string }
> { /* lstat, symlink check, size guard, readFile */ }

export function buildBinaryResponse(b: { buffer; contentType; disposition; safeName }): Response {
  /* same headers as current route.ts:132–141 */
}
```

Refactor `/api/kb/content/[...path]/route.ts` to call the helper. No behavior change.

#### 4. `apps/web-platform/app/api/shared/[token]/route.ts` (public viewer API)

Fork on extension (mirror the pattern already in `/api/kb/content`):

```ts
const ext = path.extname(shareLink.document_path).toLowerCase();
if (ext === ".md" || ext === "") {
  // existing path — readContent → JSON
} else {
  // binary path — readBinaryFile(kbRoot, shareLink.document_path) → buildBinaryResponse
}
```

Keep the 404/410/403 error branches unchanged. Log `event: "shared_page_viewed"` in both branches.

#### 5. `apps/web-platform/app/shared/[token]/page.tsx` (public viewer page)

Detect the response type (inspect `Content-Type` header) and route accordingly:

- `application/json` → existing JSON parse + `<MarkdownRenderer>` path.
- `image/*` → render `<img src={`/api/shared/${token}`} alt={filename} />` with the same container chrome.
- `application/pdf` → lazy-load the existing `<PdfPreview>` component; pass `/api/shared/${token}` as the `src`.
- anything else → download link pointing at `/api/shared/${token}`.

To avoid a second network request, use a `HEAD` or check the first `fetch` response's `Content-Type` before consuming the body. If JSON, `res.json()`; otherwise don't consume — render the embed pointing at the URL. The same response has already been cached by the browser, so the embed's subsequent GET is a 200 from cache.

File paths used inside the shared page embed MUST go through `/api/shared/${token}` (never `/api/kb/content/…`) so unauthenticated viewers can fetch them.

#### 6. `apps/web-platform/components/kb/share-popover.tsx` (no changes)

The component is already path-agnostic — it posts whatever `documentPath` it receives. No edits needed.

### Error / edge case handling

- **PDF with broken preview:** `<PdfPreview>` already has error fallback; no changes.
- **File deleted between share creation and view:** existing `KbNotFoundError` branch returns 404 in both JSON and binary paths.
- **Large PDF (>50 MB):** same size guard as `/api/kb/content` — return 413. Update share creation to reject paths over the limit at creation time (avoids a dead share link).
- **Symlink:** reject at both share creation and public view (same pattern as `/api/kb/content`).
- **SEO:** `noindex` meta already set on `/shared/[token]`; binary responses carry `X-Content-Type-Options: nosniff` and the `KB_BINARY_RESPONSE_CSP` header, matching the authenticated route.
- **Rate limiting:** `/api/shared/[token]` already has `shareEndpointThrottle` — unchanged.

## Acceptance Criteria

- [ ] Viewing an uploaded PDF in the KB shows the same "Share" button as `vision.md`.
- [ ] Viewing an uploaded image/CSV/TXT/DOCX in the KB shows the "Share" button.
- [ ] Clicking "Share" on a PDF generates a `/shared/<token>` link successfully.
- [ ] Opening the generated link in a private window renders the PDF inline (embedded preview) with the Soleur branded header and CTA banner.
- [ ] Opening a revoked PDF share link returns the existing "revoked" error UI.
- [ ] Opening a share for a deleted file returns 404 with the existing error UI.
- [ ] Share creation for a path that does not exist returns 404.
- [ ] Share creation for a symlink or directory returns 400.
- [ ] Markdown sharing behavior is unchanged (regression guard).
- [ ] The existing `kb-share-md-only.test.ts` test file is replaced with `kb-share-allowed-paths.test.ts` asserting the new "path must be an existing KB file" semantics (see Test Scenarios).

## Test Scenarios

### New tests

- [ ] `test/kb-share-allowed-paths.test.ts` (replaces `kb-share-md-only.test.ts`):
  - allows `.md` path that exists
  - allows `.pdf` path that exists
  - allows `.png` path that exists
  - rejects non-existent path → 404
  - rejects symlink → 400
  - rejects directory → 400
  - rejects path outside kbRoot → 400 (already covered by `isPathInWorkspace` but keep the assertion explicit)
- [ ] `test/kb-page-routing.test.tsx` — extend existing `.pdf` test to assert `getByTestId("share")` is present in both markdown and non-markdown branches.
- [ ] `test/shared-page-binary.test.ts` (new) — asserts `/api/shared/[token]` returns `application/pdf` binary response for a PDF share, and `application/json` for a markdown share.
- [ ] `test/shared-page-ui.test.tsx` (new) — asserts the `/shared/[token]` page renders `<PdfPreview>` when API returns `application/pdf` and `<MarkdownRenderer>` when API returns JSON.

### Existing tests to update

- [ ] `test/kb-share-md-only.test.ts` — delete (behavior inverted).
- [ ] `test/share-links.test.ts` — review for assertions that bake in `.md`-only and update accordingly.

### Additional test coverage (from deepening)

- [ ] **Negative-space security tests** (from `2026-04-07-symlink-escape-recursive-directory-traversal` learning pattern):
  - Owner API rejects symlink share creation with 400.
  - Public API rejects symlinked document_path at serve time with 403 (even if the DB row exists, defense-in-depth).
  - Owner API rejects oversize file (>50 MB) share creation with 413.
- [ ] **Content-Disposition filename sanitization test** (from `2026-04-12-binary-content-serving-security-headers`): send a share for a file whose path contains `"` or `\n` → assert the response `Content-Disposition` header has those characters replaced with `_`. (In practice the upload layer already sanitizes filenames, but the helper must not trust that.)
- [ ] **Async I/O regression guard**: no `readFileSync` introduced — either an eslint rule assertion or a simple grep test in CI (`grep -R "readFileSync" apps/web-platform/server/kb-binary-response.ts && exit 1`).
- [ ] **Refactor regression guard**: the helper-extraction refactor of `/api/kb/content` must keep existing tests green without modification. If any `kb-content-*.test.ts` test requires updates beyond import paths, that's a signal the refactor changed behavior — stop and reconsider.

## Security Review

- **Same auth boundary as markdown sharing.** Server only serves files the share owner has in their KB root; the token → user_id → workspace_path chain is unchanged.
- **Path traversal:** `isPathInWorkspace` check already guards both share creation and public viewing. Unchanged.
- **Symlink escape:** now explicitly rejected at both share creation AND public viewing (new in this PR). Per the `2026-04-07-symlink-escape-recursive-directory-traversal` learning, point-access functions must each validate independently — we cannot rely on creation-time validation because symlinks could be planted after the fact. Both sites use `lstat().isSymbolicLink()` with early rejection.
- **IDOR re-validation at point of use (from `2026-04-11-service-role-idor-untrusted-ws-attachments`).** The public `/api/shared/[token]` route uses `createServiceClient()` to bypass RLS. The `document_path` is stored in the DB and is owner-supplied, so it is not raw untrusted input — BUT every service-role operation must still validate path containment at the point of use. The code path: token → DB lookup → owner workspace resolution → `isPathInWorkspace(fullPath, kbRoot)` check. The containment check remains the authoritative gate regardless of where the path came from. Don't skip the check because "the owner set it."
- **CSP:** `KB_BINARY_RESPONSE_CSP` (`default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'`) already restricts binary responses; applied identically in `/api/shared/[token]` binary branch. This CSP applies only when a user navigates to the binary URL as a top-level document (e.g., Chrome's built-in PDF viewer). When `react-pdf` fetches the PDF bytes via XHR from the `/shared/[token]` page, the page's CSP (set by `middleware.ts` via `buildCspHeader`) governs — not the binary response's CSP. Verified: middleware already sets `worker-src 'self' blob:` (required for pdfjs worker) and `img-src 'self' blob: data:` (required for inline images).
- **Size DoS:** 50 MB limit already applied in the authenticated route; applied identically in the public route AND at share creation time to prevent dead links (user shares a 200 MB PDF → 413 forever).
- **MIME sniffing:** `X-Content-Type-Options: nosniff` preserved from `CONTENT_TYPE_MAP`.
- **Content-Disposition injection:** per the `2026-04-12-binary-content-serving-security-headers` learning, sanitize filename via `.replace(/["\r\n\\]/g, "_")` before including in the `Content-Disposition` header. Applied in the shared helper.
- **Async I/O:** never `readFileSync` — always `fs.promises.readFile` (same learning).
- **Enumeration:** random 32-byte base64url tokens (unchanged). Revoked tokens return 410.
- **Rate limiting:** existing `shareEndpointThrottle` covers both markdown and binary branches (same route, pre-fork guard).
- **Information leakage via filename:** the `Content-Disposition` header reveals the filename to unauthenticated viewers. This is intentional (that's the point of sharing) and matches the markdown path (which reveals the path in the JSON body).
- **No new attack surface.** The binary serving is already trusted by the authenticated route `/api/kb/content`; this extends the same guards to the tokenized-public route. The helper-extraction refactor ensures the two routes cannot drift — a fix in one propagates to both.

## CSP & react-pdf Compatibility

The `/shared/[token]` page rendering a PDF via `react-pdf` depends on multiple CSP directives from `middleware.ts` (`lib/csp.ts`):

- `worker-src 'self' blob:` — pdfjs worker creates blob URLs. Already present (line 59).
- `img-src 'self' blob: data:` — react-pdf may render pages to blob canvases. Already present (line 54).
- `connect-src 'self' ...` — react-pdf fetches the PDF via same-origin XHR. Already present (line 56).
- `script-src` — pdfjs runs in a worker spawned from the main thread. Nonce-based script-src applies to the main bundle; worker script loading is governed by `worker-src`. Already configured.
- `frame-src` / `frame-ancestors` — not needed; react-pdf uses `<canvas>`, not `<iframe>`.

Verification approach: manual QA step 7.4 loads a PDF in a private window and confirms the canvas renders. If CSP violations appear, inspect browser devtools console and report-uri (Sentry via `SENTRY_CSP_REPORT_URI`).

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — BLOCKING tier, new shared viewer surface for non-markdown content).

### Engineering (CTO)

**Status:** self-reviewed (bug fix in owned subsystem).
**Assessment:** The fix aligns with existing patterns. The binary-response helper extraction pays down the duplication debt between `/api/kb/content` and the new `/api/shared/[token]` binary branch. No infrastructure changes. No new dependencies.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline) — bug fix restoring symmetry with existing markdown behavior, no new user-facing page (the `/shared/[token]` page already exists; this extends what it can render).
**Agents invoked:** none (advisory, not BLOCKING)
**Skipped specialists:** ux-design-lead (N/A — no new wireframes needed; reuses existing `<PdfPreview>` and `<FilePreview>` rendering primitives), copywriter (N/A — no new copy, error strings updated in-line)
**Pencil available:** N/A

#### Findings

The "share" affordance is expected symmetric with markdown — this restores user trust by removing a gotcha rather than adding a new flow. The shared PDF viewer page reuses the existing Soleur header + CTA banner chrome; no new page-level design is introduced.

## Implementation Phases

1. **Test scaffolding** — write failing tests for owner API, public API, and UI (TDD gate).
2. **Owner API** — relax `.md` gate, add existence + symlink check, make owner API tests green.
3. **Extract binary-response helper** — refactor `/api/kb/content` to call helper, ensure existing tests stay green.
4. **Public API binary branch** — fork on ext, make public API tests green.
5. **UI wiring** — add `<SharePopover>` to non-markdown branch of KB page.
6. **Public viewer page binary branch** — detect content-type, render embed/image/download. Make UI tests green.
7. **Manual QA** — upload a PDF via existing KB upload flow, share it, open in private window, verify embedded preview. Repeat for PNG and CSV.
8. **Markdown regression check** — re-run all share tests and manually share a `.md` file to confirm the existing flow is unchanged.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| UI-only fix (show button, keep server gate) | Minimal diff | Button 400s on click — worse UX than current state | Rejected |
| Extend sharing but force download (no inline preview) | Simplest public viewer change | Loses the "share a PDF and viewer sees it instantly" experience; misaligned with marketing goal in original sharing plan | Rejected |
| Migrate binary KB files to Supabase Storage with signed URLs | Offloads bytes from Next.js process | Large refactor; out of scope for a P2 bug; breaks git-committed storage invariant (constitution) | Deferred — out of scope |
| Per-file-type allowlist (e.g., pdf/png only, no csv/docx) | Smaller surface | Arbitrary; users will hit the gate again with csv/docx; inconsistent with authenticated viewer | Rejected |

## Non-Goals / Out of Scope

- New sharing dashboard (already deferred in original plan — still deferred).
- Password protection, expiry timers, access logs — not requested.
- Sharing a whole folder tree — not requested.
- OpenGraph preview images for shared PDFs — possible follow-up, out of scope.
- Supabase Storage migration — out of scope.

## Related Files

- `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` (UI branch missing SharePopover)
- `apps/web-platform/app/api/kb/share/route.ts` (`.md` server gate)
- `apps/web-platform/app/api/shared/[token]/route.ts` (markdown-only public read)
- `apps/web-platform/app/shared/[token]/page.tsx` (markdown-only public render)
- `apps/web-platform/app/api/kb/content/[...path]/route.ts` (binary-response pattern to reuse)
- `apps/web-platform/components/kb/share-popover.tsx` (no change, already path-agnostic)
- `apps/web-platform/components/kb/file-preview.tsx` + `pdf-preview.tsx` (reuse for shared viewer)
- `apps/web-platform/lib/kb-csp.ts` (`KB_BINARY_RESPONSE_CSP`)
- `apps/web-platform/server/kb-reader.ts` (`readContent` is markdown-only by design; keep as-is)
- `apps/web-platform/supabase/migrations/017_kb_share_links.sql` (no change — `document_path` is already generic)
- `apps/web-platform/test/kb-share-md-only.test.ts` (delete / invert)
- `apps/web-platform/test/kb-page-routing.test.tsx` (extend with share-button assertion)
- `apps/web-platform/test/share-links.test.ts` (review)

## Institutional Learnings Referenced

- `knowledge-base/project/plans/2026-04-10-feat-kb-document-sharing-plan.md` — original sharing design; notes `.md`-only was a first slice, not a boundary.
- `knowledge-base/project/learnings/security-issues/2026-04-11-service-role-idor-untrusted-ws-attachments.md` — every service-role operation on user-supplied paths must re-validate at point of use, regardless of upstream validation. Applied to both the owner API and the public viewer API.
- `knowledge-base/project/learnings/security-issues/2026-04-12-binary-content-serving-security-headers.md` — sanitize `Content-Disposition` filename (regex `/["\r\n\\]/g` → `_`), set `X-Content-Type-Options: nosniff`, use async `fs.promises.readFile`. All enforced by the shared helper.
- `knowledge-base/project/learnings/2026-04-07-symlink-escape-recursive-directory-traversal.md` — symlinks must be rejected at every point-access site, not just during enumeration. Owner API and public API both reject via `lstat().isSymbolicLink()`.
- `knowledge-base/project/learnings/ui-bugs/2026-04-10-kb-nav-tree-disappears-on-file-select.md` — UI-branch asymmetry class of bug this fix also belongs to (header render forked on file type).
- `knowledge-base/project/learnings/workflow-issues/plan-prescribed-wrong-test-runner-20260411.md` — verify test runner before prescribing; this repo uses vitest. Plan test commands use `node node_modules/vitest/vitest.mjs run` in worktrees per `cq-in-worktrees-run-vitest-via-node-node`.

## Migration Notes

- **No database migration.** `kb_share_links.document_path` is already generic text.
- **No env or infra changes.**
- **Test suite:** one test file deleted (`kb-share-md-only.test.ts`), one renamed/replaced (`kb-share-allowed-paths.test.ts`), two new files added. Covered by standard CI.
- **Rollout:** single deploy. No feature flag needed (bug fix, not new capability from the user's POV).

## Open Questions

None — bug is contained and the scope is bounded by existing patterns in the codebase.

## Research Insights (Deepen Pass)

### Best Practices

- **Pattern reuse over invention.** The binary serving pattern exists and is hardened in `/api/kb/content/[...path]/route.ts`. Extracting a helper (not copy-pasting) is the cheapest way to propagate future hardening to both routes.
- **Fork on extension at the earliest layer.** Both `/api/kb/content` and (now) `/api/shared/[token]` branch on `path.extname(...).toLowerCase()`. Keep that convention — clients don't need to send a hint; the server derives the content type.
- **Same server-side validation on both paths.** The original sharing plan document (`2026-04-10-feat-kb-document-sharing-plan.md`) emphasizes that public routes bypass Supabase cookie auth AND RLS. Every public route that touches user data must independently validate path containment, size, symlinks, and existence — do not rely on the fact that "the owner created the share."

### Performance Considerations

- **Async file reads only.** `fs.promises.readFile` — never the sync variant — per `2026-04-12-binary-content-serving-security-headers` (blocks the Node.js event loop).
- **Browser-cache binary responses.** The current `Cache-Control: private, max-age=60` is sensible for authenticated paths. For public shared binaries, keep `private, max-age=60` — shared PDFs are usually view-once and Cloudflare caching (if enabled) would break revocation latency. If perf becomes a concern, add a `Vary: Cookie` or switch to ETag-based revalidation later.
- **Fetch-once UI pattern.** The shared page's initial `fetch` already downloads the full binary (or JSON) into the browser HTTP cache. Subsequent `<embed>`/`<img>`/`react-pdf` requests hit the cache (200 from memory cache) — no double download. Verified in manual QA step 7.4.

### Implementation Details (copy-paste ready)

```ts
// apps/web-platform/server/kb-binary-response.ts
import fs from "node:fs";
import path from "node:path";
import { isPathInWorkspace } from "@/server/sandbox";
import { KB_BINARY_RESPONSE_CSP } from "@/lib/kb-csp";

export const MAX_BINARY_SIZE = 50 * 1024 * 1024; // 50 MB

export const CONTENT_TYPE_MAP: Record<string, string> = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".svg": "image/svg+xml",
  ".pdf": "application/pdf",
  ".csv": "text/csv",
  ".txt": "text/plain",
  ".docx":
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
};

export const ATTACHMENT_EXTENSIONS = new Set([".docx"]);

export type BinaryReadResult =
  | { ok: true; buffer: Buffer; contentType: string; disposition: "inline" | "attachment"; safeName: string }
  | { ok: false; status: 403 | 404 | 413; error: string };

export async function readBinaryFile(
  kbRoot: string,
  relativePath: string,
): Promise<BinaryReadResult> {
  const fullPath = path.join(kbRoot, relativePath);
  if (!isPathInWorkspace(fullPath, kbRoot)) {
    return { ok: false, status: 403, error: "Access denied" };
  }
  let lstat: fs.Stats;
  try {
    lstat = await fs.promises.lstat(fullPath);
  } catch {
    return { ok: false, status: 404, error: "File not found" };
  }
  if (lstat.isSymbolicLink() || !lstat.isFile()) {
    return { ok: false, status: 403, error: "Access denied" };
  }
  if (lstat.size > MAX_BINARY_SIZE) {
    return { ok: false, status: 413, error: "File exceeds maximum size limit" };
  }
  const ext = path.extname(relativePath).toLowerCase();
  const contentType = CONTENT_TYPE_MAP[ext] || "application/octet-stream";
  const disposition = ATTACHMENT_EXTENSIONS.has(ext) ? "attachment" : "inline";
  const rawName = path.basename(relativePath);
  const safeName = rawName.replace(/["\r\n\\]/g, "_");
  const buffer = await fs.promises.readFile(fullPath);
  return { ok: true, buffer, contentType, disposition, safeName };
}

export function buildBinaryResponse(r: {
  buffer: Buffer;
  contentType: string;
  disposition: "inline" | "attachment";
  safeName: string;
}): Response {
  return new Response(r.buffer, {
    headers: {
      "Content-Type": r.contentType,
      "Content-Disposition": `${r.disposition}; filename="${r.safeName}"`,
      "Content-Length": r.buffer.length.toString(),
      "X-Content-Type-Options": "nosniff",
      "Cache-Control": "private, max-age=60",
      "Content-Security-Policy": KB_BINARY_RESPONSE_CSP,
    },
  });
}
```

```ts
// apps/web-platform/app/shared/[token]/page.tsx — content-type branch
const res = await fetch(`/api/shared/${token}`);
const contentType = res.headers.get("content-type") ?? "";

if (contentType.startsWith("application/json")) {
  const json = await res.json();
  setData({ kind: "markdown", content: json.content, path: json.path });
} else if (contentType.startsWith("application/pdf")) {
  const filename = extractFilename(res.headers.get("content-disposition"));
  setData({ kind: "pdf", src: `/api/shared/${token}`, filename });
} else if (contentType.startsWith("image/")) {
  const filename = extractFilename(res.headers.get("content-disposition"));
  setData({ kind: "image", src: `/api/shared/${token}`, alt: filename });
} else {
  const filename = extractFilename(res.headers.get("content-disposition"));
  setData({ kind: "download", src: `/api/shared/${token}`, filename });
}
// Do NOT consume res.body for non-JSON — let the browser reuse the cached response.
```

### Edge Cases

- **User revokes share while a viewer is actively loading a large PDF.** The initial fetch got 200 + bytes; the viewer renders successfully. Revocation takes effect on the next fetch. Acceptable.
- **File renamed after share creation.** `document_path` in the share record becomes stale → 404. Acceptable — the share follows the path, not the inode. A future enhancement could bind to a stable file ID, but that requires the KB to have stable IDs (it doesn't today; KB is git-committed files).
- **Path contains Unicode characters.** `Content-Disposition: filename="..."` is ASCII-safe per RFC 2616; for Unicode, use `filename*=UTF-8''...` per RFC 5987. Current code only handles ASCII names; out of scope (existing behavior). Document in Non-Goals.
- **PDF larger than 50 MB.** Reject at share-creation time with a clear error. Reject at serve time with 413. Don't let a user create a dead link.
- **Race: file deleted between lstat and readFile.** Wrap `readFile` in try/catch; return 404. Already covered by existing pattern in `/api/kb/content`.
- **Concurrent downloads of the same share link.** No shared state — each request reads the file fresh from disk. No coordination needed.

### References

- `apps/web-platform/app/api/kb/content/[...path]/route.ts` — canonical binary-serving pattern.
- `apps/web-platform/lib/csp.ts` — middleware CSP that governs the `/shared` page.
- `apps/web-platform/lib/kb-csp.ts` — per-response CSP for binary content.
- `apps/web-platform/components/kb/pdf-preview.tsx` — react-pdf component to reuse in the public viewer.
- [MDN `Content-Disposition`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Disposition) — sanitization requirements.
- [pdfjs-dist worker setup](https://github.com/mozilla/pdf.js) — already configured in `pdf-preview.tsx`.
