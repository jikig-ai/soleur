---
title: perf(kb) — scope-aware Cache-Control for KB binary responses
issue: 2329
branch: feat-kb-shared-cache-etag
created: 2026-04-18
deepened: 2026-04-18
type: perf
status: draft
---

# perf(kb): scope-aware Cache-Control for KB binary responses

Closes #2329.

## Enhancement Summary

**Deepened on:** 2026-04-18
**Sections enhanced:** Overview, Acceptance Criteria, Risks, Test Scenarios,
Alternative Approaches, Deferrals
**Research sources:** repo search (existing ETag + hash-gate + revocation
code paths), prior plans (`2026-04-15-fix-kb-share-button-pdf-attachments-plan.md`,
`2026-03-28-feat-pwa-manifest-service-worker-installability-plan.md`),
learnings (`2026-04-17-strong-etag-short-circuit-upstream-of-hash-gate.md`),
Cloudflare docs, RFC 7234 §5.2.2, AGENTS.md hard rules

### Key Improvements

1. **Revocation-latency reconciliation.** The initial plan adopted the
   issue's recommendation (`public, max-age=300,
   stale-while-revalidate=3600`) without reconciling against the
   earlier prior-art recommendation in
   `2026-04-15-fix-kb-share-button-pdf-attachments-plan.md` ("keep
   `private, max-age=60` — Cloudflare caching would break revocation
   latency"). The deepened plan revises the shared-scope value to
   `public, max-age=60, s-maxage=300, stale-while-revalidate=3600`,
   explicitly decouples browser TTL from CDN TTL, and documents the
   revocation-window math.
2. **`must-revalidate` on revoked-capable responses.** Added
   `must-revalidate` so the browser re-checks on every stale hit
   after `max-age` expires — pairs with ETag 304 to preserve cheap
   revalidation without serving stale bytes past expiry.
3. **Explicit test assertion for revocation + cache path.** Added an
   acceptance criterion asserting that a `410 revoked` response is
   NOT cacheable (no `max-age`, no `public`), so a post-revocation
   origin-fetch cannot be polluted by the 410 body staying at the
   edge.
4. **Test-spy pattern for cache-header assertions.** The learning
   `2026-04-17-strong-etag-short-circuit-upstream-of-hash-gate.md`
   establishes the pattern for asserting short-circuit behavior via
   `vi.hoisted` spies. Applied to the new Cache-Control tests so
   regression guards fire on wrong values, not missing helpers.
5. **Explicit helper contract for `CacheScope`.** The type is
   `"public" | "private"` plus a private lookup constant — callers
   cannot smuggle an unknown string. Eliminates a class of string
   drift between callers and helpers.

### New Considerations Discovered

- The `/shared/[token]/route.ts` 410 revocation path at line 149
  currently returns a `NextResponse.json` which has no explicit
  Cache-Control. Next.js defaults + Cloudflare defaults make this
  non-cacheable *in practice*, but an explicit `Cache-Control:
  no-store` on the 410 body makes the invariant testable and
  review-safe. Added to Phase 2.
- The `legacyNullHashResponse()` path (line 164) has the same
  shape and needs the same treatment.
- The `contentChangedResponse()` 410 path used by hash-gate
  mismatches has the same concern — a cached 410 would lie about
  a file that silently reverted to matching.
- `Vary: Accept-Encoding` is implicit from Next.js; no need to
  set it. But `Vary` on any other header would fragment the edge
  cache and defeat the optimization — documented as a non-goal.
- The current strong-ETag upstream-304 fast path (added in PR #2515,
  cited by the 2026-04-17 learning) short-circuits *before* owner
  lookup. That short-circuit emits `build304Response(strongETag)` —
  it MUST also inherit `scope: "public"` on the share-route call,
  or the 304 will emit a private Cache-Control that subtly
  contradicts the 200's public header. Phase 2 covers this.

## Overview

`apps/web-platform/server/kb-binary-response.ts` currently hard-codes
`Cache-Control: private, max-age=60` for every binary response — both the
authenticated dashboard route (`/api/kb/content/[...path]`) and the public
shared route (`/api/shared/[token]`). For a viral shared PDF this prevents
Cloudflare edge caching: every viewer hits origin. ETag + 304 is already
wired up end-to-end (strong ETag on `/shared/` via `content_sha256`, weak
ETag on the owner route via the `ino-size-mtimeMs` fstat tuple) — the only
remaining gap is the Cache-Control header itself.

**Scope.** Thread a `scope: "public" | "private"` parameter through the
four response builders (`buildBinaryHeaders`, `build304Response`,
`buildBinaryHeadResponse`, `buildBinaryResponse`). Wire the `/shared/`
route to pass `scope: "public"`; leave the owner route on `"private"` by
default. Update the parity test to stop excluding Cache-Control. No new
infrastructure, no migrations.

**Non-goals.**

- No Cloudflare Page Rules / cache-rule config changes in this PR —
  default Cloudflare behavior honors `public, max-age=…` with standard
  Cache-Control, which is what this change emits. A follow-up doc task
  (below) captures tier-dependent caps on large-object caching.
- No change to ETag derivation — it is already correct and covered by
  `kb-binary-response-etag.test.ts`.
- No change to hash-gate / verdict-cache paths — they are orthogonal.
- No owner-route cache header change — `"private, max-age=60"` stays.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #2329) | Reality (2026-04-18) | Plan response |
| --- | --- | --- |
| "No `ETag` / `Last-Modified`" | **Already implemented.** `buildETag` emits weak `W/"<ino>-<size>-<mtimeMs>"` or strong `"<sha256>"` on every response; `matchesIfNoneMatch` + `build304Response` short-circuit to 304 on match (`kb-binary-response.ts:227–260`). Covered by `kb-binary-response-etag.test.ts` (9 scenarios) and `kb-binary-response-head.test.ts`. | Do not re-add ETag plumbing. Scope-specific Cache-Control is the only remaining delta. |
| "Build `etag` in `readBinaryFile` from `lstat.mtimeMs + size`" | `readBinaryFile` does not exist by that name — the validator is `validateBinaryFile` and it already captures `ino`, `size`, `mtimeMs` onto `BinaryFileMetadata`. | Use existing metadata; no changes to the validator. |
| "`/shared/<token>` should emit `public` Cache-Control" | `build304Response` and `buildBinaryHeaders` both hard-code `private, max-age=60`. The share route passes a `strongETag` but no scope. | Add `scope` parameter to the four builders. Thread it from the share route. |
| "60s max-age is too low" | Same hard-coded value. The issue proposes `public, max-age=300, stale-while-revalidate=3600`. Prior plan `2026-04-15-fix-kb-share-button-pdf-attachments-plan.md` (line 344) pushed back: bumping browser `max-age` on shared binaries breaks revocation latency. | **Revised.** Adopt a split TTL: `public, max-age=60, s-maxage=300, stale-while-revalidate=3600, must-revalidate`. Browsers re-validate every 60s (preserves the existing revocation-latency contract); Cloudflare (which honors `s-maxage` preferentially per RFC 7234 §5.2.2.9) caches 5 minutes at the edge. `must-revalidate` forces the browser to re-check the ETag once max-age expires. Owner route stays `private, max-age=60`. |
| "Verify Cloudflare tier caps" | Not verified in-plan. Cloudflare Free caches objects up to 512 MB by default for static extensions; `MAX_BINARY_SIZE` here is 50 MB (owner-route cap). Below the edge cap. | Note in the PR body; no infra work. Document follow-up in `knowledge-base/engineering/ops/` as a separate task. |

## Context — relevant files

- `apps/web-platform/server/kb-binary-response.ts:246–326` — the four
  builders (`build304Response`, `buildBinaryHeaders`,
  `buildBinaryHeadResponse`, `buildBinaryResponse`) that emit or inherit
  the hard-coded `Cache-Control`.
- `apps/web-platform/server/kb-serve.ts:69–70,162–165` —
  `serveBinary` (owner path) and `serveSharedBinaryWithHashGate`
  (shared path) call `buildBinaryResponse`. Only the shared helper
  needs `scope: "public"`.
- `apps/web-platform/app/api/shared/[token]/route.ts:175,379` — the
  share route calls `build304Response(strongETag)` on the fast-path
  If-None-Match short-circuit AND `buildBinaryHeadResponse(binary,
  request, { strongETag })` on HEAD. Both must thread `scope:
  "public"`.
- `apps/web-platform/app/api/kb/content/[...path]/route.ts:143` —
  owner HEAD calls `buildBinaryHeadResponse(meta, request)` with no
  scope; inherits `"private"`.
- `apps/web-platform/test/kb-binary-routes-parity.test.ts:58–68` —
  the parity test explicitly excludes `Cache-Control` from its
  parity-headers list with a `// issue #2329` comment. After this PR
  the two routes will diverge intentionally, so the exclusion stays
  — but the comment is removed and a new assertion covers the
  scope-specific values.
