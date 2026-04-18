---
name: CF Cache Purge on KB Share Revoke
description: Active Cloudflare cache purge from revokeShare to close the s-maxage TTL leak window after a share is revoked, plus drift-path bypass remediation
type: project
date: 2026-04-18
issue: 2568
pr: 2569
related:
  - 2026-04-18-cloudflare-default-bypasses-dynamic-paths.md
  - 2026-04-15-multi-agent-review-catches-bugs-tests-miss.md
tags: [security, cloudflare, cache-invalidation, kb-share, revocation]
---

# Learning: CF Cache Purge on KB Share Revoke

## Problem

Revoked KB shares (`DELETE /api/kb/share/<token>`) continued to be served by the Cloudflare edge cache with the original 200 + body until the existing entry's `s-maxage=300` TTL expired. The DELETE updated the database `revoked` flag but never told Cloudflare to drop the cached entry. Origin correctly served `410 Gone` with `Cache-Control: no-store`, but `no-store` only governed the *new* response — Cloudflare kept serving the previously-cached 200 until the entry expired.

Discovered live on prod during the verification sweep for #2521 (X-Soleur-Kind header). Reproduced cleanly in 4 steps:

```js
// 1. POST /api/kb/share → token; 2. GET /api/shared/<token> → 200, populates CF cache
// 3. DELETE /api/kb/share/<token> → 200, DB row revoked
// 4. GET /api/shared/<token> (no cache-bust) → cached 200 ❌
//    GET /api/shared/<token>?_=<ts>      → 410 Gone (origin) ✓
```

5-minute security boundary leak window after every revoke.

## Solution

Two-layer fix:

1. **Active CF Cache Purge** in `apps/web-platform/server/kb-share.ts::revokeShare` (and the parallel content-drift path in `createShare`). Both surfaces — HTTP DELETE handler and the MCP `kb_share_revoke` tool — inherit purge by construction because both call `revokeShare`. Purge failure returns **502** + Sentry alarm (NOT silent fallback) so the operator sees the partial-failure state.
2. **Defense-in-depth**: drop `CACHE_CONTROL_BY_SCOPE.public` `s-maxage` from `300 → 60` in `apps/web-platform/server/kb-binary-response.ts`. Worst-case leak window if purge itself fails is bounded to 60s. `stale-while-revalidate=3600` blunts the origin RPS impact (edge serves stale instantly while revalidating).

Helper at `apps/web-platform/server/cf-cache-purge.ts`:

```ts
const APP_ORIGIN = "https://app.soleur.ai"; // SECURITY: hard-coded
const PURGE_TAG = { feature: "kb-share", op: "revoke-purge" } as const;

export async function purgeSharedToken(token: string): Promise<PurgeResult> {
  // ... read CF_API_TOKEN_PURGE + CF_ZONE_ID, AbortController + 5s timeout,
  // POST { files: [`${APP_ORIGIN}/api/shared/${token}`] }
  // Decode CF response { success, errors[] } — non-2xx OR success=false → cf-api error
}
```

New runtime credential `CF_API_TOKEN_PURGE` (Cache Purge:Edit on `soleur.ai` zone) in Doppler **`prd`** (NOT `prd_terraform` — runtime pod reads `prd`, per `cq-doppler-service-tokens-are-per-config`).

## Key Insights

1. **Cache invalidation is part of the security boundary.** Origin `Cache-Control: no-store` on the 410 response only governs that response — Cloudflare keeps serving the previously-cached 200 until its TTL expires. For revoke endpoints fronted by a shared cache, active purge is mandatory; TTL alone is not a security control.

2. **Wire shared-state mutations through the lifecycle module, not the route handler.** Because `revokeShare` is the consolidated module from #2298, both the HTTP DELETE and the MCP `kb_share_revoke` inherit the purge call by construction. The route handler stays a thin HTTP wrapper. Same pattern caught the agent-native parity check at no extra cost.

3. **Re-evaluate plan deferrals when their gating premise resolves mid-PR.** The plan's `## Non-Goals` section deferred the `createShare` content-drift purge as "wiring it in is mechanical, but it expands the diff." Once `purgeSharedToken` was implemented and tested, the architecture-strategist agent flagged the bypass — the deferral's premise no longer held within the same PR. Fixed inline rather than carrying to a separate issue. Lesson: deferrals tied to "X doesn't exist yet" should be re-evaluated the moment X exists.

4. **Plans should pin verbatim error strings to a single source.** The `"Revoke succeeded but cache purge failed; share may be served from cache for up to 60 seconds"` string appeared in 5 places (source + 3 tests + plan body). Code-quality agent flagged this; extracted to `REVOKE_PURGE_FAILED_MESSAGE` const. The fully-mocked test (`kb-share-tools.test.ts`) is the exception — see Session Errors §5.

