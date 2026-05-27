---
name: feat-shared-kb-team-collab
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstormed
issue: 4521
pr: 4524
---

# Spec: Shared Knowledge Base + Team Activity Feed (Phase 4)

## Problem Statement

Team workspace members have no visibility into each other's work. Conversations are technically accessible via RLS (mig 059) but client code filters by `user_id`, KB files have no database metadata layer for attribution or visibility controls, and no activity feed infrastructure exists. Flipping `TEAM_WORKSPACE_INVITE_ENABLED` ON with the current state would expose all pre-invite conversations to new members — a brand-survival risk.

## Goals

1. Per-conversation visibility controls (default private, opt-in workspace sharing) before invite flag flip
2. KB file metadata table with uploader attribution and workspace-scoped visibility
3. Team activity feed showing membership, conversation, KB, and agent-run events
4. Legal scaffolding in lockstep with each code PR

## Non-Goals

- Cross-workspace KB access (different workspaces sharing files)
- Per-message activity events (high volume, disk I/O risk)
- KB embeddings/retrieval (separate ADR)
- Supabase Realtime for activity feed (polling suffices)
- True multi-participant conversations (vs. visibility toggle)
- Changes to solo-founder positioning, pricing page, or homepage

## Functional Requirements

| ID | Requirement | PR |
|----|------------|-----|
| FR1 | `visibility` column on `conversations` table, default `'private'`, opt-in `'workspace'` | PR-A |
| FR2 | RLS predicate: `(user_id = auth.uid()) OR (visibility = 'workspace' AND is_workspace_member(workspace_id, auth.uid()))` | PR-A |
| FR3 | Backfill all existing conversations to `'private'` | PR-A |
| FR4 | Share/unshare toggle in conversation UI | PR-A |
| FR5 | Sweep 20+ `.from("conversations")` client call sites for workspace semantics | PR-A |
| FR6 | Fix `ws-handler.ts:806` conversation INSERT to include `workspace_id` | PR-A |
| FR7 | `workspace_activity` table (INSERT-only, workspace_id, actor_user_id, event_type, metadata JSONB, created_at) | PR-B |
| FR8 | SECURITY DEFINER RPC writers for activity events (no client INSERT) | PR-B |
| FR9 | Event types: member_join, member_leave, conversation_created, conversation_shared, kb_file_uploaded, kb_file_deleted, agent_run_started, agent_run_completed | PR-B |
| FR10 | Activity feed UI component in workspace dashboard with polling (30s interval) | PR-B |
| FR11 | pg_cron 90-day retention purge for `workspace_activity` | PR-B |
| FR12 | `kb_files` table (id, workspace_id, user_id, file_path, filename, visibility, content_sha256, size_bytes, uploaded_at, updated_at) | PR-C |
| FR13 | Workspace-keyed RLS on `kb_files` via `is_workspace_member()` | PR-C |
| FR14 | RESTRICTIVE policy on `workspace_id`/`visibility` columns (service-role write only) | PR-C |
| FR15 | Server-side sync: populate `kb_files` from filesystem during KB sync operations | PR-C |
| FR16 | Uploader attribution in KB viewer UI | PR-C |

## Technical Requirements

| ID | Requirement | Source |
|----|------------|--------|
| TR1 | All new RLS policies use `is_workspace_member()` predicate | CTO (established pattern, 17+ call sites) |
| TR2 | RESTRICTIVE policies on authorization-sensitive columns (workspace_id, visibility) | Learning: rls-column-takeover-github-username-20260407 |
| TR3 | `SECURITY DEFINER` RPCs pin `search_path = public, pg_temp` | `cq-pg-security-definer-search-path-pin-pg-temp` |
| TR4 | `REVOKE ALL FROM PUBLIC, anon, authenticated, service_role` on new functions | Learning: supabase-default-privileges-defeat-revoke |
| TR5 | RLS deny tests use schema-correct payloads + dual-shape accept pattern | Learning: rls-deny-tests-payload-must-type-validate |
| TR6 | WORM tables use SET NULL (not RESTRICT) for user-facing FKs | Learning: art17-cascade-deadlock-and-worm-trigger-carveout |
| TR7 | Activity feed NOT in `supabase_realtime` publication | CTO (mig 039 precedent) |
| TR8 | `/soleur:gdpr-gate` at plan Phase 2.7 and work Phase 2 exit | CLO (`hr-gdpr-gate-on-regulated-data-surfaces`) |
| TR9 | Legal doc amendments ship in lockstep per PR #4289 precedent | CLO |
| TR10 | Write-boundary sentinel sweep per `hr-write-boundary-sentinel-sweep-all-write-sites` | CTO |
| TR11 | Integration tests against real Supabase dev instance (not mocked) | Learning: mocked-tests-miss-shared-table-schema-gaps |
