---
title: Command Center Conversation Nav (in-chat switcher)
date: 2026-04-29
topic: command-center-conversation-nav
status: decided
related_issues: [3024, 3025, 3026, 3027, 3028, 2194]
related_brainstorms:
  - 2026-04-07-conversation-inbox-brainstorm.md
  - 2026-04-15-collapsible-navs-ux-review-brainstorm.md
---

# Brainstorm: Command Center Conversation Nav

## What We're Building

A **secondary navigation rail inside the chat segment** that lets a user switch between their recent conversations without round-tripping back to `/dashboard` (the Command Center inbox). The rail lives in a new `app/(dashboard)/dashboard/chat/layout.tsx` so it persists across `/dashboard/chat/[conversationId]` route changes without remount/resubscribe, and is invisible on `/dashboard`, `/dashboard/kb`, `/dashboard/settings`.

### v1 Surface

- New nested layout: `apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx`
- A `ChatConversationsRail` client component owning the conversation list state + Realtime subscription
- Reuses the existing `useConversations` hook (`apps/web-platform/hooks/use-conversations.ts`) with a `limit: 15` variant (subscription already filters `user_id=eq.${userId}` with a defensive client-side `user_id` check)
- Reuses `useSidebarCollapse` + `Cmd/Ctrl+B` (decided in the 2026-04-15 collapsible-navs brainstorm)
- Mobile: reuse the existing dashboard drawer pattern
- Each row renders: **conversation title + status badge + relative-time + unread count** — explicitly NO last-message snippet in v1
- Cap: top 15 most recent + a "View all in Command Center" link routing to `/dashboard`

## Why This Approach

**Scoped to the chat segment, not the global sidebar.** All three domain leaders (CPO, CLO, CTO) converged here. CPO: don't dilute the 3-item global IA (Command Center / KB / Settings); the inbox stays the curated triage surface. CTO: nested layouts don't remount on `[conversationId]` route changes, giving us a single Realtime subscription with no resubscribe storms; ships independently of #2194 (DashboardLayout decomposition); doesn't pay for the bundle on `/dashboard/kb`. CLO: smaller blast-radius surface than persistent global chrome.

**Title + status + time + unread, no snippets in v1.** Snippets are user-typed free text that may contain BYOK keys, emails, or card-shaped digits. Persistent rendering widens the leak window vs. today's one-shot `/dashboard` list. Re-introducing snippets later requires server-side regex redaction before the row leaves Postgres (CLO mandate) — tracked as a follow-on issue, not v1 scope.

**Reuse `useConversations`, do not fork.** The hook already implements `filter: user_id=eq.${userId}` with a defensive client-side check ("Free tier ignores server-side filter" — comment in the hook today). A thin variant (or option) for `limit: 15` keeps the Realtime contract single-sourced.

**Top 15 + escape hatch over pagination/virtualization.** The ICP behavior is switching between *active* threads. Older work belongs in Command Center. Cursor pagination + `react-virtual` is engineering work for a fraction of users — defer until usage shows it's needed.

## User-Brand Impact

**Brand-survival threshold:** `single-user incident` (USER_BRAND_CRITICAL).

| Field | Value |
|---|---|
| Artifact | Conversation list (title + status + updated-at + unread count) of the authenticated user, rendered persistently inside `/dashboard/chat/*`. |
| Vector | Cross-tenant read via (1) Supabase Realtime `postgres_changes` channel without a per-user `filter`, (2) SWR/Query cache key not user-scoped, (3) Realtime channel not torn down on `signOut`. |
| Threshold | `single-user incident` — one user seeing another user's conversation titles is brand-ending for a solo-founder agent platform. |
| Worst observed outcome | A logs in, switches into a chat, and momentarily sees B's titles (cache flash) or persistently receives B's INSERT/UPDATE payloads (Realtime broadcast unfiltered). |

**Required gates before merge** (carry forward to plan and `/work`):

1. Realtime channel MUST set `filter: user_id=eq.${authenticatedUid}` AND retain a defensive client-side `user_id !== uid` drop (matches existing hook pattern).
2. SWR/React-Query cache keys MUST include `auth.uid()`.
3. `onAuthStateChange("SIGNED_OUT")` MUST tear down the Realtime channel and clear caches before redirect (GDPR Art. 5(1)(f)).
4. Playwright cross-tenant RLS test as hard acceptance criterion: sign in as User A, assert User B's conversations are absent from the rail and absent from any received Realtime payloads.
5. `user-impact-reviewer` + `security-sentinel` (focused on cache-key scoping, Realtime filter, logout teardown) sign-off.
6. Re-read `apps/web-platform/app/privacy/page.tsx` during `/work` — likely no edit (existing clauses are surface-agnostic), but confirm.

## Key Decisions

