---
title: "fix: active/in-progress conversation missing from Recent Conversations rail"
type: fix
date: 2026-06-15
lane: single-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# fix: active/in-progress conversation missing from Recent Conversations rail

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

These two paths **agree** when `user_session_state.current_workspace_id` is non-null (the common case). They **diverge** only in the edge case where the column is null: creation throws (no row inserted) while the rail would have filtered against `workspace_id = userId`. Because creation throws rather than inserts a mismatched row, the dominant production symptom is the INSERT-path gap above — **but** the divergence is a latent correctness asymmetry worth closing in the same PR, since both paths claim to resolve "the user's active workspace" and only one self-heals to solo.

## Proposed Solution

Two coordinated fixes, both in the rail's data hook (no schema change, no server change required for the primary fix):

1. **Primary — add a scoped Realtime INSERT subscription + insert-on-event** so a freshly-created conversation appears in the rail immediately, mirroring the existing UPDATE handler's scope guards (repo_url match + workspace `visibility` guard on the shared channel). This makes the rail reflect "as soon as it is started/in progress," which is the stated expected behavior.
2. **Secondary (belt-and-suspenders) — refetch the list when the active conversation id changes to one the rail does not yet know about.** `conversations-rail.tsx` already reads `useParams().conversationId` for the `active` highlight. When that id is set but is absent from `conversations`, trigger one `refetch()`. This covers the case where the INSERT broadcast is missed (WS reconnect, race between navigation and broadcast) and the case where the conversation pre-existed but the list mounted empty due to a transient earlier failure.

Both fixes are list-membership/read-freshness changes only. RLS (`conversations_owner_or_shared`, migration 075) already isolates cross-tenant rows, and the cross-tenant integration test (`test/conversations-rail-cross-tenant.integration.test.ts`) already proves a foreign user's INSERT broadcasts **zero** payloads to another tenant — so adding an INSERT handler does not widen the trust boundary.

The workspace-id divergence is addressed by aligning the creation-path resolver's null-handling with the route's solo fallback (or by an explicit, Sentry-mirrored decision to keep fail-loud) — see Phase 3.

## Technical Considerations

