---
title: "fix: active/in-progress conversation missing from Recent Conversations rail"
type: fix
date: 2026-06-15
lane: single-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# fix: active/in-progress conversation missing from Recent Conversations rail

## Enhancement Summary

**Deepened on:** 2026-06-15
**Agents:** architecture-strategist, verify-the-negative pass, realtime best-practices research, precedent-diff (Explore).

### Key changes from the deepen pass
1. **P0 corrected:** Phase 3 no longer proposes aligning `createConversation`'s workspace resolution to the route's solo fallback — that would reintroduce the #5256 cross-tenant durable-write hazard. The fail-loud is intentional (read paths may solo-fall-back; durable cross-tenant writes must fail-loud). Phase 3 is now verify-and-document only.
2. **P1 corrected:** the "refetch when active conversationId is unknown to the list" trigger was removed (tight-loop hazard when the conversation is out-of-scope or `repoUrl` is null). Replaced with a bounded `SUBSCRIBED`-status backfill `fetchConversations()` — the canonical reconnection-gap close for at-least-once realtime.
3. **P2 added:** mandatory shared `shouldDropForScope` helper (repo_url + visibility + archive) and shared `deriveRailTitle` helper (incl. `system → "Project Analysis"`); fill-only upsert so a placeholder INSERT never downgrades an enriched row.
4. **Scope narrowed:** the plan is now **hook-only** on the client (`use-conversations.ts` + tests). `conversations-rail.tsx` is no longer edited → no UI-surface file → Product/UX Gate = NONE, no `.pen` wireframe required (recorded explicitly, not silently skipped).
5. **Citation fix:** RLS policy is `conversations_owner_select` + `conversations_shared_select` (migration 075), not a single `conversations_owner_or_shared`.

## Overview

An active/in-progress conversation does not appear in the **Recent Conversations** sidebar rail. The rail reads **"No conversations yet."** with a "Start one →" CTA even while a conversation is actively streaming in the Dashboard chat view (screenshot: a streaming "Soleur Concierge" response while the left rail shows the empty state).

This is a **regression**. PR #5317 (`6e0e5fafa`, merged 2026-06-15) fixed the *same symptom* for one root cause (the rail read the deprecated `users.repo_url` instead of `workspaces.repo_url`). The symptom has re-occurred because **a second, independent defect** remains: the rail learns about conversations only via an initial mount-time fetch plus Supabase Realtime **UPDATE** events — there is **no INSERT path**. A conversation created *after* the rail mounts on an empty list is never added to the list, so the rail stays empty until a manual remount/refetch.

A secondary contributing defect is a **workspace-id source divergence** between the conversation-creation path and the rail-query path (detailed below) that can hide an active conversation even when the INSERT-path fix lands.

## Problem Statement / Motivation

### Why the rail stays empty for an active conversation

The rail's data hook `apps/web-platform/hooks/use-conversations.ts`:

1. Fetches the conversation list **once on mount** (`useEffect(() => { fetchConversations(); }, [fetchConversations])`, lines 239–241). `fetchConversations` is a stable closure, so the effect does not re-run on navigation.
2. Subscribes to Supabase Realtime **`event: "UPDATE"`** only — two channels: own (`user_id=eq.${userId}`, line 280) and workspace-shared (`workspace_id=eq.${workspaceId}`, line 295). **There is no `event: "INSERT"` subscription.**
3. The only caller of `refetch` is the manual **"Retry"** button on the error state (`conversations-rail.tsx:127`). Nothing triggers a refetch when a new conversation is created.

Per ADR-047, the rail renders through `ConversationsRailPortal` into the persistent nav slot **outside** the Next.js `children` swap region, so navigating `/dashboard/chat/new` → `/dashboard/chat/[conversationId]` swaps only `children`; the rail and its hook **stay mounted** and do **not** re-run the mount effect.

Net effect: the user opens the Dashboard with no conversations (rail mounts → empty), starts a conversation (server INSERTs the row via `ws-handler.ts:createConversation`), the conversation streams — but the rail received no INSERT event and never refetched, so it still shows "No conversations yet."

### Why #5317 did not catch this

#5317's regression test (`test/conversations-active-repo-scope.test.tsx`) renders the hook and asserts the list **populates from an initial fetch** when the active-repo route returns a `repoUrl`. It proves the *scope source* is correct; it does **not** exercise the "conversation created after mount, list initially empty" path. The INSERT gap is orthogonal to the repo_url-source fix and was left open. (Confirmed by the repo-research agent: "Still a Gap (NOT addressed by PR #5317): the rail does NOT have an INSERT realtime subscription.")

### Secondary defect: workspace-id source divergence (creation vs. rail query)

The new conversation is stamped (`ws-handler.ts:createConversation`, lines 897–907) with:

