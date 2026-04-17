# Refactor: shared KB serving helpers (serveBinary + dispatch + isMarkdownExt + serveBinaryWithHashGate)

**Branch:** `feat-kb-serve-binary-helpers`
**Worktree:** `.worktrees/feat-kb-serve-binary-helpers/`
**PR:** #2517 (draft)
**Issues closed:** #2299, #2313, #2317, #2483
**Pattern reference:** PR #2486 (close-more-than-open refactor: 3 scope-outs, 13 files, no new deferrals)

## Enhancement Summary

**Deepened on:** 2026-04-17
**Sections enhanced:** Risks, Test Strategy, Phases 3/6/9, new Phase 11 (negative-space test migration)
**Research sources:** 4 directly-relevant project learnings + `kb-security.test.ts` inspection

### Key Improvements from deepen pass

1. **Negative-space test gate surfaced** — `test/kb-security.test.ts` already carries structural-regex assertions that scan KB route files for delegation patterns (`authenticateAndResolveKbPath` / `resolveUserKbRoot` / `readContent`). After the refactor, the content route's markdown branch still invokes `readContent` inside the `onMarkdown` callback, so the existing `logger.error` delegation regex continues to match — **no test migration needed for the content route**. The share route continues to carry inline `logger.error` calls (multiple) — the test passes via that branch. Call this out explicitly in Phase 11 to prevent a future refactor from accidentally loosening.
2. **Half-extraction risk flagged (from 2026-04-14 learning)** — `serveBinaryWithHashGate` accepts `logger` + `logContext` as parameters. If the helper accrues a return contract (e.g., `{ cachedVerdict, logContext }`) that the route ignores, that's exactly the purity-drift shape that burned #2209. Decision: helper returns ONLY `Promise<Response>`. No side-channel return fields. Any log emission happens inside the helper using the caller's logger; the route does not post-process.
3. **"Trim to negative-space only" applied (from 2026-04-17 learning)** — the plan does NOT add positive regex-on-source tests like "content route imports `serveKbFile`" or "share route invokes `serveBinaryWithHashGate`". End-to-end tests (`kb-content-binary.test.ts`, `shared-page-binary.test.ts`, `shared-token-verdict-cache.test.ts`) transitively prove delegation. Only the existing negative-space gate in `kb-security.test.ts` remains; no new regex-on-source tests are added.
4. **Companion state (from 2026-04-14 learning)** — audit the helper's inputs: `shareHashVerdictCache` is a module-level singleton. The helper reads AND writes it. Single source of truth — no ref/state split. Safe. No companion-state migration required.
5. **Plan-preflight CLI-form verification (from 2026-04-17 learning)** — the plan prescribes no CLI flag combinations that require version-aware verification. The build/test commands (`vitest`, `tsc --noEmit`, `npm run build`) are already convention in this repo. N/A.

### New Considerations Discovered

- The `contentChangedResponse` helper is used by BOTH the markdown and binary branches of the share route. Moving it into `server/kb-serve.ts` requires the route to re-import it. Verified: this is cleaner than duplicating (both branches want the same wire shape).
- `legacyNullHashResponse` is only called from the markdown-path's guard before dispatching. It stays in the route.
- The dashboard page's `extension` variable (still used for `<FilePreview extension={extension} />`) needs a secondary pass: its current computation lacks `.toLowerCase()`. Adding it is a behavior change for FilePreview consumers of `.PDF`, `.PNG`, etc. Audit: check whether `FilePreview` normalizes the extension prop internally before concluding this is safe.

## Overview

Four open code-review findings from the PR #2282 / #2477 sweep describe different shards of the same duplication: `/api/kb/content/[...path]` (owner) and `/api/shared/[token]` (recipient) both run an identical pattern:

1. Pick fork by extension (`.md` / `""` → markdown JSON; else binary).
2. `validateBinaryFile` → propagate typed result / Response.
3. `buildBinaryResponse` → propagate `BinaryOpenError` → Response.

The share route wraps step 2–3 with a verdict-cache + hash-gate dance. The dashboard page (`app/(dashboard)/dashboard/kb/[...path]/page.tsx`) carries its own slightly-divergent copy of the extension classifier.

This PR introduces one consolidated server-side helper module plus one client/server-shared primitive, and migrates all four call sites (two route handlers, one dashboard page, server-internal `validateBinaryFile`) to delegate. Net intent: close 4 issues in a single focused refactor with zero behavior change visible to clients.

## Research Reconciliation — Spec vs. Codebase

