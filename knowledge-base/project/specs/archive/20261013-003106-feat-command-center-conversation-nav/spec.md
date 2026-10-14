# Feature: Command Center Conversation Nav

**Issue:** #3024
**Brainstorm:** [`2026-04-29-command-center-conversation-nav-brainstorm.md`](../../brainstorms/2026-04-29-command-center-conversation-nav-brainstorm.md)
**Branch:** `feat-command-center-conversation-nav`
**Worktree:** `.worktrees/feat-command-center-conversation-nav`
**Draft PR:** #3021
**Brand-survival threshold:** `single-user incident` (USER_BRAND_CRITICAL)
**Deferred follow-ons:** #3025 (snippets+redaction), #3026 (pagination+virtualization), #3027 (pinning), #3028 (AGENTS.md realtime rule)

## Problem Statement

When a user is inside a conversation at `/dashboard/chat/[conversationId]`, there is no way to switch to another of their conversations without first navigating back to the Command Center inbox at `/dashboard`. This round-trip breaks flow when multitasking across active threads (typical Soleur ICP usage: a solo founder with 3-8 active conversations across CTO, CMO, CPO, etc.).

## Goals

- Render a recent-conversations rail inside the chat segment so users can switch threads in one click.
- Preserve the Command Center as the curated triage surface (with status/domain filters) — the rail is for *switching*, not re-triaging.
- Keep cross-tenant blast-radius minimal: reuse the existing `useConversations` per-user Realtime filter pattern; do not introduce a new subscription path.
- Persist sidebar collapse state per user using the existing `useSidebarCollapse` hook + `Cmd/Ctrl+B` shortcut.

## Non-Goals

- Last-message snippets in the rail (deferred — requires server-side redaction; tracked as a follow-on issue).
- Status / Domain filter dropdowns inside the rail (those belong in Command Center).
- In-rail search.
- Cursor pagination + virtualization (cap at 15 most-recent + a "View all in Command Center" link).
- Conversation pinning (deferred to UX pass).
- Touching `app/(dashboard)/layout.tsx` — this feature ships in parallel with #2194 (DashboardLayout decomposition) and must not couple to it.
- New global keyboard shortcut beyond the already-decided `Cmd/Ctrl+B`.

## Functional Requirements

### FR1: Chat-segment rail visible only inside `/dashboard/chat/*`

A new `apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx` renders a sidebar rail to the side of `{children}`. The rail is invisible on `/dashboard`, `/dashboard/kb`, `/dashboard/settings`, and the rest of `/dashboard/*`.

### FR2: Rail rows render title + status badge + relative time + unread count

Each row links to `/dashboard/chat/[conversationId]`. The currently-open conversation is visually marked. Status badges use the founder-language mapping decided in the 2026-04-07 conversation-inbox brainstorm (`Needs your decision`, `In progress`, `Done`, `Needs attention`).

### FR3: Top 15 most-recent + "View all in Command Center" link

The rail shows the user's 15 most-recent (by `last_active` desc, non-archived) conversations of the currently-active repo scope. A footer link routes back to `/dashboard` (the Command Center).

### FR4: Empty state

If the user has zero other conversations, the rail renders a single "+ New conversation" CTA (or hides entirely — to be locked in implementation; both are acceptable for v1).

### FR5: Collapse + keyboard shortcut

The rail uses `useSidebarCollapse("soleur:sidebar.chat-rail.collapsed")` (new key, existing hook). `Cmd/Ctrl+B` toggles. Collapsed state is per-user (localStorage).

### FR6: Mobile

Reuse the existing dashboard mobile drawer pattern. The rail becomes a section inside the drawer on small viewports.

### FR7: Real-time updates

When the user's conversation list changes (new conversation, status update, archive), the rail updates without a refresh, via the existing `useConversations` hook's Realtime subscription.

## Technical Requirements

### TR1: Reuse `useConversations` with a `limit: 15` variant

