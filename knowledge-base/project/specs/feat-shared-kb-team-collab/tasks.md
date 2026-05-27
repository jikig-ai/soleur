---
name: feat-shared-kb-team-collab
generated_from: knowledge-base/project/plans/2026-05-27-feat-shared-kb-team-collab-plan.md
---

# Tasks: Shared KB + Team Activity Feed (#4521)

## PR-A: Conversation Visibility Controls

### Phase 0: Preconditions
- [ ] 0.1 Verify workspace_id INSERT gap at ws-handler.ts:806 — confirm no DB trigger/DEFAULT fills it
- [ ] 0.2 Enumerate all 25 `.from("conversations")` call sites
- [ ] 0.3 Read current RLS policy shape from mig 059
- [ ] 0.4 Read use-conversations.ts Realtime subscription filter

### Phase 1: Migration 075
- [ ] 1.1 Fix latent bug: add workspace_id to conversation INSERT at ws-handler.ts:806
- [ ] 1.2 Add `visibility` column with CHECK constraint and DEFAULT 'private'
- [ ] 1.3 Backfill existing rows + SET NOT NULL
- [ ] 1.4 Add RESTRICTIVE policy on visibility column (prevent client writes)
- [ ] 1.5 Drop old workspace-wide policy, create dual-predicate RLS policy
- [ ] 1.6 Create `set_conversation_visibility` SECURITY DEFINER RPC (owner-only)
- [ ] 1.7 Write down migration (075_conversation_visibility.down.sql)

### Phase 2: Server-side call-site sweep (25 sites)
- [x] 2.1 ws-handler.ts — fix INSERT (workspace_id) + audit 5 remaining sites
- [x] 2.2 conversations-tools.ts — widen 4 MCP tool sites for shared visibility
- [x] 2.3 agent-runner.ts — audit 3 sites for workspace-scoped access
- [x] 2.4 api-messages.ts — widen for shared conversation message access
- [x] 2.5 lookup-conversation-for-path.ts — widen for shared context paths
- [x] 2.6 Remaining sites (dsar-export, account-delete, api-usage, conversation-writer, dsar-export-co-uploader) — verify owner-scoped semantics are correct

### Phase 3: Client-side UI
- [x] 3.1 Create visibility-toggle.tsx component (Private | Workspace segmented control)
- [x] 3.2 Add toggle to conversation-header.tsx
- [ ] 3.3 Update use-conversations.ts: widen Realtime filter from user_id to workspace_id
- [ ] 3.4 Add WORKSPACE badge + creator avatar to conversation list items

### Phase 4: Tests
- [x] 4.1 RLS deny test: workspace member cannot see private conversations of others
- [x] 4.2 RLS allow test: workspace member can see shared conversations
- [x] 4.3 Cross-workspace deny test
- [x] 4.4 RESTRICTIVE policy test: client UPDATE on visibility rejected
- [x] 4.5 RPC test: owner can toggle, non-owner gets exception
- [x] 4.6 Workspace_id INSERT regression test

### Phase 5: Verify + commit PR-A
- [x] 5.1 `tsc --noEmit` passes
- [x] 5.2 vitest run passes
- [ ] 5.3 Commit and push PR-A changes

## PR-B: Team Activity Feed

### Phase 1: Migration 076
- [ ] 1.1 Create `workspace_activity` table (INSERT-only, 8 event types)
- [ ] 1.2 RLS: workspace-member SELECT only
- [ ] 1.3 SECURITY DEFINER writer RPC: `record_workspace_activity`
- [ ] 1.4 Indexes: (workspace_id, created_at DESC) + (actor_user_id)
- [ ] 1.5 pg_cron: 90-day retention purge
- [ ] 1.6 `anonymise_workspace_activity` RPC for Art-17 cascade
- [ ] 1.7 Down migration

### Phase 2: Server-side event emitters
- [ ] 2.1 workspace-membership.ts — member_join, member_leave events
- [ ] 2.2 ws-handler.ts — conversation_created event
- [ ] 2.3 set_conversation_visibility — conversation_shared event (from PR-A RPC)
- [ ] 2.4 kb-reader.ts / kb-sync — kb_file_uploaded, kb_file_deleted events
- [ ] 2.5 agent-runner.ts — agent_run_started, agent_run_completed events

### Phase 3: Client-side UI
- [ ] 3.1 Create use-workspace-activity.ts hook (30s polling, paginated)
- [ ] 3.2 Create activity-feed.tsx component (timeline with actor avatars)
- [ ] 3.3 Add Team Activity tab to settings page

### Phase 4: DSAR + legal
- [ ] 4.1 Add workspace_activity to DSAR_TABLE_ALLOWLIST
- [ ] 4.2 Add anonymise step to account-delete.ts cascade
- [ ] 4.3 Legal doc amendments (Privacy Policy, DPD, GDPR Policy, Art. 30)

### Phase 5: Tests + commit
- [ ] 5.1 RLS tenant-isolation tests
- [ ] 5.2 Writer RPC tests
- [ ] 5.3 pg_cron retention test
- [ ] 5.4 DSAR coverage test
- [ ] 5.5 `tsc --noEmit` + vitest
- [ ] 5.6 Commit and push PR-B changes

## PR-C: KB Files Metadata Table

### Phase 1: Migration 077
- [ ] 1.1 Create `kb_files` table with workspace_id, user_id, visibility
- [ ] 1.2 RLS: owner + workspace-member dual-predicate SELECT
- [ ] 1.3 RESTRICTIVE policy on workspace_id/visibility
- [ ] 1.4 SECURITY DEFINER RPC: `set_kb_file_visibility`
- [ ] 1.5 Indexes
- [ ] 1.6 Down migration

### Phase 2: Server-side sync
- [ ] 2.1 kb-reader.ts — on tree read, upsert kb_files rows from filesystem
- [ ] 2.2 kb-document-resolver.ts — resolve via kb_files for workspace-scoped queries

### Phase 3: Client-side UI
- [ ] 3.1 Add uploader avatar/initials badge to KB file tree
- [ ] 3.2 Add attribution + visibility toggle to KB document viewer header

### Phase 4: DSAR + legal
- [ ] 4.1 Add kb_files to DSAR_TABLE_ALLOWLIST
- [ ] 4.2 Add anonymise step to account-delete.ts cascade
- [ ] 4.3 Art-15(4) redaction for cross-member KB content
- [ ] 4.4 Legal: PA-2 recipients amendment

### Phase 5: Tests + commit
- [ ] 5.1 RLS tenant-isolation tests
- [ ] 5.2 Sync tests (filesystem → kb_files)
- [ ] 5.3 DSAR coverage test
- [ ] 5.4 `tsc --noEmit` + vitest
- [ ] 5.5 Commit and push PR-C changes
