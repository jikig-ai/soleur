# Tasks — feat-fix-2316-stream-binary-responses

Plan: `knowledge-base/project/plans/2026-04-17-perf-stream-binary-responses-with-verdict-cache-plan.md`
Issues: Closes #2316, Closes #2466

## Phase 1: Stream shape for readBinaryFile (RED)

- [ ] 1.1 Write failing tests in `apps/web-platform/test/kb-binary-response.test.ts` for the new `{ stream, size, mtimeMs, filePath, contentType, disposition, rawName }` success shape
- [ ] 1.2 Assert all existing error paths still return identical status codes (403/404/413)
- [ ] 1.3 Confirm tests fail against current `buffer`-returning implementation

## Phase 2: Implement stream + range (GREEN)

- [ ] 2.1 Rewrite `readBinaryFile` to return `Readable.toWeb(handle.createReadStream())`
- [ ] 2.2 Guard fd close with `handedOff` flag so the stream owns the fd after handoff
- [ ] 2.3 Rewrite `buildBinaryResponse` to accept stream shape
- [ ] 2.4 Full-response branch: `new Response(stream, headers)`
- [ ] 2.5 Range branch: open a fresh `createReadStream(filePath, { start, end })`
- [ ] 2.6 Extend tests: full 200, Range 206, malformed Range fallback to 200, out-of-range 416

## Phase 3: Verdict cache module

- [ ] 3.1 Write failing tests in `apps/web-platform/test/share-hash-verdict-cache.test.ts` (TTL, mtime mismatch, size mismatch, LRU eviction)
- [ ] 3.2 Implement `server/share-hash-verdict-cache.ts` — Map-backed LRU + TTL, 500-entry bound, 60s TTL
- [ ] 3.3 Export singleton `shareHashVerdictCache` and `__resetShareHashVerdictCacheForTest`
- [ ] 3.4 Verify tests pass

## Phase 4: Wire /api/shared/[token] to cache + stream

- [ ] 4.1 Add cache lookup before hashing in share-view binary branch
- [ ] 4.2 On cache miss: drain stream through `hashStream`, compare hash, on match write cache entry and re-open stream for response
- [ ] 4.3 On cache hit: skip hash, call `buildBinaryResponse` directly
- [ ] 4.4 Update `shared-page-binary.test.ts` for new shape
- [ ] 4.5 Add cache-hit test (spy asserts hash NOT called on 2nd view)
- [ ] 4.6 Add Range-request-on-cached-token test (206, no hash)
- [ ] 4.7 Add post-edit invalidation test (new mtime triggers re-hash, returns 410 on mismatch)

## Phase 5: Wire /api/kb/content/[...path] to stream

- [ ] 5.1 Update owner route call site for new shape — no hash, no cache
- [ ] 5.2 Add/extend test: owner full GET returns 200 streaming body with correct Content-Length
- [ ] 5.3 Add/extend test: owner Range GET returns 206 with correct slice

## Phase 6: Clean up helper surface

- [ ] 6.1 Remove `buffer: Buffer` from `BinaryReadResult` success shape
- [ ] 6.2 Grep-verify no remaining consumers
- [ ] 6.3 Confirm `route.ts` files export only HTTP handlers (rule `cq-nextjs-route-files-http-only-exports`)

## Phase 7: Verify + ship

- [ ] 7.1 `tsc --noEmit` passes
- [ ] 7.2 `vitest run` passes in `apps/web-platform`
- [ ] 7.3 `next build` passes (validates route-file export restriction)
- [ ] 7.4 Optional: local `autocannon` benchmark comparing RSS on main vs branch
- [ ] 7.5 Run `/soleur:compound` to capture learnings
- [ ] 7.6 Run `/soleur:ship` to create PR with `Closes #2316` and `Closes #2466` in body