- **Realtime filter limitation (realtime-js#97):** a `postgres_changes` subscription accepts only ONE equality predicate per channel. The existing code already works around this: the own channel filters server-side by `user_id`, the shared channel by `workspace_id`, and cross-repo / non-shared payloads are dropped **client-side** in the callback (`use-conversations.ts:256, 298`). The new INSERT handler MUST apply the **same** client-side guards (repo_url equality against `repoUrlRef.current`; `visibility === "workspace"` on the shared channel) so it cannot surface a row outside the rail's current scope.
- **De-dup on INSERT:** the insert-into-state reducer must guard against adding a conversation the list already has (the secondary refetch and the INSERT broadcast can race). Use the same `c.id === updated.id` identity check pattern already used in the UPDATE reducer; if present, treat as an upsert (no duplicate row).
- **Ordering:** the list is ordered `last_active desc, created_at desc` (`use-conversations.ts:169–170`). A new conversation is stamped `last_active = now()` (`ws-handler.ts:904`) so it belongs at the top; insert at the head, but keep the reducer resilient (insert then no client-side re-sort is required because a brand-new row is always the most recent).
- **Title/preview enrichment:** the fetch path enriches rows with `title`/`preview`/`lastMessageLeader` derived from a second `messages` query (`use-conversations.ts:200–228`). A realtime INSERT payload carries only the `conversations` row (no messages). The handler must synthesize a placeholder enriched row (e.g. `title` via `deriveTitle([], id, domain_leader)` → falls through to the domain-leader label or "Untitled conversation"; `preview: null`). Subsequent UPDATE events and the next mount-time refetch refine it. **Do not** fire a per-INSERT messages fetch from the realtime callback (avoids an unbounded query-per-event surface).
- **Performance:** the rail caps at `RAIL_LIMIT = 15` (`conversations-rail.tsx:14`). The INSERT reducer must respect the limit — prepend then truncate to the hook's `limit` so the list does not grow unbounded across a long session.
- **NFR impacts:** read `knowledge-base/engineering/architecture/nfr-register.md` and assess realtime-fan-out and read-freshness NFRs during `/work`.

## Research Reconciliation — Spec vs. Codebase

| Claim (from bug report / prior context) | Reality (verified in codebase) | Plan response |
|---|---|---|
| "It worked previously" (regression) | True. #5317 (merged today) fixed the repo_url-source case; the INSERT gap is a separate, never-covered path. The rail has never had INSERT handling (grep: only `event: "UPDATE"` in `use-conversations.ts`). | Frame as a *remaining-gap* regression, not a re-revert of #5317. Add an INSERT path. |
| Bug is in "the conversations list data fetch/query / a filter that excludes in-progress conversations" | The `.eq("status", ...)` filter only applies when `statusFilter` is passed; the rail passes no `statusFilter`, so `active` conversations are NOT excluded by status. The exclusion is structural (no INSERT event + no post-create refetch), not a status filter. | Do NOT touch the status filter. Fix the membership/freshness path. |
| Screenshot prompt "Fix issue 4826" implicates issue #4826 | `gh issue view 4826` → OPEN, "feat: nav-rail position resume" — unrelated; it is the user's example prompt text, not the bug subject. | No action; noted in premise validation. |
| repo_url divergence (the #5317 cause) is the root cause again | `getCurrentRepoUrl` (creation) and the active-repo route (rail) BOTH read `workspaces.repo_url` + `normalizeRepoUrl` — parity holds post-#5317. | repo_url is NOT the cause this time; do not re-litigate it. |
| workspace_id parity holds | Creation throws on null `current_workspace_id`; route falls back to solo. Latent asymmetry. | Align in Phase 3 (or fail-loud + Sentry mirror with explicit rationale). |

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
    detection: "secondary refetch-on-unknown-active-id covers it; if both fail, rail stays empty and the error-state branch does not render (silent) — covered by a Sentry breadcrumb when activeId is set but absent from list after refetch"
    alert_route: Sentry issue -> operator
  - mode: "INSERT handler surfaces a cross-repo/workspace row (guard regression)"
    detection: "cross-tenant integration test asserts zero foreign payloads; a new unit test asserts the INSERT guard drops mismatched repo_url / non-workspace visibility"
    alert_route: CI test failure (pre-merge); Sentry if it reaches prod
  - mode: "duplicate row inserted (INSERT broadcast + refetch race)"
    detection: "unit test asserts the reducer upserts by id (no duplicate); React key-collision warning in dev"
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
- [ ] **AC2 (scope guard):** A test asserts an INSERT payload whose `repo_url` differs from the rail's current scope is **dropped** (rail stays empty), and on the shared channel an INSERT with `visibility !== "workspace"` is dropped — mirroring the UPDATE handler's guards.
- [ ] **AC3 (de-dup):** A test asserts that when an INSERT broadcast and a refetch both deliver the same conversation id, the rail renders exactly **one** row (reducer upserts by id; no duplicate React key).
- [ ] **AC4 (limit respected):** A test asserts the INSERT reducer prepends and truncates to the hook's `limit` (rail never exceeds `RAIL_LIMIT` rows after a burst of INSERTs).
- [ ] **AC5 (secondary refetch):** A test asserts that when `useParams().conversationId` is set to an id absent from the list, the hook fires exactly one `refetch()` (and does not loop when the id is already present).
- [ ] **AC6 (no regression of #5317):** `test/conversations-active-repo-scope.test.tsx` still passes; the repo_url scope source remains `/api/workspace/active-repo`.
- [ ] **AC7 (typecheck):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean.
- [ ] **AC8 (full component+unit suite):** `cd apps/web-platform && ./node_modules/.bin/vitest run` passes (or the affected projects per the vitest config) with no new failures.
- [ ] **AC9 (workspace-id divergence resolution):** Phase 3 decision is recorded: either the creation-path null-workspace handling is aligned with the route's solo fallback (with a test), OR a one-paragraph rationale + Sentry-mirror is documented for keeping fail-loud. No silent divergence remains.

### Post-merge (operator)

- [ ] **AC10 (live verification, automatable):** After deploy (the `web-platform-release.yml` pipeline restarts the container on merge to `main` touching `apps/web-platform/**`), verify via Playwright MCP: open the Dashboard with the rail empty, start a conversation, and assert the conversation appears in the Recent Conversations rail within a few seconds without a page reload. (Automation: Playwright MCP — `mcp__playwright__*`. Not operator-eyeball.)

## Test Scenarios

### Acceptance / Regression (RED-phase targets)

- Given the rail is mounted with an empty list, when a Realtime INSERT for a conversation matching the current `repo_url` + `workspace_id` arrives, then the rail renders that conversation and hides the empty CTA. (AC1)
- Given an INSERT payload whose `repo_url` does not match the rail's scope, when it arrives, then the rail drops it and stays empty. (AC2)
- Given an INSERT on the shared channel with `visibility !== "workspace"`, when it arrives, then the rail drops it. (AC2)
- Given an INSERT broadcast and a refetch both carrying conversation X, when both apply, then the rail shows exactly one row for X. (AC3)
- Given 20 INSERTs arrive in a session with `limit = 15`, when they apply, then the rail shows at most 15 rows (most-recent-first). (AC4)
- Given `conversationId` from the route is set but absent from the list, when the rail renders, then exactly one `refetch()` fires; given it is present, no refetch fires. (AC5)

### Edge cases

- Given a missed INSERT broadcast (WS reconnect) but the route's `conversationId` points at the active conversation, when the rail renders, then the secondary refetch surfaces it. (AC5 covers)
- Given `user_session_state.current_workspace_id` is null, when a conversation is created, then creation and rail-query resolve the SAME workspace id (post Phase 3 alignment) so the new conversation is visible. (AC9)

### Integration verification (for /soleur:qa)

- **Browser (Playwright MCP):** Navigate to `/dashboard/chat/new`, send a message to start a conversation, wait for streaming to begin, assert the Recent Conversations rail lists the conversation (no reload). (AC10)

## Dependencies & Risks

- **Risk:** the INSERT handler's client-side scope guards drift from the UPDATE handler's. **Mitigation:** factor the shared scope-guard predicate (repo_url equality + visibility) into a single helper used by both handlers; AC2 locks it.
- **Risk:** duplicate rows from INSERT/refetch race. **Mitigation:** upsert-by-id reducer; AC3.
- **Risk:** title/preview placeholder looks bare until the next refetch. **Mitigation:** `deriveTitle([], id, domain_leader)` already yields a sensible label; UPDATE events + next mount-refetch refine. Acceptable read-freshness gap, not a correctness break.
- **Dependency:** none new. No schema migration. The primary fix is client-only; Phase 3 may touch `server/agent-session-registry.ts` / `server/workspace-resolver.ts` if alignment is chosen.

## Files to Edit

- `apps/web-platform/hooks/use-conversations.ts` — add scoped Realtime **INSERT** subscription on both channels (own + shared) with the same client-side guards as the UPDATE handler; add an upsert-by-id + prepend + truncate-to-limit reducer; expose/trigger the secondary refetch path.
- `apps/web-platform/components/chat/conversations-rail.tsx` — wire the secondary "refetch when active `conversationId` is set but absent from the list" trigger (uses the existing `useParams` + `refetch` already in scope).
- `apps/web-platform/test/conversations-rail.test.tsx` — add INSERT regression + scope-guard + de-dup + limit + secondary-refetch tests (or a sibling `test/conversations-rail-insert.test.tsx` under the `test/**/*.test.tsx` component glob — verify the glob before choosing a path).
- `apps/web-platform/server/agent-session-registry.ts` and/or `apps/web-platform/server/workspace-resolver.ts` — **only if** Phase 3 chooses to align the creation-path null-workspace handling with the route's solo fallback. Otherwise documentation-only.

## Files to Create

- (Optional) `apps/web-platform/test/conversations-rail-insert.test.tsx` — if the new tests are kept separate from the existing rail test. Must live under a path matching the vitest `test/**/*.test.tsx` include glob (`apps/web-platform/vitest.config.ts`).

## Implementation Phases

### Phase 1 — RED: failing regression test for the INSERT gap

Write AC1 (and AC2–AC5 skeletons) as failing tests against the current hook. Confirm AC1 fails on `main` HEAD. Use the existing rail test's harness (mocked Supabase client + injectable realtime payloads; the cross-tenant integration test shows the `postgres_changes` payload shape).

### Phase 2 — GREEN: scoped INSERT subscription + secondary refetch

- Add `event: "INSERT"` subscriptions on the own and shared channels with the same server-side filter + client-side guard pattern as the UPDATE handlers.
- Implement the upsert-by-id, prepend, truncate-to-limit reducer and the placeholder enrichment.
- Add the `refetch-when-active-id-unknown` trigger in `conversations-rail.tsx` (guard against re-fire loops).
- Make AC1–AC8 pass.

### Phase 3 — workspace-id divergence decision (AC9)

- Re-verify the creation vs. route null-handling divergence with a focused read of `resolveUserWorkspaceBinding` / `readWorkspaceIdFromDb` vs. `route.ts:44`.
- Decide: (a) align creation to fall back to solo (`= userId`) like the route — preferred if it does not violate an existing fail-loud invariant the registry depends on; add a test; or (b) keep fail-loud and document the rationale + ensure the Sentry mirror already fires (it does, at `resolveUserWorkspaceBinding.unresolvable`). Record the decision in the plan/PR body.

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline auto-accept)
**Skipped specialists:** none — `ux-design-lead` N/A (no new user-facing surface; this restores existing rail rows that already have a committed design; no new page/component/flow is created)
**Pencil available:** N/A (no UI surface change — the empty-state and row components already exist; this is a list-membership/data-freshness fix)

#### Findings

The change modifies the data path feeding an existing rail (`components/chat/conversations-rail.tsx`); it adds no new pages, modals, flows, or interactive surfaces. The mechanical UI-surface override applies (a `components/chat/*.tsx` path is edited), forcing the gate to run, but the tier resolves to **advisory** because no new interactive surface is created — the rail, its rows, and its empty/error states are pre-existing. CPO sign-off is required by the `single-user incident` threshold (see User-Brand Impact); the rail rendering the user's active work is product-critical.

## References & Research

### Internal references

- `apps/web-platform/hooks/use-conversations.ts` — data hook (bug site): mount-only fetch (239–241), UPDATE-only channels (276–309), no INSERT handler.
- `apps/web-platform/components/chat/conversations-rail.tsx` — rail UI; empty-state branch (133–139), error-state (120–132), `useParams` active id (89–90), `refetch` wired only to Retry (127).
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
