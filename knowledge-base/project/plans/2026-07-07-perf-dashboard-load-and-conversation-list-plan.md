---
title: "perf: Dashboard load + conversation-list performance"
date: 2026-07-07
type: perf
branch: feat-one-shot-dashboard-load-perf
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# ⚡ perf: Dashboard page load + conversation-list loading are slow

## Overview

Two user-reported symptoms:

1. **The dashboard page load is really slow.** The dashboard (`app/(dashboard)/dashboard/page.tsx`) is a fully **client** component whose *entire render is gated* on the `/api/kb/tree` SWR fetch (`page.tsx:407` → `if (kbLoading) return <skeleton>`). That endpoint runs the heavy `buildTree()` — a **full recursive walk of the whole KB directory** — plus workspace/installation resolution, on the cold path. The dashboard consumes that whole tree only to check the existence + size of **~13 known foundation files** (`FOUNDATION_PATHS` + `OPERATIONAL_TASKS` + `overview/vision.md`). So the slowest endpoint blocks first paint, and it massively over-fetches.

2. **Loading the conversations after the page has loaded is super slow.** `useConversations` (`hooks/use-conversations.ts`) runs a **4-hop sequential waterfall** — `supabase.auth.getUser()` → `fetch("/api/workspace/active-repo")` (which itself re-runs `auth.getUser()` + 3 DB reads) → conversations query → **a `messages` query with NO `.limit()` that pulls every message's full `content` for all up-to-50 conversations** (`use-conversations.ts:277-281`). That final query transfers 250–2,500 full message bodies to the browser purely to derive a title (first user/assistant message) and a 100-char preview (last message) per conversation. This unbounded fan-out is the dominant cost.

A cross-cutting third cost compounds both: **`middleware.ts` runs 3–4 sequential Supabase round-trips on every authenticated request** (`getUser` `:195`, `getSession` `:225`, `check_my_revocation` RPC `:264`, `users` T&C/billing read `:325`) — added latency on the HTML document *and* every API/SWR call the page fires.

**Goal:** make the dashboard paint fast and the conversation list load fast, without weakening tenant isolation (RLS scope) or the realtime scope-equivalence invariants.

**Approach (impact-ordered):**
- **Phase 0 — Measure first** (diagnostic gate; guards against the low-scale-IO-is-structural false trail).
- **Phase 1 (CRITICAL) — Conversation list:** replace the 2-query + unbounded-messages read with **one RLS-respecting `list_conversations_enriched` RPC** that returns each conversation plus only the three message snippets the UI needs (first-user, first-assistant, last-content+leader) via lateral joins on the already-indexed `messages(conversation_id, created_at)`. Payload drops from O(all messages) to O(conversations).
- **Phase 2 (HIGH) — Dashboard render:** replace the render-blocking whole-tree consumer with a cheap **`/api/dashboard/foundation-status`** endpoint (existence + size for only the ~13 known paths); no `buildTree()` on cold load. Dedupe the double `/api/workspace/active-repo` fetch.
- **Phase 3 (HIGH, security-gated) — Middleware:** conservatively parallelize the provably-independent per-request Supabase reads (do **not** weaken revocation/T&C freshness). Split to a follow-up if security review deems the risk high.
- **Phase 4 (MEDIUM) — Bundle:** code-split heavy deps (`pdfjs-dist` ~3.5 MB, `@likec4/*`, `@codemirror/*`) out of the dashboard critical path so they load only on the KB/architecture surfaces that use them.

Phases 1–2 directly answer the two reported symptoms and are the primary shipping unit. Phases 3–4 are independently valuable; if the combined PR is too large or Phase 3's auth risk is high, they split to tracked follow-ups (see Deferred).

## Enhancement Summary