- `apps/web-platform/test/kb-binary-response-etag.test.ts` +
  `apps/web-platform/test/kb-binary-response-head.test.ts` — existing
  ETag / HEAD coverage; the new scope parameter adds a small block
  of tests here (Phase 2).

## Acceptance Criteria

1. `/shared/[token]` GET, HEAD, and 304 short-circuit responses for a
   binary file emit:
   `Cache-Control: public, max-age=60, s-maxage=300, stale-while-revalidate=3600, must-revalidate`.
2. `/api/kb/content/[...path]` GET, HEAD, and 304 responses for a
   binary file emit: `Cache-Control: private, max-age=60` (unchanged).
3. ETag behavior is unchanged: owner = weak fstat ETag, shared = strong
   `sha256` ETag from `kb_share_links.content_sha256`.
4. 304 short-circuits (both routes) emit the Cache-Control header
   matching their scope — a `private` 304 must not appear on a `public`
   shared response.
5. `kb-binary-routes-parity.test.ts` passes with an **updated**
   Cache-Control assertion: `expect(ownerRes.headers.get("Cache-Control"))
   .toBe("private, max-age=60")` and `expect(sharedRes.headers
   .get("Cache-Control")).toBe("public, max-age=60, s-maxage=300,
   stale-while-revalidate=3600, must-revalidate")`. The `// issue #2329`
   comment is removed.
