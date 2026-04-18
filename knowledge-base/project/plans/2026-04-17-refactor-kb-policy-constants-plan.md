# Plan: Drain KB Binary-Serving Policy-Constants Backlog

**Branch:** `feat-kb-policy-constants`
**Worktree:** `.worktrees/feat-kb-policy-constants`
**Draft PR:** [#2531](https://github.com/jikig-ai/soleur/pull/2531)
**Closes:** #2300, #2325, #2297
**Originating review:** PR #2282
**Drain pattern reference:** PR #2486 (one PR, three closures)
**Milestone:** Phase 3: Make it Sticky
**Type:** `refactor` — no behavior change for owners; shared viewer gains `.txt` inline parity (bug-closing restoration; see Drift Table)

## Overview

PR #2282 introduced KB binary serving. Code-review of that PR produced three converging findings, all in the same file:

- **#2300** (P3): `server/kb-binary-response.ts` has become a grab-bag of policy constants. `kb-share/route.ts` imports `MAX_BINARY_SIZE` from a module whose name says "responses" — leaky cohesion.
- **#2325** (P3): `ATTACHMENT_EXTENSIONS = new Set([".docx"])` is speculative generality for a 1-element set; a test hardcodes `50 * 1024 * 1024 + 1` instead of importing the constant.
- **#2297** (P2): Two implicit sources of truth for "given a KB file, how do we render it?" — owner viewer dispatches by extension, shared viewer dispatches by `X-Soleur-Kind` (which is derived from content-type + disposition by `deriveBinaryKind`). Concrete drift already visible: `.txt` renders inline with `TextPreview` on the owner page but falls into the download branch on the shared page because `deriveBinaryKind` returns `"download"` for `text/plain`.

Fix all three in one refactor PR:

1. Extract a `server/kb-limits.ts` policy module (MAX_BINARY_SIZE + CONTENT_TYPE_MAP + ATTACHMENT_EXTENSIONS).
2. Extract a `server/kb-file-kind.ts` classifier — `FileKind = 'markdown' | 'pdf' | 'image' | 'text' | 'download'` — plus `classifyByExtension(ext)` and `classifyByContentType(contentType, disposition)`. Supersedes `SharedContentKind` (add `"text"` variant).
3. Rewire every importer: `kb-binary-response.ts`, `kb-share.ts`, `kb-share/route.ts`, `agent-runner.ts`, `test/kb-share-allowed-paths.test.ts`, `test/kb-serve.test.ts`, `components/kb/file-preview.tsx`, `app/shared/[token]/classify-response.ts`.
4. Delete the speculative `ATTACHMENT_EXTENSIONS` Set — inline the `.docx`-only check at the single call site (add a doc comment directing extenders to `kb-limits.ts`).

## Research Reconciliation — Spec vs. Codebase

The feature description and codebase are largely aligned. Three reconciliations land in the plan to avoid inheriting fiction into the phase list:

| Spec claim | Reality | Plan response |
|---|---|---|
| "move `MAX_BINARY_SIZE` and `kb-share/route.ts` import" (2 files) | **6 importers** in total: `kb-binary-response.ts`, `kb-share.ts` (not `kb-share/route.ts` — the route delegates to `createShare` in the server module), `agent-runner.ts` (line 45), and two test files (`kb-share-allowed-paths.test.ts`, `kb-serve.test.ts`). The route itself does NOT import `MAX_BINARY_SIZE` — the size gate lives inside `createShare`. | Phase 1 updates every importer. The `kb-share/route.ts` bullet in #2300 is a mis-location; the real consumer is `kb-share.ts`. |
| "extract `classifyByContentType(ct)` taking content-type only" | `deriveBinaryKind` already takes `{ contentType, disposition }` — disposition is load-bearing (`.docx` returns `"download"` because disposition is `"attachment"`, not because of content-type). | `classifyByContentType` takes `(contentType, disposition)`. Matches existing server logic; avoids regressing `.docx` behavior. |
| "SharedContentKind is parallel to the new FileKind" | `@/lib/shared-kind.ts` already defines `SharedContentKind = "markdown" \| "pdf" \| "image" \| "download"` with a runtime type-guard (`isSharedContentKind`) and the `X-Soleur-Kind` header. It IS the cross-viewer kind enum, minus `"text"`. Introducing a parallel `FileKind` enum would create a third source of truth. | **Extend `SharedContentKind` to include `"text"` and alias `FileKind = SharedContentKind`.** Single enum across owner + shared + classifier. Update `isSharedContentKind` guard. |

## Open Code-Review Overlap

Three open code-review issues touch files this plan edits (other than the three we're closing). Dispositions:

- **#2329** (Cache-Control for `/shared/` binaries + ETag/304) — touches `kb-binary-response.ts`. **Acknowledge.** The issue is stale: `buildETag`, `formatStrongETag`, `ifNoneMatchMatches`, `build304Response`, and conditional-GET short-circuits were already added in subsequent PRs (#2515, #2517). The `Cache-Control: private` complaint is the one remaining item, but it's a separate perf/caching discussion (public-vs-private, Cloudflare edge, max-age tuning) that warrants its own issue triage — out of scope for a policy-constants refactor. **Action:** file a brief comment on #2329 noting the ETag/304 portion shipped; leave the cache-scope discussion open. Do not fold in.
- **#2335** (add unit tests for canUseTool callback allow/deny shape) — touches `agent-runner.ts`. **Acknowledge.** Our edit to `agent-runner.ts` is a 1-line import path change (`from "./kb-binary-response"` → `from "./kb-limits"`). Zero overlap with the canUseTool test surface. Do not fold in.
- **#1662** (extract MCP tool definitions from agent-runner when 2nd tool added) — touches `agent-runner.ts`. **Acknowledge.** Same rationale as #2335 — import-path-only change; MCP tool extraction is a bigger separate refactor. Do not fold in.
- **#2512** (review: add conversations_lookup MCP tool follow-ups) — touches `agent-runner.ts`. **Acknowledge.** Same rationale. Do not fold in.

Net backlog impact: **−3 closures** (issues #2300, #2325, #2297) with **no new scope-outs created**. This matches the PR #2486 drain pattern.

## File Inventory

### Files to create

- `apps/web-platform/server/kb-limits.ts` — policy constants module (MAX_BINARY_SIZE, CONTENT_TYPE_MAP).
- `apps/web-platform/server/kb-file-kind.ts` — shared classifier (`classifyByExtension`, `classifyByContentType`). Re-exports `SharedContentKind as FileKind` for caller ergonomics.
- `apps/web-platform/test/kb-file-kind.test.ts` — unit tests for both classifier functions; explicitly asserts the `.txt` parity (classifyByExtension('.txt') === 'text' && classifyByContentType('text/plain', 'inline') === 'text').

### Files to edit

- `apps/web-platform/lib/shared-kind.ts` — add `"text"` variant to `SharedContentKind`; update `isSharedContentKind` guard. **Do NOT re-alias to `FileKind` here** — keeping `SharedContentKind` as the canonical name preserves git blame in the header-emitting route code and in existing tests. Export the `FileKind` alias from `server/kb-file-kind.ts` for readability at classifier call sites.
- `apps/web-platform/server/kb-binary-response.ts` — import `MAX_BINARY_SIZE` + `CONTENT_TYPE_MAP` from `kb-limits.ts`; delete the `ATTACHMENT_EXTENSIONS` Set; inline the `.docx` check at line 143 as `ext === ".docx"` with a `// Extend via kb-limits.ts when adding attachment-only types` doc comment. Replace `deriveBinaryKind` implementation with a call to `classifyByContentType(meta.contentType, meta.disposition)`. Keep the export for BC (one call site in `kb-serve.ts:156`).
- `apps/web-platform/server/kb-share.ts` — change import of `MAX_BINARY_SIZE` from `@/server/kb-binary-response` to `@/server/kb-limits`.
- `apps/web-platform/server/agent-runner.ts` — change import of `MAX_BINARY_SIZE` from `./kb-binary-response` to `./kb-limits`.
- `apps/web-platform/components/kb/file-preview.tsx` — replace the extension-string dispatch (IMAGE_EXTENSIONS + `.pdf`/`.txt` ladder) with `classifyByExtension(ext)` + switch over `FileKind`. Delete the local `IMAGE_EXTENSIONS` set. Drop the component's dependency on `extension: string` in favor of `kind: FileKind` — compute the kind at the call site (`[...path]/page.tsx`) using `classifyByExtension(getKbExtension(joinedPath))`. Tighter contract: the component can't silently diverge from the classifier.
- `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` — compute `kind` via `classifyByExtension(extension)` at the call site; pass to `FilePreview` as `kind={kind}` instead of `extension={extension}`.
- `apps/web-platform/app/shared/[token]/classify-response.ts` — add a `case "text"` branch alongside `case "pdf" | "image" | "download"`. Emit `{ kind: "text", src, filename: filename ?? basenameFromToken(token) }` so the shared page can render inline.
- `apps/web-platform/app/shared/[token]/page.tsx` — add a `data.kind === "text"` render branch: fetch the text via a `TextPreview`-equivalent, or reuse the existing `FilePreview` component now that it accepts `kind`. **Decision:** reuse `FilePreview` to eliminate the second text-fetch path; pass `kind="text"`, `showDownload={false}`, and a prop-derived filename. This also removes a second divergence opportunity (shared-page inline text fetch would be a third SoT).
- `apps/web-platform/app/api/shared/[token]/route.ts` — verify `SHARED_CONTENT_KIND_HEADER` emission for `text/plain` files now yields `"text"` (the header already derives from `deriveBinaryKind` via `buildBinaryResponse`; the behavior change rides on `classifyByContentType("text/plain", "inline") === "text"`). No direct edit expected; add a test asserting the header value.
- `apps/web-platform/test/kb-share-allowed-paths.test.ts:144` — replace `Buffer.alloc(50 * 1024 * 1024 + 1)` with `Buffer.alloc(MAX_BINARY_SIZE + 1)`; add `import { MAX_BINARY_SIZE } from "@/server/kb-limits"` at the top.
- `apps/web-platform/test/kb-serve.test.ts:6` — change the import of `MAX_BINARY_SIZE` from `@/server/kb-binary-response` to `@/server/kb-limits`.
- `apps/web-platform/test/classify-response.test.ts` — add a test for `case "text"` classification (binary response with `X-Soleur-Kind: text`).
- `apps/web-platform/test/file-preview.test.tsx` — update existing assertions to pass `kind` instead of `extension`; add a `.txt` → inline render assertion.
- `apps/web-platform/test/kb-extensions.test.ts` — the existing `"Safe because ".bashrc" is not in CONTENT_TYPE_MAP"` test comment still holds; update the import path reference in the comment/text to `kb-limits`. No code change.

### Files NOT touched (explicitly)

- `apps/web-platform/server/kb-reader.ts` — references `MAX_BINARY_SIZE` in a doc comment only (line 265). Update doc comment pointer to `kb-limits.ts` in Phase 1 (single-word edit), but no logic change.
- `apps/web-platform/test/kb-page-routing.test.tsx` — references `FilePreview` in an import path check. May need a prop signature update (`extension` → `kind`) if it asserts on props. Verified in Phase 4 test-sweep.

## Implementation Phases

### Phase 1 — Extract `kb-limits.ts`; migrate all 6 importers (closes #2300 + #2325)

**Gate:** Phase 2 cannot start until Phase 1 green (vitest).

1. Create `apps/web-platform/server/kb-limits.ts` exporting `MAX_BINARY_SIZE` (50 *1024* 1024) and `CONTENT_TYPE_MAP`. Add a module-level doc comment: `// Shared policy constants for KB binary serving and share-link gating. New attachment-only extensions extend the classifyByExtension list in kb-file-kind.ts; new content-type mappings extend CONTENT_TYPE_MAP here.`
2. In `kb-binary-response.ts`:
   - Remove `export const MAX_BINARY_SIZE = ...` and `export const CONTENT_TYPE_MAP = ...`.
   - Remove `export const ATTACHMENT_EXTENSIONS = new Set([".docx"])`.
   - Add `import { MAX_BINARY_SIZE, CONTENT_TYPE_MAP } from "@/server/kb-limits";`.
   - Replace line 143 `const disposition = ATTACHMENT_EXTENSIONS.has(ext) ? "attachment" : "inline";` with `const disposition = ext === ".docx" ? "attachment" : "inline";` followed by a `// Extend via kb-limits.ts + kb-file-kind.ts when adding attachment-only types` comment.
3. Update imports in `kb-share.ts`, `agent-runner.ts`, `test/kb-share-allowed-paths.test.ts`, `test/kb-serve.test.ts` — change import path to `@/server/kb-limits` (or relative `./kb-limits` for agent-runner).
4. In `test/kb-share-allowed-paths.test.ts`, add the `MAX_BINARY_SIZE` import and replace the hardcoded literal with `Buffer.alloc(MAX_BINARY_SIZE + 1)`.
5. Update doc-comment reference in `kb-reader.ts:265` from `kb-binary-response` to `kb-limits` (pointer only; no logic).
6. Run vitest on changed files:

   ```bash
   cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-share-allowed-paths.test.ts test/kb-serve.test.ts
   ```

7. Run `tsc --noEmit` for the app to catch any stale import path.

**Verification:** `rg "from ['\"]@/server/kb-binary-response['\"]" apps/web-platform --no-heading | grep -iE "MAX_BINARY_SIZE|CONTENT_TYPE_MAP|ATTACHMENT_EXTENSIONS"` returns zero matches.

### Phase 2 — Extract `kb-file-kind.ts` classifier + extend `SharedContentKind` (closes #2297 server half)

**Gate:** Phase 3 cannot start until the classifier tests are green.

1. Update `apps/web-platform/lib/shared-kind.ts`:
   - Add `"text"` to the `SharedContentKind` union.
   - Add `value === "text"` branch to `isSharedContentKind`.
2. Create `apps/web-platform/server/kb-file-kind.ts`:

   ```ts
   import type { SharedContentKind } from "@/lib/shared-kind";
   import { CONTENT_TYPE_MAP } from "@/server/kb-limits";

   /**
    * Shared file-kind enum for KB viewers. Alias of SharedContentKind to
    * keep the server's X-Soleur-Kind header and the viewer dispatch table
    * anchored on a single type. Adding a kind requires:
    *   (1) extend SharedContentKind in lib/shared-kind.ts,
    *   (2) add a classifyByExtension branch here,
    *   (3) add a classifyByContentType branch here,
    *   (4) add a renderer to components/kb/file-preview.tsx and
    *       app/shared/[token]/page.tsx.
    * The switch statements in each consumer are exhaustive — a forgotten
    * branch is a build error, not a silent "download".
    */
   export type FileKind = SharedContentKind;

   export function classifyByExtension(ext: string): FileKind {
     // Markdown dispatch lives in isMarkdownKbPath (empty string treated as
     // markdown). Callers should isMarkdownKbPath-gate BEFORE calling this;
     // if they don't, "" falls through to "download".
     if (ext === ".md") return "markdown";
     if (ext === ".pdf") return "pdf";
     if (ext === ".png" || ext === ".jpg" || ext === ".jpeg" ||
         ext === ".gif" || ext === ".webp" || ext === ".svg") return "image";
     if (ext === ".txt") return "text";
     return "download";
   }

   export function classifyByContentType(
     contentType: string,
     disposition: "inline" | "attachment",
   ): FileKind {
     // Disposition wins — `.docx` has a specific contentType but is forced
     // attachment by kb-binary-response.ts:143.
     if (disposition === "attachment") return "download";
     if (contentType === "application/pdf") return "pdf";
     if (contentType.startsWith("image/")) return "image";
     if (contentType === "text/plain") return "text";
     // NB: markdown never flows through the binary path (route handler
     // dispatches by extension before reaching buildBinaryResponse).
     return "download";
   }
   ```

3. In `kb-binary-response.ts`, rewrite `deriveBinaryKind`:

   ```ts
   import { classifyByContentType } from "@/server/kb-file-kind";

   export function deriveBinaryKind(
     meta: Pick<BinaryFileMetadata, "contentType" | "disposition">,
   ): Exclude<SharedContentKind, "markdown"> {
     const kind = classifyByContentType(meta.contentType, meta.disposition);
     // Binary path never yields markdown (caller branches earlier); keep
     // the return type narrowed so kb-serve.ts's consumer stays typed.
     return kind === "markdown" ? "download" : kind;
   }
   ```

   The narrowing line is a safety rail — `classifyByContentType` cannot return "markdown" today, but the type-level narrow is cheap insurance.
4. Create `apps/web-platform/test/kb-file-kind.test.ts`:
   - `classifyByExtension`: `.md → "markdown"`, `.pdf → "pdf"`, each image ext → `"image"`, `.txt → "text"`, `.docx → "download"`, `.zip → "download"`, `"" → "download"`.
   - `classifyByContentType`: `("application/pdf", "inline") → "pdf"`, `("image/png", "inline") → "image"`, `("text/plain", "inline") → "text"`, `("application/vnd.openxmlformats-officedocument.wordprocessingml.document", "attachment") → "download"`, `("application/octet-stream", "inline") → "download"`.
   - **Drift regression:** explicitly assert `classifyByExtension(".txt") === classifyByContentType("text/plain", "inline")` — the same invariant in one line.
5. Add a test in `test/classify-response.test.ts` for the `"text"` kind branch (mirrors the existing `"pdf"`/`"image"`/`"download"` cases).
6. Run:

   ```bash
   cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-file-kind.test.ts test/classify-response.test.ts
   ```

**Verification:** `rg "deriveBinaryKind" apps/web-platform --no-heading` still shows the two call sites (`kb-binary-response.ts` internal + `kb-serve.ts:13/156`) — the function signature is preserved.

### Phase 3 — Rewire owner viewer to consume `FileKind` (closes #2297 owner half)

**Gate:** Phase 4 cannot start until the owner viewer test is green.

1. Edit `components/kb/file-preview.tsx`:
   - Change the prop signature: `{ path: string; kind: FileKind; showDownload?: boolean; }` — remove `extension`.
   - Remove the local `IMAGE_EXTENSIONS` set.
   - Replace the if-ladder with `switch (kind) { case "image": ...; case "pdf": ...; case "text": ...; case "download": ...; case "markdown": /* unreachable — caller branches on isMarkdownKbPath */ return null; }`. Add an exhaustiveness never-check in the default arm (mirrors `classify-response.ts`).
   - The `filename` derivation stays (`path.split("/").pop()`). No other changes to the sub-components.
2. Edit `app/(dashboard)/dashboard/kb/[...path]/page.tsx`:
   - Import `classifyByExtension` from `@/server/kb-file-kind`. (Note: importing a server file into a `"use client"` component is permitted by Next because the classifier is pure — no `node:` imports. Verified by reading the classifier: it only references `SharedContentKind` type + `CONTENT_TYPE_MAP` constant. If Next objects, relocate the classifier to `@/lib/kb-file-kind` — decision deferred to Phase 3 implementation as an accommodation, not a redesign.)
   - Compute `const kind = classifyByExtension(extension);` after the existing `const extension = getKbExtension(joinedPath);`.
   - Pass `kind={kind}` to `<FilePreview path={joinedPath} kind={kind} showDownload={false} />`.
3. Update `test/file-preview.test.tsx` — every render assertion switches from `extension="..."` to `kind="..."`. Add a new `.txt → TextPreview rendered` assertion if not present.
4. Run:

   ```bash
   cd apps/web-platform && ./node_modules/.bin/vitest run test/file-preview.test.tsx test/kb-page-routing.test.tsx
   ```

**Verification:** `rg "IMAGE_EXTENSIONS" apps/web-platform --no-heading` returns zero matches. `rg "extension={" apps/web-platform/components apps/web-platform/app --no-heading` shows no `<FilePreview extension=` call sites.

### Phase 4 — Rewire shared viewer to consume `FileKind` + unlock `.txt` parity (closes #2297 shared half)

**Gate:** Phase 5 cannot start until the shared viewer test is green.

1. Edit `app/shared/[token]/classify-response.ts`:
   - Extend `SharedData` union with `{ kind: "text"; src: string; filename: string }`.
   - Add a `case "text":` arm returning `{ data: { kind: "text", src, filename: filename ?? basenameFromToken(token) } }`.
   - The exhaustiveness `never`-guard keeps the compiler honest.
2. Edit `app/shared/[token]/page.tsx`:
   - Add a `{data?.kind === "text" && (...)}` render branch. Two options:
     - (a) Inline `<pre>` with fetch (duplicates `FilePreview`'s `TextPreview` logic) — **reject**.
     - (b) Reuse `<FilePreview path="" kind="text" showDownload={false} />` — **reject**: FilePreview computes `contentUrl = /api/kb/content/${path}` which is the owner-route, not the shared-route.
     - (c) Extract the `TextPreview` sub-component to its own file (`components/kb/text-preview.tsx`) that takes `src` + `filename` directly, then use it from both page.tsx files. **Accept.** This is the minimal extraction that avoids a third text-fetch path.
   - Implementation: create `components/kb/text-preview.tsx` (export `TextPreview({ src, filename, showDownload })`), import into `file-preview.tsx` (removing the local copy), and into `app/shared/[token]/page.tsx`. Pass `src={data.src}` in both pages.
3. Update `test/classify-response.test.ts` — the `case "text"` assertion added in Phase 2.5 already exists; confirm it passes against the final implementation.
4. Add an end-to-end-ish assertion in a new or existing shared-viewer test: HEAD `/api/shared/<token>` for a `.txt` file returns `X-Soleur-Kind: text`; GET renders an inline `<pre>` on the shared page. Pattern mirrors `test/shared-image-a11y.test.tsx`.

**Verification:**

- `rg "X-Soleur-Kind: text" apps/web-platform/test --no-heading` — new test exists.
- Manual: render a `.txt` share token — owner page and shared page both show inline text. Capture a before/after screenshot in the PR.

### Phase 5 — Audit, cleanup, PR body

1. **Discriminated-union exhaustive-switch audit.** Widening `SharedContentKind` to include `"text"` propagates across every `switch (kind)` and every `isSharedContentKind` consumer. The compiler catches exhaustive switches with a `: never` rail, but only if the rail is present — consumers that use `if`/`else if` ladders, `Set<SharedContentKind>` literals, or membership checks degrade silently. Run:

   ```bash
   # Exhaustive switches on the widened union — every hit must have a "text" arm
   rg -n ": never|as never" apps/web-platform/app apps/web-platform/components apps/web-platform/server apps/web-platform/lib
   # Guard consumers — caller must tolerate the new variant
   rg -n "isSharedContentKind\b" apps/web-platform
   # Hardcoded variant sets — a literal like `new Set(["markdown","pdf","image","download"])` is silent drift
   rg -n "SharedContentKind|FileKind" apps/web-platform | rg -v "^.*(\.test\.|lib/shared-kind|server/kb-file-kind)"
   ```

   Prior incident: `knowledge-base/project/learnings/integration-issues/discriminated-union-exhaustive-switch-miss-20260410.md` — variant widening without this grep compiled locally only because the compile step was skipped.
2. Full vitest sweep:

   ```bash
   cd apps/web-platform && ./node_modules/.bin/vitest run
   ```

3. `tsc --noEmit` on the app.
4. `npx markdownlint-cli2 --fix knowledge-base/project/plans/2026-04-17-refactor-kb-policy-constants-plan.md`.
5. Verify no unused exports remain in `kb-binary-response.ts` — `ATTACHMENT_EXTENSIONS` and the `export` line for `CONTENT_TYPE_MAP`/`MAX_BINARY_SIZE` must be gone. `rg "ATTACHMENT_EXTENSIONS" apps/web-platform --no-heading` returns zero matches.
6. Update PR #2531 body:
   - Title: `refactor(kb): extract kb-limits + kb-file-kind policy modules`.
   - Body must include literal strings `Closes #2300`, `Closes #2325`, `Closes #2297` (each on its own line).
   - Body references "drain pattern: PR #2486".
   - Body links to the plan file.
   - Body includes a before/after screenshot comparing `.txt` rendering on the shared page.
7. File a status comment on #2329 noting ETag/304 portion shipped and linking to the current `kb-binary-response.ts` header builders (#2515, #2517). Do not close #2329 — the `public` vs `private` cache-scope discussion is still open.

## Enhancement Summary

**Deepened on:** 2026-04-17
**Sections enhanced:** Phase 5 audit (exhaustive-switch grep added)
**Research agents used:** `learnings-researcher`
**Pre-existing research:** plan already absorbed codebase reconciliation during initial authoring (see "Research Reconciliation — Spec vs. Codebase" and "Open Code-Review Overlap" sections).

### Key Improvements

1. Phase 5 now enforces a discriminated-union exhaustive-switch grep (`rg ": never"` + `isSharedContentKind` caller sweep + hardcoded variant-set sweep) to catch silent drift when widening `SharedContentKind` to include `"text"`. Prior incident: `integration-issues/discriminated-union-exhaustive-switch-miss-20260410.md`.
2. Related-issue sweep for target files (`kb-binary-response.ts`, `shared-kind.ts`, `file-preview.tsx`, `classify-response.ts`) surfaced no new overlapping work beyond the already-documented #2329 disposition. `#2510` (withUserRateLimit) and `#2008` (agent binary access) are unrelated.

### New Considerations Discovered

- Variant widening is load-bearing on every `if`/`else`/`switch` consumer, not just the type guard. The exhaustive-switch grep is now a Phase 5 gate.

## Acceptance Criteria

- [x] `server/kb-limits.ts` exists and exports `MAX_BINARY_SIZE` + `CONTENT_TYPE_MAP`.
- [x] `lib/kb-file-kind.ts` exists and exports `FileKind`, `classifyByExtension`, `classifyByContentType`. (Relocated from `server/` to `lib/` per Phase 3 step 2 fallback — pure types/constants, no `node:` imports, consumed from `"use client"` components.)
- [x] `SharedContentKind` includes `"text"`.
- [x] `kb-binary-response.ts` no longer exports `MAX_BINARY_SIZE`, `CONTENT_TYPE_MAP`, or `ATTACHMENT_EXTENSIONS`. It imports `MAX_BINARY_SIZE` and `CONTENT_TYPE_MAP` from `kb-limits.ts`. `deriveBinaryKind` delegates to `classifyByContentType`.
- [x] Every call site that previously imported `MAX_BINARY_SIZE` from `kb-binary-response` now imports from `kb-limits` (`kb-share.ts`, `agent-runner.ts`, `test/kb-share-allowed-paths.test.ts`, `test/kb-serve.test.ts`).
- [x] `test/kb-share-allowed-paths.test.ts` uses `Buffer.alloc(MAX_BINARY_SIZE + 1)` (no hardcoded literal).
- [x] `FilePreview` takes `kind: FileKind` (not `extension: string`). Owner page computes `kind` at call site.
- [x] Shared page renders `.txt` files inline (parity with owner page). GET `/api/shared/<token>` returns `X-Soleur-Kind: text` for `.txt` (covered by `test/shared-page-binary.test.ts` "emits X-Soleur-Kind: text for a .txt share").
- [x] `TextPreview` is shared between `file-preview.tsx` and `app/shared/[token]/page.tsx` (one implementation).
- [x] `components/kb/file-preview.tsx` uses a `switch(kind)` with exhaustiveness guard.
- [x] All vitest suites green; `tsc --noEmit` green. (1 pre-existing flake in `test/chat-input-attachments.test.tsx` tracked in #2470 / #2524 — unrelated.)
- [ ] PR #2531 body contains `Closes #2300`, `Closes #2325`, `Closes #2297`.
- [ ] Open code-review overlap dispositions recorded: #2329 commented on (ETag portion shipped), #2335/#1662/#2512 acknowledged in PR body.

## Test Scenarios

### Unit — `kb-file-kind.test.ts`

| Input | Expected FileKind |
|---|---|
| `classifyByExtension(".md")` | `"markdown"` |
| `classifyByExtension(".pdf")` | `"pdf"` |
| `classifyByExtension(".png")` / `.jpg` / `.jpeg` / `.gif` / `.webp` / `.svg` | `"image"` |
| `classifyByExtension(".txt")` | `"text"` |
| `classifyByExtension(".docx")` | `"download"` |
| `classifyByExtension(".zip")` | `"download"` |
| `classifyByExtension("")` | `"download"` |
| `classifyByContentType("application/pdf", "inline")` | `"pdf"` |
| `classifyByContentType("image/png", "inline")` | `"image"` |
| `classifyByContentType("text/plain", "inline")` | `"text"` |
| `classifyByContentType("application/vnd...wordprocessingml.document", "attachment")` | `"download"` |
| `classifyByContentType("application/octet-stream", "inline")` | `"download"` |
| Parity: `classifyByExtension(".txt") === classifyByContentType("text/plain", "inline")` | `true` |

### Unit — existing tests updated

- `test/kb-share-allowed-paths.test.ts` "rejects oversize files with 413" — uses `MAX_BINARY_SIZE + 1`; passes.
- `test/kb-serve.test.ts` "file exceeding MAX_BINARY_SIZE returns 413" — import path only; passes.
- `test/classify-response.test.ts` — new `"text"` kind case.
- `test/file-preview.test.tsx` — all assertions use `kind=`; new `.txt` inline-render case.

### Manual — shared `.txt` parity

1. Create a `.txt` file in KB (owner session).
2. Visit `/dashboard/kb/<path>.txt` — inline text render via `TextPreview`.
3. Generate a share link.
4. Visit `/shared/<token>` in a fresh incognito — inline text render (previously: download button). Screenshot both for PR.

## Risks

- **Server classifier imported into a `"use client"` component.** `server/kb-file-kind.ts` has zero Node imports (just types and `CONTENT_TYPE_MAP`). Next.js permits client-side consumption of server files without `node:` imports, but if the bundler objects, relocate to `@/lib/kb-file-kind`. Contingency: Phase 3 step 2 documents the fallback path. No redesign required.
- **`SharedContentKind` enum widening is a cross-cutting type change.** Every `switch (kind)` must get a new arm. Compiler enforces this (exhaustiveness guards in `classify-response.ts` and `file-preview.tsx`). The only non-switch consumer is `isSharedContentKind` — updated in Phase 2 step 1.
- **`deriveBinaryKind` return type narrowing.** The `Exclude<SharedContentKind, "markdown">` return type loses `"text"` — wait, it keeps `"text"` because `Exclude` only removes `"markdown"`. Verify: `Exclude<"markdown"|"pdf"|"image"|"text"|"download", "markdown"> = "pdf"|"image"|"text"|"download"` ✓. The `classifyByContentType` call inside `deriveBinaryKind` can return `"markdown"` type-wise but never does at runtime; the narrowing `kind === "markdown" ? "download" : kind` is a safety rail, not a behavior change.
- **`TextPreview` extraction touches two render trees.** Any drift between owner and shared rendering is now a bug in a single shared component — this is the whole point. The risk is the opposite direction (accidentally regressing owner-side `TextPreview` during extraction). Phase 3 test-run covers this.
- **#2329's `Cache-Control` critique is unrelated to this refactor but shares the file.** Acknowledged in "Open Code-Review Overlap" — do not conflate.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — pure server+client refactor. No user-facing page added; `.txt` shared-viewer parity is a bug-closing restoration of expected behavior (owner and shared viewers were always intended to render the same kinds). No copy changes. No marketing/legal/sales/ops/finance surface. No brainstorm document precedes this plan; the three closed issues are themselves the specification.

CTO implication: single-file cohesion improvement + viewer drift closure. Engineering-only.

## Sharp Edges

- When Phase 3 step 2 imports a server file from a `"use client"` component, run `next build` locally (not just vitest) to catch bundler complaints — `tsc --noEmit` passes on configurations that `next build` rejects. Fallback to `@/lib/kb-file-kind` colocation if it fails.
- Phase 4 step 2 option (c) — extracting `TextPreview` — must preserve the `showDownload={false}` plumbing. The owner page passes `showDownload={false}` (dashboard supplies its own download row); the shared page passes `showDownload={false}` too (page header supplies its own). Default should remain `true` for any direct callers.
- Phase 1 step 5's `kb-reader.ts` doc comment update — don't greedy-replace. The file has one pointer at line 265; search by `MAX_BINARY_SIZE` in that comment specifically.
- Phase 5 step 5's PR body must use **literal** `Closes #2300` (one per line). GitHub parses qualifiers like "Closes #2300 partially" and still auto-closes — use `Ref` only for partial.

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-04-17-refactor-kb-policy-constants-plan.md. Branch: feat-kb-policy-constants. Worktree: .worktrees/feat-kb-policy-constants/. Issues: #2300 + #2325 + #2297 (all Phase 3 milestone). PR: #2531 (draft). Plan written, Phase 1 extract kb-limits.ts next.
```