**Deepened on:** 2026-07-07
**Key additions from deepen-plan:**
1. **Precedent-diff (SECURITY model) — decisive.** Both existing conversation-read RPCs (`027_mtd_cost_aggregate`, `037_stuck_active_finder_rpc`) are `SECURITY DEFINER` + `SET search_path` + **service_role-only** (REVOKE from `authenticated`/`anon`) — they intentionally *bypass* RLS for server-side aggregation. There is **no precedent for a client-callable conversation-read RPC.** This confirms `SECURITY INVOKER` (RLS-preserving, GRANT EXECUTE to `authenticated`) is the correct choice here, and that copying the DEFINER precedent would be the *dangerous* path (it would bypass RLS-075 and force re-implementing tenant scope in the WHERE clause). See Phase 1 Research Insights + Architecture Decision.
2. Hard gates verified: `## User-Brand Impact` + `## Observability` present and non-placeholder; no PAT-shaped variables; no downtime/hot-table-lock trigger (migration is `CREATE FUNCTION` + plain `CREATE INDEX` only); no new UI surface (no `.pen` required).
3. data-integrity-guardian review of the RPC isolation design folded into Risks (below).

## Research Reconciliation — Description vs. Codebase

No spec/brainstorm preceded this plan. The user description was validated against first-hand code reads + two research agents; findings **confirm and sharpen** the description.

| Description claim | Codebase reality | Plan response |
| --- | --- | --- |
| "Dashboard page load is really slow" | Render is gated on `/api/kb/tree` (`page.tsx:407`) which runs full `buildTree()` for a 13-file existence check | Phase 2: cheap foundation-status endpoint; no whole-tree walk on cold load |
| "Loading conversations … super slow" | `messages` query has **no `.limit()`**; fetches all content for all 50 convs to derive title+preview (`use-conversations.ts:277-281`) | Phase 1: enriched RPC returns only the 3 needed snippets/conv |
| (implicit) general slowness | Middleware runs 3–4 sequential Supabase calls per request (`middleware.ts:195,225,264,325`) | Phase 3: conservative parallelization (security-gated) |
| (implicit) | Dashboard ships pdfjs/likec4/codemirror in the client critical path | Phase 4: code-split out of dashboard |

## Hypotheses (diagnostic, confirm in Phase 0)

- **H1 (primary):** the unbounded `messages` fetch dominates conversation-load time; it scales with total message volume, not conversation count. Confirm via browser network waterfall (payload size + duration of the `messages` request) and `pg_stat_statements`.
- **H2 (primary):** `buildTree()` dominates cold dashboard first-paint because it walks the whole KB tree and gates render. Confirm via `/api/kb/tree` server timing vs a targeted-stat timing.
- **H3 (secondary):** middleware's sequential auth chain adds a fixed ~200–500 ms tax to every request. Confirm via middleware timing logs / server-timing header.
- **H-null (must rule out):** per learning `2026-05-06-supabase-disk-io-structural-overhead-dominates-at-low-scale.md`, at low scale Supabase IO can be dominated by Realtime WAL polling + `pg_cron`, not user queries. Phase 0 checks `pg_stat_statements` top-by-exec-time so we do not "index the wrong query." If H-null holds and H1/H2 do not, re-scope before building.

## Implementation Phases

### Phase 0 — Measure (diagnostic gate) [required, no code]
- Capture a baseline browser network waterfall for a cold dashboard load (Playwright MCP or devtools): record duration + response bytes for `/api/kb/tree`, `/api/workspace/active-repo` (note it fires **twice**), the `conversations` PostgREST call, and the `messages` PostgREST call.
- Pull `pg_stat_statements` top-10 by total exec time and the `messages … IN (…)` call's mean rows/exec (via Supabase MCP `execute_sql` on **dev**, read-only). Confirm H1/H2; rule out H-null.
- Record baseline numbers in the PR body (the before/after evidence). Deterministic verdict rule: proceed to Phase 1/2 only if the `messages` request and `/api/kb/tree` are ≥ the two largest contributors to their respective flows.