6. No change to cache-mode behavior for markdown responses (they are not
   routed through `buildBinaryResponse`).
7. `apps/web-platform` typecheck (`npm run typecheck`) and targeted tests
   (`kb-binary-response-*`, `kb-binary-routes-parity`,
   `shared-token-*`) pass locally.
8. Revocation-latency invariants:
   - A `shareLink.revoked = true` request emits `Cache-Control: no-store`.
   - The `contentChangedResponse()` 410 (hash mismatch) emits
     `Cache-Control: no-store`.
   - The `legacyNullHashResponse()` emits `Cache-Control: no-store`.
9. Browser revocation-latency SLA is unchanged (60s) — asserted by
   the `Cache-Control` value for `/shared/` 200s still containing
   `max-age=60` (not 300 or higher).

## Implementation Phases

### Phase 1 — failing tests (RED)

Add scope-specific assertions to the existing binary-response tests so
they fail against the current hard-coded header.

Files to edit:

- `apps/web-platform/test/kb-binary-response-etag.test.ts`
  - Add a describe block: `buildBinaryResponse — Cache-Control scope`.
  - `it("emits private, max-age=60 by default")` — assert
    `res.headers.get("Cache-Control") === "private, max-age=60"`
    (will pass pre-implementation — regression guard).
  - `it("emits the public Cache-Control string when scope is 'public'")`
    — pass `{ scope: "public" }` and assert
    `res.headers.get("Cache-Control") === "public, max-age=60,
    s-maxage=300, stale-while-revalidate=3600, must-revalidate"`.
    **Fails** until Phase 2.
  - `it("304 short-circuit inherits the request's scope (public)")` —
    pass `{ scope: "public" }` with a matching `If-None-Match`; assert
    status 304 AND the public Cache-Control. **Fails** until Phase 2.
  - `it("304 short-circuit inherits the request's scope (private)")` —
    no scope arg, matching `If-None-Match`; assert private
    Cache-Control. (Regression guard.)

