# feat: `kb_share_preview` agent tool for share view-parity

Issue: [#2322](https://github.com/jikig-ai/soleur/issues/2322)
Branch: `kb-share-preview`
Worktree: `.worktrees/kb-share-preview/`
Milestone: Phase 3: Make it Sticky
Type: feature (enhancement)
Priority: P3 — view-parity gap; create tool already returns `{ url, size }` for the common "did it work" case

## Deepening Summary

**Deepened on:** 2026-04-18
**Sources:** 5 directly-applicable learnings, the #2497 merged predecessor plan, in-codebase inspection of `server/kb-share.ts`, `server/kb-binary-response.ts`, `app/api/shared/[token]/route.ts`, and verification of `pdfjs-dist` / `sharp` availability in `apps/web-platform/node_modules`.

**Key insights applied:**

1. **Stream-response TOCTOU across fd boundary** (learning `2026-04-17-stream-response-toctou-across-fd-boundary`) — every `openBinaryStream` call in the PDF/image preview branch MUST pass `expected: { ino, size }` captured from `validateBinaryFile`. Missing `expected` on even one call reopens the rename-over-regular-file TOCTOU window. Added to the control flow spec, test 22, and a regex gate in test 34.
2. **Strong-ETag 304 short-circuit belongs upstream of the hash gate** (learning `2026-04-17-strong-etag-short-circuit-upstream-of-hash-gate`) — the route's upstream `If-None-Match` fast-path is a 304. The preview tool has no HTTP semantics, so there is no conditional-request optimization to adopt; recorded here to make the omission explicit rather than a gap.
3. **Regex-on-source delegation tests trim to negative-space only** (learning `2026-04-17-regex-on-source-delegation-tests-trim-to-negative-space`) — test 34's source-regex gate is now **negative-only**: it asserts the ABSENCE of direct `fs.open` / `isPathInWorkspace` / `fs.readFile` calls in `server/kb-share-tools.ts`. Positive `previewShare(` invocation check was removed; it is transitively proven by tests 23-28 which mock `previewShare` and assert it was called. Eliminates brittleness under legitimate refactors (aliases, barrel re-exports).
4. **KB route helper extraction cluster drain** (learning `2026-04-17-kb-route-helper-extraction-cluster-drain`) — when extracting a new helper path, run `/review` over the full cluster (all callers of the touched helpers) rather than just the changed file. Added to Phase 3 as an explicit gate.
5. **Negative-space tests must follow extracted logic** (learning `2026-04-15-negative-space-tests-must-follow-extracted-logic`) — kept for the MCP wrapper test (test 34's delegation regex). Folded with #3 above: only the negative-space assertion remains.
6. **Discriminated-union exhaustive switch miss** (learning `2026-04-10-discriminated-union-exhaustive-switch-miss`) — the wrap helper for `PreviewShareErrorCode` uses `const _exhaustive: never = result.code` to force `tsc --noEmit` errors on future code additions without wrapper updates. Same pattern PR #2497 introduced.

**pdfjs verification:** `apps/web-platform/node_modules/pdfjs-dist/legacy/build/pdf.mjs` exists. The Node-safe entry (`pdfjs-dist/legacy/build/pdf.mjs`) supports `getDocument(...).numPages` and `getPage(1).getViewport({ scale: 1 })` without requiring `canvas` — those are metadata-only operations that run on the parser, not the raster worker. Preflight step added to Phase 2 to confirm this against a real PDF fixture before wiring the tool handler.

**sharp verification:** `apps/web-platform/node_modules/sharp` is installed. `sharp(buffer).metadata()` returns `{ width, height, format, channels, ... }` synchronously-by-promise; no worker required. Safe for in-process use.

## Overview

PR [#2497](https://github.com/jikig-ai/soleur/pull/2497) shipped create/list/revoke parity (`kb_share_create`, `kb_share_list`, `kb_share_revoke`) and explicitly deferred `kb_share_preview` to this issue. The gap:

- After `kb_share_create` returns a URL, the agent has no way to **verify the link renders the way a recipient sees it** — e.g., the PDF came back with the right `Content-Type`, the filename was not mangled, the 50 MB size guard did not reject it.
- If a user asks "double-check the share link still works," the agent today cannot answer without asking the user to open the browser.
- `GET /api/shared/[token]` is **public** (throttled only, no auth — see `apps/web-platform/app/api/shared/[token]/route.ts`), but the agent sandbox has `allowedDomains: []`, so a `curl` from a Bash tool call would be blocked.

This PR adds a fourth in-process MCP platform tool — `kb_share_preview` — that **server-side fetches the share endpoint as a recipient would** and returns `{ status, contentType, size, filename, kind, revoked? }` plus an optional `firstPagePreview` for PDFs (dimensions only — no bytes). The tool runs inside `agent-runner.ts`, reuses `validateBinaryFile` + `readContentRaw` via the share-token lookup, and does NOT duplicate the traversal / hash-gate logic.

The implementation pattern — thin MCP wrapper → shared server helper → validation via `kb-share.ts` / `kb-binary-response.ts` — mirrors the #2497 extraction. No new HTTP surface is added; the browser-facing `/api/shared/[token]` route is untouched.

## Acceptance Criteria

From issue #2322:

- [x] Agent can call `kb_share_preview({ token })` and receive `{ status, contentType, size, filename, firstPagePreview? }`.
- [x] Preview tool reuses `readBinaryFile` (via `validateBinaryFile`) + `readContentRaw` via the token lookup — no duplicate traversal logic.

Expanded for completeness:

- [x] Tool surfaces the same terminal states `/api/shared/[token]` produces (200 success, 410 revoked, 410 content-changed, 410 legacy-null-hash, 404 not-found, 403 access-denied, 413 too-large) with the token never leaked in logs or error strings.
- [x] Tool is registered in `agent-runner.ts` alongside the three existing kb-share tools; tier is `auto-approve` (read-only, mirrors `kb_share_list`).
- [x] System-prompt "## Knowledge-base sharing" block is updated to advertise the preview tool so the agent discovers it from natural-language requests ("double-check that link still works").
- [x] Test coverage for each terminal state plus two happy paths (markdown, binary) and the first-page PDF preview branch.
- [x] All existing share tests (`kb-share.test.ts`, `kb-share-tools.test.ts`, `shared-token-content-hash.test.ts`, etc.) pass unchanged.

## Research Reconciliation — Spec vs. Codebase

| Spec Claim (issue #2322) | Codebase Reality | Plan Response |
|---|---|---|
| "A `kb_share_preview` platform tool that server-side fetches the share endpoint and returns headers + size + first-page render" | No fetch needed — the share endpoint itself is just `kb-share.ts` lookup + `validateBinaryFile` + `readContentRaw`. Calling that wire path in-process re-validates but wastes the HTTP layer; we can call the same helpers directly for a much cheaper + simpler result. | Build `previewShare()` in `server/kb-share.ts` (next to `createShare` / `listShares` / `revokeShare`) that takes `(serviceClient, token)` and returns a tagged-union `PreviewShareResult`. The MCP tool is a thin wrapper in `kb-share-tools.ts`. No HTTP fetch, no network egress. |
| "Preview tool reuses `readBinaryFile` + `readContent` via the token lookup — no duplicate traversal logic" | `readBinaryFile` in the issue maps to `validateBinaryFile` (`server/kb-binary-response.ts`). `readContent` maps to `readContentRaw` / `readContent` (`server/kb-reader.ts`). Both already enforce null-byte, `isPathInWorkspace`, `O_NOFOLLOW`, size, symlink checks. | `previewShare()` calls these helpers. It MUST NOT re-implement path containment, symlink rejection, size caps, or null-byte handling. |
| "First-page preview (PDFs via pdfjs, images via dimensions)" | `pdfjs-dist` is installed (`apps/web-platform/node_modules/pdfjs-dist`); `sharp` is installed for image ops. But pdfjs rendering on Node requires `canvas` or `node-canvas`, which is heavyweight and brittle in Docker; page-count + dimensions via `pdfjs.getDocument(...).numPages` and `.getPage(1).getViewport({ scale: 1 })` are CHEAP and sufficient for the agent's "did it work" verification. | Scope the `firstPagePreview` field to `{ numPages, width, height }` (pdfjs metadata, no raster). For images, use `sharp(buffer).metadata()` for `{ width, height, format }`. Rasterization is out of scope (a new dependency with build-time implications). |
| "GET `/api/shared/[token]` is public (throttled by `shareEndpointThrottle`)" | Rate-limit is IP-keyed. The MCP tool runs in-process without an IP; the rate-limiter does NOT apply. Conversely, the share-row lookup + hash-gate are the enforcement layer that matters. | `previewShare()` re-runs the same ownership-agnostic lookup the public route does (`token` → share row). Revoked, legacy-null-hash, workspace-unavailable, and content-changed all produce the same tagged-union terminal states the route returns, so telemetry keys on `code` are consistent across surfaces. |
| "Rich output that helps agent verify success" (agent-native-reviewer principle) | Existing platform tools use `{ content: [{ type: "text", text: JSON.stringify(result) }] }`. | Tool returns `{ status: 200, token, documentPath, kind: "markdown" \| "binary", contentType, size, filename, firstPagePreview? }` on success; `{ status, code, error }` on failure. Wrapped in the platform-tool text shape. |

## Open Code-Review Overlap

Four open code-review issues touch files this plan will modify. Disposition:

| Issue | Title | Files | Disposition | Rationale |
|---|---|---|---|---|
| **#2512** | review: add `conversations_lookup` MCP tool (+ list/archive follow-ups) | `agent-runner.ts` | **Acknowledge** | Unrelated domain (conversations, not KB shares). This PR registers one more tool in the same block; #2512 will register its own when it lands. No merge conflict risk — both insert after the KB-share block. |
| **#2335** | review: add unit tests for `canUseTool` callback allow/deny shape | `agent-runner.ts` | **Acknowledge** | Pre-existing test-scaffold concern. This PR adds one tier entry and exercises the new tool end-to-end in integration tests but does NOT add the callback-shape unit test #2335 asks for. |
| **#1662** | review: extract MCP tool definitions from `agent-runner` when 2nd tool added | `agent-runner.ts` | **Acknowledge** | This PR follows the correct extraction pattern — the preview tool lives in `server/kb-share-tools.ts` (already extracted in #2497), not inlined. Does not close #1662, which tracks the remaining inline tools (`createPr`, `plausible_*`). |
| **#2329** | perf(kb): fix Cache-Control for /shared/ binaries + add ETag/304 handling | `kb-binary-response.ts` | **Acknowledge** | Pure HTTP-response concern. `previewShare()` only calls `validateBinaryFile` (already extracted); it never emits HTTP headers. Unaffected by #2329. |

No scope-outs are folded in. The only rationale for folding in would be shared files AND shared concerns; none of these issues is in the preview tool's domain.

## Design

### Files to Create

1. **`apps/web-platform/test/kb-share-preview.test.ts`** — Unit tests for `previewShare()` in `server/kb-share.ts` (happy path markdown, happy path binary, revoked, content-changed, legacy-null-hash, workspace-unavailable, not-found, access-denied, too-large, invalid-path, symlink-rejected, pdf-preview metadata, image-preview metadata).
2. **`apps/web-platform/test/kb-share-preview-tools.test.ts`** — Unit tests for the `kb_share_preview` MCP wrapper (input validation, success shape, `isError` on failure, URL shape not leaked beyond `documentPath`).
3. **`apps/web-platform/test/agent-runner-kb-share-preview.test.ts`** — Integration test: tool is registered in `agent-runner.ts` and appears in `platformToolNames` and `TOOL_TIER_MAP` with `auto-approve`.

### Files to Edit

1. **`apps/web-platform/server/kb-share.ts`** — Add `previewShare()` function + `PreviewShareResult` tagged union + `PreviewShareErrorCode` literal union. Wire Sentry-mirrored logging via `reportSilentFallback`. Export alongside the existing three functions.
2. **`apps/web-platform/server/kb-share-tools.ts`** — Add a fourth `tool(...)` call in `buildKbShareTools()` for `kb_share_preview`. Export a new `wrapPreview()` helper.
3. **`apps/web-platform/server/agent-runner.ts`** — Append `"mcp__soleur_platform__kb_share_preview"` to `platformToolNames.push(...)` (around L863-867). Extend the system-prompt "## Knowledge-base sharing" block with a one-paragraph description of the preview capability.
4. **`apps/web-platform/server/tool-tiers.ts`** — Add `"mcp__soleur_platform__kb_share_preview": "auto-approve"` to `TOOL_TIER_MAP`. No `buildGateMessage` case needed — auto-approve bypasses the gate entirely (matches `kb_share_list`).

### `server/kb-share.ts` — New `previewShare()` Interface

```ts
// Added alongside createShare / listShares / revokeShare.

export type PreviewShareErrorCode =
  | "not-found"         // share row missing or workspace not ready
  | "revoked"           // share row revoked
  | "legacy-null-hash"  // pre-#2326 row, no content hash stored
  | "content-changed"   // disk state drifted from stored hash
  | "access-denied"     // null-byte / path-escape / symlink — unreachable for valid shares, but defense in depth
  | "too-large"         // file exceeds MAX_BINARY_SIZE — unreachable if share row exists, but defense in depth
  | "invalid-path"      // documentPath failed validation post-lookup — defense in depth
  | "db-error";

export interface FirstPagePreview {
  // Populated when the file is PDF or image. PDF uses pdfjs-dist
  // getDocument().getPage(1) metadata; image uses sharp(buffer).metadata().
  // No raster bytes returned — scale-independent dimensions only.
  kind: "pdf" | "image";
  width: number;
  height: number;
  numPages?: number; // PDF only
  format?: string;   // image only: sharp-detected format
}

export type PreviewShareResult =
  | {
      ok: true;
      status: 200;
      token: string;
      documentPath: string;
      kind: "markdown" | "binary";
      contentType: string;
      size: number;
      filename: string;
      firstPagePreview?: FirstPagePreview;
    }
  | {
      ok: false;
      status: 404 | 403 | 410 | 413 | 500;
      code: PreviewShareErrorCode;
      error: string;
    };

/**
 * Preview what a recipient sees at /shared/[token]. Runs the same
 * ownership-agnostic share-row lookup + hash gate as the public HTTP
 * route. Returns metadata (no bytes) for the agent to verify the link
 * renders correctly. Called by the kb_share_preview MCP tool.
 *
 * Reuses validateBinaryFile + readContentRaw via the stored document
 * path; does NOT re-implement traversal / null-byte / symlink checks.
 */
export async function previewShare(
  serviceClient: ShareServiceClient,
  token: string,
  kbRootResolver: (workspacePath: string) => string = (w) => path.join(w, "knowledge-base"),
): Promise<PreviewShareResult>;
```

**Reuse contract (acceptance criteria, line 2):**

- Markdown branch: call `readContentRaw(kbRoot, documentPath)` → get `{ buffer }` → `hashBytes(buffer)` → compare against `content_sha256` → on match, return `{ kind: "markdown", contentType: "text/markdown", size: buffer.length, filename: basename }`.
- Binary branch: call `validateBinaryFile(kbRoot, documentPath)` → get `{ size, contentType, rawName, ino, mtimeMs, filePath }` → run the same `shareHashVerdictCache` + on-miss `hashStream` gate the HEAD handler uses (`app/api/shared/[token]/route.ts` L320-366). **The `openBinaryStream` call for the hash pass MUST pass `expected: { ino, size }`** per learning `2026-04-17-stream-response-toctou-across-fd-boundary` — this fstat-verifies the fd before draining and throws `BinaryOpenError("content-changed")` on inode or size drift. Verdict-cache key is `(token, ino, mtimeMs, size)` — `ino` is the coarse-mtime-swap defense.
- First-page preview: after the hash gate, if `contentType === "application/pdf"` or `deriveBinaryKind(binary) === "image"`, open a **second** `openBinaryStream(filePath, { expected: { ino, size } })` (the hash pass stream is drained + closed; preview needs fresh bytes). The `expected` guard MUST fire on this call too — per the TOCTOU learning, missing the pass on any open reopens the window. Pipe into pdfjs / sharp. Silent-fallback to `firstPagePreview: undefined` on any parse error — the tool still returns `{ ok: true }` so the agent gets the core metadata.

### `previewShare()` Control Flow

```text
previewShare(serviceClient, token):
  1. Look up share row by token (SELECT document_path, revoked, content_sha256,
     users!inner(workspace_path, workspace_status) WHERE token = ? LIMIT 1).
     — mirrors prepareSharedRequest() in app/api/shared/[token]/route.ts L108-192
  2. If row missing → { status: 404, code: "not-found" }.
  3. If row.revoked → { status: 410, code: "revoked" }.
  4. If row.content_sha256 is null → { status: 410, code: "legacy-null-hash" }.
  5. If owner.workspace_status !== "ready" OR workspace_path null → { status: 404, code: "not-found" }.
  6. kbRoot = kbRootResolver(workspace_path).
  7. If isMarkdownKbPath(document_path):
       a. { buffer } = await readContentRaw(kbRoot, document_path).
       b. currentHash = hashBytes(buffer).
       c. If currentHash !== row.content_sha256 → { status: 410, code: "content-changed" }.
       d. Return { ok: true, kind: "markdown", contentType: "text/markdown",
                   size: buffer.length, filename: basename(document_path), ... }.
     Else (binary):
       a. meta = await validateBinaryFile(kbRoot, document_path).
       b. Run hash gate: verdict cache → on-miss openBinaryStream with { expected }
          → hashStream → compare against row.content_sha256.
       c. On mismatch or BinaryOpenError("content-changed") → { status: 410, code: "content-changed" }.
       d. If pdf / image, attempt firstPagePreview (silent-fallback on parse error).
       e. Return { ok: true, kind: "binary", contentType: meta.contentType,
                   size: meta.size, filename: meta.rawName, firstPagePreview?, ... }.
  8. Errors are mapped via a single mapPreviewError() helper that mirrors
     mapSharedError() in the route (KbAccessDeniedError → 403 access-denied,
     KbNotFoundError → 404 not-found, KbFileTooLargeError → 413 too-large,
     BinaryOpenError("content-changed") → 410 content-changed, default →
     reportSilentFallback + 500 db-error).
```

**Error-code discriminant (exhaustiveness guard).** The MCP tool's wrap function uses the `const _exhaustive: never = result.code;` pattern so any future `PreviewShareErrorCode` addition without a wrapper update fails `tsc --noEmit`. Applies learning `2026-04-10-discriminated-union-exhaustive-switch-miss`.

### `server/kb-share-tools.ts` — New Tool

Insert after `kb_share_revoke` in `buildKbShareTools()` (before the closing `]`):

```ts
tool(
  "kb_share_preview",
  "Preview what a recipient sees at /shared/<token>. Returns " +
    "{ status, contentType, size, filename, kind, firstPagePreview? }. " +
    "Use this to verify a share link renders correctly before sending it. " +
    "Works for all share terminal states — revoked links return " +
    "{ error: 'revoked' }, content-drift returns { error: 'content-changed' }. " +
    "Does NOT return the document bytes (use kb_read_content for that).",
  { token: z.string() },
  async (args) =>
    wrapPreview(await previewShare(serviceClient, args.token)),
),
```

`wrapPreview()` follows the existing `wrapCreate` / `wrapList` / `wrapRevoke` pattern — success → JSON stringify payload; failure → `{ error, code, status }` with `isError: true`.

### `agent-runner.ts` — Wiring

Insertion: modify `platformToolNames.push(...)` at L863-867 to include the new tool:

```ts
platformToolNames.push(
  "mcp__soleur_platform__kb_share_create",
  "mcp__soleur_platform__kb_share_list",
  "mcp__soleur_platform__kb_share_revoke",
  "mcp__soleur_platform__kb_share_preview",
);
```

Modify the "## Knowledge-base sharing" system-prompt block (L542-564) to append:

```text
Use kb_share_preview({ token }) to verify a link renders correctly before
sending it to someone. It returns the same metadata a recipient's browser
would see (contentType, size, filename, kind, and for PDFs/images a
firstPagePreview with dimensions and page count). Revoked or content-drifted
links surface the same terminal state the public endpoint would return. This
is the right tool when the user asks "double-check the link still works" or
"tell me how many pages that PDF is."
```

### Tool Tier Mapping (`server/tool-tiers.ts`)

```ts
// Read-only — reveals metadata only, no bytes, no state change.
"mcp__soleur_platform__kb_share_preview": "auto-approve",
```

Auto-approve rationale: preview is strictly metadata; it never exposes document bytes (only dimensions and page count) and never mutates DB state. Matches `kb_share_list` and `github_read_ci_status`. No `buildGateMessage` case is added — auto-approve tools bypass the gate entirely.

## Test Scenarios (TDD — write RED tests first)

Per `cq-write-failing-tests-before`, tests are authored and observed to FAIL before implementation lands.

### `test/kb-share-preview.test.ts` — `previewShare()` unit

**Lookup / row-state branches:**

1. **Unknown token** → returns `{ ok: false, status: 404, code: "not-found" }`.
2. **Revoked row** → returns `{ ok: false, status: 410, code: "revoked" }`.
3. **Legacy null hash** (pre-#2326 row) → returns `{ ok: false, status: 410, code: "legacy-null-hash" }`.
4. **Workspace not ready** (workspace_status != "ready") → returns `{ ok: false, status: 404, code: "not-found" }`.
5. **Workspace path null** → returns `{ ok: false, status: 404, code: "not-found" }`.
6. **DB error during lookup** → returns `{ ok: false, status: 500, code: "db-error" }` and `reportSilentFallback` fires once.

**Markdown branch:**

7. **Markdown happy path, hash matches** → returns `{ ok: true, kind: "markdown", contentType: "text/markdown", size, filename }`.
8. **Markdown content drift** (on-disk buffer hash != stored) → returns `{ ok: false, status: 410, code: "content-changed" }`.
9. **Markdown missing from disk** (after DB lookup succeeded) → returns `{ ok: false, status: 404, code: "not-found" }` via `KbNotFoundError` mapping.
10. **Markdown path with null byte** (corrupted share row) → returns `{ ok: false, status: 403, code: "access-denied" }` via `KbAccessDeniedError` mapping.

**Binary branch:**

11. **Binary happy path, hash matches** → returns `{ ok: true, kind: "binary", contentType: "application/pdf", size, filename: "report.pdf" }`.
12. **Binary content drift** (stream hash != stored) → returns `{ ok: false, status: 410, code: "content-changed" }`.
13. **Binary inode drift between validate and hash** (`BinaryOpenError("content-changed")`) → returns `{ ok: false, status: 410, code: "content-changed" }`.
14. **Binary over `MAX_BINARY_SIZE`** (defense in depth — should be unreachable for valid share) → returns `{ ok: false, status: 413, code: "too-large" }`.
15. **Binary symlink** (corrupted on-disk state) → returns `{ ok: false, status: 403, code: "access-denied" }` via `KbAccessDeniedError`.

**First-page preview branch:**

16. **PDF with pdfjs metadata** → `firstPagePreview` is `{ kind: "pdf", width, height, numPages }` with `numPages >= 1`.
17. **PDF parse failure** (corrupted PDF bytes) → returns `{ ok: true, ... }` with `firstPagePreview: undefined` (silent-fallback; core metadata still returned).
18. **Image with sharp metadata** → `firstPagePreview` is `{ kind: "image", width, height, format: "png" | ... }`.
19. **Image parse failure** → `{ ok: true, ... }` with `firstPagePreview: undefined`.
20. **Non-PDF, non-image binary** (e.g., `.docx`) → returns `{ ok: true, ... }` with NO `firstPagePreview` field (not defined, not `undefined`).

### `test/kb-share-preview.test.ts` — mock-shape assertions (learning 2026-04-10-cicd-mcp-tool-tiered-gating)

21. **Supabase lookup asserts token filter.** Every mock assertion in the lookup path MUST verify `.eq("token", token)` was called with the expected argument — prevents "mock returns data for any query" silent-pass (per the `kb-share.test.ts` pattern).
22. **Fresh `openBinaryStream` per hash gate.** The binary branch MUST open a new stream with `expected: { ino, size }` — assert via spy, same invariant the HEAD handler enforces.

### `test/kb-share-preview-tools.test.ts` — MCP wrapper unit

23. **Registers `kb_share_preview` as the fourth tool** — `buildKbShareTools(...).map(t => t.name)` contains `"kb_share_preview"`.
24. **Wraps success with `{ ok: true }` JSON** — handler returns `{ content: [{ type: "text", text }], isError: undefined }` with `JSON.parse(text).kind` defined.
25. **Wraps revoked with `isError: true`** — `JSON.parse(text).code === "revoked"`.
26. **Wraps content-changed with `isError: true`** — `JSON.parse(text).code === "content-changed"`.
27. **Wraps not-found with `isError: true`** — `JSON.parse(text).code === "not-found"`.
28. **Does not leak raw token into error text** beyond the `previewShare()` return value (telemetry / log call sites receive hashed or prefix-only tokens, mirroring #2322 privacy posture).

### `test/agent-runner-kb-share-preview.test.ts` — integration

29. **Tool is registered** when `startAgentSession` reaches the MCP server build step (workspace ready, same harness as `agent-runner-kb-share-tools.test.ts`).
30. **`platformToolNames` includes `mcp__soleur_platform__kb_share_preview`.**
31. **Tier lookup** via `getToolTier("mcp__soleur_platform__kb_share_preview")` returns `"auto-approve"`.
32. **System prompt contains the `kb_share_preview` mention** (regex match on "kb_share_preview" in `options.systemPrompt`).
33. **Not registered when workspace is not ready** — defense in depth, agent-runner no-ops rather than registering against undefined `kbRoot` (same invariant as #2497 test 32).

### Post-extraction negative-space gates (learnings `2026-04-15-negative-space-tests-must-follow-extracted-logic` + `2026-04-17-regex-on-source-delegation-tests-trim-to-negative-space`)

**Design note:** Positive delegation assertions (import present, `previewShare(` called, `{ok: false}` early-returned) are **transitively proven** by the mocked-behavior tests 23-28 (which mock `previewShare` and assert it was called with the right token AND that the wrapper returns `isError: true` on each `ok: false` shape). Per the trim-to-negative-space learning, keeping them as source-regex assertions adds brittleness under legitimate refactors (barrel re-exports, symbol aliases, formatting) without unique coverage. We keep only the negative-space assertion, which has no behavioral equivalent.

34. **`server/kb-share-tools.ts` has NO direct filesystem or path-validation imports.** Source regex rejects `from "node:fs"`, `from "fs"`, `isPathInWorkspace`, `validateBinaryFile`, `readContentRaw`, `path.join` (last one is conservative — the baseUrl concat is a string, not a path join). All filesystem + validation work happens in `server/kb-share.ts`, where the existing helpers are reused. This gate catches the exact failure mode the issue's acceptance criterion calls out ("no duplicate traversal logic") and cannot be replicated behaviorally — a future PR could add an inline `fs.open(...)` alongside the `previewShare(` call and all mocked-behavior tests would still pass.

### HTTP route regression (no-op regression check)

35. **`test/shared-token-*.test.ts`** — MUST pass unchanged. These exercise the public HTTP route; the preview tool is additive and must not alter that surface. A change here signals an accidental regression.

### Manual QA (covered in Phase 4)

- Log in as a test user, start a conversation, create a share link for `README.md` via `kb_share_create`, capture the token, then ask "preview share token `<token>`". Expect the agent to invoke `kb_share_preview` (auto-approved, no gate), return `{ contentType: "text/markdown", size, filename: "README.md", kind: "markdown" }`.
- Repeat with a committed PDF under `knowledge-base/` → expect `firstPagePreview: { kind: "pdf", numPages, width, height }`.
- Revoke the share via `kb_share_revoke`, then ask the agent to preview again → expect `{ code: "revoked", status: 410 }` surfaced to the user.
- Edit the source markdown file, then preview → expect `{ code: "content-changed", status: 410 }`.
- Preview an unknown token → expect `{ code: "not-found", status: 404 }`.

## Security Considerations

- **No expanded attack surface.** `previewShare()` runs the **identical** validation pipeline as the public `/api/shared/[token]` route — same share-row lookup, same revoked/null-hash gates, same `validateBinaryFile` / `readContentRaw` helpers, same `shareHashVerdictCache` hash gate. The tool is a metadata-only projection of what the route would return; if the route refuses to serve, preview refuses too.
- **Rate-limit not applicable.** The route's `shareEndpointThrottle` is IP-keyed; the MCP tool runs in-process without an IP. The enforcement that matters — revoked, content-changed, workspace-unavailable — is preserved. If DoS concerns arise later, we can add a per-user token-preview quota in `agent-runner.ts`; no need now because the tool is called at most a few times per user turn.
- **Auto-approve tier rationale.** Preview returns metadata (contentType, size, filename, page count, image dimensions). It does **not** return document bytes. Metadata for the user's own share links is strictly less sensitive than the public URL itself (which, by construction, is already intended to be shared). Gating this would produce consent fatigue without any security benefit.
- **Token privacy.** The token itself is never logged or echoed beyond the share-row lookup. Error responses use stable `code` strings (`revoked`, `content-changed`, etc.) rather than echoing the token. Matches the route's privacy posture.
- **Silent-fallback Sentry mirroring** (per `cq-silent-fallback-must-mirror-to-sentry`): every `catch` in `previewShare()` and the PDF/image preview branches uses `reportSilentFallback(err, { feature: "kb-share", op: "preview", extra: { tokenPrefix } })` where `tokenPrefix` is the first 8 chars of the token so Sentry can correlate without storing the full token.

## Non-Goals (Deferred — Tracking Issues Required)

- **Raster first-page render** (PNG/JPEG bytes of page 1 for the agent to display). Rationale: pdfjs rendering on Node requires `canvas` / `node-canvas`, a native dep with Docker-build implications. Dimensions + page count are sufficient for the agent's "did it work" verification. If users ever want actual previews surfaced into the conversation, open a follow-up issue — deferral is explicit, not forgotten.
- **Preview for share links owned by OTHER users.** The public route is ownership-agnostic (anyone with the token can view); for symmetry this tool is too. If the product later wants "agent can only preview the user's own links," add a `user_id` scope clause in `previewShare()` — one-line change, own PR.
- **Bytes in the tool response.** The issue explicitly limits the tool to metadata. If the agent ever needs raw bytes, it should use the existing `kb_read_content` tool (once it lands) or the user should `curl` the share URL. Keeping bytes out of this tool prevents consent-fatigue footguns for sensitive files.

No new GitHub issues filed for these deferrals — they are explicit Non-Goals for this PR, not separate features awaiting prioritization. If a user reports one of them as a gap, the issue will be created then.

## Implementation Phases

### Phase 1 — RED: Write failing tests

1. Author tests 1-22 in `test/kb-share-preview.test.ts` (driving the `previewShare()` interface).
2. Author tests 23-28 in `test/kb-share-preview-tools.test.ts`.
3. Author tests 29-33 in `test/agent-runner-kb-share-preview.test.ts`.
4. Author test 34 (negative-space delegation gate) inline with #2.
5. Run `cd apps/web-platform && ./node_modules/.bin/vitest run kb-share-preview kb-share-preview-tools agent-runner-kb-share-preview` — expect RED across all new files.

### Phase 2 — GREEN: Implement `previewShare()` + wire MCP tool

1. Add `PreviewShareErrorCode`, `PreviewShareResult`, `FirstPagePreview` exports to `server/kb-share.ts`.
2. Implement `previewShare()` following the control flow spec above. Import `readContentRaw`, `hashBytes`, `validateBinaryFile`, `openBinaryStream`, `hashStream`, `BinaryOpenError`, `KbAccessDeniedError`, `KbNotFoundError`, `KbFileTooLargeError` from existing modules. No new validation logic.
3. Extract `mapPreviewError()` as a private helper mirroring `mapSharedError()` in the route.
4. Add pdfjs + sharp metadata branches. Use silent-fallback — on any parse error, log via `reportSilentFallback` and return `{ ok: true }` without `firstPagePreview`. Do NOT fail the whole tool call.
5. Add `wrapPreview()` to `server/kb-share-tools.ts` and append the fourth `tool(...)` call in `buildKbShareTools()`.
6. Add the tier entry in `server/tool-tiers.ts`.
7. Extend `platformToolNames.push(...)` in `agent-runner.ts` to include the new tool.
8. Extend the system-prompt "## Knowledge-base sharing" block with the preview paragraph.
9. Run all new tests — expect GREEN.

### Phase 3 — REFACTOR + contract check

1. Grep `server/kb-share.ts` + `server/kb-share-tools.ts` for any traversal / symlink / null-byte / `isPathInWorkspace` / `fs.open` calls added by this PR. Expected: zero NEW call sites in `kb-share-tools.ts`; `kb-share.ts` gains new usages of the existing helpers (`validateBinaryFile`, `readContentRaw`, `openBinaryStream`) but ZERO new `fs.open` / `isPathInWorkspace` calls.
2. **`expected:` guard audit.** Grep every `openBinaryStream(` call introduced by this PR and verify each passes `expected: { ino, size }`. Per the TOCTOU learning, missing the guard on any call reopens the window. Target: `rg "openBinaryStream\(" apps/web-platform/server/kb-share.ts` returns only calls that include `expected:`.
3. **Cluster-drain review** (per learning `2026-04-17-kb-route-helper-extraction-cluster-drain`). Run `/review` over the full cluster of callers, not just the changed file: `app/api/shared/[token]/route.ts` (public route), `app/api/kb/content/[...path]/route.ts` (KB binary content), `app/api/kb/share/route.ts` (create), `app/api/kb/share/[token]/route.ts` (revoke). Verify none of these have broken invariants after the `kb-share.ts` additions. Acceptance: all four route files pass `/review` without any new findings.
4. Run full vitest suite in `apps/web-platform/`: `cd apps/web-platform && ./node_modules/.bin/vitest run`. Must be green.
5. Run `npx tsc --noEmit` from `apps/web-platform/` — no type errors (especially the exhaustive-switch guard).
6. Run `npx markdownlint-cli2 --fix knowledge-base/project/plans/2026-04-18-feat-kb-share-preview-tool-plan.md` before committing.

### Phase 4 — Manual QA

Follow the Manual QA steps above. Capture screenshots of:

1. Agent preview response for markdown.
2. Agent preview response for PDF (including `firstPagePreview.numPages`).
3. Agent response to preview of a revoked link.
4. Agent response to preview of a content-drifted link.

Attach all four to the PR as review evidence.

## Rollback

Single-commit scope for Phase 2; if regressions surface:

1. Revert the commit that added `previewShare()` and the MCP wrapper. Agent loses the preview capability; create / list / revoke unaffected.
2. No DB migrations. No new env vars. No new dependencies. Revert is pure code.

## Environment & Dependencies

- **No new npm deps.** `pdfjs-dist` and `sharp` are already installed (`apps/web-platform/node_modules/pdfjs-dist`, `apps/web-platform/node_modules/sharp`). Verified via `ls apps/web-platform/node_modules | grep -E '^(pdfjs|sharp)'`.
- **No new env vars.** Tool uses the same `createServiceClient()` and `path.join(workspacePath, "knowledge-base")` the existing share tools do.
- **No new Supabase migrations.** `kb_share_links` table reused exactly as-is.
- **pdfjs-dist on Node — use the legacy entry.** Import from `pdfjs-dist/legacy/build/pdf.mjs` (confirmed present at `apps/web-platform/node_modules/pdfjs-dist/legacy/build/pdf.mjs`). The default `pdfjs-dist` entry assumes a browser `Worker` and will fail under Node with `ReferenceError: DOMMatrix is not defined`. The legacy entry is the Node-safe surface that `react-pdf` itself pulls for SSR. `pdfjs.getDocument({ data: new Uint8Array(buffer), disableWorker: true, isEvalSupported: false }).promise.then(d => d.numPages)` + `d.getPage(1).getViewport({ scale: 1 })` work without `canvas` — these are parser-only operations.
- **pdfjs preflight task (Phase 2).** Before writing the `firstPagePreview` branch, run a one-shot preflight in `apps/web-platform/test/fixtures/` (or a `tsx` scratch script): load a 2-page PDF fixture, call `getDocument` with the legacy entry + `disableWorker: true`, assert `numPages === 2` and `viewport.width > 0`. This confirms the exact call form works in the pinned `pdfjs-dist` version before wiring the tool handler. Per sharp-edge "When a plan prescribes a specific CLI invocation form… the preflight task MUST exercise the exact form with realistic input."
- **pdfjs memory cap.** `getDocument` parses the entire buffer into a JS object graph. For a 50 MB PDF the peak JS-heap footprint can be 200-300 MB. Acceptable for occasional agent-initiated previews (not batched); out-of-scope for future scenarios. If preview is called in a tight loop, we should add per-user quota — noted as a defer, not a Phase-2 change.

## Progressive-Rendering Assessment

Per `cq-progressive-rendering-for-large-assets`, this feature is **exempt** from progressive loading:

- (a) Range/Accept-Ranges: N/A — tool returns metadata, not bytes.
- (b) Progressive render: N/A — response is a small JSON payload.
- (c) Progress indicator: N/A — the agent conversation naturally displays "calling kb_share_preview" via the SDK's tool-call UI.
- (d) Large-asset handling: the underlying 50 MB file is hashed via `hashStream` (already streaming), never held in memory as one `Buffer`. PDF metadata is parsed from the first ~100 KB of the file by pdfjs, not the full 50 MB. No regression from the existing route.

## Domain Review

**Domains relevant:** Engineering (CTO)

Fresh assessment run: this PR adds one MCP tool that returns metadata. No user-facing UI, no marketing copy, no legal / financial / ops / sales / support implications. The brainstorm carry-forward does not apply — no brainstorm was authored for this P3 follow-up (sister PR #2497's brainstorm addressed the create/list/revoke parity but explicitly deferred preview).

### Engineering (CTO)

**Status:** reviewed (inline — no agent delegation needed; pattern is well-established by #2497)
**Assessment:** The extraction pattern (new function in `server/kb-share.ts`, new tool in `server/kb-share-tools.ts`, one line in `agent-runner.ts`, one line in `tool-tiers.ts`) is the canonical in-repo pattern for adding MCP tools. Precedents: `kb_share_create/list/revoke` (#2497 verbatim), `github_read_ci_status`, `plausible_get_stats`. Risk is low — all validation logic is REUSED (`validateBinaryFile`, `readContentRaw`, `shareHashVerdictCache`), not duplicated. Agent-runner changes are two-line additions within an existing block. The `cq-nextjs-route-files-http-only-exports` rule is respected (no route files modified).

### Product (CPO) — Product/UX Gate

**Tier:** NONE

**Rationale:** No new user-facing pages, components, flows, or UI surfaces. The agent's new behavior surfaces through the existing conversation UI as a tool call + text response. The mechanical BLOCKING-escalation check (new files under `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`) is negative — only `server/` + `test/` files are created or edited.

UX artifacts are not required.

## SpecFlow

The user flow "user asks agent to verify a share link" has three states:

1. **Prompt** — "double-check that share link still works." Covered: system prompt block tells the agent what tool to call and when.
2. **Call** — Agent invokes `kb_share_preview({ token })`, receives metadata, surfaces to user in conversation. No review gate (auto-approve). Covered.
3. **Follow-up** — If `firstPagePreview.numPages === 42`, agent can say "yep, the 42-page PDF renders." If `code === "revoked"`, agent says "that link was revoked — want me to create a new one?" Covered by tool response shape.

Dead ends identified and handled:

- **Agent calls preview with a malformed token** (e.g., user pastes a URL instead of a token). Mitigation: tool returns `{ code: "not-found", status: 404 }` via the Supabase lookup's `null` row case. Agent surfaces the error.
- **Agent calls preview on a share that has since been content-drifted.** Returns `{ code: "content-changed", status: 410 }`. Agent can suggest recreating the share.
- **Agent calls preview on an attachment-extension file (`.docx`) where the content-type is `attachment`.** Preview returns `contentType: "application/octet-stream"` or similar + `kind: "binary"` + NO `firstPagePreview` (docx is neither PDF nor image). Agent correctly reports "it's a download link, not a preview."
- **Agent calls preview repeatedly in a loop.** No rate limit in-process; fine. Per-user quota can be added later if observed.

## Implementation Notes

- **Why `previewShare()` accepts a `kbRootResolver` closure.** Tests can inject a fixture path without mocking `path.join`. Production uses the default `(w) => path.join(w, "knowledge-base")` to match the HTTP route's `prepareSharedRequest()` at L188. Keeps the production call site one-line while tests stay readable.
- **Why `firstPagePreview` is optional, not required.** Markdown files have no concept of a first page. `.docx` downloads don't parse via pdfjs/sharp. Returning `undefined` (absent) is semantically cleaner than a nullable field, and the MCP tool's JSON serialization omits undefined keys.
- **Why `wrapPreview()` uses the same tagged-union discriminant.** Consistency with `wrapCreate / wrapList / wrapRevoke`. One exhaustive-switch guard per wrapper; `tsc --noEmit` enforces completeness across the whole `kb-share-tools.ts` module.
- **Why we do NOT fetch `/api/shared/[token]` via `fetch()`.** (a) No HTTP origin in-process; (b) re-validates what we just validated via `validateBinaryFile`; (c) adds a network hop that the sandbox's `allowedDomains: []` would block anyway; (d) the issue's acceptance criterion explicitly says "reuses `readBinaryFile` + `readContent` via the token lookup — no duplicate traversal logic," which is pointing AWAY from an HTTP fetch. In-process helper reuse is the right layer.

## Acceptance Checklist (Ship Gate)

- [ ] All new tests pass.
- [ ] All pre-existing share tests pass unchanged.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run` is green repo-wide.
- [ ] `npx tsc --noEmit` in `apps/web-platform/` is clean (especially exhaustive-switch).
- [ ] `npx markdownlint-cli2 --fix` clean on this plan file.
- [ ] Manual QA: four screenshots captured and attached to PR.
- [ ] PR body contains `Closes #2322`.
- [ ] Semver label: `semver:minor` (new agent capability).
- [ ] CMO not required (no user-facing copy).
- [ ] Compound skill run before commit (per `wg-before-every-commit-run-compound-skill`).

## Research Insights & Learnings Applied

### Learning: `2026-04-17-stream-response-toctou-across-fd-boundary` (HIGH severity)

**Finding quoted:** "Callers that already have metadata (`validateBinaryFile` result) MUST pass `expected` on every subsequent `openBinaryStream` call. Missing the pass on any call silently reopens the TOCTOU window."

**Applied to this plan:** Both the hash-gate `openBinaryStream` (in `previewShare()`'s binary branch) AND the first-page-preview `openBinaryStream` (fresh stream for pdfjs/sharp) pass `expected: { ino, size }`. The verdict cache key is `(token, ino, mtimeMs, size)` so the coarse-mtime swap attack is defended. Test 22 asserts this via spy. Without this pattern, a rename-over-regular-file between the hash pass and the preview pass could produce mismatched metadata.

### Learning: `2026-04-17-strong-etag-short-circuit-upstream-of-hash-gate` (PR #2515)

**Finding quoted:** "Move the conditional-match check into the resolver immediately after the strong ETag is known, before any downstream work."

**Applied to this plan:** The preview MCP tool has NO HTTP conditional-request semantics (no `If-None-Match` input). There is no 304 optimization to adopt — but the learning is cited here to make the omission explicit: the public route's fast-path stays where it is; the tool does not duplicate it. If a future MCP caching layer wants to skip the hash drain, it can pass `contentSha256` as an input parameter and `previewShare()` can short-circuit. Left as a future extension, not scoped now.

### Learning: `2026-04-17-regex-on-source-delegation-tests-trim-to-negative-space`

**Finding quoted:** "Keep only the negative-space assertion. Delete the positive regex assertions."

**Applied to this plan:** Test 34 was rewritten from a two-regex positive+negative pair into a single negative-space-only regex — "`server/kb-share-tools.ts` has no direct filesystem imports." The positive "`previewShare(` is called and early-returns on `!ok`" assertion was removed because tests 23-28 prove it transitively via mocked behavior. This eliminates brittleness under legitimate refactors.

### Learning: `2026-04-17-kb-route-helper-extraction-cluster-drain`

**Finding quoted:** (from Phase 3) "When extracting a new helper path, run `/review` over the full cluster (all callers of the touched helpers)."

**Applied to this plan:** Phase 3 REFACTOR adds a cluster-drain step: after the extraction, grep for every caller of `validateBinaryFile`, `readContentRaw`, `openBinaryStream`, and `hashStream` and verify none of them has broken invariants. Explicitly listed in Phase 3 step 5.

### Learning: `2026-04-17-kb-share-mcp-parity-lstat-toctou-and-mock-cascade`

**Finding applied:** PR #2497 caught a TOCTOU window where a pre-open `lstat` introduced a CodeQL `js/file-system-race` violation. Resolution: `O_NOFOLLOW` at `fs.open` is the sole pre-open guard; symlink rejection happens at open time, not lstat time. This plan inherits that pattern verbatim via `validateBinaryFile` / `readContentRaw` — no new filesystem access code is written in `previewShare()`.

### Learning: `2026-04-15-kb-share-binary-files-lifecycle`

**Finding applied:** "When the same hardening pattern appears in two routes, extract it BEFORE duplicating it." The preview tool follows this by not re-implementing the share-row lookup + hash-gate pipeline. `prepareSharedRequest()` in `app/api/shared/[token]/route.ts` and `previewShare()` in `server/kb-share.ts` share the same terminal states and the same hash-gate logic — the tool is a strict metadata projection of what the route would return.

### Learning: `2026-04-10-discriminated-union-exhaustive-switch-miss`

**Finding applied:** `PreviewShareErrorCode` is declared as a string-literal union. The wrap helper in `kb-share-tools.ts` uses `const _exhaustive: never = result.code;` to force compile errors when a new error code is added without a wrapper case. Same pattern PR #2497 introduced for `CreateShareResult`.

### Learning: `2026-04-15-negative-space-tests-must-follow-extracted-logic`

**Finding applied:** Test 34 is a regex check that requires BOTH `previewShare(` invocation AND `if (!result.ok)` (or equivalent) early-return in `kb-share-tools.ts`. Substring match of the helper name alone is rejected. Same gate PR #2497 used for the create/list/revoke extraction.

### Learning: `2026-04-10-cicd-mcp-tool-tiered-gating-review-findings`

**Finding applied:** Tests 21-22 assert the Supabase mock was called with the expected `token` filter value, and the binary stream was opened with `expected: { ino, size }`. Prevents the "mock returns data for any query" silent-pass bug.

### Learning: `service-tool-registration-scope-guard-20260410`

**Finding applied:** Test 33 verifies the preview tool is NOT registered when the workspace is not ready. This mirrors the scope-guard test PR #2497 introduced for the other three share tools — the tool's only prerequisite is a ready workspace, independent of GitHub installation or connected services. Put differently: installing the tool must not accidentally gate it behind an unrelated check.

### Capability-Map alignment (agent-native-reviewer principle)

Entry appended to the capability map table introduced in PR #2497:

| UI Action | Location | Agent Tool | Prompt Ref | Status |
|---|---|---|---|---|
| Generate share link | `components/kb/share-popover.tsx` | `kb_share_create` | "## Knowledge-base sharing" | Shipped (#2497) |
| List share links | `components/kb/share-popover.tsx` | `kb_share_list` | "## Knowledge-base sharing" | Shipped (#2497) |
| Revoke share link | `components/kb/share-popover.tsx` | `kb_share_revoke` | "## Knowledge-base sharing" | Shipped (#2497) |
| **Preview as recipient** | `/shared/[token]` page (public) | **`kb_share_preview`** | **"## Knowledge-base sharing"** | **This PR** |

All four action-parity rows are covered after this PR — the capability map is complete for the share affordance.

### Simplification pass (DHH / code-simplicity self-review)

- **Could we call `fetch("/api/shared/[token]")` instead of building `previewShare()`?** Considered. Rejected — the sandbox's `allowedDomains: []` blocks egress, adds unnecessary HTTP layering, and the issue's acceptance criterion explicitly asks for in-process helper reuse. In-process wins on all axes.
- **Could we skip `firstPagePreview` entirely and let the agent ask "how many pages?" via a separate tool?** Considered. Rejected — the issue calls it out as explicitly valuable ("first-page render"). Metadata (numPages, dimensions) is cheap to compute and sharply more useful than `{ contentType, size }` alone.
- **Could we return bytes so the agent can render the document inline?** Considered. Rejected — out of scope per the issue; adds consent-fatigue and privacy-leak risk; keeps the tool auto-approve. If a future issue asks for bytes, it would need a gated tier and a review gate.
- **Could `previewShare()` live in `server/kb-share-preview.ts` instead of `server/kb-share.ts`?** Considered. Rejected — it's one function that belongs with the other lifecycle operations (create / list / revoke). Separating would fragment the file without adding anything. Keep alongside.
- **Could the tier default ("gated" for unknown tools) be good enough without an explicit `TOOL_TIER_MAP` entry?** Considered. Rejected — auto-approve is the *correct* tier for a metadata-only read; leaving it default would gate every preview call through a review prompt and produce consent fatigue. Explicit entry is a one-line improvement.

No YAGNI violations identified. The plan is not overengineered.