| # | Decision | Choice | Alternatives Considered |
|---|---|---|---|
| 1 | Surface placement | Nested `app/(dashboard)/dashboard/chat/layout.tsx` rail | 4th main-sidebar panel; collapsible group under Command Center; hybrid with filters |
| 2 | Row contents | Title + status badge + relative-time + unread count | + last-message snippet (deferred); minimal title-only |
| 3 | List size | Top 15 most recent + "View all in Command Center" link | Cursor-paginate 30/page + virtualize >200; no cap |
| 4 | Filter dropdowns | None in v1 (Status/Domain belong in Command Center) | Inherit dashboard filters into the rail |
| 5 | Mobile | Reuse existing dashboard drawer | Separate mobile treatment; hide on mobile |
| 6 | Subscription owner | Chat-segment layout (single subscribe across `[conversationId]` changes) | Per-page subscription in `[conversationId]/page.tsx` |
| 7 | Hook reuse | Reuse `useConversations` with `limit: 15` variant | New parallel hook |
| 8 | Collapse + shortcut | Reuse `useSidebarCollapse` + `Cmd/Ctrl+B` | New shortcut |
| 9 | Snippets | Out of scope in v1; tracked as follow-on issue with server-side redaction | Include in v1 with redaction |
| 10 | Coupling with #2194 | Ship in parallel — does not touch `(dashboard)/layout.tsx` | Predicate on #2194 first |
| 11 | New AGENTS.md rule | Draft + track in a separate issue: "Realtime `postgres_changes` channels MUST set `filter: user_id=eq.<uid>` — RLS does not gate broadcasts" | Bake the rule into this PR; skip the rule |

## Open Questions

1. **Pinning.** Should the user be able to pin a conversation to the top of the rail? Defer to UX design pass; not v1.
2. **Active-row indication.** Highlight the currently open conversation in the rail. Treat as implementation detail; spec it as part of acceptance criteria.
3. **Empty state.** When there are no other conversations, render the rail with a single "+ New conversation" CTA, or hide the rail entirely? Slight CPO lean toward CTA.
4. **Realtime free-tier filter behavior.** The existing hook's comment ("Free tier ignores server-side filter") suggests Supabase plan tier may affect server-side filter enforcement. Verify current plan and document the fact in the brainstorm doc / new AGENTS.md rule.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support
**Mandatory by USER_BRAND_CRITICAL:** Product (CPO), Legal (CLO), Engineering (CTO).
**Not consulted:** Marketing, Operations, Sales, Finance, Support — no signals match (post-auth utility nav, no content/brand impact, no vendor decision, no revenue/sales motion, no support-process change).

### Product (CPO)

**Summary:** Recommends a scoped chat-segment rail rendering title + status + time + unread for the 15 most-recent conversations of the current user, reusing `useSidebarCollapse`. Hard acceptance criterion: Playwright cross-tenant RLS test before merge. Snippets and filter dropdowns explicitly out of v1. Capability gap: `spec-flow-analyzer` should flag specs lacking a cross-tenant scenario as an acceptance criterion.

### Legal (CLO)

**Summary:** No new privacy-policy disclosure expected (re-affirm existing surface-agnostic clauses; verify by reading `apps/web-platform/app/privacy/page.tsx`). RLS is necessary but insufficient for snippets — defer them. Cross-tenant leak vectors ranked: SWR cache key not user-scoped (most likely) > Realtime channel filter typo > Next.js `fetch` memoization > RLS gap. Logout race is a compliance concern under GDPR Art. 5(1)(f) — must clear caches and channels before redirect. Required: `user-impact-reviewer` + `security-sentinel` with cache/Realtime/logout focus.

### Engineering (CTO)

**Summary:** Recommends `app/(dashboard)/dashboard/chat/layout.tsx` (server shell + client `ChatSidebar` owning the channel). Ship independently of #2194. Single biggest risk: Supabase Realtime `postgres_changes` does NOT enforce RLS on broadcast payloads — only on initial REST snapshots. Without explicit `filter: user_id=eq.<uid>`, every tenant receives every other tenant's row changes; **no current AGENTS.md rule, hook, or reviewer catches this**. Mandate the per-user filter, a cross-tenant test, and propose a new `cq-` rule. The existing `useConversations` hook (verified post-assessment) already follows this pattern with a defensive client-side `user_id` check; the new layout should reuse it rather than fork.

## Capability Gaps

| Gap | Domain | Why needed |
|---|---|---|
| No reviewer or skill audits Supabase Realtime `postgres_changes` channel filters for per-user scoping | Engineering | The USER_BRAND_CRITICAL failure mode for this feature; must be caught by tooling, not memory. Track as new AGENTS.md `cq-` rule + drafted issue. |
| No reviewer validates that long-lived Realtime/WebSocket subscriptions live in the correct segment-layout (not in `page.tsx` where they remount on every nav) | Engineering | Re-subscribe storms inflate cost and create channel-leak windows. |
| `spec-flow-analyzer` does not flag user-facing data-list features lacking a cross-tenant Playwright scenario | Product | Direct improvement to the existing acceptance-criteria gate. |

## Deferrals (file as separate issues at Phase 3.6)

1. **Snippet rendering with server-side redaction** — title + status + time + unread is sufficient for v1. Snippets require regex strip of BYOK keys, emails, card-shaped digits before the row leaves Postgres. Re-evaluate when usage shows users are squinting at titles to disambiguate threads.
2. **Cursor pagination + virtualization for the rail** — defer until usage shows >15 active threads is common.
3. **Pinning conversations in the rail** — defer to a UX pass.
4. **In-rail search** — defer; "View all in Command Center" link is the v1 escape hatch.
5. **New AGENTS.md `cq-` rule: per-user Realtime filter mandate** — draft + land alongside this feature's first use of the pattern.

## Next Steps

1. Phase 3.6 will create:
   - Tracking issue for this feature (Phase 3 milestone if applicable, else `Post-MVP / Later`)
   - Deferred-item issues from the list above
   - Spec at `knowledge-base/project/specs/feat-command-center-conversation-nav/spec.md`
2. `skill: soleur:plan` to generate `tasks.md` with TDD acceptance criteria including the cross-tenant Playwright scenario.