| Claim in issues | Reality in branch `feat-kb-serve-binary-helpers` | Plan response |
|---|---|---|
| #2299: "`readBinaryFile` + `buildBinaryResponse` two-step API" | `readBinaryFile` was renamed to `validateBinaryFile` in PR #2316 and is now a deprecated alias. Current two-step is `validateBinaryFile` + `buildBinaryResponse`. | Plan targets current names; `serveBinary` wraps `validateBinaryFile` + `buildBinaryResponse`. Deprecated `readBinaryFile` export stays (removal is out of scope). |
| #2313: "`/api/kb/content` lines 49–80; `/api/shared/[token]` lines 70–129" | Current content route: lines 48–96. Current share route: lines 107–162 (markdown branch) and 164–280 (binary+hash branch). | Line numbers are illustrative only; plan references the semantic branches, not byte offsets. |
| #2483: "extract after #2309 lands" | #2309 merged via PR #2497 on 2026-04-17 (confirmed in args). `content_sha256` always-required path now stable. | Precondition met; safe to extract `serveBinaryWithHashGate` now. |
| #2317: "client uses `joinedPath.includes('.')` + `split('.').pop()` without `.toLowerCase()`" | Confirmed at `app/(dashboard)/dashboard/kb/[...path]/page.tsx:24`. `NOTES.MD` would classify as non-markdown on client, markdown on server. | Plan extracts `lib/kb-extensions.ts`, migrates both sides, adds case-sensitivity regression test. |
| PR #2486 "net-negative pattern" | Confirmed merged. Closed #2467/#2468/#2469 in one PR with 13 files touched. | Mirror the approach: single-PR drain, no new scope-out issues filed from this PR. |

## Goals / Non-goals

**Goals:**

1. One server module (`server/kb-serve.ts`) exporting `serveKbFile`, `serveBinary`, `serveBinaryWithHashGate`.
2. One shared primitive (`lib/kb-extensions.ts`) exporting `getKbExtension` + `isMarkdownKbPath`.
3. `/api/kb/content/[...path]/route.ts` delegates to `serveKbFile` (owner variant, no hash gate).
4. `/api/shared/[token]/route.ts` delegates to `serveKbFile` with `serveBinaryWithHashGate`.
5. `app/(dashboard)/dashboard/kb/[...path]/page.tsx` uses `isMarkdownKbPath` instead of the inline expression.
6. Behavior-preserving: status codes, headers, log events, error-code strings (`content-changed`, `revoked`, `legacy-null-hash`) all unchanged.
7. No new dependencies. No migration.

**Non-goals (out of scope — do NOT chase these):**

