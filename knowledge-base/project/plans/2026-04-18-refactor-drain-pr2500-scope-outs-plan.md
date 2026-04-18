# Drain deferred-scope-out backlog for apps/web-platform (PR #2500 follow-ups)

**Branch:** `feat-one-shot-drain-pr2500-scope-outs`
**Closes:** #2510, #2511, #2512
**References:** PR #2500 (origin review), PR #2486 (one-PR-three-closures pattern), PR #2497 (MCP registration pattern)
**Milestone:** Phase 4: Validate + Scale
**Type:** refactor (cross-cutting cleanup)

## Overview

PR #2500 shipped the KB-chat sidebar cleanup. Its review surfaced three sibling scope-outs — all targeted at `apps/web-platform`, all review-origin, all labeled `deferred-scope-out` — which this PR drains in a single focused refactor. Rationale for bundling: every issue names a distinct file (no merge conflicts), the fixes compose cleanly in a linear dependency (#2510 → #2511 → #2512), and the scope-out bodies explicitly invite re-evaluation "when the first batch-frequency caller of `/api/conversations` ships" — which is exactly #2512 in this bundle.

### What ships

1. **`withUserRateLimit` helper** (#2510) — extracts the pattern from `app/api/analytics/track/throttle.ts` into a reusable `server/with-user-rate-limit.ts`. Applied to GET `/api/chat/thread-info` and GET `/api/conversations` at 60 req/min keyed by `user.id`.
2. **Single-query lookup** (#2511) — collapses the two-round-trip SELECT + COUNT in `server/lookup-conversation-for-path.ts` into one PostgREST call using an embedded-resource count. Unblocks the batch-frequency MCP caller from #2512.
3. **`conversations_lookup` MCP tool** (#2512 P2 slice) — registers one new tool via `buildConversationsTools()` following the `kb-share-tools.ts` precedent from PR #2497. Defers `conversations_list` + `conversation_archive` (P3) to a separate issue because they require new HTTP endpoints out of scope.

### What does not ship

- `conversations_list` MCP tool — needs `GET /api/conversations` (list variant, no path filter) endpoint; deferred to follow-up issue.
- `conversation_archive` MCP tool — needs `PATCH /api/conversations/:id` endpoint; deferred to same follow-up issue.
- RPC or denormalized `message_count` alternatives from #2511 — subselect is chosen as minimal-risk; RPC/denorm remain re-evaluation triggers if p95 latency crosses threshold after batch-frequency callers ship.
- Rate-limit helper applied to `/api/kb/tree`, `/api/kb/search`, `/api/flags` — audited per #2510 fix step 4, outcome documented inline (see "Rate-limit audit of other authenticated GETs" below).

## Open Code-Review Overlap

Five open scope-outs touch files this PR modifies:

| Issue | File | Disposition |
|-------|------|-------------|
| #2510 | `server/with-user-rate-limit.ts` (new) | **Fold in.** This PR creates the helper + applies it. `Closes #2510`. |
| #2511 | `server/lookup-conversation-for-path.ts` | **Fold in.** This PR collapses the 2-query pattern. `Closes #2511`. |
| #2512 | `server/agent-runner.ts` | **Fold in (P2 slice only).** This PR ships `conversations_lookup`. `Closes #2512` — PR body explicitly notes that P3 items are split into a new follow-up issue. |
| #2335 | `server/agent-runner.ts` | **Acknowledge.** Asks for unit tests on `canUseTool` allow/deny shape. Separate concern from MCP tool registration; our tests cover the new tool's handler, not the permission gate. Issue stays open. |
| #1662 | `server/agent-runner.ts` | **Acknowledge.** Asks to generalize MCP tool extraction. `kb-share-tools.ts` already established the sibling-module pattern (PR #2497); this PR mirrors that pattern via `conversations-tools.ts`. The meta-extraction (a shared factory abstraction) is still out of scope — issue stays open to track that design cycle. |

No fresh scope-outs are expected to be filed for the files in this PR.

## Rate-limit audit of other authenticated GETs (#2510 step 4)

| Route | GET authenticated? | Needs rate limit? | Reasoning |
|-------|-------------------|-------------------|-----------|
| `/api/kb/tree` | Yes (via `supabase.auth.getUser()`). | **Yes — wrap.** Agent-native caller could loop this to enumerate KB state per turn. Call cost: service-client DB lookup + filesystem tree walk. Apply `withUserRateLimit` at 60 req/min. |
| `/api/kb/search` | Yes. | **Yes — wrap.** Same cost profile (DB + FS); additionally accepts a free-text `q` param with no existing length bound. 60 req/min. |
| `/api/flags` | No auth at all — returns server-side feature-flag env state with no user context. | **No.** Keyed by nothing the caller controls. Cost is negligible (synchronous in-memory object serialization). Annotate inline: `// No rate limit: returns static server flags, no DB/FS cost, no auth key.` |
| `/api/chat/thread-info` | Yes. | **Yes — wrap (core of this PR).** |
| `/api/conversations` | Yes. | **Yes — wrap (core of this PR).** |

Decision: wrap `kb/tree` and `kb/search` in this PR (low incremental cost; the helper is already being built); annotate `flags` with an inline comment explaining the exemption. Non-goals: changing `flags` to be authenticated (out of scope).

## Research Reconciliation — Spec vs. Codebase

No spec file exists for this feature branch — the driver is the three issue bodies, which I verified line-for-line against `gh issue view`. One reconciliation point worth flagging:

| Issue claim | Codebase reality | Plan response |
|-------------|------------------|---------------|
| #2510: reference shape at `apps/web-platform/app/api/analytics/track/throttle.ts`. | Exists; uses `SlidingWindowCounter` + `startPruneInterval`, keyed by IP (via `extractClientIpFromHeaders`). | Follow the same structure but key on `user.id` instead of IP — matches #2510's "keyed by `user.id`" requirement. Document the key-strategy divergence in a comment. |
| #2511: subselect syntax via PostgREST. | Supabase JS client supports `select("col, embedded:fk_table(count)")` (confirmed by existing usage in `lookup-conversation-for-path.ts` → `select("id", { count: "exact", head: true })`). The inline subselect form is `.select("id, context_path, last_active, messages(count)")`. | Use the PostgREST embedded-resource `messages(count)` form — NOT raw SQL. Raw SQL requires an RPC (rejected per issue justification). **Verify syntax against Supabase JS docs before implementing.** |
| #2512: "follow `kb_share_{create,list,revoke}` registration pattern from PR #2497". | `server/kb-share-tools.ts` exports `buildKbShareTools()` returning an array of `tool(name, desc, schema, handler)` calls; `agent-runner.ts` imports and `push(...)` into `platformTools`. | Mirror exactly: create `server/conversations-tools.ts` exporting `buildConversationsTools()` that returns a one-element array containing the `conversations_lookup` tool. `agent-runner.ts` imports + spreads into `platformTools` + appends the tool name to `platformToolNames`. |

## Files to create

- `apps/web-platform/server/with-user-rate-limit.ts` — the rate-limit helper factory.
- `apps/web-platform/server/conversations-tools.ts` — MCP tool builder for `conversations_lookup` (mirrors `kb-share-tools.ts`).
- `apps/web-platform/test/with-user-rate-limit.test.ts` — helper unit tests.
- `apps/web-platform/test/api-chat-thread-info.test.ts` — route-level test covering 429 + Sentry mirror (if not already covered).
- `apps/web-platform/test/conversations-tools.test.ts` — MCP tool handler tests (null on miss, row on hit, 500 propagation).

## Files to edit

- `apps/web-platform/app/api/chat/thread-info/route.ts` — wrap GET with `withUserRateLimit`.
- `apps/web-platform/app/api/conversations/route.ts` — wrap GET with `withUserRateLimit`.
- `apps/web-platform/app/api/kb/tree/route.ts` — wrap GET (bundled audit outcome).
- `apps/web-platform/app/api/kb/search/route.ts` — wrap GET (bundled audit outcome).
- `apps/web-platform/app/api/flags/route.ts` — add one-line exemption comment (no code change to handler).
- `apps/web-platform/server/lookup-conversation-for-path.ts` — collapse to single `.select()` with embedded `messages(count)`.
- `apps/web-platform/server/agent-runner.ts` — import `buildConversationsTools`, push into `platformTools`, append tool name, extend system prompt with one sentence announcing the capability.
- `apps/web-platform/test/api-conversations.test.ts` — add assertion pinning `messageCount` with `.toBe(exact)` for the single-query path.

## Implementation Phases

### Phase 1 — `withUserRateLimit` helper (#2510)

Dependency order: #2510 first because its output (the helper) is imported by the thread-info and conversations routes.

1. **RED** — write `test/with-user-rate-limit.test.ts`:
   - Helper is a higher-order function: `withUserRateLimit(handler, { perMinute, feature })` returns a new handler.
   - When user is unauthenticated, delegates to inner handler (the inner handler's own 401 branch wins — the helper does not fabricate auth errors).
   - When user IS authenticated and under the quota, delegates to inner handler unchanged.
   - When user is over the quota, returns `NextResponse.json({ error: "Too many requests" }, { status: 429, headers: { "Retry-After": "60" } })` and calls `reportSilentFallback(null, { feature, op: "rate-limit", extra: { userId } })`.
   - Uses `user.id` (not IP) as the counter key.
   - Counter is module-scoped per call-site (feature string is the discriminator — e.g., `"kb-chat.thread-info"` and `"kb-chat.conversations"` each get their own `SlidingWindowCounter`).
   - **DO NOT** add config knobs beyond `{ perMinute, feature }`. `code-simplicity-reviewer` will reject premature parameterization.

2. **GREEN** — write `server/with-user-rate-limit.ts`. Shape:

   ```ts
   // Per-user rate limit wrapper for authenticated GET handlers. Keyed by
   // user.id (not IP) — authenticated callers have stable identity across
   // NAT/VPN transitions; IP keys would both over- and under-limit.
   import { NextResponse } from "next/server";
   import { createClient } from "@/lib/supabase/server";
   import {
     SlidingWindowCounter,
     startPruneInterval,
   } from "@/server/rate-limiter";
   import { reportSilentFallback } from "@/server/observability";

   type Handler = (req: Request) => Promise<Response>;

   interface Options {
     perMinute: number;
     /** Feature tag for Sentry (e.g., "kb-chat.thread-info"). */
     feature: string;
   }

   export function withUserRateLimit(handler: Handler, opts: Options): Handler {
     const counter = new SlidingWindowCounter({
       windowMs: 60_000,
       maxRequests: opts.perMinute,
     });
     startPruneInterval(counter);
     return async (req: Request) => {
       const supabase = await createClient();
       const { data: { user } } = await supabase.auth.getUser();
       if (!user) return handler(req); // Let inner handler emit 401.
       if (!counter.isAllowed(user.id)) {
         reportSilentFallback(null, {
           feature: opts.feature,
           op: "rate-limit",
           message: "Per-user rate limit tripped",
           extra: { userId: user.id },
         });
         return NextResponse.json(
           { error: "Too many requests" },
           { status: 429, headers: { "Retry-After": "60" } },
         );
       }
       return handler(req);
     };
   }

   /** Test-only helper — passes the internal counter to tests for reset. */
   export const __testonly__ = { createCounterForTest: SlidingWindowCounter };
   ```

   Deviation note vs. issue body: `reportSilentFallback` on rate-limit **is** a judgment call against rule `cq-silent-fallback-must-mirror-to-sentry`'s exemption list ("rate-limit hit" is listed as exempt). The issue body asks for it. Resolution: **emit via `warnSilentFallback` not `reportSilentFallback`** — it's an expected degraded state (not an error), matches rule's "warning" tier, and still surfaces in Sentry for operator visibility. Flag this divergence in the PR body for `security-sentinel` review.

3. **REFACTOR** — per `cq-nextjs-route-files-http-only-exports`, confirm the helper lives in `server/` (sibling module), not in a route file. ✓.

### Phase 2 — Apply helper to five routes

4. **RED** — extend `test/api-conversations.test.ts` with a case that fires 61 GETs in the same window and asserts the 61st returns 429. Add the equivalent test file for `thread-info`, `kb/tree`, and `kb/search`.

5. **GREEN** — wrap each route's GET:

   ```ts
   // Before: export async function GET(req: Request) { ... }
   // After:
   async function getHandler(req: Request) { /* original body */ }
   export const GET = withUserRateLimit(getHandler, {
     perMinute: 60,
     feature: "kb-chat.conversations", // or "kb-chat.thread-info" / "kb.tree" / "kb.search"
   });
   ```

   Per `cq-nextjs-route-files-http-only-exports`, the `getHandler` **must not** be exported — only `GET` leaves the module.

6. For `app/api/flags/route.ts`, add ONE comment line above the handler:

   ```ts
   // No rate limit: returns static server feature-flag state; no DB/FS cost,
   // no user-specific key. Audit outcome from #2510 step 4.
   export async function GET() { ... }
   ```

### Phase 3 — Collapse the 2-query lookup (#2511)

7. **RED** — extend `test/api-conversations.test.ts` (existing file) with:
   - A case where the mocked Supabase client returns a row with an embedded `messages(count)` shape, and the helper returns `message_count` pinned to the exact value via `.toBe(7)` — NOT `.toContain`. Rule `cq-mutation-assertions-pin-exact-post-state`.
   - A case where the mocked client returns an error; the helper returns `{ ok: false, error: "lookup_failed" }` (the `count_failed` variant goes away when the count collapses into the same call).
   - A case for miss (no row): returns `{ ok: true, row: null }`.

8. **GREEN** — rewrite `server/lookup-conversation-for-path.ts`:

   ```ts
   export async function lookupConversationForPath(
     userId: string,
     contextPath: string,
   ): Promise<LookupConversationResult> {
     const service = createServiceClient();
     // Single round-trip: SELECT with an embedded aggregate count.
     // Replaces the former SELECT + head-COUNT pair (2 round-trips → 1).
     // PostgREST syntax: `messages(count)` requests an aggregate on the
     // foreign-key-embedded `messages` resource. Reference:
     //   https://supabase.com/docs/reference/javascript/select (aggregate section)
     const { data, error } = await service
       .from("conversations")
       .select("id, context_path, last_active, messages(count)")
       .eq("user_id", userId)
       .eq("context_path", contextPath)
       .is("archived_at", null)
       .order("last_active", { ascending: false })
       .limit(1)
       .maybeSingle();

     if (error) {
       reportSilentFallback(error, {
         feature: "kb-chat",
         op: "conversation-lookup",
         extra: { contextPath },
       });
       return { ok: false, error: "lookup_failed" };
     }
     if (!data) return { ok: true, row: null };

     // PostgREST returns the embedded aggregate as messages: [{ count: N }]
     const messageCount = data.messages?.[0]?.count ?? 0;

     return {
       ok: true,
       row: {
         id: data.id,
         context_path: data.context_path,
         last_active: data.last_active,
         message_count: messageCount,
       },
     };
   }
   ```

   The `LookupConversationResult` union's `"count_failed"` variant can be removed — the single call collapses both error sources into `lookup_failed`. Grep every caller: the two routes (`thread-info`, `conversations`) only branch on `ok` vs. not-ok, not on the discriminant. Safe to remove.

9. **Preflight on PostgREST syntax.** Before committing, run one sanity check in dev: hit the local Supabase PostgREST endpoint with the chained form and confirm the returned JSON has the `messages: [{ count: N }]` shape. Per the sharp-edge learning (PostgREST embedded resource syntax is more limited than expected). Command:

   ```bash
   cd apps/web-platform && doppler run -p soleur -c dev -- node -e '
     const { createClient } = require("./node_modules/@supabase/supabase-js");
     const c = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
     c.from("conversations")
       .select("id, context_path, last_active, messages(count)")
       .limit(1).then(r => console.log(JSON.stringify(r, null, 2)));
   '
   ```

### Phase 4 — `conversations_lookup` MCP tool (#2512 P2 slice)

10. **RED** — write `test/conversations-tools.test.ts`:
    - `buildConversationsTools({ serviceClient, userId })` returns an array of exactly one tool (no `_list`/`_archive`).
    - The tool's `name` is `"conversations_lookup"`.
    - Handler returns a `ToolTextResponse` with `content[0].text` JSON-parseable to `null` when `lookupConversationForPath` returns `{ ok: true, row: null }`.
    - Handler returns the full camelCase shape `{ conversationId, contextPath, lastActive, messageCount }` when `lookupConversationForPath` returns a row.
    - Handler returns `isError: true` when `lookupConversationForPath` returns `{ ok: false, error: "lookup_failed" }`.

11. **GREEN** — write `server/conversations-tools.ts`:

    ```ts
    import { tool } from "@anthropic-ai/claude-agent-sdk";
    import { z } from "zod/v4";
    import {
      lookupConversationForPath,
      type LookupConversationResult,
    } from "@/server/lookup-conversation-for-path";

    interface BuildOpts { userId: string; }

    type ToolTextResponse = {
      content: Array<{ type: "text"; text: string }>;
      isError?: true;
    };

    function textResponse(payload: unknown, isError = false): ToolTextResponse {
      const body: ToolTextResponse = {
        content: [{ type: "text", text: JSON.stringify(payload) }],
      };
      if (isError) body.isError = true;
      return body;
    }

    export function buildConversationsTools(opts: BuildOpts) {
      const { userId } = opts;
      return [
        tool(
          "conversations_lookup",
          "Look up the existing KB-chat conversation thread bound to a " +
            "knowledge-base document. Use this before starting a new thread " +
            "to check whether an existing one can be resumed. " +
            "Input: contextPath (the KB file path, e.g., " +
            "'knowledge-base/product/roadmap.md'). " +
            "Returns { conversationId, contextPath, lastActive, messageCount } " +
            "when a thread exists, or null when no thread is bound to the path. " +
            "Does NOT return message bodies (threads are opaque from the agent's " +
            "perspective — use the UI to read them).",
          { contextPath: z.string() },
          async (args) => {
            const result: LookupConversationResult =
              await lookupConversationForPath(userId, args.contextPath);
            if (!result.ok) {
              return textResponse(
                { error: "Lookup failed", code: result.error },
                true,
              );
            }
            if (result.row === null) return textResponse(null);
            return textResponse({
              conversationId: result.row.id,
              contextPath: result.row.context_path,
              lastActive: result.row.last_active,
              messageCount: result.row.message_count,
            });
          },
        ),
      ];
    }
    ```

12. **Wire into `agent-runner.ts`:**
    - Import `buildConversationsTools` alongside `buildKbShareTools`.
    - After the existing `platformTools.push(...kbShareTools)` block (~line 875), push `buildConversationsTools({ userId })` and append `"mcp__soleur_platform__conversations_lookup"` to `platformToolNames`.
    - Extend the system prompt with a one-paragraph capability announcement, sibling to the `## Knowledge-base sharing` block at line 548:

      ```
      ## KB-chat thread discovery

      You can look up whether a KB-chat thread already exists for a knowledge-base
      document using conversations_lookup. Input: contextPath (the KB file path).
      Returns thread metadata ({ conversationId, lastActive, messageCount }) if a
      thread exists, or null otherwise. Use this before creating a new thread —
      resuming an existing thread preserves context for the user.
      ```

13. **Defer the P3 items.** After PR merges, file ONE follow-up issue titled `review: add conversations_list + conversation_archive MCP tools (requires new HTTP endpoints)` milestoned to **Phase 4: Validate + Scale**, labels `priority/p2-medium`, `code-review`, `deferred-scope-out`. Body lists both missing HTTP endpoints (`GET /api/conversations` list variant, `PATCH /api/conversations/:id`), their design concerns (filter/pagination semantics for list; soft-delete vs. archive-at for PATCH), and the re-evaluation trigger (first multi-thread agent caller). Cross-link from PR body: "Closes #2512 (P2 slice only). P3 items filed as #<new-number>."

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `server/with-user-rate-limit.ts` exists and exports `withUserRateLimit(handler, { perMinute, feature })`.
- [ ] Helper's signature has exactly two options (`perMinute`, `feature`) — no other config knobs.
- [ ] `withUserRateLimit` is applied to GET on `/api/chat/thread-info`, `/api/conversations`, `/api/kb/tree`, `/api/kb/search` at 60 req/min, each with a distinct `feature` tag.
- [ ] `/api/flags` route has a one-line inline comment explaining the audit-outcome exemption.
- [ ] Over-quota GET returns HTTP 429 with `{ error: "Too many requests" }` body and `Retry-After: 60` header.
- [ ] Over-quota GET emits exactly one `warnSilentFallback` (or `reportSilentFallback`) call with `feature: "kb-chat.<route>"`, `op: "rate-limit"`, `extra: { userId }`.
- [ ] `server/lookup-conversation-for-path.ts` makes exactly **one** Supabase call (verified by mock-call count assertion in the helper test).
- [ ] `LookupConversationResult` discriminant no longer includes `"count_failed"`.
- [ ] `test/api-conversations.test.ts` pins `messageCount` with `.toBe(<exact>)` — not `.toContain`.
- [ ] `server/conversations-tools.ts` exports `buildConversationsTools()` returning exactly ONE tool (`conversations_lookup`).
- [ ] `agent-runner.ts` imports and wires the builder, and `platformToolNames` includes `"mcp__soleur_platform__conversations_lookup"`.
- [ ] System prompt in `agent-runner.ts` has a `## KB-chat thread discovery` section announcing the new tool.
- [ ] PR body includes `Closes #2510`, `Closes #2511`, `Closes #2512` on separate lines.
- [ ] PR body references PR #2486 (multi-closure pattern) and PR #2497 (MCP registration pattern).
- [ ] PR body documents the rate-limit-on-Sentry divergence (warn vs. error tier) for `security-sentinel`.
- [ ] `npx markdownlint-cli2 --fix <plan-file>` passes on the plan file.
- [ ] TDD gate: every new test file exists in git history as a RED commit before the GREEN implementation commit (enforced by `cq-write-failing-tests-before`).

### Post-merge (operator)

- [ ] Verify production GET `/api/conversations?contextPath=...` still returns the same JSON shape as before (no regression) via Playwright MCP smoke test against app.soleur.ai.
- [ ] Verify Sentry has `feature: kb-chat.*` events with `op: rate-limit` tagged (fire a synthetic over-quota burst in a scratch browser session or skip if no dev traffic).
- [ ] File the `conversations_list + conversation_archive` follow-up issue (step 13 above). Cross-link from PR description.
- [ ] Update `knowledge-base/product/roadmap.md` if the Phase 4 "Per-user rate limiting" row has a checkbox — this PR starts that work.

## Test Scenarios

### `withUserRateLimit` unit tests

| # | Scenario | Expectation |
|---|----------|-------------|
| 1 | Unauthenticated request | Helper delegates to inner; inner emits 401. |
| 2 | 1st authenticated GET under quota | Handler invoked, normal response returned. |
| 3 | 60th GET under quota | Handler invoked (at-limit boundary). |
| 4 | 61st GET over quota | Helper returns 429 + `Retry-After: 60`; inner NOT invoked. |
| 5 | Over-quota path | `warnSilentFallback` (or `reportSilentFallback`) called once with `{ feature, op: "rate-limit", extra: { userId } }`. |
| 6 | Key isolation | User A at 60 does not limit user B at 1. |
| 7 | Feature isolation | Wrapping two different routes (different `feature` strings) uses distinct counters. |

### `/api/conversations` + `/api/chat/thread-info` route tests

| # | Scenario | Expectation |
|---|----------|-------------|
| 8 | Existing 5 tests in `api-conversations.test.ts` | Still pass. |
| 9 | Pinned `messageCount` | `.toBe(7)` when mock returns `messages: [{ count: 7 }]` — rule `cq-mutation-assertions-pin-exact-post-state`. |
| 10 | Over-quota GET | 429 + correct body shape. |
| 11 | Single-query path | Mock `service.from().select().eq().eq().is().order().limit().maybeSingle()` called exactly once per request (verifies collapse — no second COUNT call). |

### `conversations_lookup` MCP tool tests

| # | Scenario | Expectation |
|---|----------|-------------|
| 12 | Builder returns 1 tool | `buildConversationsTools({...}).length === 1` and `[0].name === "conversations_lookup"`. |
| 13 | Hit path | Handler returns `ToolTextResponse` with `JSON.parse(content[0].text)` deep-equal to `{ conversationId, contextPath, lastActive, messageCount }`. |
| 14 | Miss path | `JSON.parse(content[0].text) === null`. |
| 15 | Error path | `isError === true`, payload has `code: "lookup_failed"`. |
| 16 | Zod schema | `contextPath` is required; missing input is rejected by the SDK before the handler runs. |

## Dependency Graph

```
Phase 1 (#2510 helper)
  └─> Phase 2 (apply helper to 5 routes)
        ├─> /api/chat/thread-info (new rate limit)
        ├─> /api/conversations (new rate limit; also consumer of Phase 3)
        ├─> /api/kb/tree (audit-outcome bonus)
        ├─> /api/kb/search (audit-outcome bonus)
        └─> /api/flags (comment only)

Phase 3 (#2511 query collapse)
  └─> Phase 4 (#2512 MCP tool uses the helper — benefits from single-round-trip)
        └─> conversations_lookup registration in agent-runner.ts
```

## Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| PostgREST embedded-resource `messages(count)` syntax returns unexpected shape. | Medium — the sharp-edge note explicitly flags PostgREST limits. | Phase 3 step 9 preflight against local Supabase before committing. If the shape differs, fall back to RPC (then this PR scope expands — STOP and re-scope with user). |
| Rate-limit counter memory leak if `startPruneInterval` isn't called. | Low — helper factory always calls it. | Test #5 verifies prune interval is started (inspect internal). |
| Sentry spam on expected rate-limit hits. | Medium — the issue body mandated Sentry mirror; rule `cq-silent-fallback-must-mirror-to-sentry` lists rate-limit as exempt. | Use `warnSilentFallback` (warning tier) not `reportSilentFallback` (error tier). Document divergence in PR body for `security-sentinel` review. |
| `agent-runner.ts` reaches ~1700 lines; adding another tool block risks hitting cognitive-load threshold. | Low — this PR only adds ~10 lines of wiring (imports + push + system-prompt string). | Extraction is handled by the sibling `conversations-tools.ts` module (matches `kb-share-tools.ts` precedent). `#1662` tracks the meta-extraction (not in scope). |
| `conversations_lookup` agent description could tempt agents to use it as a semantic-content query (prompt injection via contextPath). | Low — `contextPath` is a file-path string validated downstream by `validateContextPath`. | Handler delegates to existing validated helper. No new attack surface. `agent-native-reviewer` should confirm the tool description makes the null-return behavior clear so agents don't loop-probe paths. |
| Helper's `feature` string appears in Sentry tags — could leak internals. | Very low. | Feature strings are internal tag vocabulary (`kb-chat.conversations`), not user-facing. Same pattern as `kb-share` tags. |

## Alternative Approaches Considered (for #2511)

| Approach | Write-cost | Read-cost | Revert-cost | Verdict |
|----------|------------|-----------|-------------|---------|
| **Subselect / embedded count (CHOSEN)** | Zero (no migration). | 1 round-trip, aggregated in DB. | Cheap — revert the `.select()` string. | Ship. |
| Postgres RPC (`lookup_conversation_for_path`) | Migration required. | 1 round-trip, explicit contract. | Medium — migration + helper rewrite. | Defer. Helpful if multiple call sites want the same aggregate, not the case yet. |
| Denormalized `message_count` column with write-path trigger | Migration + trigger; every `INSERT INTO messages` incurs a trigger. | Zero round-trips (just SELECT). | Expensive — backfill + drop trigger + drop column. | Defer. Premature until p95 latency on the MCP caller crosses a Better Stack threshold. |

Re-evaluation criterion for Row 2/3: when p95 latency on `/api/chat/thread-info` or `/api/conversations` exceeds 200ms in Better Stack with the subselect in place. Until then, subselect is minimal-risk.

## Non-Goals

- Introducing Redis-backed rate limiting. In-memory `SlidingWindowCounter` is sufficient for the single-Hetzner-node deployment. Rule: `hr-all-infrastructure-provisioning-servers` — infra change would require Terraform planning.
- Adding IP-based fallback for unauthenticated endpoints. All wrapped endpoints are auth-gated; unauthenticated traffic trips 401 before the rate limiter (per `withUserRateLimit` design — the wrapper is post-auth).
- Running the helper against POST routes in this PR. Bundle stays focused on GETs to match issue scope.
- Backporting rate limits to every authenticated GET in the app. The audit in #2510 step 4 targets three routes; other routes are out of scope.
- Reworking the MCP server registration abstraction (per #1662). That's a separate design cycle.

## Review Focus

PR review should surface feedback in these lanes:

- **`security-sentinel`** — rate-limit correctness, key strategy (user.id vs. IP fallback absence), 429 body-shape consistency, Sentry warn-vs-error tier choice.
- **`performance-oracle`** — subselect-vs-RPC-vs-denorm decision documented in Alternatives table; re-evaluation criterion (p95 latency threshold) is explicit.
- **`agent-native-reviewer`** — `conversations_lookup` tool description quality (actionable, returns-null-semantics clear), auth model (per-user isolation via `userId` closure), P3 deferral justification.
- **`code-simplicity-reviewer`** — final pass: `withUserRateLimit` has only `{ perMinute, feature }` (no timeouts, no custom key functions, no onReject callbacks). `conversations-tools.ts` mirrors `kb-share-tools.ts` without introducing a shared factory (that's #1662's job).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure-and-tooling refactor. All three issues are review-origin scope-outs with narrow, technical scope:

- No user-facing UI changes (no new routes, no component additions, no copy).
- No content/marketing surface.
- No pricing, billing, or legal touch.
- No new external-service signups or expense lines.
- Security implications (rate limits, MCP auth model) are covered by `security-sentinel` + `agent-native-reviewer` at review time, not a separate domain-leader gate.

The Product/UX Gate tier is **NONE** — no `components/**/*.tsx`, no `app/**/page.tsx`, no `app/**/layout.tsx`, no user-visible surfaces.

## PR Body Template

```markdown
Closes #2510
Closes #2511
Closes #2512 (P2 slice only — P3 items (`conversations_list`, `conversation_archive`) split to #<followup> because they require new HTTP endpoints out of scope)

Drains three deferred-scope-out sibling issues from the PR #2500 review in one focused refactor. All three are apps/web-platform, all three review-origin, all three compose cleanly in a linear dependency. Follows the one-PR-three-closures precedent of PR #2486 and the MCP registration pattern of PR #2497.

## What ships

1. `server/with-user-rate-limit.ts` — reusable `withUserRateLimit(handler, { perMinute, feature })` helper keyed by `user.id`, returning 429 + `Retry-After: 60` on over-quota. Applied to GET `/api/chat/thread-info`, `/api/conversations`, `/api/kb/tree`, `/api/kb/search`. `/api/flags` annotated as intentional exemption.
2. `server/lookup-conversation-for-path.ts` — collapsed 2-query SELECT+COUNT into one PostgREST call using embedded `messages(count)` aggregate. `LookupConversationResult` simplified (no `count_failed` variant).
3. `server/conversations-tools.ts` + wiring in `agent-runner.ts` — one new MCP tool `conversations_lookup` wrapping GET `/api/conversations`. Mirrors `kb-share-tools.ts` module pattern.

## Divergence flagged for review

- **Sentry mirror for rate-limit hits**: the issue body mandated `reportSilentFallback`; rule `cq-silent-fallback-must-mirror-to-sentry` lists rate-limit hits as an exempt expected state. Resolution: use `warnSilentFallback` (warning tier) instead of `reportSilentFallback` (error tier). Flagging for `security-sentinel`.
- **P3 deferral**: `conversations_list` + `conversation_archive` filed as #<followup> because they need new HTTP endpoints (`GET /api/conversations` list variant; `PATCH /api/conversations/:id`).

## Test plan

- [ ] `test/with-user-rate-limit.test.ts` — 7 scenarios (auth bypass to inner, under-quota, at-boundary, over-quota, Sentry mirror, key isolation, feature isolation).
- [ ] `test/api-conversations.test.ts` — adds `messageCount` `.toBe(7)` pin + 429 path + single-call assertion.
- [ ] `test/conversations-tools.test.ts` — 5 scenarios for the new MCP tool.
- [ ] Manual smoke: GET `/api/conversations?contextPath=...` returns same shape pre/post (no regression).
- [ ] Manual over-quota burst: confirm Sentry receives one `feature: kb-chat.conversations, op: rate-limit` event.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```