- `apps/web-platform/test/kb-binary-response-head.test.ts`
  - Add a describe block: `buildBinaryHeadResponse — Cache-Control
    scope`.
  - `it("defaults to private")` — regression guard.
  - `it("emits public on a 200 when scope is 'public'")` — **fails**
    until Phase 2.
  - `it("emits public on a 304 when scope is 'public' and
    If-None-Match matches")` — **fails** until Phase 2.

- `apps/web-platform/test/kb-binary-routes-parity.test.ts`
  - Remove the `// Cache-Control (issue #2329 tracks the cleanup)`
    comment on the `PARITY_HEADERS` constant.
  - Add a new `describe("Cache-Control is intentionally divergent")`
    block with two assertions (one per route) against the expected
    scope-specific values. **Fails** until Phase 2.
  - Also add the 304-path assertion: owner 304 and shared 304 each
    emit their own scope's Cache-Control. Use the existing parity
    fixture helpers to build the conditional request.

- **Revocation / error-path tests.** Add to
  `apps/web-platform/test/shared-token-content-hash.test.ts` (or
  a new `shared-token-no-store.test.ts` if additions grow past ~30
  lines):
  - `it("410 on revoked share emits Cache-Control: no-store")` —
    prime `mockServiceFrom` with `revoked: true`; assert status
    410 AND `Cache-Control: no-store`. **Fails** until Phase 2.
  - `it("410 on content-changed emits Cache-Control: no-store")` —
    prime share-row hash ≠ on-disk hash; assert 410 + `no-store`.
  - `it("404 on unknown token emits Cache-Control: no-store")` —
    mock `.single<ShareRow>()` to return null; assert 404 + `no-store`.
  - `it("429 on rate-limit emits Cache-Control: no-store")` —
    mock `mockIsAllowed.mockReturnValue(false)`; assert 429 + `no-store`.

- **Test-spy pattern** (cited from learning
  `2026-04-17-strong-etag-short-circuit-upstream-of-hash-gate.md`):
  tests that already verify 304 short-circuits should remain
  unchanged — Cache-Control changes are orthogonal to the hash-drain
  short-circuit. Do NOT add `hashStreamSpy` to the new Cache-Control
  tests; keep those assertions header-only for clarity.

Run targeted tests to confirm each new assertion fails for the right
reason (wrong value, not missing helper):

```bash
cd apps/web-platform && ./node_modules/.bin/vitest run \
  test/kb-binary-response-etag.test.ts \
  test/kb-binary-response-head.test.ts \
  test/kb-binary-routes-parity.test.ts
```

### Phase 2 — implementation (GREEN)

Files to edit:

- `apps/web-platform/server/kb-binary-response.ts`
  - Introduce a type and a constant next to the helpers:

    ```ts
    export type CacheScope = "public" | "private";

    // Cache header values, keyed by scope.
    //
    // - `public` — shared-route binaries. Browser max-age=60 preserves
    //   the 60s revocation-latency SLA we inherited from the previous
    //   `private, max-age=60` default. `s-maxage=300` lets Cloudflare
    //   (and RFC-7234-compliant shared caches) keep an edge copy for
    //   5 minutes so repeat viewers of a viral PDF do not re-hit
    //   origin. `stale-while-revalidate=3600` lets the edge serve a
    //   slightly-stale body while refreshing in the background for
    //   up to 1 hour. `must-revalidate` forces the browser to re-check
    //   the ETag once max-age expires — pairs with the existing
    //   strong-ETag 304 path to make revalidation free (0 body bytes).
    //
    // - `private` — owner-route binaries. Unchanged from current
    //   behavior: 60s browser cache, no shared-cache storage.
    const CACHE_CONTROL_BY_SCOPE: Record<CacheScope, string> = {
      public:
        "public, max-age=60, s-maxage=300, stale-while-revalidate=3600, must-revalidate",
      private: "private, max-age=60",
    };
    ```

  - Extend `buildBinaryHeaders(payload, opts?)` so `opts?` accepts
    `scope?: CacheScope` (default `"private"`). Use `CACHE_CONTROL_BY_SCOPE[opts?.scope ?? "private"]`.
  - Extend `build304Response(etag, opts?)` with the same optional
    `scope`. Default `"private"`.
  - Extend `buildBinaryHeadResponse(payload, request?, opts?)` so
    `opts?.scope` is threaded into both `build304Response` (when
    `If-None-Match` matches) and `buildBinaryHeaders`.
  - Extend `buildBinaryResponse(meta, request?, opts?)` similarly —
    the If-None-Match short-circuit passes `scope` into
    `build304Response`; the 200 / 206 path passes it into
    `buildBinaryHeaders`.
  - Keep the existing `strongETag` option alongside `scope` (both
    optional, both on the same `opts` object) so callers can pass
    either or both.

