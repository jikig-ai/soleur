# Session State

## Plan Phase

- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-fix-2316-stream-binary-responses/knowledge-base/project/plans/2026-04-17-perf-stream-binary-responses-with-verdict-cache-plan.md
- Status: complete

### Errors

None

### Decisions

- **Stream primitive:** `filehandle.readableWebStream({ autoClose: true })` as primary path (Next.js canonical). Range branch uses `Readable.toWeb(fs.createReadStream(path, { start, end }))` because `readableWebStream` doesn't accept offsets.
- **Verdict cache:** hand-rolled `Map`-based bounded cache (~60 LOC, 500 entries, 60s TTL) matching existing `SlidingWindowCounter` pattern — no new `lru-cache` dependency.
- **Cache singleton location:** `apps/web-platform/server/share-hash-verdict-cache.ts` — NOT in `route.ts` (avoids PR #2347/#2401 Next.js route-file-exports outage class).
- **Owner vs share asymmetry:** `/api/kb/content/[...path]` streams unconditionally (no hash gate); only `/api/shared/[token]` hash-gates + caches.
- **Trade-offs flagged:** Range branch re-opens fd without `O_NOFOLLOW` (Node's `createReadStream` doesn't expose it) — TOCTOU window documented; cache-miss = 2× disk I/O; cache-miss + Range still requires full-file hash before serving any Range slice.

### Components Invoked

- Skill: soleur:plan, soleur:deepen-plan
- Context7 MCP: /nodejs/node, /vercel/next.js, /isaacs/node-lru-cache (evaluated, rejected)
- Codebase inspection: kb-binary-response.ts, kb-reader.ts, kb-content-hash.ts, shared/[token]/route.ts, kb/content/[...path]/route.ts, rate-limiter.ts, shared-page-binary.test.ts
- gh issue view: #2316, #2466
- markdownlint-cli2