- `repo_url = await getCurrentRepoUrl(userId)` → `server/current-repo-url.ts`, reads `workspaces.repo_url` and applies `normalizeRepoUrl`. **Parity with the rail: OK** (the rail reads the route, which also reads `workspaces.repo_url` + `normalizeRepoUrl`).
- `workspace_id = await resolveUserWorkspaceBinding(userId, readWorkspaceIdFromDb)` → `server/agent-session-registry.ts:288` + `server/workspace-resolver.ts:248`. This reads `user_session_state.current_workspace_id` and **throws** (fail-loud, no solo fallback) when that column is null.

The rail's `workspace_id` filter (`use-conversations.ts:168`) uses the value from `GET /api/workspace/active-repo`, which resolves `current_workspace_id` **with a fallback to the solo workspace (`= userId`)** (`route.ts:44`).

These two paths **agree** when `user_session_state.current_workspace_id` is non-null (the common case). They **diverge** only in the edge case where the column is null: creation throws (no row inserted) while the rail filters against `workspace_id = userId`. **This asymmetry is intentional and load-bearing, not a bug** (architecture review P0; confirmed in the resolver docblocks):

- The route is a **read** (`SELECT` scoping). Solo-falling-back to `userId` only shows the user *fewer* rows — it cannot misattribute anyone's data. Safe to self-heal.
- `createConversation` performs a **durable cross-tenant write** (`conversations.workspace_id` persists). `readWorkspaceIdFromDb` (`server/workspace-resolver.ts:228-247`) and `resolveUserWorkspaceBinding` (`server/agent-session-registry.ts:276-286`) are documented as the deliberate fail-loud siblings of `resolveCurrentWorkspaceId`, created by **#5256** precisely because "a silent solo-fallback to the caller's own id … could bind one tenant's write into another's workspace." Aligning the write path to the route's solo fallback would **reintroduce the #5256 cross-tenant write hazard.**

So this is not a correctness gap to "close" — the dominant (and only) production symptom is the INSERT-path gap above. The Phase 3 work is to **verify** the fail-loud Sentry mirror fires and **document** the read-vs-write asymmetry as intentional. (In practice the divergence is near-theoretical: when the DB binding is genuinely null, `createConversation` throws and no row is inserted, so there is nothing for the rail to fail to show.)

## Proposed Solution

Two coordinated fixes in the rail's data hook (no schema change, no server change required):

1. **Primary — add a scoped Realtime INSERT subscription + insert-on-event** so a freshly-created conversation appears in the rail immediately, mirroring the existing UPDATE handler's client-side scope guards (repo_url equality + workspace `visibility` guard on the shared channel + archive-state guard). This makes the rail reflect "as soon as it is started/in progress."
2. **Secondary (reconnection-gap close) — refetch on `SUBSCRIBED` status.** Per the realtime best-practices research, Supabase Realtime delivers INSERTs **at-least-once** and does **not replay** events buffered during a disconnect window. The canonical fix for the reconnection/initial-load gap is to issue one `fetchConversations()` in the `.subscribe((status) => …)` callback when `status === "SUBSCRIBED"`. This backfills any conversation created between the mount-time fetch and the channel going live — including the exact screenshot scenario (rail mounts empty, conversation starts, channel subscribes). It is **bounded** (fires once per subscribe transition, not per-render) and replaces the originally-proposed "refetch when active id unknown" trigger, which the architecture review (P1) showed can storm into a tight refetch loop when the active conversation is genuinely out-of-scope or the route returns `repoUrl: null` (both produce a stable "id absent from list" state that never clears).

Both fixes are list-membership/read-freshness changes only. RLS on `conversations` (migration `075_conversation_visibility.sql` — policies `conversations_owner_select` and `conversations_shared_select`; there is no single `conversations_owner_or_shared` policy) already isolates cross-tenant rows, and the cross-tenant integration test (`test/conversations-rail-cross-tenant.integration.test.ts:201-226`) proves a foreign user's INSERT broadcasts **zero** payloads to another tenant — so adding an INSERT handler does not widen the trust boundary.

The workspace-id divergence (Phase 3) is **verification + documentation only** — it must NOT be "fixed" by aligning the creation path to the route's solo fallback (see the P0 finding below).

## Technical Considerations

