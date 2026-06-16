# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-active-conversation-missing-from-nav/knowledge-base/project/plans/2026-06-15-fix-active-conversation-missing-from-rail-plan.md
- Status: complete

### Errors
None. (Initial pwd matched on first attempt. Push emitted an informational Dependabot vulnerability notice, unrelated to this change.)

### Decisions
- Root cause (primary): the rail's `use-conversations.ts` fetches only on mount and subscribes only to Realtime UPDATE events — no INSERT handler. Per ADR-047 the rail portals outside the Next.js swap region so it stays mounted and never refetches after a conversation is created → an actively-streaming conversation never appears. Remaining gap from same-symptom fix #5317 (merged today), which only addressed repo_url source divergence. Fix: scoped Realtime INSERT subscription + bounded SUBSCRIBED-status backfill refetch.
- Architecture P0 (corrected): Phase 3 originally proposed aligning `createConversation` workspace resolution to the route's solo fallback; strategist proved this reintroduces the #5256 cross-tenant durable-write hazard (fail-loud is intentional). Phase 3 is now verify-and-document only.
- Architecture P1 (corrected): "refetch when active conversationId unknown to list" trigger has a tight-loop hazard; replaced with bounded SUBSCRIBED backfill.
- Architecture P2 + scope narrowing: added shared `shouldDropForScope` (repo_url + visibility + archive) and `deriveRailTitle` (incl. `system → "Project Analysis"`) helpers, fill-only upsert. Plan narrowed to hook-only — `conversations-rail.tsx` not edited; Product/UX Gate resolves to NONE; wg-ui-feature-requires-pen-wireframe does not fire.
- Citation fix: RLS is `conversations_owner_select` + `conversations_shared_select` (migration 075). Brand-survival threshold `single-user incident` → `requires_cpo_signoff: true`.

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan
- Agents: repo-research-analyst, learnings-researcher, architecture-strategist, 3× Explore, general-purpose (verify-the-negative)