### Phase 1 — Enriched conversation-list RPC (CRITICAL)
- Add migration `supabase/migrations/125_list_conversations_enriched.sql` defining `list_conversations_enriched(p_repo_url text, p_workspace_id uuid, p_archive text, p_status text, p_domain text, p_limit int)`.
  - **Default to `SECURITY INVOKER`** so migration-075 RLS (`conversations_owner_select` + `conversations_shared_select`) and the messages RLS bound the result set exactly as the direct client queries do today — **no new trust boundary**. Only if a lateral read is not RLS-reachable, escalate to `SECURITY DEFINER` with `SET search_path = public, pg_temp` (`cq-pg-security-definer-search-path-pin-pg-temp`) **and** author an ADR (see Architecture Decision). deepen-plan + data-integrity-guardian decide the final SECURITY model.
  - Returns one row per conversation: the full typed `Conversation` column set **plus** `first_user_content`, `first_assistant_content`, `last_content`, `last_leader` — each computed by a `LATERAL` subquery over `messages` ordered by `created_at` using the existing `idx_messages_conversation_created` index (`LIMIT 1` per snippet). This ships ≤ 4 short message fields per conversation instead of every message.
  - Applies the same filters the hook applies today: `repo_url`, `workspace_id`, `archived_at` (active/archived), optional `status`, optional `domain_leader` (`general` → `IS NULL`), `ORDER BY last_active DESC, created_at DESC`, `LIMIT p_limit`.
- Supporting index: verify whether the rail predicate is already covered by `idx_conversations_user_repo` / `idx_conversations_active_unarchived`. If not, add a **plain** partial composite `CREATE INDEX idx_conversations_rail ON conversations (workspace_id, repo_url, last_active DESC) WHERE archived_at IS NULL;` — **no `CONCURRENTLY`** (Supabase runner wraps each migration in a txn; SQLSTATE 25001; per learning `2026-04-18-supabase-migration-concurrently-forbidden.md`).
- Rewrite `use-conversations.ts` `fetchConversations` to call `supabase.rpc("list_conversations_enriched", {...})` in place of the two `.from()` queries. Feed the returned snippets into the **unchanged** `deriveTitle`/`derivePreview`/`deriveRailTitle` logic (single source of truth for title semantics — no SQL title logic). The `messages`-array `.filter()` derivation collapses to per-row snippet reads.
- **Preserve invariants:** the RPC still returns/derives `workspaceId` + `repoUrl` so the realtime `own`/`shared` channel subscriptions and `shouldDropForScope` stay **scope-equivalent** to the fetch (learnings `2026-06-16-realtime-event-guard-must-equal-fetch-query-scope.md` + `2026-06-16-realtime-connect-race-recover-via-scope-resolve-backfill.md`). Do NOT alter `shouldDropForScope`, the scope-resolve backfill, or the `CONVERSATION_CREATED_EVENT` retry loop. `.down.sql` drops the function + index.
- Test-mock sweep (`2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper.md` + constitution): grep every `createQueryBuilder`/supabase mock for the conversations/messages chains; add `.rpc()` support (recursive chain) so the mocks don't silently drop it.

#### Phase 1 — Research Insights (precedent-diff, Phase 4.4)

**Precedent (git grep over `supabase/migrations/*.sql`):**
- `027_mtd_cost_aggregate.sql:46-69` — `LANGUAGE sql SECURITY DEFINER SET search_path = public`, then `REVOKE EXECUTE … FROM PUBLIC/authenticated/anon` (service_role-only aggregation over `conversations`).
- `037_stuck_active_finder_rpc.sql:46-64` — `language sql security definer set search_path = public, pg_temp`, `revoke all … from public; grant execute … to service_role` (RLS-bypassing cross-user scan).