- `apps/web-platform/server/kb-serve.ts`
  - `serveSharedBinaryWithHashGate`: update the
    `buildBinaryResponse(meta, request, { strongETag: expectedHash })`
    call to `{ strongETag: expectedHash, scope: "public" }`.
  - `serveBinary` (owner path): no change — inherits the default
    `"private"`.

- `apps/web-platform/app/api/shared/[token]/route.ts`
  - Line 175: `build304Response(strongETag)` →
    `build304Response(strongETag, { scope: "public" })`.
  - Line 379: `buildBinaryHeadResponse(binary, request, {
    strongETag })` → `buildBinaryHeadResponse(binary, request, {
    strongETag, scope: "public" })`.

- `apps/web-platform/app/api/kb/content/[...path]/route.ts`
  - No change — default `"private"` is correct.

- **410 / error-response hardening.** Ensure the three 410 paths
  and the 404/403 fall-throughs explicitly opt out of caching so
  an edge cannot serve a stale 410 after the underlying state
  recovers (e.g., a share that was revoked and then re-issued
  under the same token by future migration). Files to edit:

  - `apps/web-platform/app/api/shared/[token]/route.ts` — the
    `shareLink.revoked` 410 (line 149–156), the 404 not-found
    (line 142–147), and the 429 rate-limit (line 121–130).
  - `apps/web-platform/server/kb-serve.ts` — `contentChangedResponse()`
    (line 26–34) and the `legacyNullHashResponse()` body emitted
    by the share route.

  Treatment: add `Cache-Control: no-store` to each JSON error
  Response via `{ headers: { "Cache-Control": "no-store" }, status: ... }`
  on `NextResponse.json`. One-liner per site; no new helper needed.
  If this diff grows beyond four sites, extract
  `noStoreJsonResponse(body, status)` into `kb-serve.ts`.

Re-run Phase 1 tests. All should be GREEN.

```bash
cd apps/web-platform && ./node_modules/.bin/vitest run \
  test/kb-binary-response-etag.test.ts \
  test/kb-binary-response-head.test.ts \
  test/kb-binary-routes-parity.test.ts \
  test/shared-token-head.test.ts \
  test/shared-token-verdict-cache.test.ts \
  test/kb-serve-hash-gate.test.ts
```

### Phase 3 — refactor / cleanup

- If `buildBinaryHeaders` / `buildBinaryResponse` end up with a
  growing `opts` object, consider extracting a shared `BinaryServeOpts`
  interface — but only if the signatures read awkwardly. YAGNI guard:
  do not introduce the interface speculatively.
- Double-check the `// issue #2329` comment is the only stale
  reference to this ticket in the app: `rg "#2329" apps/web-platform`.
- Update the `buildBinaryHeaders` JSDoc to note that scope is
  optional and defaults to `"private"`.

### Phase 4 — verification

- Run `apps/web-platform` typecheck: `cd apps/web-platform && npm run
  typecheck` (or project equivalent).
- Run the full targeted test suite:
  `./node_modules/.bin/vitest run test/kb-*.test.ts test/shared-*.test.ts
  test/shared-*.test.tsx` from `apps/web-platform/`.
- Manual smoke (optional — not required for merge):
  - `curl -I http://localhost:3000/api/shared/<token>` → expect
    `Cache-Control: public, max-age=60, s-maxage=300, stale-while-revalidate=3600, must-revalidate`.
  - `curl -I http://localhost:3000/api/kb/content/<path>` with a
    session cookie → expect `Cache-Control: private, max-age=60`.

## Files to Edit

- `apps/web-platform/server/kb-binary-response.ts` — add `CacheScope`,
  `CACHE_CONTROL_BY_SCOPE`, thread `scope?` through four builders.