## Session Errors

1. **Bash CWD reset between sequential calls** — `cd apps/web-platform && ./node_modules/.bin/vitest` worked, then a bare `./node_modules/.bin/vitest` in the next call failed because the harness reset cwd. **Recovery:** chained `cd && command` pattern explicitly. **Prevention:** in long sessions running app-level binaries from a worktree, default to absolute paths or always re-`cd` in the same Bash call.

2. **Edit-without-read on `infra/cache.tf`** — Edit tool rejected; the file hadn't been read in this turn. **Recovery:** Read first, then Edit. **Prevention:** AGENTS.md rule `hr-always-read-a-file-before-editing-it` already covers this; the violation reflects context-compaction-erased prior reads. No new rule needed; behavior is already enforced by the Edit tool.

3. **Edit-without-read on `app/api/kb/share/[token]/route.ts`** — same class as #2. **Recovery:** Read first. **Prevention:** same as #2.

4. **`AbortSignal.timeout` does not play nicely with `vi.useFakeTimers`** — pattern-recognition agent recommended switching from manual `AbortController + setTimeout` to `AbortSignal.timeout(MS)` to match `github-api.ts`. After refactor, the timeout test hung 5s (real timer) because vitest's fake-timer mock does not reliably intercept the runtime-internal timer that `AbortSignal.timeout` uses. **Recovery:** reverted to manual `AbortController + setTimeout(controller.abort, ms)` which vi *does* intercept. **Prevention:** propose AGENTS.md sharp-edge — see Workflow Proposals below.

5. **Constant import from fully-mocked module** — extracted `REVOKE_PURGE_FAILED_MESSAGE` from `kb-share.ts` for drift-resistance, then attempted to `import { REVOKE_PURGE_FAILED_MESSAGE } from "@/server/kb-share"` in `kb-share-tools.test.ts`. That test fully `vi.mock()`s `@/server/kb-share`, so the import resolved to the mock factory's exports (undefined since the factory only exposed the function mocks). **Recovery:** verbatim string copy in that one test file with a sync-comment explaining why; cross-file drift is caught by `kb-share.test.ts` which imports the real symbol. **Prevention:** propose work-skill instruction — see Workflow Proposals below.

## Workflow Proposals

### A. AGENTS.md sharp-edge — `AbortSignal.timeout` + `vi.useFakeTimers`

Add to `## Code Quality`:

> When writing a test-friendly timeout-bounded async helper, use manual `AbortController + setTimeout(controller.abort, ms)` rather than `AbortSignal.timeout(ms)`. `vi.useFakeTimers` intercepts the manual `setTimeout` reliably across Node versions; `AbortSignal.timeout` uses a runtime-internal timer that vi does not consistently intercept, causing the timeout test to hang 5s (real). **Why:** PR #2569 cf-cache-purge.ts refactor — see this learning §Session Errors #4.

Enforcement tier: prose rule (cannot mechanically detect; pattern-recognition agents may recommend the inverse).

### B. Work-skill instruction — Constant import from mocked module

Add to `plugins/soleur/skills/work/SKILL.md` Phase 2 sharp edges:

> When extracting a constant for drift-resistance, identify all downstream test files that mock the source module. If any test fully `vi.mock("module-X")`s the source, it cannot import the constant from `module-X` — the import resolves to the mock factory's value (often `undefined`). Choose: (a) include the constant in the mock factory return value, (b) extract the constant to a separate non-mocked module, or (c) verbatim copy the literal in that single test file with a sync-comment. **Why:** PR #2569 — see this learning §Session Errors #5.

Enforcement tier: skill instruction (prose; the failure mode surfaces only when the test is run, so prose is the highest viable enforcement).

## Cross-References

- Issue: #2568 — security: revoked KB shares served from CF edge cache for up to s-maxage TTL
- PR: #2569
- Related learnings:
    - `2026-04-18-cloudflare-default-bypasses-dynamic-paths.md` — sibling: CF default cache-eligibility (this learning's TTL backstop is meaningful only because that ruleset opts `/api/shared/*` *into* edge caching)
    - `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` — meta: the architecture-strategist agent caught the drift-path bypass inline that the plan had deferred
- Plan: `knowledge-base/project/plans/2026-04-18-fix-purge-cf-cache-on-share-revoke-plan.md`
- AGENTS.md rules applied: `cq-silent-fallback-must-mirror-to-sentry`, `cq-doppler-service-tokens-are-per-config`, `cq-cloudflare-dynamic-path-cache-rule-required`, `cq-vite-test-files-esm-only`, `cq-in-worktrees-run-vitest-via-node-node`, `cq-always-run-npx-markdownlint-cli2-fix-on`