- **Realtime filter limitation (realtime-js#97):** a `postgres_changes` subscription accepts only ONE equality predicate per channel. The existing code already works around this: the own channel filters server-side by `user_id`, the shared channel by `workspace_id`, and cross-repo / non-shared payloads are dropped **client-side** in the callback (`use-conversations.ts:256, 298`). The new INSERT handler MUST apply the **same** client-side guards (repo_url equality against `repoUrlRef.current`; `visibility === "workspace"` on the shared channel) so it cannot surface a row outside the rail's current scope.
- **At-least-once delivery → de-dup is mandatory:** Supabase Realtime delivers INSERTs **at-least-once** (an INSERT may arrive more than once, and may also race the `SUBSCRIBED` backfill refetch). The insert-into-state reducer must guard against adding a conversation the list already has, using the `c.id === updated.id` identity check from the UPDATE reducer.
- **Placeholder is FILL-ONLY (never downgrade an enriched row) — architecture review P2:** a realtime INSERT payload carries only the `conversations` row (no messages), so the handler synthesizes a placeholder enriched row. But the backfill refetch can land an **enriched** row (real title + preview) *before* the INSERT broadcast (placeholder) arrives. On an id collision the reducer MUST keep the existing populated `title`/`preview`/`lastMessageLeader` and only fill from the placeholder when the existing row is absent — a naive upsert-by-id overwrite would downgrade "Real title" back to "Untitled conversation."
- **Title derivation must share the fetch path's `system` branch — architecture review P2:** the fetch path maps `domain_leader === "system"` → literal `"Project Analysis"` (`use-conversations.ts:219-221`), bypassing `deriveTitle`. The INSERT placeholder must apply the SAME branch, or a live-created system conversation reads "Untitled conversation" until the next refetch. Factor a single `deriveRailTitle(conv, messages)` helper (including the system branch) used by BOTH the fetch enrichment and the INSERT handler. For non-system rows, `deriveTitle([], id, domain_leader)` is safe (verified: empty messages → domain-leader label or "Untitled conversation", never throws).
- **Scope guard must be ONE shared helper covering all three drop conditions — architecture review P2:** extract `shouldDropForScope(payload, { repoUrl, channel, archiveFilter })` covering (a) `repo_url` mismatch (own channel, `use-conversations.ts:256`), (b) `visibility !== "workspace"` (shared channel, `:298`), (c) archive-state mismatch (`:259-264`). The INSERT and UPDATE handlers MUST both route through it so they cannot drift. A conversation created already-archived must be dropped when `archiveFilter === "active"` (low-likelihood but the helper encapsulates it). Mandatory, not optional.
- **Do not fire a per-INSERT messages fetch** from the realtime callback (avoids an unbounded query-per-event surface — architecture review confirms this is the right call; the `SUBSCRIBED` backfill + subsequent UPDATEs refine the placeholder).
- **Ordering:** the list is ordered `last_active desc, created_at desc` (`use-conversations.ts:169–170`). A new conversation is stamped `last_active = now()` (`ws-handler.ts:904`) so it belongs at the top; prepend at the head (no client-side re-sort needed — a brand-new row is always the most recent).
- **Performance / limit:** the rail caps at `RAIL_LIMIT = 15` (`conversations-rail.tsx:14`). The INSERT reducer prepends then truncates to the hook's `limit` so the list does not grow unbounded across a long session.
- **Single channel, branch on event:** add the `event: "INSERT"` subscription to the EXISTING `ownChannel` / `sharedChannel` (`use-conversations.ts:276-303`) rather than new channels (best-practice research: single channel, branch on `payload.eventType`; fewer WS connections). The subscription effect is already keyed on `[userId, workspaceId, archiveFilter]` so lifecycle/teardown is handled.
- **NFR impacts:** read `knowledge-base/engineering/architecture/nfr-register.md` and assess realtime-fan-out and read-freshness NFRs during `/work`.

## Research Reconciliation — Spec vs. Codebase

| Claim (from bug report / prior context) | Reality (verified in codebase) | Plan response |
|---|---|---|
| "It worked previously" (regression) | True. #5317 (merged today) fixed the repo_url-source case; the INSERT gap is a separate, never-covered path. The rail has never had INSERT handling (grep: only `event: "UPDATE"` in `use-conversations.ts`). | Frame as a *remaining-gap* regression, not a re-revert of #5317. Add an INSERT path. |
| Bug is in "the conversations list data fetch/query / a filter that excludes in-progress conversations" | The `.eq("status", ...)` filter only applies when `statusFilter` is passed; the rail passes no `statusFilter`, so `active` conversations are NOT excluded by status. The exclusion is structural (no INSERT event + no post-create refetch), not a status filter. | Do NOT touch the status filter. Fix the membership/freshness path. |
| Screenshot prompt "Fix issue 4826" implicates issue #4826 | `gh issue view 4826` → OPEN, "feat: nav-rail position resume" — unrelated; it is the user's example prompt text, not the bug subject. | No action; noted in premise validation. |
| repo_url divergence (the #5317 cause) is the root cause again | `getCurrentRepoUrl` (creation) and the active-repo route (rail) BOTH read `workspaces.repo_url` + `normalizeRepoUrl` — parity holds post-#5317. | repo_url is NOT the cause this time; do not re-litigate it. |
| workspace_id parity holds | Creation throws on null `current_workspace_id` (durable cross-tenant write → fail-loud per #5256); route falls back to solo (read → safe to self-heal). The asymmetry is **intentional**. | Phase 3 = verify Sentry mirror + document; do NOT align the write path to solo fallback (would reintroduce #5256 cross-tenant write hazard). |
| RLS policy is named `conversations_owner_or_shared` | Migration `075_conversation_visibility.sql` defines TWO policies: `conversations_owner_select` (line 55) and `conversations_shared_select` (line 59). No single combined policy exists. | Cite the two real policy names; do not invent a combined name. |

## User-Brand Impact

- **If this lands broken, the user experiences:** the Recent Conversations rail shows "No conversations yet." while they are actively talking to Soleur — the product appears to have lost their work / not be recording the conversation. They cannot navigate back to an in-progress conversation from the rail.
- **If this leaks, the user's workflow is exposed via:** the new INSERT realtime handler — if its client-side scope guards (repo_url equality + `visibility === "workspace"` on the shared channel) are weaker than the existing UPDATE handler's, a conversation belonging to a different repo/workspace could surface in the rail. RLS (075) prevents cross-*tenant* leakage at the DB; the client guard prevents cross-*repo/workspace* surfacing within the same tenant.
- **Brand-survival threshold:** `single-user incident`

CPO sign-off required at plan time before `/work` begins (carry forward / confirm via Phase 2.5). `user-impact-reviewer` will run at review time per the review-skill conditional-agent block.

## Observability

```yaml
liveness_signal:
  what: "Sentry breadcrumb/event volume on the conversations-rail feature tag; absence of a sustained 'rail empty while active conversation exists' class"
  cadence: per-session (client realtime); review weekly in Sentry
  alert_target: Sentry issue (web-platform project) routed to operator
  configured_in: apps/web-platform/hooks/use-conversations.ts (reportSilentFallback calls) + existing client Sentry init

error_reporting:
  destination: "Sentry web-platform via NEXT_PUBLIC_SENTRY_DSN (client) / SENTRY_DSN (server)"
  fail_loud: "INSERT-handler scope-guard rejection and any refetch failure mirror via reportSilentFallback (cq-silent-fallback-must-mirror-to-sentry); the rail's existing error state (data-testid=conversations-rail-error) renders on fetch failure"

failure_modes:
  - mode: "INSERT realtime broadcast missed (WS reconnect / race)"
    detection: "the SUBSCRIBED-status backfill refetch covers the reconnection/initial-load gap; if the channel never reaches SUBSCRIBED the existing error-state branch renders on the mount fetch path"
    alert_route: Sentry issue -> operator
  - mode: "INSERT handler surfaces a cross-repo/workspace row (guard regression)"
    detection: "cross-tenant integration test asserts zero foreign payloads; a new unit test asserts the shared shouldDropForScope helper drops mismatched repo_url / non-workspace visibility / archived rows"
    alert_route: CI test failure (pre-merge); Sentry if it reaches prod
  - mode: "duplicate row OR title-downgrade (INSERT broadcast + backfill refetch race, at-least-once delivery)"
    detection: "unit test asserts fill-only upsert by id (no duplicate; enriched title never overwritten by placeholder)"
    alert_route: CI test failure (pre-merge)

logs:
  where: "browser console (dev) + Sentry (prod) via reportSilentFallback; server-side createConversation already logs via ws-handler"
  retention: Sentry default retention (90 days, project setting)

discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/conversations-rail.test.tsx test/conversations-active-repo-scope.test.tsx"
  expected_output: "all tests pass, including the new RED->GREEN 'active conversation created after mount appears in rail' regression test"
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (RED→GREEN regression):** A new test in `apps/web-platform/test/conversations-rail.test.tsx` (or a sibling `test/conversations-rail-insert.test.tsx` under the vitest `test/**/*.test.tsx` component glob) asserts: rail mounts with an empty list (mount-time fetch returns 0 rows), then a Realtime **INSERT** payload for a conversation matching the current `repo_url` + `workspace_id` is delivered → the rail renders that conversation row (and no longer shows `data-testid="conversations-rail-empty"`). Test fails on `main` HEAD, passes after the fix.
- [ ] **AC2 (scope guard — shared helper):** A test asserts an INSERT whose `repo_url` differs from scope is **dropped**; on the shared channel an INSERT with `visibility !== "workspace"` is dropped; an INSERT with `archived_at != null` is dropped when `archiveFilter === "active"`. All three drops route through the single `shouldDropForScope` helper used by BOTH the INSERT and UPDATE handlers.
- [ ] **AC3 (fill-only de-dup):** Two assertions. (a) An INSERT broadcast + a backfill refetch carrying the same id render exactly **one** row. (b) **Fill-only:** when an *enriched* row (real `title`/`preview`) is already present and a *placeholder* INSERT for the same id arrives, the row keeps its enriched `title`/`preview` (the placeholder must NOT downgrade it to "Untitled conversation").
- [ ] **AC3b (system title parity):** A test asserts an INSERT for a `domain_leader === "system"` conversation renders title `"Project Analysis"` (shared `deriveRailTitle` helper), not "Untitled conversation".
- [ ] **AC4 (limit respected):** A test asserts the INSERT reducer prepends and truncates to the hook's `limit` (rail never exceeds `RAIL_LIMIT` rows after a burst of INSERTs).
- [ ] **AC5 (SUBSCRIBED backfill, bounded):** A test asserts that when the channel `.subscribe()` callback fires with `status === "SUBSCRIBED"`, exactly one `fetchConversations()` runs; and that it does NOT re-fire on every render (bounded to the subscribe transition). No `useParams`-based "refetch when active id unknown" trigger exists (it was removed — P1 loop hazard).
- [ ] **AC6 (no regression of #5317):** `test/conversations-active-repo-scope.test.tsx` still passes; the repo_url scope source remains `/api/workspace/active-repo`.
- [ ] **AC7 (typecheck):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean.
- [ ] **AC8 (full component+unit suite):** `cd apps/web-platform && ./node_modules/.bin/vitest run` passes (or the affected projects per the vitest config) with no new failures.
- [ ] **AC9 (workspace-id asymmetry documented — NOT aligned):** Phase 3 records that the creation-path fail-loud is **intentional** (durable cross-tenant write, #5256) and is NOT changed to a solo fallback. Verify the `resolveUserWorkspaceBinding.unresolvable` Sentry mirror exists (`agent-session-registry.ts:316-323`). No code change to the resolvers. The PR body cites #5256 and the two resolver docblocks.

### Post-merge (operator)

- [ ] **AC10 (live verification, automatable):** After deploy (the `web-platform-release.yml` pipeline restarts the container on merge to `main` touching `apps/web-platform/**`), verify via Playwright MCP: open the Dashboard with the rail empty, start a conversation, and assert the conversation appears in the Recent Conversations rail within a few seconds without a page reload. (Automation: Playwright MCP — `mcp__playwright__*`. Not operator-eyeball.)

## Test Scenarios

### Acceptance / Regression (RED-phase targets)

- Given the rail is mounted with an empty list, when a Realtime INSERT for a conversation matching the current `repo_url` + `workspace_id` arrives, then the rail renders that conversation and hides the empty CTA. (AC1)
- Given an INSERT payload whose `repo_url` does not match the rail's scope, when it arrives, then the rail drops it and stays empty. (AC2)
- Given an INSERT on the shared channel with `visibility !== "workspace"`, when it arrives, then the rail drops it. (AC2)
- Given an INSERT broadcast and a backfill refetch both carrying conversation X, when both apply, then the rail shows exactly one row for X. (AC3a)
- Given an enriched row for X is already in the list and a placeholder INSERT for X arrives (at-least-once / out-of-order), then X keeps its real title/preview. (AC3b — fill-only)
- Given an INSERT for a `system` conversation, then the rail shows "Project Analysis". (AC3b)
- Given 20 INSERTs arrive in a session with `limit = 15`, when they apply, then the rail shows at most 15 rows (most-recent-first). (AC4)
- Given the channel reaches `SUBSCRIBED`, then exactly one backfill `fetchConversations()` fires (and not again on subsequent re-renders). (AC5)

### Edge cases

- Given a conversation created between the mount-time fetch and the channel going live (the screenshot scenario), when the channel reaches `SUBSCRIBED`, then the backfill refetch surfaces it. (AC5)
- Given a missed/duplicate INSERT broadcast (at-least-once delivery, WS reconnect), then the fill-only de-dup keeps the list correct (no duplicate, no downgrade). (AC3)
- Given `user_session_state.current_workspace_id` is null, when a conversation is created, then `createConversation` throws (fail-loud, #5256) and no mismatched row is inserted — the rail correctly shows nothing for a write that never happened; the asymmetry is intentional. (AC9)

### Integration verification (for /soleur:qa)

- **Browser (Playwright MCP):** Navigate to `/dashboard/chat/new`, send a message to start a conversation, wait for streaming to begin, assert the Recent Conversations rail lists the conversation (no reload). (AC10)

## Dependencies & Risks

- **Risk (P2, arch review):** INSERT and UPDATE scope guards drift. **Mitigation:** ONE `shouldDropForScope` helper (repo_url + visibility + archive) used by both; mandatory, AC2 locks it.
- **Risk (P2, arch review):** placeholder INSERT downgrades an already-enriched row (out-of-order vs backfill refetch, at-least-once delivery). **Mitigation:** fill-only upsert; AC3.
- **Risk (P2, arch review):** live-created `system` conversation reads "Untitled conversation". **Mitigation:** shared `deriveRailTitle` with the `system → "Project Analysis"` branch; AC3b.
- **Risk (P1, arch review — DESIGNED OUT):** a "refetch when active id unknown" trigger storms into a tight loop when the conversation is genuinely out-of-scope or the route returns `repoUrl: null` (stable "absent" state never clears). **Mitigation:** that trigger was removed; the reconnection-gap close is the bounded `SUBSCRIBED`-status backfill (fires once per subscribe transition); AC5.
- **Risk (P0, arch review — FORBIDDEN ACTION):** aligning `createConversation`'s workspace resolution to the route's solo fallback would reintroduce the #5256 cross-tenant write hazard. **Mitigation:** Phase 3 is doc-only; the fail-loop stays; AC9.
- **Dependency:** none new. No schema migration. Entirely client-only (hook); Phase 3 is documentation.

## Research Insights (deepen-plan)

**Supabase Realtime (supabase-js v2.49.0 installed):**
- `postgres_changes` filters accept only ONE equality predicate per channel (realtime-js#97, unfixed). The codebase already works around this: server-side filter on the high-cardinality field (`user_id` / `workspace_id`), drop secondary conditions client-side. The INSERT handler must follow the same dual-layer pattern.
- INSERT delivery is **at-least-once** (may duplicate; may race the backfill refetch) and is **not replayed** across a disconnect window. → de-dup is mandatory; the `SUBSCRIBED`-status backfill closes the reconnection/initial-load gap. (Both confirmed against the codebase's own `leader-loop-status.tsx:146-192` polling-fallback precedent.)
- Single channel + branch on `payload.eventType` is preferred over separate INSERT/UPDATE channels (fewer WS connections).
- Prepend at head (new row is `last_active = now()`), truncate to `limit`; no client-side re-sort needed.
- Refs: https://supabase.com/docs/guides/realtime/postgres-changes#filters ; https://github.com/supabase/realtime-js/issues/97

**Precedent-diff (Phase 4.4):** No prior realtime **INSERT** handler exists in `apps/web-platform` — the pattern is novel for this codebase (verified: only `event: "UPDATE"` in `use-conversations.ts` and `leader-loop-status.tsx`; the integration test uses `event: "*"` only to assert isolation, not to maintain a list). The UPDATE handler (`handleConversationUpdate`, `use-conversations.ts:253-272`) is the sibling to mirror for the reducer shape and client-side guards. The `leader-loop-status.tsx` subscribe-status + polling-fallback is the precedent for the `SUBSCRIBED` backfill.

**Verify-the-negative (Phase 4.45):** all 8 negative/structural claims confirmed against code EXCEPT the RLS policy name — corrected (075 has two policies: `conversations_owner_select`, `conversations_shared_select`; no combined `conversations_owner_or_shared`).

## Sharp Edges

- **Do NOT add a `useParams`-based "refetch when active conversationId is absent from the list" trigger.** It storms into a tight refetch loop when the active conversation is genuinely out-of-scope or `/api/workspace/active-repo` returns `repoUrl: null` — both yield a stable "id absent" state that never clears, so the effect re-fires forever (architecture review P1). Use the bounded `SUBSCRIBED`-status backfill instead.
- **Do NOT change `createConversation`'s `workspace_id` resolution to a solo fallback.** The fail-loud in `resolveUserWorkspaceBinding` / `readWorkspaceIdFromDb` is intentional (#5256): it guards a durable cross-tenant write. The route may solo-fall-back because it is only a read. Aligning them reintroduces the #5256 hazard (architecture review P0).
- **The INSERT placeholder must be FILL-ONLY.** At-least-once delivery + the backfill refetch mean a placeholder INSERT can arrive AFTER an enriched row is already in the list; a naive upsert-by-id overwrite downgrades the real title to "Untitled conversation" (architecture review P2).
- **The INSERT title path must reuse the fetch path's `domain_leader === "system" → "Project Analysis"` branch**, or live-created system conversations read "Untitled conversation" until the next refetch (architecture review P2).
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is complete.)

## Files to Edit

- `apps/web-platform/hooks/use-conversations.ts` — add `event: "INSERT"` to the existing own + shared channels (branch on event); add the shared `shouldDropForScope` helper (repo_url + visibility + archive) and the shared `deriveRailTitle` helper (incl. `system → "Project Analysis"`); add the fill-only prepend + de-dup + truncate-to-limit INSERT reducer; add the `SUBSCRIBED`-status backfill `fetchConversations()` call inside the `.subscribe()` callback.
- `apps/web-platform/test/conversations-rail.test.tsx` — add INSERT regression + scope-guard + fill-only-dedup + limit tests; add a `SUBSCRIBED`-backfill test (or a sibling `test/conversations-rail-insert.test.tsx` under the `test/**/*.test.tsx` component glob — verify the glob before choosing a path; reuse the channel mock from `test/conversations-rail.test.tsx` / `use-conversations-limit.test.tsx` which returns a chainable `.on()`/`.subscribe()` mock so the test can extract and invoke the INSERT callback + the subscribe-status callback).
- `apps/web-platform/server/agent-session-registry.ts` / `apps/web-platform/server/workspace-resolver.ts` — **documentation-only** (Phase 3): confirm the fail-loud docblocks reference #5256; no code change (aligning to solo fallback is forbidden — P0).
- **NOTE:** `conversations-rail.tsx` is **no longer edited** — the secondary refetch moved into the hook's `subscribe` callback (the component-edit + `useParams`-based trigger of plan v1 was removed per architecture review P1). The plan is now hook-only on the client. (This also means the UI-surface mechanical override no longer fires on a `components/**` file — see updated Domain Review.)

## Files to Create

- (Optional) `apps/web-platform/test/conversations-rail-insert.test.tsx` — if the new tests are kept separate from the existing rail test. Must live under a path matching the vitest `test/**/*.test.tsx` include glob (`apps/web-platform/vitest.config.ts`).

## Implementation Phases

### Phase 1 — RED: failing regression test for the INSERT gap

Write AC1 (and AC2–AC5 skeletons) as failing tests against the current hook. Confirm AC1 fails on `main` HEAD. Reuse the existing rail test's channel mock (chainable `.on()`/`.subscribe()` — extract the registered INSERT callback and the subscribe-status callback from the mock spy and invoke them with synthetic `{ new: <row>, eventType: "INSERT" }` payloads; the cross-tenant integration test shows the payload shape).

### Phase 2 — GREEN: scoped INSERT subscription + helpers + SUBSCRIBED backfill

- Extract `shouldDropForScope(payload, { repoUrl, channel, archiveFilter })` (repo_url + visibility + archive) and `deriveRailTitle(conv, messages)` (incl. `system` branch); refactor the existing UPDATE handler to use them (no behavior change — locked by AC6 + existing tests).
- Add `event: "INSERT"` to the own and shared channels (branch on event), routing through `shouldDropForScope`.
- Implement the fill-only prepend + de-dup + truncate-to-limit reducer with placeholder enrichment via `deriveRailTitle(conv, [])`.
- Add the `SUBSCRIBED`-status backfill `fetchConversations()` inside the `.subscribe()` callback (bounded to the subscribe transition).
- Make AC1–AC8 pass. (Do NOT add any `useParams`-based refetch trigger — P1.)

### Phase 3 — workspace-id asymmetry: verify + document (AC9), NO code change

- Read `resolveUserWorkspaceBinding` (`agent-session-registry.ts:276-327`) / `readWorkspaceIdFromDb` (`workspace-resolver.ts:228-276`) and confirm the fail-loud docblocks cite #5256, and that the `resolveUserWorkspaceBinding.unresolvable` Sentry mirror exists (`:316-323`).
- Record in the PR body: the read-vs-durable-write rule (route may solo-fall-back; createConversation must fail-loud). Do NOT change the resolvers. Aligning to solo fallback is the #5256 regression and is forbidden (P0).

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** none
**Decision:** N/A — no UI-surface file in scope after the v2 revision
**Agents invoked:** none
**Skipped specialists:** none — `ux-design-lead` correctly N/A (no UI-surface file edited)
**Pencil available:** N/A (no UI surface change)

#### Findings

After the architecture-review revision (P1), the plan is **hook-only on the client** — `apps/web-platform/hooks/use-conversations.ts` and tests, plus doc-only resolver verification. **No `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` file is edited**, so the mechanical UI-surface override does not fire and the Product/UX Gate tier resolves to NONE. The rail component (`conversations-rail.tsx`) and its rows/empty/error states are entirely unchanged; only *which rows the already-designed list renders* changes, and that is decided in the data hook. CPO sign-off remains required by the `single-user incident` threshold (User-Brand Impact) — the rail rendering the user's active work is product-critical — but there is no page/flow/component design to review.

**Wireframe determination (`wg-ui-feature-requires-pen-wireframe` / deepen-plan Phase 4.9):** NO `.pen` wireframe required and the Phase 4.9 halt does not trigger — the plan's `## Files to Edit` / `## Files to Create` contain no path matching the UI-surface glob superset (`plugins/soleur/skills/brainstorm/references/ui-surface-terms.md`). This is a backend-of-UI data-freshness fix with zero pixel/layout change. Recorded explicitly (not a silent skip) so deepen-plan Phase 4.9 and work Check-9 agree.

## References & Research

### Internal references

- `apps/web-platform/hooks/use-conversations.ts` — data hook (bug site): mount-only fetch (239–241), UPDATE-only channels (276–309), no INSERT handler.
- `apps/web-platform/components/chat/conversations-rail.tsx` — rail UI (NOT edited): empty-state branch (133–139), error-state (120–132). Consumes `conversations` from the hook; no change needed once the hook supplies the new row.
- `apps/web-platform/components/dashboard/leader-loop-status.tsx:146-192` — precedent for subscribe-status handling + polling fallback (the `SUBSCRIBED` backfill mirrors this).
- `apps/web-platform/server/workspace-resolver.ts:228-276` + `apps/web-platform/server/agent-session-registry.ts:276-327` — fail-loud workspace resolvers (#5256); doc-only verification target.
- `apps/web-platform/supabase/migrations/075_conversation_visibility.sql` — RLS policies `conversations_owner_select` (55) + `conversations_shared_select` (59).
- `apps/web-platform/app/api/workspace/active-repo/route.ts` — repo/workspace scope source; solo fallback at line 44; `normalizeRepoUrl` at 73.
- `apps/web-platform/server/ws-handler.ts` — `createConversation` (851–907); stamps `repo_url` via `getCurrentRepoUrl` (865) and `workspace_id` via `resolveUserWorkspaceBinding` (892–894); INSERT at 897.
- `apps/web-platform/server/current-repo-url.ts` — `getCurrentRepoUrl` reads `workspaces.repo_url` + `normalizeRepoUrl` (parity with the route — confirmed).
- `apps/web-platform/server/agent-session-registry.ts:288` (`resolveUserWorkspaceBinding`, fail-loud on null) and `apps/web-platform/server/workspace-resolver.ts:248` (`readWorkspaceIdFromDb`, returns null, never userId).
- `apps/web-platform/server/conversations-tools.ts` — `conversations_list` + `conversation_update_status` MCP tools already exist (agent-native read parity present).
- `apps/web-platform/test/conversations-rail-cross-tenant.integration.test.ts` — proves RLS isolates foreign INSERT broadcasts (zero cross-tenant payloads); `postgres_changes` payload shape reference (`event: "*"` at 147).
- `apps/web-platform/vitest.config.ts` — test runner is **vitest**; component glob `test/**/*.test.tsx` (happy-dom); `apps/web-platform/bunfig.toml` blocks bun test.
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — repo state moved users→workspaces; `normalizeRepoUrl` parity load-bearing; threshold `single-user incident`.
- `knowledge-base/engineering/architecture/decisions/ADR-047-nav-context-band-outside-swap.md` — rail portals outside the swap region → stays mounted across chat navigation (why the mount-only fetch never re-runs).
- `knowledge-base/project/plans/2026-06-15-fix-conversations-rail-empty-repo-url-source-divergence-plan.md` — the #5317 plan (prior fix, same symptom, different root cause).
- `knowledge-base/engineering/operations/post-mortems/conversations-rail-repo-url-divergence-postmortem.md` — #5317 postmortem.

### Learnings

- `knowledge-base/project/learnings/2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper.md` — Realtime subscriptions are a separate query pathway that must apply the same scope guards as the fetch; directly applies to the new INSERT handler's client-side guards.
- `knowledge-base/project/learnings/2026-04-11-deferred-ws-conversation-creation-and-pending-state.md` — exhaustive handler coverage; the "UPDATE-only, no INSERT" gap is the partial-coverage failure class.
- `knowledge-base/project/learnings/2026-05-27-client-server-rls-mismatch-post-workspace-sweep.md` — client filter must mirror RLS scope (workspace_id, not just user_id).
- `knowledge-base/project/learnings/2026-04-02-defensive-state-clear-on-useeffect-remount.md` — subscription lifecycle / clear-stale-state on the realtime effect (already keyed on `[userId, workspaceId, archiveFilter]`; the INSERT subscription joins the same effect).

### Related work

- Related PRs: #5317 (prior same-symptom fix), #4524/#4521 (team visibility + workspace_id), #3021 (in-chat rail + cross-tenant realtime isolation), #2766 (scope by repo_url).
- Related issues: #4543 (CLOSED, dual-ownership trap context). #4826 (OPEN, unrelated — the screenshot's example prompt text only).

## Open Code-Review Overlap

None. (Queried open `code-review`-labeled issues against the planned file set; no overlap.)