**Divergence + justification:** those are server-side, RLS-*bypassing*, service_role-only. `list_conversations_enriched` is **client-invoked with the user JWT** and must **preserve** tenant scope, so it diverges deliberately:
- `SECURITY INVOKER` (not DEFINER) → RLS-075 `conversations_owner_select`/`conversations_shared_select` + messages RLS (059/075) bound the result exactly as today's direct client queries do. The client already reads both tables directly under these policies, so the `authenticated` role has the required SELECT and the LATERAL messages read is RLS-reachable.
- `GRANT EXECUTE ON FUNCTION list_conversations_enriched(...) TO authenticated;` (the inverse of the precedents' REVOKE-all) — because this one is meant to be called by the browser client.
- If (and only if) data-integrity review shows INVOKER cannot reach a needed row, escalate to DEFINER **with** `SET search_path = public, pg_temp` (`cq-pg-security-definer-search-path-pin-pg-temp`), an explicit tenant-scope WHERE clause reproducing RLS, REVOKE-all + a narrow GRANT, **and an ADR** — matching the precedent's hardening. This is the higher-risk path; default stays INVOKER.

**Novelty flag:** no precedent for a client-callable conversation-read RPC → reviewers (data-integrity-guardian, security-sentinel) must scrutinize RLS-reachability of the LATERAL snippet reads under INVOKER and confirm a set-returning SQL function does not skip row policies.

#### Research Insights — Phase 1 (precedent-diff, deepen-plan)

**Precedent-diff gate (SECURITY mode).** `git grep` for existing RPCs reading `conversations`/`messages` found two precedents, both **`SECURITY DEFINER` + `SET search_path` + service_role-only** (REVOKE from `authenticated`/`anon`):
- `027_mtd_cost_aggregate.sql:42-69` — `sum_user_mtd_cost` — `SECURITY DEFINER`, `SET search_path = public`, `REVOKE EXECUTE … FROM PUBLIC, authenticated, anon` (server-invoked cost aggregation).
- `037_stuck_active_finder_rpc.sql:43-64` — `find_stuck_active_conversations` — `security definer`, `set search_path = public, pg_temp`, `grant execute … to service_role` only (cross-user maintenance scan).

**Divergence + resolution.** Both precedents are DEFINER *because they intentionally bypass RLS* for server-side aggregation/maintenance and are never callable by the browser. This plan's RPC is the opposite: **client-callable with the user JWT**, and must *preserve* RLS. There is **no precedent for a client-callable conversation-read RPC** (novel shape — flag for reviewer scrutiny). Therefore:
- Use **`SECURITY INVOKER`** (the function runs as the caller → RLS-075 `conversations_owner_select`/`conversations_shared_select` and the `messages` RLS bound the result exactly as the current direct client queries do). Mimicking the DEFINER precedent here would **bypass 075** and force re-implementing tenant scope in the WHERE clause — strictly higher isolation risk, and would require an ADR + `search_path` pin.
- **GRANT hygiene inverts the precedent:** `GRANT EXECUTE ON FUNCTION list_conversations_enriched(...) TO authenticated;` (NOT the DEFINER precedents' `REVOKE … FROM authenticated`). Even under INVOKER, pin `SET search_path = public, pg_temp` (defense-in-depth; matches 037).
- **RLS-reachability confirmation:** the client already reads `messages` directly today (`use-conversations.ts:277` Query 2 under the user JWT), so the LATERAL snippet subqueries are RLS-reachable under INVOKER — no DEFINER escalation needed. (data-integrity-guardian to confirm LATERAL/SRF does not skip RLS.)
- Keep the app-level `.eq("repo_url")` + `.eq("workspace_id")` filters *inside* the RPC as defense-in-depth atop RLS (they are the same discriminator the current query + realtime guard use; do not drop them).

### Phase 2 — De-block + de-over-fetch the dashboard render (HIGH)
- Add `app/api/dashboard/foundation-status/route.ts` (HTTP-only exports per `cq-nextjs-route-files-http-only-exports`) returning `{ paths: { "<kbPath>": { exists, size } } }` for **only** the `FOUNDATION_PATHS`, `OPERATIONAL_TASKS`, and `overview/vision.md` set — a targeted stat of known paths via the existing kb-reader access resolution, **not** `buildTree()`. Wrap with `withUserRateLimit`. Mirror failures to Sentry via `reportSilentFallback` (`cq-silent-fallback-must-mirror-to-sentry`).
- In `page.tsx`, replace the `DASHBOARD_KB_TREE_KEY` / `fetchDashboardKbTree` consumer with a SWR fetch of `/api/dashboard/foundation-status`; derive `visionExists` + `foundationCards`/`operationalCards` `done` from it. Keep a **light** loading gate on this cheap call (first-run/empty-state correctness needs `visionExists`) — it resolves far faster than a whole-tree walk. Preserve the ADR-067 warm-cache behavior (returning to the dashboard stays instant) and the 401/503/404 → redirect/provisioning/empty-tree state mapping.
- Dedupe the double `/api/workspace/active-repo` fetch: the page's `swrKeys.workspaceActiveRepo()` SWR and the hook's raw `fetch` should share one SWR entry (thread the resolved value into the hook, or have the hook read the same SWR key) so active-repo is fetched once per dashboard mount.

### Phase 3 — Trim middleware per-request cost (HIGH, security-gated)
- In `middleware.ts`, only after Phase 0 confirms H3, parallelize the **provably-independent** reads (e.g., run the T&C/billing `users` read concurrently with steps that do not depend on it) via `Promise.all`, preserving strict ordering wherever a later check depends on an earlier result. **Do NOT** weaken `check_my_revocation` freshness or the fail-closed T&C redirect. security-sentinel + deepen-plan gate this phase; if the safe win is marginal or the risk non-trivial, split to a tracked follow-up rather than force it.

### Phase 4 — Trim the dashboard client bundle (MEDIUM)
- `next/dynamic` (SSR-safe) code-split `pdfjs-dist`, `@likec4/*`, and `@codemirror/*` so they load only on the KB PDF viewer / architecture / editor surfaces — not in the dashboard critical path. Confirm no eager import path pulls them into the dashboard chunk (`next build` bundle analysis). Independent of Phases 1–3; may split to a follow-up.

## Files to Edit
- `apps/web-platform/hooks/use-conversations.ts` — swap 2-query read for the enriched RPC; keep realtime + derivation invariants.
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` — foundation-status consumer; light gate; active-repo dedupe.
- `apps/web-platform/middleware.ts` — (Phase 3) conservative parallelization.
- Heavy-dep import sites for Phase 4 (KB PDF viewer, architecture view, editor components) — `next/dynamic` wrapping.
- Test mocks for supabase `createQueryBuilder`/`.rpc()` (grep-derived list — do not hardcode).

## Files to Create
- `apps/web-platform/supabase/migrations/125_list_conversations_enriched.sql` (+ `.down.sql`).
- `apps/web-platform/app/api/dashboard/foundation-status/route.ts`.
- Vitest specs: RPC-backed `use-conversations` fetch, foundation-status route, migration RPC scope test.

## User-Brand Impact

**If this lands broken, the user experiences:** an empty or wrong conversation list on their dashboard (missing their own conversations), or a stale/incorrect foundation-card completion state.

**If this leaks, the user's conversation data is exposed via:** a mis-scoped `list_conversations_enriched` RPC returning conversation rows or message snippets across a `workspace_id`/`repo_url`/RLS boundary — i.e. one tenant seeing another tenant's conversation titles/previews.

**Brand-survival threshold:** single-user incident.

- `requires_cpo_signoff: true` (CPO sign-off at plan time before `/work`; carry forward from Domain Review, or confirm CPO review).
- `user-impact-reviewer` runs at review time (conditional-agent block in review skill).
- **Primary mitigation:** default to `SECURITY INVOKER` so the RPC inherits migration-075 RLS unchanged — no new trust boundary. Any `SECURITY DEFINER` escalation requires pinned `search_path` + an ADR + a data-integrity review that proves the WHERE clause reproduces RLS scope exactly. Include a Phase 1 test that a workspace-B user cannot retrieve workspace-A rows through the RPC.

## Observability

```yaml
liveness_signal:
  what: conversation-list RPC + foundation-status route error rate/latency surfaced in Sentry (client breadcrumb on RPC error; server timing on the route)
  cadence: per dashboard load (on-demand, not cron)
  alert_target: Sentry (existing web-platform project)
  configured_in: reportSilentFallback mirror + existing Sentry client init
error_reporting:
  destination: Sentry via reportSilentFallback / warnSilentFallback
  fail_loud: true  # RPC/route error sets hook `error` state → ErrorCard renders; no silent empty list
failure_modes:
  - mode: RPC returns error (bad args / missing function / RLS denial)
    detection: supabase-js error → setError → ErrorCard + Sentry breadcrumb
    alert_route: Sentry
  - mode: foundation-status 5xx
    detection: SWR error → dashboard falls through to neutral card state + reportSilentFallback
    alert_route: Sentry
  - mode: migration/index not applied on prd (function missing 42883)
    detection: RPC error surfaced in ErrorCard + Sentry; caught pre-close by dev→prd apply verification
    alert_route: Sentry + migration runbook
logs:
  where: Sentry + pino server logs (route handler)
  retention: existing web-platform retention
discoverability_test:
  command: "curl -s -X POST \"$SUPABASE_URL/rest/v1/rpc/list_conversations_enriched\" -H \"apikey: $ANON\" -H \"Authorization: Bearer $USER_JWT\" -H 'Content-Type: application/json' -d '{...scoped args...}' | jq 'length'"  # no ssh
  expected_output: "200 with a bounded array (≤ p_limit rows), each row carrying ≤4 short snippet fields — never full message arrays"
```

## Architecture Decision (ADR/C4)

**Default path (SECURITY INVOKER): no ADR required.** The enriched-list RPC is a read-path *optimization* of the existing `dashboard → supabase` conversation read; RLS-075 remains the trust boundary (unchanged). No new ownership/tenancy boundary, substrate, or resolver.

**Conditional:** if data-integrity review forces `SECURITY DEFINER`, that introduces a new trust boundary → author `ADR-101` (next free ordinal; re-verify against `origin/main` at ship — `/ship`'s ordinal-collision gate) recording the DEFINER decision, the pinned `search_path`, and the WHERE-clause-reproduces-RLS proof.

**### C4 views — no C4 impact (verified).** Read all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`). Actors/systems/stores checked and found already-modeled: external human actor `founder` (`model.c4:313 founder -> dashboard`); container `dashboard` (`model.c4:34`, "Conversation UI"); data store `supabase` (`model.c4:156`); the touched edges `dashboard -> api` (`:314`), `api -> supabase` (`:334`), `webapp -> supabase` (`:280`) all exist. The change adds no external actor, no external system, and no new data store — it moves work *inside* the existing dashboard↔supabase read edge. No `.c4` element or view line changes.

## Domain Review

**Domains relevant:** Engineering (CTO/architecture — RPC read boundary + middleware auth), Product (dashboard UX-adjacent, ADVISORY).

### Engineering
**Status:** assessed inline (pipeline). **Assessment:** read-path optimization; the load-bearing risks are (a) RLS scope-equivalence of the RPC, (b) realtime `shouldDropForScope` staying scope-equivalent to the new fetch, (c) middleware auth-freshness preservation. All routed to deepen-plan domain agents (data-integrity-guardian, security-sentinel, architecture-strategist) and review.

### Product/UX Gate
**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (headless pipeline)
**Skipped specialists:** ux-design-lead — N/A (no new UI surface; perf-only change to existing dashboard, no visual redesign; the only visible delta is faster paint + an existing-component loading state)
**Pencil available:** N/A (no UI surface)

#### Findings
The dashboard's visual output is unchanged: same components, same layout, same states — only load *timing* improves and the foundation-cards may briefly show their existing neutral/loading state while the cheap status call resolves. No new interactive surface, page, or flow is created, so no wireframe is warranted. Classified ADVISORY (modifies an existing user-facing page's data-loading behavior).

