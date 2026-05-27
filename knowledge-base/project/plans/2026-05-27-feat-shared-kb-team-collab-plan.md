---
title: "feat: shared KB + team activity feed (Phase 4)"
type: enhancement
issue: 4521
pr: 4524
branch: feat-shared-kb-team-collab
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Plan: Shared KB + Team Activity Feed (#4521)

## Overview

Three independent PRs behind `TEAM_WORKSPACE_INVITE_ENABLED` flag (currently OFF):

- **PR-A** (mig 075): Conversation visibility controls — add `visibility` column, update RLS, sweep 25 client call sites, fix workspace_id INSERT gap
- **PR-B** (mig 076): Team activity feed — new `workspace_activity` table, SECURITY DEFINER writer RPCs, polling-based UI, pg_cron retention
- **PR-C** (mig 077): KB files metadata — new `kb_files` table, workspace-keyed RLS, server-side filesystem sync, uploader attribution UI

Sequencing: A → B → C (conversations most ready, KB metadata largest scope).

## User-Brand Impact

**If this lands broken, the user experiences:** Private conversation content (BYOK cost data, personal brainstorms, agent outputs) visible to newly-invited workspace members who should not see pre-invite conversations.

**If this leaks, the user's data is exposed via:** RLS predicate misconfiguration on `conversations`, `workspace_activity`, or `kb_files` — cross-tenant read where User A from workspace X sees data from workspace Y, or unauthorized workspace member sees private conversations.

**Brand-survival threshold: single-user incident** — one mis-written RLS predicate leaking a founder's private conversation to an invited workspace member.

CPO sign-off: carry-forward from brainstorm Phase 0.5 (CPO, CLO, CTO triad assessed). `user-impact-reviewer` will run at review time.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| FR6: `ws-handler.ts:806` omits workspace_id | **Confirmed.** INSERT payload has no `workspace_id` despite NOT NULL column (mig 059:62). No DEFAULT, no BEFORE INSERT trigger. Latent bug — works only because N2 invariant (`workspace_id === user_id`) somehow masks it. | PR-A Phase 1 task 1.1: fix INSERT to include `getUserWorkspace(userId)`. Must verify if DB trigger/default exists first. |
| FR5: 20+ call sites | **25 call sites** across 10 files: `ws-handler.ts` (6), `conversations-tools.ts` (4), `dsar-export.ts` (2), `agent-runner.ts` (3), `conversation-writer.ts` (1), `api-messages.ts` (1), `api-usage.ts` (1), `lookup-conversation-for-path.ts` (1), `dsar-export-co-uploader.ts` (1), `account-delete.ts` (1) | FR5 updated: 25 sites, all server-side. Client-side uses hooks. |
| spec.md TR7: activity feed NOT in Realtime publication | **Consistent.** `messages` removed from Realtime in mig 039. Only `conversations` and `action_sends` in `supabase_realtime` publication (mig 034/070). | Plan confirms: `workspace_activity` NOT added to publication. |
| Brainstorm: kb_files doesn't exist | **Confirmed.** Mig 073 audit: "The table public.kb_files does NOT exist. Zero migrations create it." | PR-C creates it fresh. No migration conflict. |
| Latest migration | **074** (`byok_delegation_acceptances`) | PR-A = 075, PR-B = 076, PR-C = 077 |
| DSAR allowlist location | `server/dsar-export-allowlist.ts:59` | PR-B and PR-C add entries here |
| pg_cron pattern | Established in mig 029/036/038 (`user_concurrency_slots_sweep`) | PR-B follows same pattern for 90-day retention purge |

## Implementation Phases

### PR-A: Conversation Visibility Controls (mig 075)

#### Phase 0: Preconditions

- [ ] Verify `workspace_id` INSERT gap: `grep -n "workspace_id" apps/web-platform/server/ws-handler.ts` — confirm no DB trigger or DEFAULT auto-fills it
- [ ] Enumerate all 25 `.from("conversations")` sites: `grep -rn '\.from("conversations")' apps/web-platform/server/`
- [ ] Read current RLS policy shape: `grep -A3 "conversations_workspace_member_all" apps/web-platform/supabase/migrations/059_workspace_keyed_rls_sweep.sql`
- [ ] Read `use-conversations.ts` Realtime subscription filter

#### Phase 1: Migration 075 — conversation visibility + RLS update

**File:** `apps/web-platform/supabase/migrations/075_conversation_visibility.sql`

1.1. Fix latent bug: add `workspace_id` to conversation INSERT helper or add a BEFORE INSERT trigger that resolves workspace_id from `auth.uid()` → `workspace_members` lookup. Decide: application-layer fix (pass workspace_id in INSERT) vs DB-layer fix (trigger).

1.2. Add `visibility` column:
```sql
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS visibility text
  CHECK (visibility IN ('private', 'workspace'))
  DEFAULT 'private';
```

1.3. Backfill existing rows (all to 'private' — safe default, no-op since DEFAULT handles it):
```sql
UPDATE public.conversations SET visibility = 'private' WHERE visibility IS NULL;
ALTER TABLE public.conversations ALTER COLUMN visibility SET NOT NULL;
```

1.4. Protect `visibility` column via column-level REVOKE (per Kieran C3 — self-referential RESTRICTIVE `WITH CHECK` compares NEW vs NEW, always passes):
```sql
-- Column-level REVOKE prevents direct client UPDATE of visibility.
-- Only the SECURITY DEFINER RPC (which runs as function owner) can write it.
REVOKE UPDATE(visibility) ON public.conversations FROM authenticated;
```
This is simpler and more correct than a RESTRICTIVE policy. Same pattern as mig 017 `kb_sync_history`.

1.5. Drop old workspace-wide policy and create new dual-predicate policy:
```sql
DROP POLICY IF EXISTS conversations_workspace_member_all ON public.conversations;

CREATE POLICY conversations_owner_or_shared ON public.conversations
  FOR ALL TO authenticated
  USING (
    user_id = auth.uid()
    OR (visibility = 'workspace' AND public.is_workspace_member(workspace_id, auth.uid()))
  )
  WITH CHECK (
    user_id = auth.uid()
    OR (visibility = 'workspace' AND public.is_workspace_member(workspace_id, auth.uid()))
  );
```

1.6. Create `set_conversation_visibility` SECURITY DEFINER RPC (owner-only):
```sql
CREATE OR REPLACE FUNCTION public.set_conversation_visibility(
  p_conversation_id uuid,
  p_visibility text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_visibility NOT IN ('private', 'workspace') THEN
    RAISE EXCEPTION 'Invalid visibility: %', p_visibility;
  END IF;
  UPDATE public.conversations
     SET visibility = p_visibility
   WHERE id = p_conversation_id
     AND user_id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conversation not found or not owned by caller';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.set_conversation_visibility FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_conversation_visibility TO authenticated;
```

1.7. Down migration: `075_conversation_visibility.down.sql`

#### Phase 2: Server-side call-site sweep (25 sites)

Per `hr-write-boundary-sentinel-sweep-all-write-sites`, audit each `.from("conversations")` site:

| File | Line | Current filter | Action |
|---|---|---|---|
| `ws-handler.ts` | 806 | `.insert({...})` no workspace_id | **FIX**: add `workspace_id: getUserWorkspace(userId)` |
| `ws-handler.ts` | 826 | `.eq("user_id", userId)` | Keep — context-path lookup is owner-scoped |
| `ws-handler.ts` | 384 | `.eq("user_id", userId)` | Keep — status update is owner-scoped |
| `ws-handler.ts` | 1390 | Read context — verify | Audit: add `.eq("workspace_id", wsId)` if workspace-scoped |
| `ws-handler.ts` | 1574 | Read context — verify | Audit |
| `ws-handler.ts` | 1855 | Read context — verify | Audit |
| `conversations-tools.ts` | 161,227,269,317 | MCP tools — `.eq("user_id", userId)` | Widen to workspace-scoped for shared conversations visibility |
| `agent-runner.ts` | 633,658,2373 | Various | Audit: agent runs against shared conversations |
| `conversation-writer.ts` | 185 | Single UPDATE site | Keep — owner-only per PR-C §2.4 pattern |
| `api-messages.ts` | 106 | `.eq("user_id", userId)` | Widen for shared conversation message access |
| `api-usage.ts` | 141 | Cost aggregation | Keep user-scoped (BYOK cost is per-user) |
| `dsar-export.ts` | 502,508 | DSAR — `.eq("user_id", userId)` | Keep — DSAR exports are per-user per Art. 15 |
| `dsar-export-co-uploader.ts` | 43 | Co-uploader — verify | Audit: may need workspace-scoped access |
| `account-delete.ts` | 528 | Cascade delete | Keep — deletion cascade is per-user |
| `lookup-conversation-for-path.ts` | 86 | Context path lookup | Widen for shared context paths |

#### Phase 3: Client-side UI — share/unshare toggle

**Files:**
- New: `apps/web-platform/src/components/conversation/visibility-toggle.tsx`
- Edit: `apps/web-platform/src/components/conversation/conversation-header.tsx` — add toggle
- Edit: `apps/web-platform/src/hooks/use-conversations.ts` — widen Realtime filter from `user_id` to `workspace_id`, add client-side visibility filter

Toggle component: segmented `Private | Workspace` control (per design mockup `12-conversation-share-toggle-inbox.png`). Calls `set_conversation_visibility` RPC on toggle.

Conversation list: add `WORKSPACE` badge for shared conversations, show creator avatar+name.

#### Phase 4: Tests — RLS deny + integration

- Tenant-isolation test: User B in same workspace can SELECT shared conversation, cannot SELECT private conversation
- Cross-workspace test: User C in different workspace cannot SELECT any conversation
- RLS deny tests use schema-correct payloads + dual-shape accept pattern (TR5)
- Positive control: owner can always see own conversations regardless of visibility
- Conversation INSERT includes workspace_id (regression test for the latent bug fix)
- Integration tests against real Supabase dev instance (TR11)

### PR-B: Team Activity Feed (mig 076)

#### Phase 1: Migration 076 — workspace_activity table + writer RPCs

**File:** `apps/web-platform/supabase/migrations/076_workspace_activity.sql`

1.1. Create table:
```sql
CREATE TABLE public.workspace_activity (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  event_type text NOT NULL,
  metadata jsonb DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.workspace_activity ENABLE ROW LEVEL SECURITY;
```

Notes per plan review:
- `actor_user_id` is NULLABLE + `ON DELETE SET NULL` (not `ON SET NULL` which is invalid SQL; not `NOT NULL` which contradicts SET NULL — per Kieran C1).
- `event_type` is plain `text NOT NULL` (no CHECK constraint) — allows adding event types without migration. Validation in the SECURITY DEFINER RPC body (per Simplicity S3a).
- MVP ships with 3 event types: `member_join`, `member_leave`, `conversation_shared`. `conversation_created`, `kb_file_*`, `agent_run_*` deferred to when their emitters ship (per Simplicity S3a — reduces cross-PR coupling).
- This is a SEPARATE table from `workspace_member_actions` (mig 063) because that table uses WORM constraints + RESTRICT FKs + trigger-driven writes incompatible with: (a) 90-day pg_cron purge, (b) SET NULL for Art-17, (c) application-driven writes. Two tables justified (per DHH R1).

1.2. RLS policies (workspace-member SELECT only, no client INSERT) + JTI deny:
```sql
CREATE POLICY workspace_activity_member_select ON public.workspace_activity
  FOR SELECT TO authenticated
  USING (public.is_workspace_member(workspace_id, auth.uid()));

-- JTI deny RESTRICTIVE policy (per mig 068 pattern — Kieran H1)
CREATE POLICY workspace_activity_jti_not_denied ON public.workspace_activity
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT public.is_jti_denied_from_jwt())
  WITH CHECK (NOT public.is_jti_denied_from_jwt());
```

1.3. SECURITY DEFINER writer RPC:
```sql
CREATE OR REPLACE FUNCTION public.record_workspace_activity(
  p_workspace_id uuid, p_actor_user_id uuid, p_event_type text, p_metadata jsonb DEFAULT '{}'
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  INSERT INTO public.workspace_activity (workspace_id, actor_user_id, event_type, metadata)
  VALUES (p_workspace_id, p_actor_user_id, p_event_type, p_metadata);
END;
$$;

REVOKE ALL ON FUNCTION public.record_workspace_activity FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_workspace_activity TO service_role;
```

1.4. Indexes:
```sql
CREATE INDEX workspace_activity_feed_idx ON public.workspace_activity (workspace_id, created_at DESC);
CREATE INDEX workspace_activity_actor_idx ON public.workspace_activity (actor_user_id);
```

1.5. pg_cron 90-day retention purge (idempotent per Kieran H3):
```sql
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'workspace_activity_purge') THEN
    PERFORM cron.unschedule('workspace_activity_purge');
  END IF;
  PERFORM cron.schedule(
    'workspace_activity_purge',
    '0 3 * * *',
    $$DELETE FROM public.workspace_activity WHERE created_at < now() - interval '90 days'$$
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
```

1.6. DSAR + Art-17 support: Add `anonymise_workspace_activity` RPC following the `anonymise_workspace_member_actions` pattern (mig 063).

#### Phase 2: Server-side event emitters (MVP: 3 event types)

Per Simplicity S3a, PR-B ships only events whose emitters exist in PR-B's scope:
- `workspace-membership.ts` — `member_join`, `member_leave` (after successful add/remove)
- `set_conversation_visibility` RPC (from PR-A) — `conversation_shared` (when visibility changes to 'workspace')

All emitters call the RPC via service-role client (not authenticated — per Kieran C2 fix, the RPC is service_role-only). Server-side code already has access to the service-role client.

Deferred event types (added when their emitters ship): `conversation_created` (PR-A follow-up — skip for private conversations per Kieran M4), `kb_file_uploaded`/`kb_file_deleted` (PR-C), `agent_run_started`/`agent_run_completed` (follow-up — avoids wiring into the 2373-line agent-runner.ts for activity feed MVP).

#### Phase 3: Client-side UI — activity feed component

**Files:**
- New: `apps/web-platform/src/components/dashboard/activity-feed.tsx`
- New: `apps/web-platform/src/hooks/use-workspace-activity.ts` — polling hook (60s interval, paginated — 60s per Simplicity S6 for flag-gated feature)
- Edit: `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx` — add Team Activity tab (per design mockup `13-team-activity-feed.png`)

Activity feed component: lightweight timeline with actor avatar, action description, relative timestamp, resource link. "Load more" button for pagination. Handle NULL `actor_user_id` gracefully (show "Former member" per Simplicity S5).

#### Phase 4: DSAR + legal

- Add `workspace_activity` to `DSAR_TABLE_ALLOWLIST` in `dsar-export-allowlist.ts` with OR-semantics over `actor_user_id`
- Add `anonymise_workspace_activity` to `account-delete.ts` cascade (between workspace_member steps)
- Legal doc amendments: Privacy Policy §4.11 (activity feed disclosure), DPD §2.3(u) (new data class), GDPR Policy (Art. 6(1)(b) basis), Art. 30 PA-2 amendment or new PA-24

#### Phase 5: Tests

- RLS: workspace member can SELECT activity for own workspace, cannot SELECT other workspace's activity
- Writer RPC: authenticated user can call `record_workspace_activity` for own workspace only
- pg_cron: verify retention purge deletes rows > 90 days
- DSAR: verify `workspace_activity` rows appear in export bundle
- Art-17: verify `anonymise_workspace_activity` anonymises actor_user_id on account deletion

### PR-C: KB Files Metadata Table (mig 077)

#### Phase 1: Migration 077 — kb_files table

**File:** `apps/web-platform/supabase/migrations/077_kb_files_metadata.sql`

1.1. Create table (simplified per Simplicity — drop `content_sha256`, `size_bytes` which have no MVP consumer):
```sql
CREATE TABLE public.kb_files (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  file_path text NOT NULL,
  filename text NOT NULL,
  visibility text NOT NULL CHECK (visibility IN ('private', 'workspace')) DEFAULT 'workspace',
  uploaded_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, file_path)
);

ALTER TABLE public.kb_files ENABLE ROW LEVEL SECURITY;
```

Notes per plan review:
- `user_id` is NULLABLE + `ON DELETE SET NULL` (not `NOT NULL` + `ON SET NULL` — per Kieran C1).
- `content_sha256` and `size_bytes` dropped — no MVP consumer. Add when sync/quota needs them (per Simplicity S3c).
- `visibility` defaults to `'workspace'` — KB is a shared knowledge base; conversations default to private.
- Add `updated_at` trigger (per Kieran M5) to auto-set on UPDATE.

1.2. RLS policies:
```sql
CREATE POLICY kb_files_owner_or_shared ON public.kb_files
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR (visibility = 'workspace' AND public.is_workspace_member(workspace_id, auth.uid()))
  );

CREATE POLICY kb_files_owner_insert ON public.kb_files
  FOR INSERT TO authenticated
  WITH CHECK (public.is_workspace_member(workspace_id, auth.uid()));
```

1.3. Protect authorization-sensitive columns via column-level REVOKE (per Kieran C3 — self-referential RESTRICTIVE always passes):
```sql
REVOKE UPDATE(visibility, workspace_id) ON public.kb_files FROM authenticated;
```

Add JTI deny RESTRICTIVE policy (per Kieran H1, mig 068 pattern):
```sql
CREATE POLICY kb_files_jti_not_denied ON public.kb_files
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT public.is_jti_denied_from_jwt())
  WITH CHECK (NOT public.is_jti_denied_from_jwt());
```

1.4. SECURITY DEFINER RPC for visibility changes:
```sql
CREATE OR REPLACE FUNCTION public.set_kb_file_visibility(
  p_file_id uuid, p_visibility text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF p_visibility NOT IN ('private', 'workspace') THEN
    RAISE EXCEPTION 'Invalid visibility: %', p_visibility;
  END IF;
  UPDATE public.kb_files
     SET visibility = p_visibility, updated_at = now()
   WHERE id = p_file_id
     AND user_id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'KB file not found or not owned by caller';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.set_kb_file_visibility FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_kb_file_visibility TO authenticated;
```

1.5. Indexes (drop kb_files_user_idx — no query path filters by user_id alone, per Simplicity S3d):
```sql
CREATE INDEX kb_files_workspace_idx ON public.kb_files (workspace_id);
```

#### Phase 2: Server-side — INSERT on upload (simplified per Simplicity S2)

**Replaces the incremental sync engine** (a YAGNI violation — full sync solves quota/search/integrity problems not in scope). Instead: single INSERT into `kb_files` at the upload call site.

**Files:**
- Edit: `apps/web-platform/server/kb-reader.ts` — on file upload/create, INSERT a `kb_files` row
- Files that exist on disk but not in `kb_files` (pre-existing) show "Unknown uploader" in the UI

Service-role client handles INSERT (bypasses RLS — per Kieran H2, no authenticated UPDATE/DELETE policies needed at MVP since all mutations go through service-role).

#### Phase 3: Client-side UI — uploader attribution

**Files:**
- Edit: KB file tree component — add uploader avatar/initials badge per file (per design mockup `14-kb-file-attribution.png`)
- Edit: KB document viewer header — show "Uploaded by [avatar] [name]" + visibility toggle

#### Phase 4: DSAR + legal

- Add `kb_files` to `DSAR_TABLE_ALLOWLIST` in `dsar-export-allowlist.ts`
- Add `anonymise_kb_files` to `account-delete.ts` cascade
- Art-15(4) redaction: if shared KB files contain PII authored by another user, apply redaction logic
- Legal: PA-2 recipients amendment (add kb_files to workspace co-member visibility scope)

#### Phase 5: Tests

- RLS: workspace member can see 'workspace' visibility files, cannot see 'private' files from other users
- Cross-workspace: user from different workspace sees nothing
- Sync: filesystem changes reflected in `kb_files` table
- DSAR: `kb_files` rows appear in export bundle
- Art-17: anonymisation on account deletion

## Files to Edit

### PR-A
- `apps/web-platform/supabase/migrations/075_conversation_visibility.sql` (create)
- `apps/web-platform/supabase/migrations/075_conversation_visibility.down.sql` (create)
- `apps/web-platform/server/ws-handler.ts` (fix workspace_id INSERT + audit 6 sites)
- `apps/web-platform/server/conversations-tools.ts` (widen 4 MCP tool sites)
- `apps/web-platform/server/agent-runner.ts` (audit 3 sites)
- `apps/web-platform/server/api-messages.ts` (widen 1 site)
- `apps/web-platform/server/lookup-conversation-for-path.ts` (widen 1 site)
- `apps/web-platform/src/hooks/use-conversations.ts` (widen Realtime filter)
- `apps/web-platform/src/components/conversation/visibility-toggle.tsx` (create)
- `apps/web-platform/src/components/conversation/conversation-header.tsx` (add toggle)
- `apps/web-platform/test/server/conversation-visibility.tenant-isolation.test.ts` (create)

### PR-B
- `apps/web-platform/supabase/migrations/076_workspace_activity.sql` (create)
- `apps/web-platform/supabase/migrations/076_workspace_activity.down.sql` (create)
- `apps/web-platform/server/workspace-membership.ts` (add event emitters)
- `apps/web-platform/server/ws-handler.ts` (add conversation_created event)
- `apps/web-platform/server/agent-runner.ts` (add agent_run events)
- `apps/web-platform/server/dsar-export-allowlist.ts` (add workspace_activity)
- `apps/web-platform/server/account-delete.ts` (add anonymise step)
- `apps/web-platform/src/components/dashboard/activity-feed.tsx` (create)
- `apps/web-platform/src/hooks/use-workspace-activity.ts` (create)
- `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx` (add Team Activity tab)
- `apps/web-platform/test/server/workspace-activity.tenant-isolation.test.ts` (create)

### PR-C
- `apps/web-platform/supabase/migrations/077_kb_files_metadata.sql` (create)
- `apps/web-platform/supabase/migrations/077_kb_files_metadata.down.sql` (create)
- `apps/web-platform/server/kb-reader.ts` (add kb_files sync)
- `apps/web-platform/server/kb-document-resolver.ts` (resolve via kb_files)
- `apps/web-platform/server/dsar-export-allowlist.ts` (add kb_files)
- `apps/web-platform/server/account-delete.ts` (add anonymise step)
- KB file tree component (add uploader badge + visibility indicator)
- KB document viewer header (add attribution + toggle)
- `apps/web-platform/test/server/kb-files.tenant-isolation.test.ts` (create)

## Files to Create

- `apps/web-platform/supabase/migrations/075_conversation_visibility.sql`
- `apps/web-platform/supabase/migrations/075_conversation_visibility.down.sql`
- `apps/web-platform/supabase/migrations/076_workspace_activity.sql`
- `apps/web-platform/supabase/migrations/076_workspace_activity.down.sql`
- `apps/web-platform/supabase/migrations/077_kb_files_metadata.sql`
- `apps/web-platform/supabase/migrations/077_kb_files_metadata.down.sql`
- `apps/web-platform/src/components/conversation/visibility-toggle.tsx`
- `apps/web-platform/src/components/dashboard/activity-feed.tsx`
- `apps/web-platform/src/hooks/use-workspace-activity.ts`
- `apps/web-platform/test/server/conversation-visibility.tenant-isolation.test.ts`
- `apps/web-platform/test/server/workspace-activity.tenant-isolation.test.ts`
- `apps/web-platform/test/server/kb-files.tenant-isolation.test.ts`

## Open Code-Review Overlap

6 open code-review issues touch planned files. All on different concerns — **acknowledged**:

- `ws-handler.ts`: #3374 (slot_reclaimed WS frame), #3243 (decompose cc-dispatcher), #2961 (repo_url immutability), #2191 (clearSessionTimers) — none conflict with visibility changes
- `conversations-tools.ts`: #3289 (conversation_messages MCP tool) — additive, our changes widen existing tools
- `agent-runner.ts`: #3454 (pdf_metadata MCP tool), #3242 (tool_use WS event) — neither conflicts
- `conversation-writer.ts`: #2963 (Supabase typegen) — type safety, could fold-in later

Disposition: **Acknowledge all** — different concerns from visibility/activity/KB work.

## Domain Review

**Domains relevant:** Product (CPO), Engineering (CTO), Legal (CLO)

### Product (CPO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Strong "keep deferred" recommendation overridden by operator. Conversations most ready; KB architecture mismatch corrected. Feature flag OFF provides safety net.

### Engineering (CTO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** 25 call sites confirmed (vs brainstorm "20+"). Workspace_id INSERT gap is a latent bug. Recommended conversations → activity → KB sequencing. Activity feed polling over Realtime.

### Legal (CLO)

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Shared conversations legally covered. Activity feed completely uncovered — needs 6 legal doc amendments. KB partially covered. GDPR gate mandatory. TC_VERSION bump assessment needed.

## Observability

```yaml
liveness_signal:
  what: workspace_activity INSERT count > 0 when flag is ON
  cadence: per-event (INSERT-driven)
  alert_target: Sentry breadcrumb on RPC error
  configured_in: record_workspace_activity RPC error path

error_reporting:
  destination: Sentry (via existing server error reporting)
  fail_loud: RPC errors raise exceptions (not swallowed)

failure_modes:
  - mode: RLS predicate too permissive (cross-tenant read)
    detection: tenant-isolation integration tests (CI)
    alert_route: CI failure blocks merge
  - mode: workspace_id INSERT gap resurfaces
    detection: NOT NULL constraint violation in Sentry
    alert_route: Sentry alert on 23502 error code
  - mode: Activity feed polling overloads DB
    detection: Supabase dashboard query latency
    alert_route: pg_stat_statements slow query alert

logs:
  where: Sentry breadcrumbs + pino structured logs
  retention: Sentry 90 days, activity table 90 days (pg_cron purge)

discoverability_test:
  command: |
    curl -s https://app.soleur.ai/api/health | jq '.status'
  expected_output: "ok"
```

## Acceptance Criteria

### Pre-merge (PR-A)

- [ ] AC1: Migration 075 applies cleanly on dev Supabase: `supabase db push --linked`
- [ ] AC2: `SELECT visibility FROM conversations LIMIT 1` returns `'private'`
- [ ] AC3: RLS deny test: User B in workspace X cannot SELECT User A's private conversation. Payload uses `randomUUID()` for uuid columns.
- [ ] AC4: RLS allow test: User B in workspace X CAN SELECT User A's conversation when `visibility = 'workspace'`
- [ ] AC5: Cross-workspace deny: User C in workspace Y cannot SELECT any conversation from workspace X
- [ ] AC6: `ws-handler.ts:806` INSERT includes `workspace_id` field
- [ ] AC7: `set_conversation_visibility` RPC: owner can toggle, non-owner gets exception
- [ ] AC8: RESTRICTIVE policy: client `.update({visibility: 'workspace'})` is rejected (must use RPC)
- [ ] AC9: `tsc --noEmit` passes
- [ ] AC10: All 25 `.from("conversations")` sites audited (comment annotation on each)

### Pre-merge (PR-B)

- [ ] AC11: Migration 076 applies cleanly
- [ ] AC12: RLS: workspace member can SELECT activity, cross-workspace user cannot
- [ ] AC13: `record_workspace_activity` RPC succeeds for authenticated user in workspace
- [ ] AC14: Activity feed UI renders events with actor avatar, action text, timestamp
- [ ] AC15: pg_cron job `workspace_activity_purge` registered: `SELECT * FROM cron.job WHERE jobname = 'workspace_activity_purge'`
- [ ] AC16: `workspace_activity` in `DSAR_TABLE_ALLOWLIST`
- [ ] AC17: `anonymise_workspace_activity` in `account-delete.ts` cascade

### Pre-merge (PR-C)

- [ ] AC18: Migration 077 applies cleanly
- [ ] AC19: RLS: workspace member sees 'workspace' files, cannot see 'private' files from others
- [ ] AC20: `kb_files` populated from filesystem on KB sync
- [ ] AC21: Uploader attribution visible in KB viewer
- [ ] AC22: `kb_files` in `DSAR_TABLE_ALLOWLIST`
- [ ] AC23: `set_kb_file_visibility` RPC: owner can toggle, non-owner gets exception

### Post-merge (operator)

- [ ] AC24: `supabase db push` to prd (per `hr-menu-option-ack-not-prod-write-auth`): Automation: not feasible because production migration push requires operator acknowledgment per hard rule.
- [ ] AC25: Verify `TEAM_WORKSPACE_INVITE_ENABLED` flag remains OFF after deploy
- [ ] AC26: Legal doc amendments committed in lockstep PRs

## Test Strategy

**Test runner:** `./node_modules/.bin/vitest run` (per `apps/web-platform/package.json` scripts; `bunfig.toml` blocks `bun test` discovery per #1469)

**Integration tests:** Opt-in via `SUPABASE_DEV_INTEGRATION=1` against dev Supabase instance. Follow dual-shape RLS deny pattern (TR5): `if (error) { expect(error.code).toBe("42501"); } else { expect(data).toEqual([]); }` with service-role re-read poison-check.

**Tenant-isolation tests:** Follow `test/conversations-rail-cross-tenant.integration.test.ts` precedent for cross-workspace assertions.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| RLS predicate too permissive (cross-tenant leak) | Tenant-isolation integration tests + dual-shape deny assertions + service-role poison-checks |
| `visibility` column client-writable via UPDATE | Column-level REVOKE blocks direct UPDATE; must use SECURITY DEFINER RPC |
| Activity feed disk I/O regression (mig 039 precedent) | NOT in Realtime publication; polling only; pg_cron 90-day retention cap |
| WORM trigger deadlock on Art-17 cascade | SET NULL FK on actor_user_id (not RESTRICT) per TR6 |
| workspace_id INSERT gap causes production errors | Fix in Phase 1 of PR-A; regression test in Phase 4 |
| Legal scaffolding drift from code | Legal doc amendments ship in lockstep PRs per #4289 precedent |

## Plan Review Findings Applied

3 reviewers (DHH, Kieran, Simplicity) ran in parallel. Key changes applied:

| Finding | Severity | Fix |
|---------|----------|-----|
| Kieran C1: `ON SET NULL` invalid SQL + `NOT NULL` contradicts SET NULL | CRITICAL | Changed to `ON DELETE SET NULL` + dropped NOT NULL on PII columns |
| Kieran C2: `record_workspace_activity` RPC has no auth check | CRITICAL | Changed GRANT to `service_role` only (all emitters are server-side) |
| Kieran C3: RESTRICTIVE self-referential WITH CHECK is always-true no-op | CRITICAL | Replaced with column-level `REVOKE UPDATE(visibility)` |
| Kieran H1: New tables missing JTI deny policies | HIGH | Added `_jti_not_denied` RESTRICTIVE policies to both tables |
| Kieran H3: pg_cron schedule not idempotent | HIGH | Wrapped in DO/EXCEPTION block per mig 038 precedent |
| DHH R1: workspace_activity duplicates workspace_member_actions | HIGH | Added explicit justification (WORM incompatible with purge + SET NULL) |
| Simplicity S2: kb_files sync engine is YAGNI | HIGH | Replaced with single INSERT at upload site |
| Simplicity S3a: 8-type enum too wide for MVP | MEDIUM | Narrowed to 3 MVP types, removed CHECK constraint |
| Simplicity S3c/S3d: content_sha256, size_bytes, kb_files_user_idx unused | LOW | Dropped from initial migration |

## Sharp Edges

- Column-level `REVOKE UPDATE(visibility)` prevents direct client UPDATE. All visibility changes MUST use the SECURITY DEFINER RPC.
- `workspace_activity.actor_user_id` is NULLABLE + `ON DELETE SET NULL` (not NOT NULL + RESTRICT). The UI must handle NULL gracefully ("Former member").
- `workspace_activity` is a SEPARATE table from `workspace_member_actions` — different constraints (purge vs WORM, SET NULL vs RESTRICT, application vs trigger writes).
- The `kb_files` table defaults visibility to `'workspace'` (shared), unlike conversations which default to `'private'`.
- `conversations_owner_or_shared` uses `FOR ALL` which covers INSERT. Workspace members CAN create conversations in a shared workspace — intentional per Kieran M3.
- At `brand_survival_threshold: single-user incident`, deepen-plan is recommended before `/work` but user authorized autonomous execution.