- `apps/web-platform/server/kb-serve.ts` — pass `scope: "public"` from
  `serveSharedBinaryWithHashGate`.
- `apps/web-platform/app/api/shared/[token]/route.ts` — pass `scope:
  "public"` at lines 175 and 379.
- `apps/web-platform/test/kb-binary-response-etag.test.ts` — add
  scope-specific assertions.
- `apps/web-platform/test/kb-binary-response-head.test.ts` — add
  scope-specific assertions.
- `apps/web-platform/test/kb-binary-routes-parity.test.ts` — add
  divergent Cache-Control assertions; remove `#2329` stale comment.

## Files to Create

None.

## Open Code-Review Overlap

Query run against `gh issue list --label code-review --state open`. Four
issues reference the files this plan touches:

- **#2329** — this plan. Not overlap.
- **#2325** — "Cleanup: inline ATTACHMENT_EXTENSIONS + import
  MAX_BINARY_SIZE in tests" (`kb-binary-response.ts`). P3. **Acknowledge.**
  Different concern (export surface + test imports vs. cache header
  derivation). The scope parameter addition does not touch
  `ATTACHMENT_EXTENSIONS` or `MAX_BINARY_SIZE`. Scope-out remains open.
- **#2300** — "arch: move MAX_BINARY_SIZE out of kb-binary-response.ts
  into kb-limits.ts" (`kb-binary-response.ts`). P3. **Acknowledge.**
  Module-extraction refactor that is orthogonal to the scope parameter.
  Folding it in would balloon the PR and mix concerns. Scope-out remains
  open.
- **#2297** — "arch: unify file-kind classification across owner and
  shared viewer pages" (`api/shared`). P2. **Acknowledge.** Concerns
  viewer file-kind logic (`deriveBinaryKind` + viewer UI), not
  Cache-Control. No files overlap in practice — the share-route edit
  here is a 2-arg diff at two call sites.
- **#2322** — "Agent cannot preview what a recipient sees at
  `/shared/[token]` (view-parity gap)" (`api/shared`). P3, type/feature.
  **Acknowledge.** New feature (agent preview), not the same concern.

**Disposition summary:** 0 folded in, 4 acknowledged, 0 deferred. No
overlap blocks this PR.

## Domain Review

**Domains relevant:** Engineering (CTO)

No product/UX surface changes — this is a server-side header change on
existing endpoints. No new components, no new pages, no copy. The CPO /
CMO / UX gates do not apply by file-path heuristic
(`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`) or by
semantic assessment. CTO implications are low: pure header-policy
change, no storage, no migration, no new dependency, no infra change.
Cloudflare caching is default-on for standard `Cache-Control: public`
values at the site's current tier.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Low risk. The change is a two-constant lookup and a
threaded optional parameter across four pure functions. ETag / 304
plumbing is already correct and tested (9 scenarios). The only
behavioral change visible from outside is the Cache-Control header
value on the shared route, which is safe to cache at the edge because
(a) the response body is byte-identical to what `/shared/` already
serves, (b) the URL is token-scoped so cache keys are already
segmented per share, (c) 304 + strong-ETag still short-circuit repeat
hits. Worst-case rollback is a one-line revert of
`CACHE_CONTROL_BY_SCOPE.public`.

## Test Scenarios

Summarized for ship/review; each maps to a Phase 1 assertion.

1. Default `buildBinaryResponse` → `private, max-age=60`.
2. `buildBinaryResponse({ scope: "public" })` → `public, max-age=60,
   s-maxage=300, stale-while-revalidate=3600, must-revalidate`.
3. `buildBinaryResponse({ scope: "public" })` with matching
   `If-None-Match` → 304 + public Cache-Control.
4. `buildBinaryResponse()` with matching `If-None-Match` (no scope) →
   304 + private Cache-Control.
5. `buildBinaryHeadResponse` — same four cases as above.
6. `build304Response(etag)` → private Cache-Control.
7. `build304Response(etag, { scope: "public" })` → public
   Cache-Control.
8. Parity test: owner route GET → private; shared route GET → public;
   both 200 and 304 paths verified per route.