Do NOT introduce a new Realtime subscription path. Either add a `limit` option to `apps/web-platform/hooks/use-conversations.ts` or extract a shared subscription primitive both call sites use. The single-source contract must be preserved: Realtime channel filter `user_id=eq.${userId}` + the existing client-side defensive `user_id !== uid` drop check.

**Repo-scope inheritance.** `useConversations` filters server-side by both `user_id` AND `repo_url` (the user's currently-connected repo). The rail inherits this scoping for free: disconnected users (`repo_url IS NULL`) see an empty list by design — that's the empty-state contract for FR4, not a bug. Any future variant MUST preserve the `repo_url` filter, including its disconnect-empty behaviour.

### TR2: Subscription owned by the chat-segment layout

The Realtime channel MUST live in the chat-segment layout (or a client component it mounts), not in `[conversationId]/page.tsx`. App Router does not remount segment layouts on intra-segment navigation, so this guarantees a single subscription per session-in-chat instead of one per conversation switch.

### TR3: Per-user cache scoping

Any client cache (SWR, React Query, in-memory map) used by the rail MUST include `auth.uid()` in its key. Cross-tenant cache reuse is the highest-likelihood leak vector per CLO assessment.

### TR4: Logout teardown

`onAuthStateChange("SIGNED_OUT")` (or the existing equivalent in the auth provider) MUST tear down the Realtime channel and clear caches before any redirect. This closes the GDPR Art. 5(1)(f) flash-of-other-user-data window on shared devices.

### TR5: Cross-tenant Playwright RLS test (HARD ACCEPTANCE CRITERION)

A Playwright e2e test that:

1. Seeds two users (A and B) each with ≥3 conversations.
2. Signs in as A, opens `/dashboard/chat/<A's conversation>`.
3. Asserts only A's conversations appear in the rail.
4. Asserts no Realtime payload received by A includes any of B's `conversation_id`s (intercept at network or hook level).
5. Signs out, signs in as B, asserts no flash of A's conversations.

This test MUST pass before merge.

### TR6: Server-side title length cap

Conversation titles derived from the first message can be arbitrarily long. The query (or the hook) MUST cap the title server-side (~80 chars) to prevent layout breakage and to bound the data sent over Realtime.

### TR7: Bundle isolation

The rail's client component must be lazy-loaded so `/dashboard` and `/dashboard/kb` bundles are not affected. Acceptable patterns: server-component layout shell + `next/dynamic` client child; or co-locate inside the `/chat` segment so route-based code splitting handles it.

### TR8: Privacy-policy re-affirmation

During `/work`, re-read `docs/legal/privacy-policy.md` (the canonical Eleventy-rendered policy; mirrored at `plugins/soleur/docs/pages/legal/privacy-policy.md`). The Next.js path `apps/web-platform/app/privacy/page.tsx` does NOT exist — the privacy policy is rendered by Eleventy on the docs site, not by the Next.js app. If existing language scopes "conversation history display" to a specific surface, broaden to the authenticated app generally. Likely a no-op; verify rather than skip.

## Required Review Gates Before Merge

- `user-impact-reviewer` (mandatory by USER_BRAND_CRITICAL)
- `security-sentinel` with explicit focus on: Realtime channel filter, client-cache key scoping, logout teardown
- Cross-tenant Playwright test passing (TR5)

## Dependencies

- Existing: `useConversations` hook, `useSidebarCollapse` hook, mobile drawer pattern, conversation status enum + RLS, `relative-time.ts`, `leader-colors.ts`.
- Migration: none (REPLICA IDENTITY FULL already in `015_conversations_replica_identity.sql`).
- Schema: none.
- New AGENTS.md `cq-` rule (tracked as a separate issue, may land alongside this PR or in a follow-on).

## Out-of-Scope (Tracked as Separate Issues)

- Snippet rendering with server-side redaction.
- Cursor pagination + virtualization.
- Conversation pinning.
- In-rail search.
- New AGENTS.md rule mandating per-user `filter:` on `postgres_changes` channels.