### GDPR / Compliance
Touches API routes + a migration reading message content, so the gate applies. Assessment: **no new processing activity, no new data movement, no new external recipient** — the RPC reads the *same* conversation/message data under the *same* RLS scope, only more efficiently. Advisory-only; no Article 30 change. Flag for gdpr-gate confirmation at deepen-plan if the SECURITY model changes to DEFINER.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] Phase 0 baseline + after numbers recorded in the PR body (network waterfall bytes/duration for the `messages` call and `/api/kb/tree`, before vs after).
- [ ] `use-conversations` fetch issues **one** `rpc("list_conversations_enriched", …)` call and **zero** unbounded `.from("messages")` selects; grep proves the old `messages … .in(ids)` fetch is gone.
- [ ] RPC payload carries ≤ 4 message-snippet fields per conversation (no full message arrays) — asserted in a route/RPC test against a seeded conversation with many messages.
- [ ] Tenant-isolation test: a workspace-B user calling the RPC scoped to workspace-A retrieves **0** rows (RLS/scope proof).
- [ ] `shouldDropForScope`, the scope-resolve backfill, and the `CONVERSATION_CREATED_EVENT` retry loop are unchanged (git diff shows no edits to those blocks).
- [ ] `/api/dashboard/foundation-status` returns existence+size for the known-path set only; `page.tsx` no longer calls `buildTree()`-backed `/api/kb/tree` on cold load; grep shows the dashboard KB-tree consumer removed.
- [ ] `/api/workspace/active-repo` is fetched once per dashboard mount (dedupe verified).
- [ ] Migration `125_*` uses plain `CREATE INDEX` (no `CONCURRENTLY`); `.down.sql` drops function + index.
- [ ] Supabase test mocks support the new `.rpc()` chain (recursive-chain sweep done).
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes; `node node_modules/vitest/vitest.mjs run` (worktree-safe) passes for the touched specs.