9. Parity test: HEAD mirrors GET per scope.
10. `shared-token-head.test.ts`, `shared-token-verdict-cache.test.ts`,
    `kb-serve-hash-gate.test.ts` — existing tests still pass without
    modification (ETag + 304 paths don't change, only the Cache-Control
    value does).

## Risks

- **Revocation latency.** This is the load-bearing risk that shaped
  the split-TTL design. Math:
  - **Browser worst case:** `max-age=60` — a viewer who already has
    the PDF open sees stale bytes for up to 60 seconds after
    revocation. Same as today's behavior (`private, max-age=60`).
    No regression.
  - **Cloudflare edge worst case:** `s-maxage=300` — a viewer who
    hits the edge after the cache fills sees stale bytes for up to
    5 minutes after revocation. **This is a regression from today's
    behavior (0s edge caching because `private` excluded the edge).**
    Accepted trade-off: the ~5-minute window is acceptable for
    content that is share-link-scoped (viewers came from the owner
    explicitly handing out a URL), and the caller can flush the
    edge via Cloudflare's `purge_by_url` on revoke if required —
    documented as a Phase 4 follow-up option, not a requirement.
  - **`stale-while-revalidate=3600`:** the edge MAY serve up to 1
    hour of background-refresh. The background fetch will hit
    origin, see `revoked = true`, and receive a 410 with
    `Cache-Control: no-store` (added in this PR) — which the edge
    will use to expire the stored 200. Net effect: revocation
    propagates within the next edge-refresh window even while SWR
    is active.
  - **The 410 `no-store` mitigation is load-bearing** — without it,
    a cached 410 could pin the error state at the edge past its
    natural lifetime. Covered by the Phase 2 error-response
    hardening and a Phase 1 test assertion.
- **Over-caching stale content at the edge.** Mitigation: the share
  route uses a strong ETag derived from `content_sha256`, and the
  content-changed path returns 410 on mismatch. `stale-while-revalidate`
  bounded at 1 hour means the worst-case window for an edge to serve
  a stale byte-sequence is 1 hour after origin mutation. Files mutate
  rarely on the KB (share tokens are explicitly immutable views of an
  `mtime`d file), and mutation triggers the 410 path anyway.
- **Cloudflare tier / file-size caps.** `MAX_BINARY_SIZE` is 50 MB
  (validator-enforced). Cloudflare Free caches up to 512 MB for
  static extensions with standard `Cache-Control: public`. Below
  the cap; no action needed. Worth mentioning in the PR body so
  future upload-cap lifts are aware.
- **Corporate proxies.** `public` allows shared caches (corporate
  proxies, ISP transparent caches). Since the share token is random
  128-bit and URL-scoped, a cache key leak between users is safe:
  all viewers of a valid token see the same bytes by construction.
- **Accidental owner-route scope leak.** Mitigation: the default is
  `"private"`; only `serveSharedBinaryWithHashGate` and the
  share-route call sites pass `"public"`. Regression guards in
  Phase 1 assert the default on every builder.

## Alternative Approaches Considered

