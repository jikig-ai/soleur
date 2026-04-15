---
title: "fix: KB share button missing on PDF attachments"
type: fix
date: 2026-04-15
issue: 2232
branch: feat-kb-share-btn-pdf-attachments
---

# Fix: KB share button missing on PDF (and other non-markdown) attachments

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

## Security Review

- **Same auth boundary as markdown sharing.** Server only serves files the share owner has in their KB root; the token → user_id → workspace_path chain is unchanged.
- **Path traversal:** `isPathInWorkspace` check already guards both share creation and public viewing. Unchanged.
- **Symlink escape:** now explicitly rejected at both share creation and public viewing (new in this PR).
- **CSP:** `KB_BINARY_RESPONSE_CSP` already restricts binary responses; applied identically in `/api/shared/[token]` binary branch.
- **Size DoS:** 50 MB limit already applied in the authenticated route; applied identically in the public route. Also applied at share creation time to avoid dead links.
- **MIME sniffing:** `X-Content-Type-Options: nosniff` preserved.
- **Enumeration:** random 32-byte base64url tokens (unchanged). Revoked tokens return 410.
- **Rate limiting:** existing `shareEndpointThrottle` covers both markdown and binary branches (same route).

No new attack surface — the binary serving is already trusted by the authenticated route; this extends it to the tokenized-public route under the same guards.

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
- `knowledge-base/project/learnings/security-issues/2026-04-11-service-role-idor-untrusted-ws-attachments.md` — keep service client to owner-scoped lookups (already followed by existing code).
- `knowledge-base/project/learnings/ui-bugs/2026-04-10-kb-nav-tree-disappears-on-file-select.md` — UI-branch asymmetry class of bug this fix also belongs to.

## Migration Notes

- **No database migration.** `kb_share_links.document_path` is already generic text.
- **No env or infra changes.**
- **Test suite:** one test file deleted (`kb-share-md-only.test.ts`), one renamed/replaced (`kb-share-allowed-paths.test.ts`), two new files added. Covered by standard CI.
- **Rollout:** single deploy. No feature flag needed (bug fix, not new capability from the user's POV).

## Open Questions

None — bug is contained and the scope is bounded by existing patterns in the codebase.