### Post-merge (operator/automated)
- [ ] Migration `125_*` applied to **dev** then **prd** via Supabase MCP/REST (dev≠prd per `hr-dev-prd-distinct-supabase-projects`); verify the function exists (`gh`/MCP query, no ssh) before closing.
- [ ] Post-deploy dashboard cold-load waterfall re-measured on the deployed app; conversation-list and first-paint improved vs the Phase 0 baseline.

## Test Scenarios
- Conversation with 200+ messages → rail title/preview identical to pre-change output, but RPC payload bounded to snippet fields.
- Owner with two same-repo workspaces → rail shows only the active workspace's conversations (scope discriminator preserved).
- Archived filter, status filter, `general` domain filter → each still applied by the RPC.
- Realtime INSERT during the connect window → row still recovered via the unchanged scope-resolve backfill.
- Dashboard cold load with no `vision.md` → first-run screen still renders (foundation-status drives `visionExists`).
- foundation-status 5xx → dashboard degrades gracefully (neutral cards, Sentry mirror), does not blank.

## Alternatives Considered / Deferred
- **Denormalize `title`/`preview`/`last_message_leader` onto `conversations` (trigger-maintained).** Cleanest read (single query, no snippets) but requires a write-path trigger encoding title semantics into SQL, plus a backfill migration and higher isolation risk. Rejected as primary for a perf fix; the INVOKER RPC keeps title logic in one JS place and is read-only. Revisit if the RPC's lateral cost is later shown to dominate.
- **Phase 3 (middleware) and Phase 4 (bundle)** may split to tracked follow-up issues if the combined PR is too large or Phase 3's auth risk is non-trivial. **Deferral action:** if split, file a GitHub issue per deferred phase (what/why/re-eval criteria + milestone from `knowledge-base/product/roadmap.md`) — a deferral without a tracking issue is invisible.