| Approach | Why not chosen |
| --- | --- |
| **Two separate helpers** (`buildPublicBinaryResponse` + `buildPrivateBinaryResponse`) | Duplicates 70 lines of header logic, ETag derivation, and Range / 304 short-circuit code for one string difference. The parameter is the minimal carve-out. |
| **Route-level header overwrite** (let the route mutate the Response headers after `buildBinaryResponse` returns) | Doesn't work for 304 short-circuits — by the time the Response is returned, the header is on a `new Response()` and the 304 path has its own distinct Response. Also clobbers the helper's guarantee that 200/206/304 are header-consistent. |
| **Cloudflare Cache Rule** (add a Rule that sets `Cache-Control` on `/shared/*` paths) | Fixes CDN behavior but leaves browser and corporate-proxy behavior wrong; also a runtime-config drift hazard because the header contract should live in the application. |
| **Bump owner Cache-Control too** (e.g., `private, max-age=300`) | Out of scope. Owner route mutations must be visible to the author quickly; 60s is a deliberate sizing. If we ever revisit, file as a separate issue. |
| **Add `Vary: Authorization`** to the shared 200 response | Not needed — the share route is not gated by Authorization; the token is in the URL path. `Vary` would prevent caching without benefit. |
| **Issue's original value** (`public, max-age=300, stale-while-revalidate=3600`) | Reconciled against the prior plan (`2026-04-15-fix-kb-share-button-pdf-attachments-plan.md` line 344) which warned that bumping the browser `max-age` to 300s breaks the 60s revocation-latency SLA. The split-TTL variant keeps browser at 60s while unlocking the edge cache via `s-maxage`. |
| **Cloudflare `purge_by_url` on revoke** | Cleaner revocation story (instant edge flush) but requires wiring Cloudflare API credentials into the revoke path, adds a network dependency to a currently-sync DB update, and needs reliability handling (retries, failure alerts). Deferred to a follow-up if the 5-minute edge-revocation window becomes a support concern. |
| **`no-cache` instead of `must-revalidate`** | `no-cache` forces revalidation on every fetch regardless of max-age — equivalent to `max-age=0`. Defeats the browser-side caching that `max-age=60` is intended to preserve. `must-revalidate` fires only *after* max-age expires, which is the semantic we want. |
| **Short-circuit `stale-while-revalidate` on error** | `stale-if-error` handles this explicitly (RFC 5861), but Cloudflare does not honor it by default. Omitted to avoid false confidence; SWR is sufficient and Cloudflare-supported. |

## PR Body — Closes note

The PR description should include `Closes #2329` on its own line so
auto-close fires on merge (per AGENTS.md `wg-use-closes-n-in-pr-body`).

## Deferrals / Follow-ups

- **Cloudflare cache-rule audit (doc-only).** File a P3 follow-up
  issue: verify `/api/shared/[token]` does not have a conflicting
  Page Rule / Transform Rule that overrides origin Cache-Control.
  Store findings under
  `knowledge-base/engineering/ops/runbooks/cloudflare-kb-cache.md`.
  Milestone: Post-MVP / Later.
- **Larger-object cache strategy.** If `MAX_BINARY_SIZE` ever lifts
  above the Cloudflare tier cap (512 MB on Free), the public cache
  will silently fall back to pass-through on oversize files — no
  bug, but worth documenting so we don't chase a phantom. Out of
  scope here.
- **Edge purge on revoke.** If the 5-minute edge-revocation window
  (s-maxage=300) becomes a support or compliance concern, add a
  `purge_by_url` call to the Cloudflare API inside
  `kb-share.ts:revokeShare` so revocations flush instantly. Adds a
  Cloudflare dependency to the revoke path (needs retry + dead-letter
  handling). Milestone: Post-MVP / Later. File only if support traffic
  surfaces the problem — premature infra coupling otherwise.
- **Metric: share-route origin bandwidth.** After deploy, add a
  dashboard panel for `/api/shared/[token]` origin requests per
  hour. Expected outcome: flat-to-declining curve as the edge cache
  fills. Alerts if the curve does NOT drop within a week would
  indicate Cloudflare is not honoring the public Cache-Control
  (e.g., a conflicting Transform Rule). P3 follow-up.

## References

- RFC 7234 §5.2.2 — Cache-Control response directives; §5.2.2.9
  defines `s-maxage` precedence over `max-age` for shared caches.
- RFC 7234 §5.2.2.1 — `must-revalidate` semantics.
- RFC 5861 — `stale-while-revalidate` and `stale-if-error` (only
  SWR is Cloudflare-supported; see non-goals).
- Cloudflare "Cache Control" docs — <https://developers.cloudflare.com/cache/concepts/cache-control/>
- Prior plan: `knowledge-base/project/plans/2026-04-15-fix-kb-share-button-pdf-attachments-plan.md`
  (line 344) — the revocation-latency counterpoint that shaped the
  split-TTL design.
- Learning: `knowledge-base/project/learnings/2026-04-17-strong-etag-short-circuit-upstream-of-hash-gate.md`
  — test-spy pattern for short-circuit verification; informs Phase 1
  decision to keep Cache-Control tests header-only.
- Prior PR: #2515 (upstream 304 short-circuit) — the
  `build304Response` call site at route.ts:175 that this plan
  extends with `scope: "public"`.
