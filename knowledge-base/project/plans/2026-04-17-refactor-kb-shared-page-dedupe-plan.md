---
title: "refactor(kb): de-duplicate shared viewer / dashboard KB page concerns"
type: refactor
date: 2026-04-17
---

# refactor(kb): de-duplicate shared viewer / dashboard KB page concerns

Focused refactor PR draining 5 code-review findings against `app/shared/[token]/page.tsx` and `app/(dashboard)/dashboard/kb/[...path]/page.tsx`, modeled on the net-negative #2486 cleanup pattern.

## Overview

Five open `code-review` issues (#2321, #2318, #2312, #2306, #2301) all sit on the shared-viewer + dashboard-KB page boundary. Each is small, low-risk, and shares the same theme: page-level concerns duplicated across the authenticated owner surface and the public `/shared/[token]` surface. Closing them as five separate PRs would triple review overhead without architectural payoff. Closing them as one PR:

- Extracts `classifyResponse` from the shared page `useEffect` (#2321) — pure, testable helper.
- Extracts `KbContentHeader` from the dashboard page's two header clones (#2318) — duplicate JSX removed.
- Extracts `KbContentSkeleton` into `components/kb/` and imports from both pages (#2312) — one place for the skeleton widths.
- Fixes the shared image viewer's `alt` text to default to "Shared image" and treats filename as `title` (#2306) — a11y fix, two-line change.
- Aligns the symlink-reject response across `/api/kb/share`, `/api/kb/content/[...path]`, and `/api/shared/[token]` on `(403, "Access denied")`, and aligns `/api/shared/[token]`'s 404 message across the markdown and binary branches (#2301) — server-side consistency.

Net impact on the `code-review` backlog: **-5 issues, 0 new scope-outs** (matches the #2486 pattern).

Reference PR: [#2486](https://github.com/jikigai/soleur/pull/2486) — same author, same surface, same "close more than we open" shape.

Milestone: **Phase 3: Make it Sticky**.

Branch: `feat-kb-shared-page-dedupe` (current).

## Research Reconciliation — Spec vs. Codebase

No spec exists for this refactor (cleanup drain, not feature work). Issue descriptions were reconciled against the source files directly during planning:

| Issue claim | Reality at HEAD | Plan response |
|---|---|---|
| #2312: shared page inlines `["85%", "70%", "90%", "65%", "80%"]` | Confirmed at `app/shared/[token]/page.tsx:227`. | Extract `KbContentSkeleton` component. |
| #2312: dashboard page has `CONTENT_SKELETON_WIDTHS` constant with **6** widths | Confirmed at `app/(dashboard)/dashboard/kb/[...path]/page.tsx:199` — dashboard has 6 widths, shared has 5. Not identical. | Plan preserves both widths as the optional `widths` prop default variant the component accepts (shared passes 5-width, dashboard passes 6-width). Issue treated as "same component with configurable widths", not "identical widths". |
| #2312 recommendation: extract to `components/kb/KbContentSkeleton` | Confirmed — `components/kb/loading-skeleton.tsx` already exports a **different** `LoadingSkeleton` (sidebar file-tree skeleton). A reused `LoadingSkeleton` name would collide. | New file `components/kb/kb-content-skeleton.tsx` with distinct component name `KbContentSkeleton`. |
| #2301: `/api/kb/share` returns `400 "Invalid document path"` for symlinks | Confirmed at `server/kb-share.ts:185-190` (`code: "symlink-rejected"`, `status: 400`). | Re-map symlink-rejected to `(403, "Access denied", code: "symlink-rejected")` in `kb-share.ts`. HTTP-level change; internal `code` tag preserved for telemetry. |
| #2301: `/api/shared/[token]` 404 message differs between markdown (`"Document no longer available"`) and binary (`"File not found"` via `validateBinaryFile`) | Confirmed — markdown branch at `route.ts:101` returns `"Document no longer available"`; binary branch returns whatever `validateBinaryFile` errors with (`"File not found"`). | Binary 404 path in `/api/shared/[token]` re-maps to `"Document no longer available"` for public-facing opacity; `/api/kb/content` (owner route) keeps `"File not found"` (owner-facing, less need for opacity). |
| #2306: `extractFilename` returns `"file"` fallback when `Content-Disposition` missing | Confirmed at `app/shared/[token]/page.tsx:32`. | Fallback string changed to `"Shared image"` for images (via `alt`), and filename-fallback-to-basename for downloads' `filename`. `title` holds filename for hover on images. |
| #2318: dashboard page duplicates header JSX in two branches | Confirmed at lines 116-146 (FilePreview branch) and 157-175 (markdown branch). Headers differ only in the download button (present in FilePreview branch, absent in markdown branch). | Extract `KbContentHeader` with optional `downloadHref` / `downloadFilename` props. |
| #2321: `classifyResponse` claim of ~50 lines | Confirmed — lines 47-105 (59 lines) of the `useEffect`. | Extract `classifyResponse(res, token) → { data } \| { error }` as a pure async helper. `useEffect` keeps only abort + state wiring. |

No inherited spec fiction — each issue's "problem" claim matches the file at HEAD.

## Open Code-Review Overlap

Checked all planned `Files to edit` + `Files to create` against open `code-review` issues.

| File | Open issues touching it | Disposition |
|---|---|---|
| `app/shared/[token]/page.tsx` | #2297, #2304, #2306, #2312, #2318, #2321, #2324 | #2306 / #2312 / #2321 → **folded in** (closed by this PR). #2297, #2304, #2324 → **acknowledged** (architectural pivots: unify file-kind classifier across owner/shared, add `/raw` sub-route, or eliminate double-GET — each is its own PR-scoped cycle). #2318 is on the dashboard page, not shared. |
| `app/(dashboard)/dashboard/kb/[...path]/page.tsx` | #2297, #2312, #2317, #2318, #2348 | #2312 / #2318 → **folded in**. #2317 (shared `isMarkdownExt` helper), #2297, #2348 → **acknowledged** (adjacent refactors, independent scope). |
| `app/api/kb/share/route.ts` | #2300 | **Acknowledged** — `MAX_BINARY_SIZE` module extraction is unrelated to the symlink-reject alignment. |
| `app/api/kb/content/[...path]/route.ts` | #2299, #2308, #2313, #2317 | **Acknowledged** — each is a larger refactor (serveBinary helper, error-shape convention, markdown-vs-binary dispatch, isMarkdownExt). |
| `app/api/shared/[token]/route.ts` | #2299, #2304, #2305, #2308, #2313, #2317, #2322, #2324, #2328, #2483 | **Acknowledged** — same reason. #2305 (error-handling symmetry) is tempting but requires changes inside `validateBinaryFile` semantics (ENOENT vs EACCES differentiation) that expand the blast radius beyond the symlink-message alignment in #2301. |
| `server/kb-share.ts` | none | Clean. |
| `server/kb-binary-response.ts` | #2299, #2303, #2311, #2324, #2325, #2329 | **Acknowledged** — no edit to this file in the current plan (changes are at the route layer, not helper). |
| `components/kb/kb-content-skeleton.tsx` (new) | none | Clean. |
| `components/kb/kb-content-header.tsx` (new) | none | Clean. |

**Rationale for "acknowledge, don't fold":** The five acknowledged architectural refactors (#2297, #2304, #2305, #2313, #2299, #2308) share a common dependency — they all require reshaping the shared-page HTTP contract and/or the `kb-binary-response` error model. Folding any of them into this PR would collapse the "small, boring, low-risk" character that justifies batching 5 issues. They deserve their own dedicated planning cycle. Review default is fix-inline; this cycle is scoped deliberately to the five named issues.

## Files to Edit

- `apps/web-platform/app/shared/[token]/page.tsx`
  - Remove inline `LoadingSkeleton` function (lines 222-237).
  - Remove inline `extractFilename` (lines 31-35) — moved into the classifier helper.
  - Replace the 50-line `useEffect` body with a call to `classifyResponse`; `useEffect` becomes ~15 lines (abort + state wiring only).
  - Import `KbContentSkeleton` from `@/components/kb/kb-content-skeleton`.
  - Change image `alt={data.alt}` → `alt="Shared image"` and add `title={data.filename}` (hover). Rename `SharedData.image.alt` → `SharedData.image.filename` in the type; renderer updated accordingly.

- `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx`
  - Remove the two duplicate `<header>` blocks (lines 116-146 and 157-175) and replace with `<KbContentHeader joinedPath={joinedPath} chatUrl={chatUrl} downloadHref={contentUrl} downloadFilename={filename} />` (FilePreview branch) and `<KbContentHeader joinedPath={joinedPath} chatUrl={chatUrl} />` (markdown branch, no download).
  - Remove `CONTENT_SKELETON_WIDTHS` + `ContentSkeleton` (lines 199-219); replace with `<KbContentSkeleton widths={["85%", "70%", "90%", "65%", "80%", "75%"]} />` (6-width variant; the 5-width default matches the shared page).

- `apps/web-platform/server/kb-share.ts`
  - Change the `symlink-rejected` branch (lines 185-190) from `status: 400` → `status: 403`. Message stays `"Invalid document path"` OR is aligned to `"Access denied"` — **plan chooses `"Access denied"`** to match the canonical `KbAccessDeniedError` convention noted in #2301. Preserve the `code: "symlink-rejected"` tag for downstream telemetry. Update the `CreateShareResult` union's status set (`400 | 404 | 409 | 413 | 500` → add `403`).

- `apps/web-platform/app/api/kb/share/route.ts`
  - No change — it already forwards `result.status` and `result.error` verbatim. Status change is sourced from `kb-share.ts`.

- `apps/web-platform/app/api/shared/[token]/route.ts`
  - Binary branch: when `validateBinaryFile` returns `status: 404, error: "File not found"`, re-map to `status: 404, error: "Document no longer available"` before returning. This single-site adaptation avoids changing `validateBinaryFile`'s contract (which is shared with the owner route) and aligns the 404 message between the markdown and binary forks of the shared endpoint.

- `apps/web-platform/app/api/kb/content/[...path]/route.ts`
  - No change — owner-facing route keeps `"File not found"` (less need for opacity; matches existing convention).

- `apps/web-platform/test/shared-page-binary.test.ts`
  - Update 404 assertion on binary missing-file to `"Document no longer available"`.

- `apps/web-platform/test/kb-share.test.ts` (and any related file in `kb-share-*.test.ts` that asserts on the symlink case)
  - Update symlink-rejected status expectation from `400` → `403`. Update the error-message expectation if tests pin the message.

- `apps/web-platform/test/shared-page-ui.test.tsx` (if it exists and covers the image/skeleton/download paths)
  - Update `alt="Shared image"` expectation. Verify `title` matches filename. Verify skeleton imports the shared component.

- `apps/web-platform/test/kb-share-allowed-paths.test.ts`
  - Update 403 expectation for the symlink-rejected path if the test pins status.

## Files to Create

- `apps/web-platform/components/kb/kb-content-skeleton.tsx`
  - Named export `KbContentSkeleton` with optional `widths?: string[]` prop (default `["85%", "70%", "90%", "65%", "80%"]`).
  - Renders the title bar + width-varied rows used by both pages. No internal branching — just the skeleton markup.
  - Add `KbContentSkeleton` to `components/kb/index.ts`.

- `apps/web-platform/components/kb/kb-content-header.tsx`
  - Named export `KbContentHeader` with props:
    - `joinedPath: string` (for `KbBreadcrumb`)
    - `chatUrl: string` (for `KbChatTrigger` fallback)
    - `downloadHref?: string` — when present, renders the Download anchor; when absent, no download affordance (matches the current markdown-branch behavior).
    - `downloadFilename?: string` — paired with `downloadHref`. Required if `downloadHref` is set (enforced at the type level with a discriminated union or paired props).
  - Reuses `KbBreadcrumb`, `SharePopover`, `KbChatTrigger` — no new dependencies.
  - Add to `components/kb/index.ts`.

- `apps/web-platform/app/shared/[token]/classify-response.ts`
  - Named export `classifyResponse(res: Response, token: string): Promise<{ data: SharedData } | { error: PageError }>`.
  - Absorbs `extractFilename` as a private helper inside the module.
  - Pure (no React, no state writes) — unit-testable without mocking `fetch`.
  - Exported `SharedData` / `PageError` types move here (or stay in the page module if re-exported).

- `apps/web-platform/test/classify-response.test.ts`
  - Tests for every response-shape branch: 404, 410 revoked, 410 content-changed, 410 legacy-null-hash, !ok generic, markdown JSON, PDF, image, download, and a network throw.
  - Tests for `extractFilename` fallback, including the `"file"` → default fallback rename.

- `apps/web-platform/test/kb-content-header.test.tsx`
  - Renders header without `downloadHref` → no download anchor.
  - Renders header with `downloadHref` + `downloadFilename` → download anchor present with correct href and aria-label.
  - Breadcrumb and share popover rendered in both cases.

- `apps/web-platform/test/kb-content-skeleton.test.tsx`
  - Renders N width rows for `widths.length`.
  - Default widths rendered when `widths` prop omitted.

- `apps/web-platform/test/shared-image-a11y.test.tsx`
  - Renders the shared page in the `kind: "image"` state and asserts `alt="Shared image"` on the `<img>` element.
  - Asserts `title` prop matches the filename (or is absent when filename is unknown).
  - Asserts fallback when `Content-Disposition` is missing: `alt="Shared image"`, no `title`.

## Implementation Phases

### Phase 1 — RED: write failing tests

AGENTS.md `cq-write-failing-tests-before` — Acceptance Criteria exist, TDD gate applies.

1. `test/classify-response.test.ts` — tests for every branch of the new `classifyResponse` helper. Imports `classifyResponse` from `@/app/shared/[token]/classify-response` (module does not yet exist → RED).
2. `test/kb-content-header.test.tsx` — renders `KbContentHeader` (does not yet exist → RED).
3. `test/kb-content-skeleton.test.tsx` — renders `KbContentSkeleton` (does not yet exist → RED).
4. `test/shared-image-a11y.test.tsx` — asserts `alt="Shared image"` (current value is `data.alt` = filename or `"file"` → RED).
5. Update `test/shared-page-binary.test.ts` — change 404 expectation to `"Document no longer available"` (currently `"File not found"` → RED).
6. Update `test/kb-share.test.ts` / `test/kb-share-allowed-paths.test.ts` — change symlink-rejected status expectation from `400` → `403` and message alignment (RED).

Run `./node_modules/.bin/vitest run` (from `apps/web-platform/`) and confirm all 6 test files go RED in the expected way.

### Phase 2 — GREEN: implement

1. Create `components/kb/kb-content-skeleton.tsx`. Export from `components/kb/index.ts`.
2. Create `components/kb/kb-content-header.tsx`. Export from `components/kb/index.ts`.
3. Create `app/shared/[token]/classify-response.ts` with `SharedData`, `PageError`, `extractFilename` (private), `classifyResponse`. Update fallback: filename defaults to last path segment from the token URL (`token`), not the string `"file"`; for images, the returned `SharedData.image` carries `filename` (rename from `alt`).
4. Edit `app/shared/[token]/page.tsx`:
   - Import `classifyResponse`, `SharedData`, `PageError` from `./classify-response`.
   - Import `KbContentSkeleton` from `@/components/kb`.
   - Replace `useEffect` body with `classifyResponse` invocation + state writes.
   - Replace inline `LoadingSkeleton` usage with `<KbContentSkeleton />`.
   - Change `<img alt={data.alt} />` → `<img alt="Shared image" title={data.filename} />`.
   - Delete inline `extractFilename` and inline `LoadingSkeleton`.
5. Edit `app/(dashboard)/dashboard/kb/[...path]/page.tsx`:
   - Import `KbContentHeader`, `KbContentSkeleton` from `@/components/kb`.
   - Replace both header blocks with `<KbContentHeader ... />`.
   - Replace `ContentSkeleton` usage with `<KbContentSkeleton widths={["85%", "70%", "90%", "65%", "80%", "75%"]} />`.
   - Delete `CONTENT_SKELETON_WIDTHS` + `ContentSkeleton`.
6. Edit `server/kb-share.ts` — flip `symlink-rejected` to `status: 403, error: "Access denied"`. Update the `CreateShareResult` union to include `403`.
7. Edit `app/api/shared/[token]/route.ts` — binary branch error re-map: if `binary.status === 404`, substitute `"Document no longer available"` before returning JSON. Leave 403 / 413 unchanged.
8. Run `./node_modules/.bin/vitest run`. Confirm all 6 RED tests from Phase 1 → GREEN.
9. Run `./node_modules/.bin/tsc --noEmit` (from `apps/web-platform/`). Confirm no type errors.

### Phase 3 — REFACTOR + polish

1. Run the full vitest suite. Confirm no pre-existing tests broke. If any broke due to shared-skeleton / shared-header imports, update assertions to reference the new component names; do NOT weaken assertions.
2. Grep for remaining `extractFilename`, `LoadingSkeleton` (inside `shared/[token]`), `CONTENT_SKELETON_WIDTHS`, `ContentSkeleton` tokens in the web-platform — ensure only new-component references remain.
3. Grep for `"Invalid document path"` to confirm the symlink-rejected path is the only changed site; other callers of that string (e.g., null-byte, workspace-escape, not-a-file) are untouched.
4. Run `next build` locally via `cd apps/web-platform && doppler run -p soleur -c dev -- ./scripts/dev.sh` (smoke — start-then-kill; full Docker build runs in CI) — AGENTS.md `cq-nextjs-route-files-http-only-exports` applies but neither new file is a route file, so the risk is low.
5. Run `npx markdownlint-cli2 --fix knowledge-base/project/plans/2026-04-17-refactor-kb-shared-page-dedupe-plan.md`.

### Phase 4 — ship

1. `/ship` — compound, commit, push, create PR.
2. PR body **MUST** include:
   - `Closes #2321`
   - `Closes #2318`
   - `Closes #2312`
   - `Closes #2306`
   - `Closes #2301`
   - Reference to #2486 as the pattern.
   - Net-impact table matching the #2486 shape.
3. Labels: `type/chore`, `domain/engineering`, `code-review`, `priority/p3-low` (match the issues' own labels; #2301 is `priority/p2-medium` so include that too — the highest priority among closed issues wins).
4. Semver label: `semver:patch` (refactor + a11y fix + message alignment; no behavior change users opt into).
5. Milestone: `Phase 3: Make it Sticky` (matches all five issues).

## Acceptance Criteria

- [ ] `apps/web-platform/components/kb/kb-content-skeleton.tsx` exists and is imported by both `/shared/[token]/page.tsx` and `/(dashboard)/dashboard/kb/[...path]/page.tsx`.
- [ ] `apps/web-platform/components/kb/kb-content-header.tsx` exists and renders both the with-download and without-download header variants.
- [ ] `apps/web-platform/app/shared/[token]/classify-response.ts` exists as a pure, exported helper with its own test file.
- [ ] `app/shared/[token]/page.tsx` `useEffect` body is <= 20 lines and contains no content-type sniffing logic.
- [ ] Shared image viewer: `<img>` has `alt="Shared image"` (or the filename, chosen deliberately — see #2306 proposal). No `alt="file"` path remains.
- [ ] `/api/kb/share` symlink-rejected response: `{ status: 403, error: "Access denied", code: "symlink-rejected" }` (the `code` remains in the JSON body for telemetry continuity).
- [ ] `/api/shared/[token]` returns `"Document no longer available"` (not `"File not found"`) for every 404 path, regardless of extension.
- [ ] All 5 issues reference-closed by the PR body and move to `closed` on merge.
- [ ] Full vitest suite green (`./node_modules/.bin/vitest run`).
- [ ] Typecheck clean (`tsc --noEmit`).
- [ ] No new `deferred-scope-out` issues filed from this PR's review — all findings fix-inline.
- [ ] Net impact on Phase 3 `code-review` backlog: **-5 issues, 0 new scope-outs**.

## Test Scenarios

### classify-response.ts (unit)

- `404` → `{ error: "not-found" }`.
- `410` with body `{ code: "content-changed" }` → `{ error: "content-changed" }`.
- `410` with body `{ code: "legacy-null-hash" }` → `{ error: "content-changed" }`.
- `410` with no parseable body / other code → `{ error: "revoked" }`.
- `!ok` 500 → `{ error: "unknown" }`.
- `200` with `application/json` body `{ content, path }` → `{ data: { kind: "markdown", content, path } }`.
- `200` with `application/pdf` and `Content-Disposition: attachment; filename="doc.pdf"` → `{ data: { kind: "pdf", src: "/api/shared/...", filename: "doc.pdf" } }`.
- `200` with `image/png` and no `Content-Disposition` → `{ data: { kind: "image", src, filename: "<token-derived basename or null>" } }`. **Never** the string `"file"`.
- `200` with `application/octet-stream` → `{ data: { kind: "download", src, filename: ... } }`.
- `fetch` throw → `{ error: "unknown" }`.

### KbContentHeader (render)

- Without `downloadHref`: breadcrumb + share + chat-trigger present; no anchor with `download` attribute.
- With `downloadHref="/api/kb/content/foo.pdf"` and `downloadFilename="foo.pdf"`: anchor rendered with correct `href`, `download`, and `aria-label="Download foo.pdf"`.
- TypeScript-level: passing only `downloadHref` without `downloadFilename` fails typecheck (paired props / discriminated union).

### KbContentSkeleton (render)

- Default widths → 5 rows with the inline widths `["85%", "70%", "90%", "65%", "80%"]`.
- Custom `widths={["100%", "50%"]}` → 2 rows with the provided widths.

### Shared image a11y (component)

- Page in `kind: "image"` state with filename `"photo_001.jpg"` → `<img alt="Shared image" title="photo_001.jpg" />`.
- Page in `kind: "image"` state with no filename → `<img alt="Shared image" />` (no `title` attribute set, or `title=""`).

### Symlink-reject response alignment (HTTP)

- `POST /api/kb/share` with a body path resolving to a symlink → response `403` with JSON `{ error: "Access denied", code: "symlink-rejected" }`.
- `GET /api/kb/content/<symlink>` → response `403` with JSON `{ error: "Access denied" }` (unchanged).
- `GET /api/shared/<token>` where stored path is a symlink → response `403` with JSON `{ error: "Access denied" }` (unchanged at the status/message level; the contract is now aligned to the share route as well).

### Shared 404 message alignment (HTTP)

- `GET /api/shared/<token>` where stored `.md` path is missing → response `404 { error: "Document no longer available" }`.
- `GET /api/shared/<token>` where stored binary path is missing → response `404 { error: "Document no longer available" }` (previously `"File not found"`).
- `GET /api/kb/content/<missing-file>` (owner route) → response `404 { error: "File not found" }` (unchanged).

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Fold in #2297 / #2304 (unify file-kind classifier server-side via `/raw` sub-route or `X-Soleur-Kind` header) | **Rejected for this PR.** Reshapes the shared-page HTTP contract and couples to a viewer-agnostic file-kind enum — larger blast radius. Worth its own cycle. |
| Fold in #2305 (binary-branch observability symmetry in `/api/shared/[token]`) | **Rejected for this PR.** Would require `validateBinaryFile` to distinguish ENOENT from EACCES, which changes the owner route's behavior too. Also its own cycle. |
| Fold in #2308 (unify error-shape convention across `kb-reader` + `kb-binary-response`) | **Rejected for this PR.** Cross-module refactor; no user-facing payoff; pure style. |
| Keep `LoadingSkeleton` name for the new shared component | **Rejected.** Name already taken by `components/kb/loading-skeleton.tsx` (sidebar file-tree skeleton). Distinct name `KbContentSkeleton` avoids collision and matches #2312's proposed name. |
| Change `"Invalid document path"` to `"Access denied"` everywhere (not just symlink-rejected) | **Rejected.** Null-byte, workspace-escape, and not-a-file paths are genuine 400s (client-input errors), not 403s (security rejects). Only the symlink case is a security reject misclassified as 400. |
| Use `alt={filename}` instead of `alt="Shared image"` for images | **Rejected per #2306's recommendation.** Filenames like `photo_2024_001.jpg` convey nothing to a screen reader. Generic `"Shared image"` is a11y-correct; filename goes to `title` for sighted hover. |

## Risks

- **Test-suite breadth.** Several test files pin status codes and messages precisely. Plan accounts for this explicitly under "Files to Edit" — if grep turns up additional test files at GREEN time, update them with the same pattern. Acceptance gate is `vitest run` green and `tsc --noEmit` clean.
- **Telemetry drift.** Downstream tooling that greps Sentry logs for `"Invalid document path"` on the share POST will miss 403s after this PR. Mitigation: the `code: "symlink-rejected"` tag on the JSON body is preserved and queryable in Sentry structured data — grepping should key on that tag, not the message string. Note this in PR body.
- **Cache-Control / ETag behavior unaffected.** This PR does not touch `buildBinaryResponse` or the hash verdict cache. The #2486 changes (strong ETag, weak ETag, conditional 304) are preserved.

## Domain Review

**Domains relevant:** none

Infrastructure/tooling cleanup — no product, marketing, legal, or brand implications. Five issues from a PR-triggered code review drained in one PR. UX tier is **NONE**:

- No new user-facing pages, flows, or components (two new internal components extracted from existing rendered JSX).
- Shared-image `alt` change is a silent a11y correctness fix, not a UI redesign.
- Error-message alignment is server-side; only visible to clients that currently show the raw response body (the shared viewer's `ErrorMessage` component renders tailored copy, not the server string).

No CPO / CMO / ux-design-lead / copywriter invocation required.

## Tasks

See `knowledge-base/project/specs/feat-kb-shared-page-dedupe/tasks.md` for the derived task breakdown.
