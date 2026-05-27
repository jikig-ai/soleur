---
date: 2026-05-27
category: security-issues
module: supabase, web-platform/hooks
severity: high
tags: [rls, workspace, client-filter, defense-in-depth, brainstorm-discovery]
related_issues: [4521, 4516]
---

# Learning: Client-Side Filters Lag DB-Layer RLS After Workspace Sweep

## Problem

Migration 059 (workspace-keyed RLS sweep) widened DB-layer permissions on conversations, messages, and 7 other tables from `auth.uid() = user_id` to `is_workspace_member(workspace_id, auth.uid())`. This correctly allows any workspace member to access all workspace data at the Postgres level.

However, 20+ client-side call sites in the web platform still filter by `user_id`:
- `use-conversations.ts:146` → `.eq("user_id", currentUserId)`
- `use-conversations.ts:239` (Realtime) → `filter: user_id=eq.${userId}`
- `agent-runner.ts:633`, `api-messages.ts:106`, `conversation-writer.ts` — various `user_id` filters

The result is a **client-server permission mismatch**: the DB allows workspace-member access, but the client only fetches the current user's rows. This creates two problems:

1. **Invisible feature**: Shared conversation visibility (a key #4521 deliverable) silently works at the DB layer but never surfaces in the UI because client code filters it out.
2. **False sense of privacy**: Users may assume conversations are private (client only shows their own), but a direct Supabase query or a client-side filter removal would expose all workspace conversations. The defense-in-depth convention (learning: `2026-04-11-deferred-ws-conversation-creation-and-pending-state.md`) recommends keeping `.eq("user_id", ...)` filters even when RLS is active, but this becomes contradictory when the intended behavior IS cross-member visibility.

## Solution

When implementing workspace-scoped features, the client-side filter audit must happen IN THE SAME PR as the RLS change. The sentinel sweep per `hr-write-boundary-sentinel-sweep-all-write-sites` should enumerate both:
1. Server/migration RLS predicates (the DB layer)
2. Client-side `.eq("user_id", ...)` / `.filter(...)` calls on the same tables (the application layer)

For #4521 PR-A specifically: add a `visibility` column to conversations, update the RLS predicate to `(user_id = auth.uid()) OR (visibility = 'workspace' AND is_workspace_member(...))`, and sweep all 20+ client call sites to use `workspace_id` instead of `user_id` where workspace-scoped results are intended.

## Key Insight

A DB-layer RLS sweep without a corresponding client-layer filter sweep creates a permission mismatch where the database is more permissive than the UI shows. The defense-in-depth convention (always include `.eq("user_id", ...)`) and the workspace-visibility intent (show other members' data) are in tension. The resolution is: defense-in-depth filters should match the intended RLS predicate, not the pre-sweep predicate. When RLS says "workspace member can see all," the client filter should be `.eq("workspace_id", wsId)`, not `.eq("user_id", userId)`.

## Session Errors

1. **Telemetry emit failed in bare repo** — `source .claude/hooks/lib/incidents.sh && emit_incident ...` returned `fatal: this operation must be run in a work tree` because it ran before the worktree was created. **Prevention:** Defer telemetry emits to after worktree creation in brainstorm Phase 0.1, or use `git -C <worktree-path>` for the rev-parse.