- Collapsing share-link + owner Supabase queries into one (tracked in #2328).
- Eliminating the double-GET for PDFs/images (tracked in #2324).
- Error-shape convention unification (tracked in #2308).
- Removing deprecated `readBinaryFile` alias (should be a separate cleanup PR once no callers remain).
- Extracting `KbContentHeader`, `LoadingSkeleton`, or `classifyResponse` (tracked in #2312, #2318, #2321).
- `BinaryFilePayload` parameter object (#2311) — deliberately not bundled to keep this PR small.
- File-kind classification unification for the viewer page (#2297) — dashboard page uses the extracted `isMarkdownKbPath`, but the shared viewer page's Content-Type inference (`#2304`) is a different concern and remains.

## Open Code-Review Overlap

These open scope-outs touch files this PR will modify:

- **#2299** (`serveBinary` extraction) — **Fold in.** This IS the first helper extracted. Closes.
- **#2313** (markdown/binary dispatch extraction) — **Fold in.** This IS `serveKbFile`. Closes.
- **#2317** (`isMarkdownExt` helper) — **Fold in.** This IS `lib/kb-extensions.ts`. Closes.
- **#2483** (`serveBinaryWithHashGate` after #2309 lands) — **Fold in.** #2309 confirmed merged via PR #2497. Closes.
- **#2303** (contract test: owner + shared return identical bytes/headers) — **Acknowledge.** Different concern (new contract test, not a refactor). After `serveBinary` lands, writing this test becomes easier — but filing it as part of this PR would balloon scope. Leave open; reference this PR in a follow-up.
- **#2308** (mixed error-shape conventions) — **Acknowledge.** Semantic decision (typed errors vs tagged-union). This PR preserves both shapes at their current sites; unifying them is a separate design call. Leave open.
- **#2301** (symlink-reject message parity) — **Acknowledge.** Different concern (status-code parity, not helper extraction). The `serveBinary` helper returns `{ error: 'Access denied' }` uniformly, which happens to improve parity, but a full fix requires touching the JSON envelope shapes on the share route. Leave open; this PR may reduce its surface incidentally.
- **#2305** (error-handling symmetry between markdown and binary branches of share route) — **Acknowledge.** After `serveKbFile` extraction, markdown and binary both flow through the same try/catch shape in the route — partially addresses the smell, but the markdown branch's inline `hashBytes` comparison stays in-route. Leave open.
- **#2297** (unify file-kind classification across owner and shared viewer pages) — **Acknowledge.** Dashboard page gets `isMarkdownKbPath` here, but the shared viewer page's kind inference happens client-side on Content-Type and is a separate refactor. Leave open.
- **#2321** (`classifyResponse` from shared page useEffect) — **Acknowledge.** Client-side concern; orthogonal to server helpers. Leave open.
- **#2311** (`BinaryFilePayload` parameter object) — **Defer.** DHH-style "don't abstract until there's a third caller". Leave open; re-evaluate if a third caller appears.
- **#2325** (inline `ATTACHMENT_EXTENSIONS`) — **Defer.** Cleanup on `kb-binary-response.ts` internals; orthogonal. Leave open.
- **#2300** (move `MAX_BINARY_SIZE` to `kb-limits.ts`) — **Defer.** Pure file-move; orthogonal. Leave open.
- **#2322** (agent preview of shared recipient view) — **Defer.** Feature work, not refactor. Leave open.
- **#2304** (shared page infers kind from Content-Type) — **Defer.** Client-side refactor in a different file. Leave open.
- **#2306** (a11y: image viewer alt text) — **Defer.** Orthogonal. Leave open.
- **#2312** (duplicate `LoadingSkeleton`) — **Defer.** Component extraction, orthogonal. Leave open.
- **#2318** (`KbContentHeader` extraction) — **Defer.** Component extraction, orthogonal. Leave open.
- **#2328** / **#2324** / **#2329** — **Defer.** All performance/DB concerns, not helper extraction. Leave open.
- **#2348** (vitest mock-factory export drift) — **Acknowledge.** If `serveKbFile` extraction causes any test file to need an updated mock factory, the fix will be made in that same test file. If the tests pass unchanged, leave the issue open.

Net: +0 new scope-out issues. 4 closures (#2299, #2313, #2317, #2483). 13+ items acknowledged or deferred with rationale.

## Files to create

1. `apps/web-platform/lib/kb-extensions.ts` — shared client/server extension classifier.
    - `getKbExtension(relPath: string): string` — lastIndexOf('.') based, returns lowercased ext or `""`.
    - `isMarkdownKbPath(relPath: string): boolean` — `ext === ".md" || ext === ""`.
2. `apps/web-platform/server/kb-serve.ts` — server-side dispatch + binary serve helpers.
    - `serveBinary(kbRoot, relativePath, { request, onError? }): Promise<Response>` — wraps `validateBinaryFile` + `buildBinaryResponse` + `BinaryOpenError` → error Response.
    - `serveBinaryWithHashGate({ token, expectedHash, meta, request, logger, logContext }): Promise<Response>` — verdict-cache + hash-stream + serve with strong ETag.
    - `serveKbFile(kbRoot, relativePath, { request, onMarkdown, onBinary? }): Promise<Response>` — dispatches by `isMarkdownKbPath`; markdown callback produces the JSON envelope; binary defaults to `serveBinary`, or caller overrides with `serveBinaryWithHashGate` wrapper.
3. `apps/web-platform/test/kb-extensions.test.ts` — unit tests for the two helpers (Windows-style separators, case folding, multiple dots, hidden files, empty strings).
4. `apps/web-platform/test/kb-serve.test.ts` — unit tests for `serveBinary` and `serveKbFile` behavior (404/403/413 paths, markdown callback invocation, binary callback override).
5. `apps/web-platform/test/kb-serve-hash-gate.test.ts` — unit tests for `serveBinaryWithHashGate` (cache hit, cache miss + match, cache miss + mismatch → 410, inode drift → 410, BinaryOpenError → error response, strong ETag echoed).

## Files to edit

1. `apps/web-platform/app/api/kb/content/[...path]/route.ts` — delegate to `serveKbFile` with `onMarkdown` returning `NextResponse.json(result)`.
2. `apps/web-platform/app/api/shared/[token]/route.ts` — delegate to `serveKbFile`; markdown branch still does `hashBytes` against `shareLink.content_sha256` before returning the JSON envelope; binary branch calls `serveBinaryWithHashGate`.
3. `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx` — import `isMarkdownKbPath`, replace the inline expression.
4. `apps/web-platform/server/kb-binary-response.ts` — internal: use `getKbExtension` from `lib/kb-extensions.ts` in `validateBinaryFile` so the server has one authoritative classifier.
5. `apps/web-platform/test/kb-content-binary.test.ts` — no behavior change expected; if any mock-factory drift occurs (c.f. #2348), update in place.
6. `apps/web-platform/test/shared-page-binary.test.ts` — same. No behavior change expected.
7. `apps/web-platform/test/shared-token-content-hash.test.ts` — same.
8. `apps/web-platform/test/shared-token-verdict-cache.test.ts` — same.
9. `apps/web-platform/test/kb-share-content-hash.test.ts` — same.

## Implementation Phases

### Phase 1 — Shared extension primitive (`lib/kb-extensions.ts`)

**TDD gate:** Write `test/kb-extensions.test.ts` FIRST. Assert:

- `getKbExtension("foo.md") === ".md"`
- `getKbExtension("FOO.MD") === ".md"` (case folds)
- `getKbExtension("notes/doc.PDF") === ".pdf"`
- `getKbExtension("noext") === ""`
- `getKbExtension(".hidden") === ""` (lastIndexOf is 0 → returns `".hidden"`.lowerCased — **document intended behavior:** leading dot with no further dot → treat as no extension per bash/unix convention; return `""`). Verify chosen semantics in the test.
- `getKbExtension("a/b/c.tar.gz") === ".gz"` (last dot only)
- `getKbExtension("") === ""`
- `isMarkdownKbPath("NOTES.MD") === true` (regression for the #2317 bug)
- `isMarkdownKbPath("foo") === true` (extensionless)
- `isMarkdownKbPath("foo.pdf") === false`

Then implement the two functions. Keep them pure — no Node APIs (`path`/`fs`), no Next APIs. They must be importable from both client (React component) and server (Next route handler).

### Phase 2 — `serveBinary` helper (closes #2299)

**TDD gate:** Extend `test/kb-serve.test.ts`. Cover:

- validate returns 403 (path traversal / symlink) → Response with status 403 JSON body `{ error: "Access denied" }`.
- validate returns 404 (missing / non-file) → 404 JSON.
- validate returns 413 (size exceeds max) → 413 JSON.
- `validateBinaryFile` ok → `buildBinaryResponse` succeeds → 200 stream with expected headers (`Content-Type`, `ETag`, `Accept-Ranges`).
- `buildBinaryResponse` throws `BinaryOpenError(404)` → 404 JSON, `onError` callback invoked with `(404, "File not found")` if passed.
- `buildBinaryResponse` throws non-`BinaryOpenError` → error rethrows (caller's outer try/catch handles it).

Implement in `server/kb-serve.ts`:

```ts
import { NextResponse } from "next/server";
import {
  validateBinaryFile,
  buildBinaryResponse,
  BinaryOpenError,
} from "@/server/kb-binary-response";

export async function serveBinary(
  kbRoot: string,
  relativePath: string,
  opts: {
    request: Request;
    onError?: (status: number, reason: string, code?: string) => void;
  },
): Promise<Response> {
  const result = await validateBinaryFile(kbRoot, relativePath);
  if (!result.ok) {
    opts.onError?.(result.status, result.error);
    return NextResponse.json({ error: result.error }, { status: result.status });
  }
  try {
    return await buildBinaryResponse(result, opts.request);
  } catch (err) {
    if (err instanceof BinaryOpenError) {
      opts.onError?.(err.status, err.message, err.code);
      return NextResponse.json({ error: err.message }, { status: err.status });
    }
    throw err;
  }
}
```

The `onError` hook preserves the owner route's existing `logger.warn` on `BinaryOpenError` and the share route's 403 `logger.warn` on traversal — both route-specific log events stay where they are instead of being centralized (DHH: "the helper shouldn't know the caller's log namespace").

### Phase 3 — `serveBinaryWithHashGate` helper (closes #2483)

**TDD gate:** Write `test/kb-serve-hash-gate.test.ts` BEFORE editing. Cover:

- **Cache hit path.** `shareHashVerdictCache.get` returns `true` → no `openBinaryStream` for hashing, serves with strong ETag.
- **Cache miss + hash match.** Drains stream via `hashStream`, compares, calls `shareHashVerdictCache.set`, serves with strong ETag.
- **Cache miss + hash mismatch.** Logs `shared_content_mismatch` with `kind: "binary"`, returns 410 `{ error, code: "content-changed" }`.
- **Inode drift during hash stream.** `openBinaryStream` throws `BinaryOpenError("content-changed")` → logs `inode-drift`, returns 410.
- **Inode drift during serve.** `buildBinaryResponse` throws `BinaryOpenError("content-changed")` → logs `inode-drift-serve`, returns 410.
- **Generic `BinaryOpenError` during hash** → logs warn, returns helper's status.
- **Non-error throw during hash** → logs error, returns 500.

Signature in `server/kb-serve.ts`:

```ts
import type { Logger } from "pino";
import {
  BinaryFileMetadata,
  BinaryOpenError,
  buildBinaryResponse,
  openBinaryStream,
} from "@/server/kb-binary-response";
import { hashStream } from "@/server/kb-content-hash";
import { shareHashVerdictCache } from "@/server/share-hash-verdict-cache";

export interface HashGateLogContext {
  event?: string;
  token: string;
  documentPath: string;
}

export async function serveBinaryWithHashGate(args: {
  token: string;
  expectedHash: string;
  meta: BinaryFileMetadata;
  request: Request;
  logger: Logger;
  logContext: HashGateLogContext;
}): Promise<Response>;
```

**Return-type discipline (from learning `2026-04-14-pure-reducer-extraction-requires-companion-state-migration.md`):** The helper returns ONLY `Promise<Response>`. No side-channel fields like `{ response, cachedVerdict, logEmitted }`. If a future caller needs the verdict-cache hit rate for metrics, that caller adds its own instrumentation — do NOT bolt a return-tuple onto the helper "for observability" and then let the route ignore most of its fields. "Never ship a contract the consumer ignores" is the specific anti-pattern that burned PR #2209.

**Companion-state audit.** Helper state surface:

- Reads: `shareHashVerdictCache` (module-level singleton, imported from `@/server/share-hash-verdict-cache`).
- Writes: `shareHashVerdictCache.set(...)` on hash match.
- No ref/state split. No reducer-and-ref hybrid. Single authority. Safe.

Move the cache-miss + hash-pass + mismatch-response + serve orchestration from the current `/api/shared/[token]/route.ts:178-279` into this helper verbatim. Preserve:

- All `logger.info` / `logger.warn` / `logger.error` call sites. Pass `logger` in; helper does not take its own child logger.
- Exact log field names (`event`, `token`, `documentPath`, `kind`, `reason`).
- Exact response-builder functions for 410s (`contentChangedResponse`) — move helper into `server/kb-serve.ts` as a module-private function; the route's one remaining caller of it (markdown branch) imports from the new module.
- Strong ETag passed via `buildBinaryResponse(meta, request, { strongETag: expectedHash })`.

### Phase 4 — `serveKbFile` dispatcher (closes #2313)

**TDD gate:** Add dispatch tests to `test/kb-serve.test.ts`:

- Path `foo.md` → `onMarkdown` callback invoked with `(kbRoot, "foo.md")`. Return value of callback returned.
- Path `notes/` (extensionless) → `onMarkdown` invoked.
- Path `NOTES.MD` → `onMarkdown` invoked (case-fold regression).
- Path `foo.pdf` → `serveBinary` (or overridden `onBinary`) invoked.
- Path `foo.PDF` → binary branch (case-fold regression).

Signature:

```ts
export async function serveKbFile(
  kbRoot: string,
  relativePath: string,
  opts: {
    request: Request;
    onMarkdown: (kbRoot: string, relativePath: string) => Promise<Response>;
    onBinary?: (kbRoot: string, relativePath: string) => Promise<Response>;
  },
): Promise<Response> {
  if (isMarkdownKbPath(relativePath)) {
    return opts.onMarkdown(kbRoot, relativePath);
  }
  return (opts.onBinary ?? ((root, p) => serveBinary(root, p, { request: opts.request })))(
    kbRoot,
    relativePath,
  );
}
```

### Phase 5 — Migrate owner route

Edit `app/api/kb/content/[...path]/route.ts`. After the workspace lookup and `relativePath` validation, dispatch:

```ts
return serveKbFile(kbRoot, relativePath, {
  request,
  onMarkdown: async (root, rel) => {
    try {
      const result = await readContent(root, rel);
      return NextResponse.json(result);
    } catch (err) {
      // existing KbAccessDeniedError / KbNotFoundError / KbValidationError mapping
    }
  },
  onBinary: (root, rel) =>
    serveBinary(root, rel, {
      request,
      onError: (status, message, code) => {
        if (status !== 404 && status !== 403) return;
        logger.warn(
          { err: message, code, path: rel },
          "kb/content: open failed on serve",
        );
      },
    }),
});
```

Run `kb-content-binary.test.ts` + `kb-content-csp.test.ts` after the edit. Every test must pass unchanged. If any test fails, the helper has drifted from the original behavior — fix the helper, not the test.

### Phase 6 — Migrate share route

Edit `app/api/shared/[token]/route.ts`. Structure after refactor:

```ts
// ... rate-limit, shareLink fetch, revoked/legacy checks unchanged ...
// ... owner workspace fetch unchanged ...
const kbRoot = path.join(owner.workspace_path, "knowledge-base");

return serveKbFile(kbRoot, shareLink.document_path, {
  request,
  onMarkdown: async (root, rel) => {
    try {
      const { buffer, raw } = await readContentRaw(root, rel);
      const currentHash = hashBytes(buffer);
      if (currentHash !== shareLink.content_sha256) {
        logger.info(
          { event: "shared_content_mismatch", token, documentPath: rel, kind: "markdown" },
          "shared: content hash mismatch",
        );
        return contentChangedResponse();
      }
      const { content } = parseFrontmatter(raw);
      logger.info(
        { event: "shared_page_viewed", token, documentPath: rel },
        "shared: document viewed",
      );
      return NextResponse.json({ content, path: rel });
    } catch (err) {
      // existing error mapping unchanged
    }
  },
  onBinary: async (root, rel) => {
    const binary = await validateBinaryFile(root, rel);
    if (!binary.ok) {
      if (binary.status === 403) {
        logger.warn({ token, path: rel }, "shared: binary access denied (symlink / outside root)");
      }
      return NextResponse.json({ error: binary.error }, { status: binary.status });
    }
    return serveBinaryWithHashGate({
      token,
      expectedHash: shareLink.content_sha256,
      meta: binary,
      request,
      logger,
      logContext: { token, documentPath: rel },
    });
  },
});
```

Run `shared-page-binary.test.ts`, `shared-token-content-hash.test.ts`, `shared-token-verdict-cache.test.ts`, `kb-share-content-hash.test.ts`, `kb-share-allowed-paths.test.ts`. All must pass unchanged.

### Phase 7 — Migrate dashboard page (closes #2317)

Edit `app/(dashboard)/dashboard/kb/[...path]/page.tsx`:

```ts
import { isMarkdownKbPath } from "@/lib/kb-extensions";

// ...
const joinedPath = pathSegments.join("/");
const isMarkdown = isMarkdownKbPath(joinedPath);
const extension = joinedPath.includes(".") ? `.${joinedPath.split(".").pop()?.toLowerCase()}` : "";
```

Note: The `extension` variable is still used for `<FilePreview extension={extension} />`. Verified at `components/kb/file-preview.tsx:33`: `FilePreview` internally lowercases the prop before switching on it (`const ext = extension.toLowerCase();`). So the page-level `extension` variable does NOT need `.toLowerCase()` — leave it as-is to keep the diff minimal. The only behavior change from this phase is the `isMarkdown` branch: `NOTES.MD` now correctly routes to the markdown fetch path (was: non-markdown → FilePreview with `.MD` extension → DownloadPreview fallback).

### Phase 8 — Internal: unify `kb-binary-response` classifier

In `server/kb-binary-response.ts:117`:

```ts
const ext = path.extname(relativePath).toLowerCase();
```

Change to:

```ts
import { getKbExtension } from "@/lib/kb-extensions";
// ...
const ext = getKbExtension(relativePath);
```

This completes the "one classifier everywhere" property. `path.extname` and `getKbExtension` return the same string for paths without edge cases, but `getKbExtension` is also available client-side where `node:path` is not. Single source of truth.

### Phase 9 — Route-file export audit (AGENTS.md `cq-nextjs-route-files-http-only-exports`)

Verify: `app/api/kb/content/[...path]/route.ts` and `app/api/shared/[token]/route.ts` export ONLY the `GET` HTTP handler. No helpers, no constants, no test resets. The `contentChangedResponse` and `legacyNullHashResponse` helpers currently defined in the share route at lines 26–44: move `contentChangedResponse` into `server/kb-serve.ts` (the hash-gate helper needs it); keep `legacyNullHashResponse` in the route since it's only called from the route. **Verification:** run `npm run build` in `apps/web-platform/` — if Next.js route-file validator rejects any export, fix before commit. `tsc --noEmit` does not catch this.

### Phase 10 — Run the full test + build pipeline

```bash
cd apps/web-platform
./node_modules/.bin/vitest run
./node_modules/.bin/tsc --noEmit
npm run build
```

All three must pass. The `next build` step is non-negotiable per AGENTS.md `cq-nextjs-route-files-http-only-exports`.

### Phase 11 — Verify negative-space test gate still holds

`test/kb-security.test.ts` runs structural-regex assertions on every KB route file. Specifically:

- Line 22: `expect(content).toContain("readContent")` — content route. Preserved: `readContent` now lives inside the `onMarkdown` callback, which is inline in the route source. Passes.
- Line 23: `expect(content).toContain("KbAccessDeniedError")` — content route. Preserved: still referenced in the callback's catch block. Passes.
- Lines 72–98: all KB route handlers must have either inline auth OR proven delegation to `authenticateAndResolveKbPath`. The content route keeps its inline `supabase.auth.getUser` call (workspace lookup is NOT delegated). Passes.
- Lines 101–125: all KB route handlers must have either inline `workspace_status` OR proven helper delegation. The content route keeps its inline `.select("workspace_path, workspace_status")` check. Passes.
- Lines 143–168: all KB route handlers must have inline `logger.error` OR proven tagged-union delegation. The content route's `onMarkdown` callback still includes `logger.error({ err }, "kb/content: unexpected error")`. Passes.

**Verification step:** after Phase 5 (content route migration) and Phase 6 (share route migration), run `./node_modules/.bin/vitest run test/kb-security.test.ts` explicitly. If any assertion fails, the refactor has drifted past a negative-space gate — fix the callback / route shape to preserve the pattern, do NOT weaken the test. Per learning `2026-04-15-negative-space-tests-must-follow-extracted-logic.md`, loosening the substring match on `readContent` to something like `onMarkdown` would accept dead imports, comment-only references, and callbacks that never fire.

**Do not add new regex-on-source tests.** Per learning `2026-04-17-regex-on-source-delegation-tests-trim-to-negative-space.md`, do NOT add assertions like "content route imports `serveKbFile`" or "share route invokes `serveBinaryWithHashGate`". The existing end-to-end tests (`kb-content-binary.test.ts`, `shared-token-verdict-cache.test.ts`, etc.) transitively prove delegation via mocked `validateBinaryFile` / `hashStream` / `shareHashVerdictCache`. Positive regex assertions duplicate coverage and break on harmless edits (alias imports, barrel re-exports, whitespace around `await`).

## Test Strategy

- **Unit tests (new):**
  - `test/kb-extensions.test.ts` — 10+ cases covering case fold, multi-dot, hidden files, extensionless.
  - `test/kb-serve.test.ts` — dispatch routing + `serveBinary` error paths (validate/buildBinaryResponse/BinaryOpenError).
  - `test/kb-serve-hash-gate.test.ts` — cache hit/miss, hash match/mismatch, inode drift pre-serve and mid-serve, generic `BinaryOpenError`.
- **Existing tests (regression):** All 7 existing tests listed in Files to edit #5–#9 MUST pass unchanged. Any change to their expectations indicates a behavior drift; fix the helper, not the test.
- **Contract test (#2303, out of scope):** After this PR lands, authoring "owner and shared return identical bytes + headers for same file" becomes trivial — both sides invoke the same `serveBinary`. Do NOT add this test to this PR; leave #2303 open.

## Acceptance Criteria

1. `serveBinary`, `serveKbFile`, `serveBinaryWithHashGate` exist in `server/kb-serve.ts`.
2. `getKbExtension`, `isMarkdownKbPath` exist in `lib/kb-extensions.ts`.
3. `/api/kb/content/[...path]/route.ts` GET handler is ≤ ~40 lines (workspace lookup + one `serveKbFile` call). Currently ~97 lines.
4. `/api/shared/[token]/route.ts` GET handler is shorter: the ~100 line binary+hash orchestration is reduced to a `serveBinaryWithHashGate` call; the markdown branch stays inline (hash-compare + JSON envelope is route-specific).
5. `app/(dashboard)/dashboard/kb/[...path]/page.tsx` imports `isMarkdownKbPath` instead of computing extension inline.
6. `server/kb-binary-response.ts` `validateBinaryFile` uses `getKbExtension`.
7. Full vitest suite passes (`./node_modules/.bin/vitest run`).
8. TypeScript clean (`./node_modules/.bin/tsc --noEmit`).
9. Next.js build clean (`npm run build`) — verifies route-file export validator.
10. No new dependencies in `package.json`.
11. PR body contains `Closes #2299`, `Closes #2313`, `Closes #2317`, `Closes #2483`.

## Risks

- **Log-field drift.** The share route has highly specific log field names (`event: "shared_content_mismatch"`, `kind: "binary"`, `reason: "inode-drift-serve"`). Moving the hash-gate into a helper risks a typo. **Mitigation:** tests assert the logger-mock call args exactly; reviewer visually diffs the log fields line by line.
- **Error-code drift.** `code: "content-changed"`, `code: "revoked"`, `code: "legacy-null-hash"` are contract strings the client keys on. **Mitigation:** `contentChangedResponse` / `legacyNullHashResponse` are copied verbatim with matching body shape; existing `shared-token-content-hash.test.ts` assertions cover this.
- **`BinaryOpenError` pass-through regression.** The share route's outer try/catch around `buildBinaryResponse` catches both `content-changed` (maps to 410) and generic errors (maps to err.status). If `serveBinaryWithHashGate` swallows these incorrectly, a 404 could become a 500. **Mitigation:** dedicated test cases `test/kb-serve-hash-gate.test.ts` lines 30–60.
- **Client-server import boundary.** `lib/kb-extensions.ts` must not import any server-only module. **Mitigation:** file uses only JavaScript strings; no imports needed. CI would reject a server import via Next.js build, but catch it at review time.
- **Route-file export validator.** Per AGENTS.md `cq-nextjs-route-files-http-only-exports`, only HTTP methods can be exported from route files. The current share route exports only `GET` but defines `contentChangedResponse` / `legacyNullHashResponse` as module-private functions — that's fine. **Do not** export either helper from a route file during migration. Move `contentChangedResponse` to `server/kb-serve.ts` (the only remaining share-route consumer is the markdown branch, which imports it from the new module). `legacyNullHashResponse` stays module-private in the route.
- **#2348 mock-factory drift.** If adding new named exports to `server/kb-reader` or `server/kb-binary-response` causes vitest mocks to miss a factory entry, existing tests will fail with "is not a function". **Mitigation:** run the full suite after Phase 8; if any test fails with this class of error, fix the mock factory in the test file in the same commit.

- **Negative-space test gate silent-break.** The existing `test/kb-security.test.ts` scans route files for `readContent` substring presence (line 22). If Phase 5's `onMarkdown` callback is extracted further (e.g., into `handleMarkdownContent(kbRoot, relativePath)` inside the route file), the literal `readContent` may stop appearing in route source. **Mitigation:** do NOT extract the markdown callback into a named local function; keep the `readContent(root, rel)` call inline inside the arrow-function callback. If a future maintainer wants a named callback, they must add a companion assertion on the helper file per the 2026-04-15 learning pattern. Documented in Phase 11.

- **Half-extraction / purity drift in `serveBinaryWithHashGate`.** Helper accepts `logger` + `logContext` for log emission. Risk: if a future change adds a return field like `{ response, cachedVerdict: boolean }` for observability, the route may ignore the boolean, producing the same "contract the consumer ignores" pattern that PR #2209 burned. **Mitigation:** helper-signature review during implementation — return type is strictly `Promise<Response>`. If a caller needs verdict-hit metrics, instrumentation goes in the helper, not the return type. Documented in Phase 3.

- **Positive regex-on-source test temptation.** Reviewers commonly ask for "test that confirms the route imports and calls the helper" after an extraction. These assertions duplicate behavioral-test coverage and break on aliased imports, barrel re-exports, or whitespace changes. **Mitigation:** do not add them. Phase 11 explicitly calls this out with a reference to the 2026-04-17 learning.

## Domain Review

**Domains relevant:** engineering only — pure refactor, no product/UX/marketing/legal/finance/security surface change.

No cross-domain implications detected — infrastructure/tooling change behind a stable API. The refactor is behavior-preserving; user-facing surfaces (dashboard KB viewer, shared-link recipient page) render identical output before and after.

## Research Insights

**Applied learnings:**

- `2026-04-14-pure-reducer-extraction-requires-companion-state-migration.md` — helper returns only `Response`, no side-channel fields; companion-state audit confirms `shareHashVerdictCache` has a single authority.
- `2026-04-15-negative-space-tests-must-follow-extracted-logic.md` — existing `test/kb-security.test.ts` gate verified to still pass without modification; `onMarkdown` callback keeps `readContent` inline in route source.
- `2026-04-17-regex-on-source-delegation-tests-trim-to-negative-space.md` — no new positive regex-on-source tests added. End-to-end tests transitively prove delegation.
- `2026-04-17-review-backlog-net-positive-filing.md` — mirror #2486 pattern: net-negative scope-out ledger. 4 closes, 0 new filings, all acknowledgments recorded in `## Open Code-Review Overlap`.

**Deliberately NOT applied:**

- External research (Context7 / WebSearch) — this is a pure behavior-preserving refactor in first-party TypeScript. No new library APIs, no framework migrations. External doc lookup adds zero signal.
- Product/UX specialists — engineering-only refactor, no surface change. Per `## Domain Review` section.
- `BinaryFilePayload` parameter object (#2311) — deliberately out of scope. Wait for a third caller before further abstraction (Fowler's rule of three). Helper signatures stay positional + options-object as established in current `validateBinaryFile` / `buildBinaryResponse`.

**Edge cases captured:**

- `getKbExtension(".hidden")` — leading-dot-only files (unix hidden files) return `""`. Tested.
- `getKbExtension("a.tar.gz")` — only last segment returned (`.gz`). Tested.
- `NOTES.MD` (case fold) — now correctly classified as markdown on client, matching server. Tested with dedicated assertion (regression for #2317).
- Path with no slashes (`foo.pdf`) vs path with slashes (`notes/foo.pdf`) — helper strips via `split("/").pop()`. Tested.

## PR Body (reminder for ship phase)

The PR body MUST include the following Closes lines (AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`):

```text
Closes #2299
Closes #2313
Closes #2317
Closes #2483
```

Title suggestion: `refactor(kb): shared serve-binary + dispatch + isMarkdownExt helpers`

Summary bullets:

- `serveBinary` / `serveKbFile` / `serveBinaryWithHashGate` in `server/kb-serve.ts`.
- `isMarkdownKbPath` + `getKbExtension` in `lib/kb-extensions.ts`, used by dashboard page + server.
- Owner route (`/api/kb/content`) reduced to a single `serveKbFile` call.
- Share route (`/api/shared/[token]`) delegates binary+hash orchestration to `serveBinaryWithHashGate`.
- Case-sensitivity regression closed: `NOTES.MD` now classified as markdown on client (was: non-markdown).
- Net backlog impact: 4 closures, 0 new scope-out issues. Mirrors the #2486 pattern.

Test plan:

- [ ] `./node_modules/.bin/vitest run` clean
- [ ] `./node_modules/.bin/tsc --noEmit` clean
- [ ] `npm run build` clean (route-file export validator)
- [ ] Manual smoke: owner KB page opens a PDF; shared link opens same PDF; `NOTES.MD` renders as markdown on dashboard.