## Open Code-Review Overlap
2 open code-review issues touch files this plan edits:
- **#2590** (`refactor(dashboard): extract useFirstRunAttachments + FirstRunComposer from DashboardPage`) — touches `page.tsx`. **Acknowledge:** different concern (first-run composer component extraction, not perf). This plan's `page.tsx` edits are confined to the KB-tree→foundation-status consumer swap and the active-repo dedupe; they do not touch the first-run attachment code the scope-out targets. Remains open for its own cycle.
- **#2591** (`docs(security): document CSP middleware + route intersection`) — touches `middleware.ts`. **Acknowledge:** docs-only CSP documentation, orthogonal to Phase 3's auth-read parallelization. Remains open.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6 — this one is filled (threshold = single-user incident).
- Do **not** widen `shouldDropForScope` to "fix" any row that appears/disappears — it is the F3 cross-workspace containment invariant; the scope-resolve backfill is the sanctioned recovery.
- Verify the rail predicate against **existing** indexes (`idx_conversations_user_repo`, `idx_conversations_active_unarchived`) before adding a new one — avoid a redundant index.
- Confirm the `messages` lateral snippets read is RLS-reachable under INVOKER before assuming DEFINER; DEFINER changes the trust boundary and the whole review posture (ADR + search_path pin). **Verified RLS anchors (deepen-plan):** `conversations` → `conversations_owner_select`/`conversations_shared_select` (075:55-60, `FOR SELECT TO authenticated`); `messages` → `messages_workspace_member_select` (059:102-104, `USING (public.is_workspace_member(workspace_id, auth.uid()))`). Under INVOKER both apply to the RPC body, so a cross-workspace conversation row or message snippet cannot leak. The `is_workspace_member`-bound messages policy is the load-bearing isolation anchor for the LATERAL read.
- **SQL set-returning + RLS:** a `LANGUAGE sql SECURITY INVOKER` set-returning function applies the caller's row policies to every table it reads (RLS is not skipped for INVOKER). deepen-plan review must still confirm no `SECURITY DEFINER` helper is transitively called inside the body that would re-open the boundary.
