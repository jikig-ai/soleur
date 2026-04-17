---
name: Strong-ETag 304 short-circuit belongs upstream of the hash gate
description: When the strong ETag is available from a cheap source (DB row) before filesystem work, short-circuit on If-None-Match there — not in the response builder
category: performance-issues
module: kb-binary-response
date: 2026-04-17
pr: 2515
issues: [2324, 2311, 2303]
tags: [http-caching, etag, if-none-match, toctou, verdict-cache, tagged-union, test-patterns]
---

# Learning: Strong-ETag 304 short-circuit belongs upstream of the hash gate

## Problem

The `/api/shared/[token]` endpoint has a multi-stage pipeline: rate-limit → share-lookup (Supabase) → owner-lookup (Supabase) → `validateBinaryFile` (fd open + fstat) → hash gate (SHA-256 drain on cache miss) → response emission. The strong ETag for share responses is `kb_share_links.content_sha256` — it is in memory the moment share-lookup returns.

The initial HEAD implementation placed the `If-None-Match` check inside `buildBinaryHeadResponse` (the response builder). That meant every conditional HEAD on a cached client paid the full gate cost — two Supabase round-trips, one `validateBinaryFile` fstat, and on cold-verdict a full file hash drain — only to return a 304 with no body.

Equivalent symptom for GET: a client with a fresh `If-None-Match: "<content_sha256>"` pays the full hash drain (up to 50 MB) before the 304 short-circuit fires.

## Solution

Move the conditional-match check into the resolver **immediately after** the strong ETag is known, before any downstream work:

```ts
// server/share-route-helpers.ts (inside resolveShareForServe, after share-lookup)
const strongETag = formatStrongETag(shareLink.content_sha256);
const ifNoneMatch = request.headers.get("if-none-match");
if (ifNoneMatch && ifNoneMatchMatches(ifNoneMatch, strongETag)) {
  return { kind: "response", response: build304Response(strongETag) };
}
```

Placement matters: the check runs *after* `content_sha256` is in hand but *before* owner-lookup, filesystem validation, and hash drain. Revocation and legacy-null-hash gates still run before this fast path because they short-circuit to 410 on states a 304 would falsely hide.

Three supporting extractions in `server/kb-binary-response.ts` make this clean:

1. `build304Response(etag)` — the 304 body-less response, shared by `buildBinaryResponse`, `buildBinaryHeadResponse`, and the upstream fast path.
2. `formatStrongETag(sha)` — canonical `"${sha}"` formatting so the upstream comparison uses the same wire format as the downstream emitter.
3. `ifNoneMatchMatches(header, etag)` — re-exports the private weak-equality comparator so upstream callers get RFC 7232 semantics without reimplementing.

### Verifying the optimization behaviorally

Tests that assert the optimization fires must count hash drains, not response statuses. A status-only test passes even if the hash drain still runs. The pattern that works:

```ts
const hashStreamSpy = vi.hoisted(() => vi.fn());
vi.mock("@/server/kb-content-hash", async () => {
  const actual = await vi.importActual<typeof import("@/server/kb-content-hash")>(
    "@/server/kb-content-hash",
  );
  return {
    ...actual,
    hashStream: (...args) => {
      hashStreamSpy(...args);
      return actual.hashStream(...args);  // preserve behavior
    },
  };
});
```

This wraps the real implementation in a spy, so the hash check still mutates return values correctly (share-lookup's hash must match the drained hash for a 200), *and* the test can assert `hashStreamSpy.toHaveBeenCalledTimes(0)` on the fast path or `.toHaveBeenCalledTimes(1)` on a HEAD+GET sequence to prove verdict-cache sharing.

## Key Insight

HTTP-layer conditional-request short-circuits are usually described as "bandwidth savings." That framing undersells them. When the validator lives in a **cheap upstream source** (a DB row, a cached header, a tiny manifest file), moving the If-None-Match check upstream of the expensive gate transforms them into **work-savings AND bandwidth-savings**. The test to spot this opportunity: "What is the cheapest place I can produce a correct ETag?" — if that place is upstream of filesystem or CPU work, the 304 check belongs there.

Corollary for security pipelines: the fast path does NOT leak information to the client. A 304 with a matching If-None-Match tells the client only that their cached ETag is still valid — the same information the server already committed to by issuing that ETag on a prior 200. Skipping the hash gate on a conditional match is not a security regression because the client already has the bytes the hash would have validated.

## Session Errors

- **Bash CWD not persistent across tool invocations** — Recovery: re-prefixed each `./node_modules/.bin/vitest` call with `cd <abs-path> &&`. Prevention: already covered by `cq-for-local-verification-of-apps-doppler`; kept to one-shot cd-prefixed commands thereafter.
- **markdownlint-cli2 --fix promoted `#2515` to `# 2515` (new h1)** — Recovery: rewrote the line as `PR #2515` so the `#` is no longer the first character after a blank line. Prevention: when writing standalone PR/issue references in markdown files, always use the `PR #N` / `Issue #N` form, never `#N` alone on a line. (Skill edit proposed below: markdownlint runs automatically via pre-commit hook; the rule should note this edge case.)

## Related

- PR #2477 — established the `expected: { ino, size }` TOCTOU defense this PR preserves across HEAD paths.
- PR #2486 — introduced the strong-ETag path (`content_sha256` → `"<sha>"`); this PR extends it with an upstream 304 fast path.
- Learning `2026-04-17-stream-response-toctou-across-fd-boundary.md` — documents the fd-split TOCTOU invariants carried into HEAD.
- Learning `2026-04-17-kb-share-mcp-parity-lstat-toctou-and-mock-cascade.md` — documents why pre-open `lstat` must not be re-added.
