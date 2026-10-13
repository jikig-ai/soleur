# perf(kb): stream binary responses with hash-verdict cache

**Date:** 2026-04-17
**Branch:** `feat-fix-2316-stream-binary-responses`
**Worktree:** `.worktrees/feat-fix-2316-stream-binary-responses/`
**Issues:** Closes #2316 (P1 perf) and Closes #2466 (deferred-scope-out — Range-request hash regression)
**Milestone:** Phase 3: Make it Sticky
**Type:** perf (refactor + new internal cache)

## Enhancement Summary

**Deepened on:** 2026-04-17
**Sources queried:** Node.js stream/fs API docs via Context7 (`/nodejs/node`), Next.js App Router streaming patterns (`/vercel/next.js`), lru-cache ergonomics (`/isaacs/node-lru-cache`), codebase inspection of `server/rate-limiter.ts` for existing in-process cache patterns.

### Key changes from the initial plan

1. **Stream primitive switched: use `filehandle.readableWebStream({ autoClose: true })`, not `Readable.toWeb(handle.createReadStream())`.** This is the canonical Next.js pattern straight from the official docs; it is byte-oriented (web `ReadableStream` with `type: 'bytes'`, so Range support downstream is native) and ships an explicit `autoClose: true` flag that closes the fd when the stream ends. The `handedOff` flag gymnastics in Phase 2 of the initial plan are eliminated.
2. **Range branch uses `fs.createReadStream(filePath, { start, end, flags: 'r', autoClose: true })` wrapped via `Readable.toWeb`.** `filehandle.readableWebStream` does not accept `start`/`end`, so a second primitive is needed for ranged responses. The `autoClose: true` default on `fs.createReadStream` covers fd cleanup.
3. **No `lru-cache` dependency.** The repo pattern (see `apps/web-platform/server/rate-limiter.ts` — `SlidingWindowCounter` is ~40 LOC of hand-rolled `Map`) is hand-rolled bounded structures. A 500-entry verdict cache with insertion-order eviction and per-entry expiry is ~60 LOC in one file. Pulling in `lru-cache` for 500 entries is overkill and inflates bundle.
4. **Cloudflare / proxy buffering verified non-blocking.** The repo has no `X-Accel-Buffering` header. Deploy path is Cloudflare Tunnel → Next.js Node runtime; Cloudflare proxy-streams by default for `Content-Length`-present responses. No infra change needed for streaming to work in prod.
5. **TOCTOU window for Range re-open explicitly flagged and accepted.** Range requests open a second fd without `O_NOFOLLOW` (Node's `createReadStream` does not expose it). The acceptance reasoning is documented below in "Sharp Edges".

## Overview

`readBinaryFile` currently allocates a full `Buffer` (up to 50 MB) plus a second `Uint8Array` copy before shipping the first byte. Under concurrent load this OOMs the process and starves the libuv threadpool (which also serves markdown I/O). This plan replaces the buffered path with a streaming path where possible, while preserving the SHA-256 content-integrity gate shipped in PR #2463 for `/api/shared/[token]`.

Naive streaming breaks the gate: the share-view route hashes the in-memory buffer and returns 410 on mismatch. If `readBinaryFile` returns only a stream, the buffer is gone and hashing must happen before or during response shipping. The two sibling concerns are deeply coupled, so #2316 and #2466 are shipped together:

- **#2316 (streaming):** Return a web `ReadableStream` from `readBinaryFile` so `new Response(stream, …)` emits bytes with O(64 KB) RSS instead of O(file size) RSS.
- **#2466 (verdict cache):** After the first hash succeeds for a given `(token, mtimeMs, size)` tuple, subsequent views skip the hash and stream directly. Without this, every Range request (PDF.js issues 8–20 per document open) re-hashes 50 MB, which was the regression #2466 called out.

**Out of scope:** #2309 agent-user parity, `/api/kb/share` POST (creation-side hash already uses `hashStream`), any refactor of `readContentRaw` for markdown. This PR closes 2 of the 27 Phase-3 code-review issues (#2326 shipped as PR #2463).

## Research Reconciliation — Spec vs. Codebase

| Spec claim (from #2316 / #2466) | Codebase reality (verified 2026-04-17) | Plan response |
| --- | --- | --- |
| `readBinaryFile` currently reads the full file into a `Buffer` via `handle.readFile()` then wraps in `new Uint8Array(buffer)` (~2× memory). | Confirmed at `apps/web-platform/server/kb-binary-response.ts:98` and `:148`/`:160`. | Streaming path must also drop the `Uint8Array` wrap — `Response(stream)` needs no copy. |
| `/api/shared/[token]` hashes on every view including Range requests. | Confirmed at `apps/web-platform/app/api/shared/[token]/route.ts:168`. | Introduce verdict cache keyed on `(token, mtimeMs, size)`. |
| `/api/kb/content/[...path]` has no hash check. | Confirmed at `apps/web-platform/app/api/kb/content/[...path]/route.ts:76–80`. | Owner path streams unconditionally, no cache needed. |
| `hashStream` exists and is used at share creation. | Confirmed at `apps/web-platform/server/kb-content-hash.ts:28`. | Reuse — no new hashing primitives. |
| `buildBinaryResponse` already supports 206 Range via `buffer.subarray`. | Confirmed at `apps/web-platform/server/kb-binary-response.ts:127–156`. Depends on in-memory buffer. | Re-implement Range as `createReadStream(path, { start, end })` so range slicing never requires the full buffer. Cache verdict keeps Range viable on the share-view path. |
| Node 22 + Next.js 15 run the App Router. `Readable.toWeb` is GA. | Confirmed in `apps/web-platform/package.json` (target node22, next 15.5). | Use `filehandle.readableWebStream({ autoClose: true })` as the primary primitive (canonical Next.js streaming idiom per official docs); use `Readable.toWeb(fs.createReadStream(path, { start, end }))` for the Range branch. |

## Chosen Approach

**Option (a): Hash-then-stream with per-token LRU verdict cache.**

The two alternatives were rejected:

- **Option (b) — stream-and-hash concurrently with abort:** Already-shipped bytes can't be unsent. A client that receives mismatched PDF bytes followed by an aborted connection has a corrupt file with no clear error signal. For a gate whose purpose is "if content changed, show 410 instead of stale content," shipping 1 KB of the new content before aborting is worse than buffering.
- **Option (c) — pre-hash by reading, then serve via second stream:** 2× disk I/O on every view, plus the fstat→read→hash→open→read window is a TOCTOU reopening of the bug class PR #2463's `O_NOFOLLOW`+fd pattern was written to close.

### Data flow

1. `readBinaryFile(kbRoot, relativePath)` returns a discriminated union with two success shapes:
   - `{ ok: true, stream: ReadableStream, size, mtimeMs, contentType, disposition, rawName, filePath }` — default stream path, no buffer allocated.
   - For Range requests, `buildBinaryResponse` opens a second stream with `createReadStream(filePath, { start, end })`. This keeps the bounded-range fast path without requiring the full buffer.
2. `/api/kb/content/[...path]` calls `readBinaryFile` → `buildBinaryResponse` directly. No hash, no cache.
3. `/api/shared/[token]` calls `readBinaryFile`, then:
   - Computes the cache key `(token, mtimeMs, size)`.
   - On cache hit (`verified: true` within TTL): skip hashing, call `buildBinaryResponse` directly. Fast path.
   - On cache miss: consume the stream into a hash (`hashStream`), compare to `shareLink.content_sha256`. On mismatch → 410. On match → store `{ verified: true, expiresAt: Date.now()+60_000 }` in cache, then re-issue the response by opening a **new** stream on the held fd path. The first-view hash pass is unavoidable for the first byte of a newly-cached entry; subsequent views are hash-free.
4. LRU cache bounds: 500 entries, 60 s TTL (matching `Cache-Control: private, max-age=60`). Tuple-keyed on `mtimeMs+size` so any file mutation invalidates naturally.

### Why `mtimeMs + size` (not just `mtimeMs`)

`mtimeMs` resolution on Linux ext4 is nanosecond; on NFS and some container overlay FS it's second-level. A same-second rewrite with identical size is vanishingly unlikely in practice but the size guard is free insurance. The fstat already happens inside `readBinaryFile`, so we piggy-back on it.

### fd-ownership and TOCTOU preservation

PR #2463's `O_NOFOLLOW`+fstat-on-fd pattern must survive. The streaming path opens the fd once, stats it on the fd (existing `handle.stat()`), then derives the `ReadStream` from the held fd via `handle.createReadStream()`. This keeps the bytes served identical to the bytes stat'd and hashed — the same TOCTOU closure the buffered path had.

For Range requests (second stream), we re-open by path using `fs.createReadStream(fullPath, { start, end })` under the same `O_NOFOLLOW` flag. The verdict cache ensures we don't hash on the Range path, so the Range request doesn't need the same fd-lifetime guarantee as the hash check (which ran on the first view's fd).

## Implementation Phases

### Phase 1 — Refactor `readBinaryFile` to return a stream (RED)

Files:

- `apps/web-platform/server/kb-binary-response.ts` (modify)
- `apps/web-platform/test/kb-binary-response.test.ts` (new — RED tests first)

Tasks:

1. Add a failing test `test/kb-binary-response.test.ts` asserting:
   - `readBinaryFile` returns `{ ok: true, stream, size, mtimeMs, contentType, disposition, rawName, filePath }` (new shape).
   - The stream is a web `ReadableStream`.
   - `size` equals the byte length on disk.
   - `mtimeMs` matches `fs.statSync(path).mtimeMs`.
   - All existing error paths (403 traversal, 403 symlink, 403 null-byte, 404 ENOENT, 413 oversize) still return the same status shape.
2. Modify `readBinaryFile`:
   - Keep the `O_RDONLY | O_NOFOLLOW` open, keep `handle.stat()`, keep all size/type/path guards.
   - Replace `handle.readFile()` with `handle.readableWebStream({ autoClose: true })` — the canonical Next.js streaming primitive. `autoClose: true` closes the `FileHandle` when the stream ends or errors, so we do NOT need a `try/finally handle.close()` on the success path.
   - Return the new shape `{ ok: true, stream, size, mtimeMs, contentType, disposition, rawName, filePath }`. Return `filePath` (absolute) so `buildBinaryResponse` can re-open on Range.
   - Keep `handle.close()` on ERROR paths only (stat-failed, oversize, non-file). Once `readableWebStream` is called with `autoClose: true`, the fd lifetime is tied to the stream — calling `handle.close()` after handoff would double-close.

Reference (Next.js docs):

```ts
// Canonical pattern for streaming file responses from App Router:
import { open } from "node:fs/promises";
const file = await open(absolutePath);
return new Response(file.readableWebStream({ autoClose: true }), {
  headers: { "Content-Type": "...", "Content-Length": String(size) },
});
```

### Phase 2 — Teach `buildBinaryResponse` to stream (GREEN)

Files:

- `apps/web-platform/server/kb-binary-response.ts` (modify)
- `apps/web-platform/test/kb-binary-response.test.ts` (extend)

Tasks:

1. Change `buildBinaryResponse`'s input type from `{ buffer, … }` to `{ stream, size, contentType, disposition, rawName, filePath }`.
2. Full response branch: `new Response(stream, { headers: { …, "Content-Length": size.toString() } })`. The `stream` came from `readableWebStream({ autoClose: true })` upstream; no further lifecycle work.
3. Range branch: parse the Range header as before, then open a fresh stream with `fs.createReadStream(filePath, { start, end, flags: "r", autoClose: true })` and wrap via `Readable.toWeb(nodeStream)`. `autoClose: true` is the default but pass explicitly for clarity. Return 206 with `Content-Length: chunk.length` and `Content-Range: bytes start-end/size`.

Why the asymmetry (two stream primitives): `filehandle.readableWebStream` is byte-oriented and has the best fd-lifetime ergonomics for full responses, but it does NOT accept `start`/`end`. `fs.createReadStream` accepts the offsets we need for Range but returns a Node `Readable`, so we adapt via `Readable.toWeb`. Both are GA in Node 22 and documented by Next.js as the App Router streaming idioms.
4. Extend tests:

- Full GET returns stream with `Content-Length` matching file size.
- Range `bytes=0-99` returns 206 with `Content-Length: 100` and `Content-Range: bytes 0-99/<size>`.
- Malformed Range falls through to 200 full response.
- Out-of-range (start ≥ size) returns 416 with `Content-Range: bytes */<size>`.

### Phase 3 — Introduce the verdict cache module (RED + GREEN)

Files:

- `apps/web-platform/server/share-hash-verdict-cache.ts` (new)
- `apps/web-platform/test/share-hash-verdict-cache.test.ts` (new)

> **Route-file hygiene note (rule `cq-nextjs-route-files-http-only-exports`):** the verdict-cache singleton, `__resetShareHashVerdictCacheForTest`, and cache-metric helpers must live in `share-hash-verdict-cache.ts`. Never export them from `app/api/shared/[token]/route.ts`. The post-merge Next.js route validator only allows HTTP method handlers + config exports in `route.ts`; exporting the cache singleton from the route file would reproduce the PR #2347/#2401 outage pattern.

Tasks:

1. Write failing tests covering:
   - `get(token, mtimeMs, size)` returns `null` on miss.
   - `set(token, mtimeMs, size, verified)` stores and subsequent `get` returns the verdict within TTL.
   - `get` returns `null` after TTL expires (use `vi.useFakeTimers` and advance 60 001 ms).
   - Different `mtimeMs` on same token misses.
   - Different `size` on same token and `mtimeMs` misses.
   - LRU eviction: insert 501 entries, first key returns null, last 500 hit.
   - `__resetShareHashVerdictCacheForTest()` clears state (for test isolation).
2. Implement with a simple `Map<string, { verified: boolean; expiresAt: number; mtimeMs: number; size: number }>` plus insertion-order eviction. Pattern matches `apps/web-platform/server/rate-limiter.ts` `SlidingWindowCounter` (hand-rolled `Map`-based, ~40 LOC). Key on `token` alone and include `mtimeMs`/`size` in the value; treat mismatches as cache misses. This simplifies invalidation: a new tuple silently overwrites the old entry, so stale mtimes never accumulate.

   ```ts
   // Sketch — final form in share-hash-verdict-cache.ts
   const TTL_MS = 60_000; // matches Cache-Control: max-age=60
   const MAX_ENTRIES = 500;

   type Entry = { verified: true; mtimeMs: number; size: number; expiresAt: number };
   const cache = new Map<string, Entry>();

   export const shareHashVerdictCache = {
     get(token: string, mtimeMs: number, size: number): true | null {
       const entry = cache.get(token);
       if (!entry) return null;
       if (entry.expiresAt <= Date.now()) { cache.delete(token); return null; }
       if (entry.mtimeMs !== mtimeMs || entry.size !== size) return null;
       // Refresh LRU position.
       cache.delete(token);
       cache.set(token, entry);
       return true;
     },
     set(token: string, mtimeMs: number, size: number) {
       if (cache.size >= MAX_ENTRIES && !cache.has(token)) {
         // Evict oldest (Map preserves insertion order).
         const oldest = cache.keys().next().value;
         if (oldest !== undefined) cache.delete(oldest);
       }
       cache.set(token, { verified: true, mtimeMs, size, expiresAt: Date.now() + TTL_MS });
     },
     // Test-only helper — never export from route.ts (rule cq-nextjs-route-files-http-only-exports).
   };
   export function __resetShareHashVerdictCacheForTest() { cache.clear(); }
   ```

**Why not `lru-cache`:** The `lru-cache` package is excellent (and present transitively) but adds a direct dep, a bundle-surface change, and 46+ config options for a use case where our total state is 500 entries × ~40 bytes. The hand-rolled version above matches the repo's existing rate-limiter style and is trivially reviewable. If eviction patterns ever get more complex (size-weighted, async fetch-on-miss), revisit.
3. Export a singleton `shareHashVerdictCache` and `__resetShareHashVerdictCacheForTest` helper.
4. Optional counters for observability: `hits`, `misses`, `evictions` — expose via a `stats()` method. Deferred to follow-up if the basic cache is working; do not block ship on metrics.

### Phase 4 — Wire the cache into `/api/shared/[token]` (GREEN)

Files:

- `apps/web-platform/app/api/shared/[token]/route.ts` (modify)
- `apps/web-platform/test/shared-page-binary.test.ts` (update mocks for new shape)
- `apps/web-platform/test/shared-token-content-hash.test.ts` (extend with cache-hit test)

Tasks:

1. In the binary branch, after `readBinaryFile` returns:

   ```ts
   const cached = shareHashVerdictCache.get(token, binary.mtimeMs, binary.size);
   if (cached === true) {
     // Fast path: known-good, skip hash.
     logger.info({ event: "shared_page_viewed_cached", token }, "…");
     return buildBinaryResponse(binary, request);
   }
   // Slow path: consume stream through hash, compare, then re-stream.
   const hashResult = await hashStreamThenTee(binary.stream);
   if (hashResult.hash !== shareLink.content_sha256) {
     return contentChangedResponse();
   }
   shareHashVerdictCache.set(token, binary.mtimeMs, binary.size, true);
   // binary.stream is consumed; re-open via filePath for the response body.
   const streamForResponse = Readable.toWeb(fs.createReadStream(binary.filePath));
   return buildBinaryResponse({ ...binary, stream: streamForResponse }, request);
   ```

2. For markdown (`.md` / extensionless) branch: unchanged. `readContentRaw` already returns a buffer at ~1 MB ceiling; streaming it is not worth the complexity. The hash-on-view behavior stays identical. Optional follow-up: the markdown path could use a similar verdict cache keyed on the markdown hash, but it's deferred because markdown is already O(1 MB) not O(50 MB).

3. Add a `hashStreamThenTee` helper in `server/kb-content-hash.ts`: takes a `ReadableStream`, drains it through `createHash("sha256")`, returns `{ hash, bytesRead }`. (Note: does NOT tee — we discard the consumed stream and re-open below. The name reflects intent that the caller will need a fresh stream.) Add a failing test first.

4. Update `shared-page-binary.test.ts`:
   - Existing test helpers need to accept the new `{ stream, size, mtimeMs, filePath, … }` shape from `readBinaryFile`, or re-stub by just writing the file to disk and letting the real reader run (simpler — most tests already do this).
   - Add one cache-hit test: issue two GETs for the same token, assert the second one does NOT invoke `hashStream` (spy on the exported function) and returns 200.
   - Add one Range-request test: issue a GET with `Range: bytes=0-99` on a share with a known-good cached verdict, assert 206 and that the byte body length is 100.
   - Add one cache-miss-after-edit test: issue GET, mutate the file (changes `mtimeMs`), issue second GET — verify hash runs again and 410 is returned (mismatch).

### Phase 5 — Wire `/api/kb/content/[...path]` to the streaming API (GREEN)

Files:

- `apps/web-platform/app/api/kb/content/[...path]/route.ts` (modify)
- `apps/web-platform/test/kb-content-route.test.ts` (new or extend existing)

Tasks:

1. Update the call site to use the new shape. No cache, no hash — owner route streams unconditionally.
2. Test: owner GET of a PDF returns 200 with `Content-Type: application/pdf`, `Accept-Ranges: bytes`, `Content-Length` matching size.
3. Test: owner Range GET returns 206 with the correct slice length.

### Phase 6 — Remove the buffer type from the public helper surface

Files:

- `apps/web-platform/server/kb-binary-response.ts` (cleanup)

Tasks:

1. Remove the `buffer: Buffer` field from `BinaryReadResult`'s success shape. Any test that still destructures `binary.buffer` fails loudly — grep confirms only `test/shared-page-binary.test.ts` and the share-route files touch it, and both are updated in Phase 4.
2. Ensure the only exports from `kb-binary-response.ts` remain: the types, `MAX_BINARY_SIZE`, `CONTENT_TYPE_MAP`, `ATTACHMENT_EXTENSIONS`, `formatContentDisposition`, `readBinaryFile`, `buildBinaryResponse`. No route-file exports leak.

### Phase 7 — Manual benchmark (optional, local verification)

Defer to post-merge if the local Doppler env isn't handy. Ship steps:

1. Create a 50 MB dummy PDF in the dev workspace.
2. Issue `autocannon -c 10 -d 30 https://soleur.ai/api/shared/<token>`, capture p99 and peak RSS.
3. Compare against pre-merge baseline (main). Expected: RSS flat; p99 unchanged or lower.

Non-blocking for the PR. If the numbers regress, open a follow-up.

## Acceptance Criteria

- `readBinaryFile` returns a web `ReadableStream`, `size`, `mtimeMs`, `filePath`, plus existing type/disposition fields. Type check passes.
- `buildBinaryResponse` accepts the new shape for both full (200) and Range (206) paths; no `Buffer` in the hot path.
- `/api/kb/content/[...path]` streams binaries with no hash check.
- `/api/shared/[token]` preserves hash-on-first-view gate, returns 410 on mismatch, returns 200 streaming body on match, caches verdict for 60 s.
- Second view of the same `(token, mtimeMs, size)` skips the hash (verified via spy).
- Range request on a cached token returns 206 without a hash pass.
- File mutation (`mtimeMs` change) invalidates the cache; next view re-hashes.
- All existing security tests still pass (`shared-page-binary.test.ts`, `shared-token-content-hash.test.ts`, `kb-share-content-hash.test.ts`, `kb-content-hash.test.ts`).
- `tsc --noEmit` passes. `next build` passes. `vitest run` passes.
- No new exports added to `app/api/shared/[token]/route.ts` (rule `cq-nextjs-route-files-http-only-exports`).

## Test Scenarios

| Scenario | Expected |
| --- | --- |
| Owner GET /api/kb/content/file.pdf (full) | 200, streaming body, Content-Length matches |
| Owner GET /api/kb/content/file.pdf with Range: bytes=0-99 | 206, Content-Length=100, Content-Range: bytes 0-99/size |
| Shared GET first view, hash matches | 200, streaming body, cache entry set |
| Shared GET second view, same mtime | 200, streaming body, hash NOT invoked (spy asserts) |
| Shared GET Range, cache hit | 206, streaming body, hash NOT invoked |
| Shared GET after file edit (new mtime) | 410, hash invoked, cache rewrites verdict for new tuple |
| Shared GET mismatched hash (file changed post-share) | 410, no cache entry stored for mismatched hash |
| Shared GET on revoked share | 410 (unchanged from #2463) |
| Shared GET on legacy null-hash share | 410 (unchanged) |
| Shared GET on symlink at stored path | 403 (O_NOFOLLOW preserved) |
| Shared GET on null-byte path | 403 (unchanged) |
| Shared GET on oversize file (>50 MB) | 413 (unchanged) |
| Cache TTL expiry (advance 60 001 ms) | Next GET re-hashes |
| Cache LRU eviction (>500 entries) | Oldest entry evicted, re-hashes on next view |

## Domain Review

**Domains relevant:** engineering (performance, security-adjacent).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** This is a performance+correctness refactor of server-side code that participates in the share-link security boundary. The fd-lifetime and O_NOFOLLOW invariants from PR #2463 must survive. The cache is in-process, bounded, with clear invalidation on file change — no new persistence surface, no cross-request state leakage across users (keyed on per-share token). No domain leaders beyond CTO apply: no UI, no copy, no marketing surface, no legal commitments, no expense.

No cross-domain implications detected — internal engineering/performance change.

## Non-Goals / Out of Scope

- **#2309 agent-user parity:** explicitly deferred by user. Separate issue.
- **Markdown streaming:** markdown responses stay buffered via `readContentRaw` (1 MB ceiling). A verdict cache for markdown would be a ~10 LOC addition but adds API surface; deferred unless benchmarks show hot contention.
- **Cross-instance cache coherence:** in-process cache is fine because share-view traffic is low-cardinality and the only correctness risk (stale `verified: true` after file mutation) is eliminated by `mtimeMs+size` keying. When we scale to multi-instance, the cache is still correct per-instance; worst case is each instance re-hashes once per 60 s window.
- **Observability dashboard for cache hit rate:** optional `stats()` method is included for a future Grafana panel; not required for this PR.
- **Rate-limit tuning:** the `shareEndpointThrottle` gate already precedes all hash/filesystem work. No changes.

## Sharp Edges / Known Gotchas

- **fd lifetime with `filehandle.readableWebStream({ autoClose: true })`:** with `autoClose: true`, the fd closes automatically when the stream ends or errors. Do NOT call `handle.close()` in `finally` on the success path — that would double-close. Keep `handle.close()` only on error branches *before* `readableWebStream` is called (stat failure, oversize, non-file).
- **Range path TOCTOU (explicitly accepted):** the Range branch opens a second fd via `fs.createReadStream(filePath, { start, end })` WITHOUT `O_NOFOLLOW`. Node's `createReadStream` does not expose that flag. This reopens a symlink-swap window between the first open (which passed `O_NOFOLLOW` + size/type guards) and the Range-branch re-open. Mitigating factors: (a) `isPathInWorkspace(fullPath, kbRoot)` is re-verified at request entry, (b) the verdict-cache path means Range requests don't require a new hash pass, (c) the same window exists on any subsequent request for the same path — this is not a new regression. If a reviewer pushes back, the alternative is opening a second `FileHandle` with `O_NOFOLLOW`, stat-on-fd, then `handle.createReadStream({ start, end })`. That's more code and the win is marginal since we still re-verify the path. Document the trade-off in the PR body.
- **Full response + cache-miss = two disk reads.** On cache miss, we drain the first stream through `hashStream`, discard, then re-open via `fs.createReadStream(filePath)` for the actual response body. 2× I/O on miss is acceptable because misses are rare (first view of a token OR file-change events). Cache hits are 1× I/O (streaming only). This is the cost of not shipping bytes until hash verification completes, which is the correctness requirement #2463 established.
- **Cache-miss + Range request:** rare edge case. We must hash the full file before serving any Range (otherwise a Range client could receive mismatched bytes before the hash gate runs). Implementation: on cache miss, always hash the full file first, store verdict, *then* handle the Range header. No shortcut.
- **Test file conflict with PR #2401 learning:** keep cache singleton in `server/share-hash-verdict-cache.ts`, never co-located with `route.ts`. Phase 3 enforces this.
- **Node stream support:** `filehandle.readableWebStream` GA in Node 20+; `Readable.toWeb` GA since Node 17. Repo targets Node 22. No flag needed.
- **Next.js 15 + stream on Response body:** supported and documented. `new Response(readableStream, …)` on App Router Node runtime is the canonical idiom (see Next.js streaming guide — `file.readableWebStream()` example is verbatim the pattern we're using).
- **Cloudflare / proxy buffering:** no `X-Accel-Buffering` configuration in this repo. Deploy path is Cloudflare Tunnel → Next.js Node runtime; Cloudflare proxies stream responses with `Content-Length` by default. Not a blocker; if streaming stalls on the edge, add `X-Accel-Buffering: no` to `buildBinaryResponse` headers as a follow-up.
- **Hash-stream consumption state:** after draining through `hashStream`, the `ReadableStream` is consumed and locked. The response MUST re-open via `filePath`; do not try to re-use the locked stream.
- **`Content-Length` still required:** `PdfPreview` progress indicator and many clients expect `Content-Length`. Already on the fstat from before the stream opens, so no extra syscall. Keep it in `buildBinaryResponse`.

## References

- Issue #2316 — perf(kb): stream binary responses (P1)
- Issue #2466 — review: cache hash verdict on /api/shared/[token] for Range requests (deferred-scope-out, now scoped in)
- PR #2463 — content-hash gate for share links (shipped earlier this session)
- PR #2451 — added `Accept-Ranges: bytes` to `buildBinaryResponse`
- PR #2401 — learning: Next.js route files must export only HTTP handlers + config
- `apps/web-platform/server/kb-binary-response.ts:56–105` — `readBinaryFile` current implementation
- `apps/web-platform/server/kb-binary-response.ts:107–166` — `buildBinaryResponse` current implementation
- `apps/web-platform/server/kb-content-hash.ts:14–37` — `hashBytes` / `hashStream`
- `apps/web-platform/app/api/shared/[token]/route.ts:157–191` — share-view binary branch
- `apps/web-platform/app/api/kb/content/[...path]/route.ts:75–81` — owner binary branch
- `knowledge-base/project/learnings/2026-04-15-kb-share-binary-files-lifecycle.md` — origin of the shared helper pattern
- `knowledge-base/project/learnings/runtime-errors/2026-04-15-nextjs-15-route-file-non-http-exports.md` — why cache goes in its own module

## Files to Modify

- `apps/web-platform/server/kb-binary-response.ts` — return stream, accept stream shape
- `apps/web-platform/server/kb-content-hash.ts` — add `hashStreamThenDiscard` (or reuse `hashStream` directly)
- `apps/web-platform/app/api/shared/[token]/route.ts` — wire cache + stream
- `apps/web-platform/app/api/kb/content/[...path]/route.ts` — wire stream (no cache)
- `apps/web-platform/test/shared-page-binary.test.ts` — update for new shape, add cache tests
- `apps/web-platform/test/shared-token-content-hash.test.ts` — extend with cache-hit/miss cases

## Files to Create

- `apps/web-platform/server/share-hash-verdict-cache.ts` — LRU+TTL verdict cache (singleton)
- `apps/web-platform/test/share-hash-verdict-cache.test.ts` — unit tests for the cache
- `apps/web-platform/test/kb-binary-response.test.ts` — unit tests for the refactored helper
- `apps/web-platform/test/kb-content-route.test.ts` — (if not already covered) streaming + Range for owner route

## Resume Prompt

Run `/soleur:work knowledge-base/project/plans/2026-04-17-perf-stream-binary-responses-with-verdict-cache-plan.md`. Branch: `feat-fix-2316-stream-binary-responses`. Worktree: `.worktrees/feat-fix-2316-stream-binary-responses/`. Issues: Closes #2316, Closes #2466. Plan written and deepened — implementation starts with Phase 1 RED tests on `readBinaryFile` stream shape.
