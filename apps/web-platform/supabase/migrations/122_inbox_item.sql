-- 122_inbox_item.sql
-- feat-severity-ranked-inbox (#6007, Multica-adaptation epic #6006 child 1) —
-- a NEW general operational-notification store, SEPARATE from the
-- email_triage_items WORM statutory ledger (ADR-085). Operational (mutable
-- read/act/archive state), workspace-grain, Owner-shared reads per ADR-066.
--
-- Why a new table (not generalizing email_triage_items): that table is a
-- GDPR-hardened WORM ledger with email-specific NOT NULL columns and a strict
-- mutation-matrix trigger; nullable-ing frozen columns to host operational
-- notifications would pollute a statutory-evidence surface. Severity for
-- email-triage rows is computed at the merge layer from statutory_class — this
-- migration does NOT touch email_triage_items.
--
-- Contrast with the WORM ledger (deliberate, ADR-085):
--   * MUTABLE: read/act/archive transitions via set_inbox_item_state RPC.
--   * CASCADE (not RESTRICT): operational data follows workspace + user
--     lifecycle. mig 111 used RESTRICT to protect statutory EVIDENCE — that
--     protection is inappropriate for operational ephemera.
--   * 90d retention (more aggressive than the email ledger's 365d) — justified
--     as content-minimized operational noise (ADR-085 AP-009 deviation), with a
--     hard NEVER-DELETE carve-out for un-acted action_required.
--
-- Reuses the shipped public.is_workspace_owner(uuid,uuid) helper (mig 098:67 —
-- SECURITY DEFINER plpgsql, search_path-pinned, role='owner'). No new helper.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: the RPC pins
-- SET search_path = public, pg_temp.
-- Transaction wrapping: NO top-level BEGIN/COMMIT — run-migrations.sh wraps the
-- body + the _schema_migrations INSERT in one --single-transaction stream.

-- =====================================================================
-- 0. Preconditions
-- =====================================================================

DO $$ BEGIN
  IF to_regclass('public.workspaces') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.workspaces must exist before 122';
  END IF;
  IF to_regclass('public.users') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.users must exist before 122';
  END IF;
  IF to_regprocedure('public.is_workspace_owner(uuid, uuid)') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.is_workspace_owner(uuid,uuid) must exist before 122 (mig 098)';
  END IF;
END $$;

-- =====================================================================
-- 1. Table
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.inbox_item (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Operational data follows workspace lifecycle: CASCADE (NOT the mig-111
  -- statutory RESTRICT — that protected legal evidence, not operational noise).
  workspace_id uuid        NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  -- NULL = workspace-broadcast (visible to every Owner); set = personally
  -- targeted (private to that recipient — see the RLS SELECT predicate).
  user_id      uuid        NULL REFERENCES public.users(id) ON DELETE CASCADE,
  severity     text        NOT NULL CHECK (severity IN ('action_required', 'attention', 'info')),
  -- v1-emittable set ONLY. #4672 (approval_required) / #4674 (autopilot_run)
  -- each ALTER … the CHECK in the migration that ships their emitter — the
  -- inbox surface degrades gracefully for a source whose deep-link target does
  -- not exist yet.
  source       text        NOT NULL CHECK (source IN ('task_completed', 'system')),
  -- Server-generated + sanitized. NEVER agent output / email subject / message
  -- body — a co-Owner-visible row must carry nothing the founder would not want
  -- a co-Owner to see (ADR-085 content-minimization).
  title        text        NOT NULL,
  -- ids ONLY (e.g. {"conversationId": "..."}). The deep link is BUILT AT RENDER
  -- from these, never stored (a stored URL rots when a route path changes or the
  -- target is deleted).
  source_ref   jsonb       NULL,
  -- Idempotent emit (ADR-035): notifyInboxItem plain-inserts and catches 23505.
  dedup_key    text        NULL,
  -- Inline v1 state (NO per-Owner recipient-state join — deferred to #4672,
  -- where broadcast approval_required is the first source that actually needs
  -- independent per-Owner state). acted_at is the single GLOBAL resolution
  -- signal (one approver resolves for the workspace).
  status       text        NOT NULL DEFAULT 'unread' CHECK (status IN ('unread', 'read', 'archived')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  read_at      timestamptz NULL,
  acted_at     timestamptz NULL,
  archived_at  timestamptz NULL
);

COMMENT ON TABLE public.inbox_item IS
  'General operational-notification store (ADR-085, feat-severity-ranked-inbox '
  '#6007). Workspace-grain, Owner-shared reads; SEPARATE from the '
  'email_triage_items WORM statutory ledger. Mutable read/act/archive state via '
  'set_inbox_item_state. Content-minimized: title + source_ref ids only, never '
  'agent/email content. 90d retention except un-acted action_required.';

-- =====================================================================
-- 2. Indexes
-- =====================================================================

-- Dedup — workspace-scoped partial-unique (ADR-035). notifyInboxItem
-- plain-inserts and catches 23505 (ON CONFLICT DO NOTHING is unreliable under
-- supabase-js — returns data:null). Partial so NULL dedup_key rows (no
-- idempotency requested) never collide.
CREATE UNIQUE INDEX IF NOT EXISTS inbox_item_dedup_key_uniq
  ON public.inbox_item (workspace_id, dedup_key)
  WHERE dedup_key IS NOT NULL;

-- Workspace read index for the merge — the non-archived feed by recency.
CREATE INDEX IF NOT EXISTS inbox_item_workspace_created_idx
  ON public.inbox_item (workspace_id, created_at DESC)
  WHERE status <> 'archived';

-- Retention sweep support: age scan across all rows.
CREATE INDEX IF NOT EXISTS inbox_item_created_idx
  ON public.inbox_item (created_at);

-- =====================================================================
-- 3. RLS — operational (NOT WORM). Reads: targeted rows private to their
--    recipient; broadcasts (user_id NULL) visible to workspace Owners. Writes:
--    service-role dispatcher (INSERT) + set_inbox_item_state RPC (UPDATE) ONLY
--    — no authenticated write policy (2026-05-21 bypass-path learning). SELECT
--    stays granted (Supabase default) and is gated SOLELY by the policy below.
-- =====================================================================

ALTER TABLE public.inbox_item ENABLE ROW LEVEL SECURITY;

REVOKE INSERT ON TABLE public.inbox_item FROM PUBLIC, anon, authenticated;
REVOKE UPDATE ON TABLE public.inbox_item FROM PUBLIC, anon, authenticated;
REVOKE DELETE ON TABLE public.inbox_item FROM PUBLIC, anon, authenticated;

CREATE POLICY inbox_item_owner_select ON public.inbox_item
  FOR SELECT TO authenticated
  USING (
    (user_id = auth.uid())
    OR (user_id IS NULL AND public.is_workspace_owner(workspace_id, auth.uid()))
  );

-- =====================================================================
-- 4. set_inbox_item_state(p_id, p_action) — the ONLY authenticated write path.
--    Actions: 'read' | 'acted' | 'archived'. SECURITY DEFINER, auth.uid() pin,
--    same error for missing + non-authorized (no existence oracle), FOR UPDATE.
--    Authorization mirrors the SELECT policy exactly. Archive-guard: reject
--    archiving an action_required row not yet acted (a misclick must never
--    permanently lose an approval — mirrors the email precedent where statutory
--    rows have no archive button). acted_at is set-once/idempotent (pre-wires
--    the deferred multi-Owner "already resolved" banner).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.set_inbox_item_state(p_id uuid, p_action text)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.inbox_item%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'set_inbox_item_state: authenticated callers only'
      USING ERRCODE = '42501';
  END IF;

  IF p_action NOT IN ('read', 'acted', 'archived') THEN
    RAISE EXCEPTION 'set_inbox_item_state: invalid action %; only read|acted|archived', p_action
      USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_row
  FROM public.inbox_item
  WHERE id = p_id
  FOR UPDATE;

  -- Same error for missing row and non-authorized row — no existence oracle.
  -- Authorize exactly as the SELECT policy: recipient of a targeted row, or an
  -- Owner of a broadcast row's workspace.
  IF NOT FOUND
     OR NOT (
       (v_row.user_id = auth.uid())
       OR (v_row.user_id IS NULL AND public.is_workspace_owner(v_row.workspace_id, auth.uid()))
     )
  THEN
    RAISE EXCEPTION 'set_inbox_item_state: not authorized'
      USING ERRCODE = '42501';
  END IF;

  IF p_action = 'archived' THEN
    -- Archive-guard: an un-acted action_required item must be acted before it
    -- can be archived (a misclick must not permanently lose an approval).
    IF v_row.severity = 'action_required' AND v_row.acted_at IS NULL THEN
      RAISE EXCEPTION 'set_inbox_item_state: cannot archive an un-acted action_required item'
        USING ERRCODE = 'P0001';
    END IF;
    UPDATE public.inbox_item
       SET status = 'archived', archived_at = now()
     WHERE id = p_id;

  ELSIF p_action = 'acted' THEN
    -- Set-once: already-acted is a no-op (idempotent). Acting also marks read
    -- (an item you acted on is necessarily seen). Never demotes an archived row.
    IF v_row.acted_at IS NULL THEN
      UPDATE public.inbox_item
         SET acted_at = now(),
             read_at  = COALESCE(read_at, now()),
             status   = CASE WHEN status = 'archived' THEN status ELSE 'read' END
       WHERE id = p_id;
    END IF;

  ELSE  -- 'read'
    IF v_row.read_at IS NULL THEN
      UPDATE public.inbox_item
         SET read_at = now(),
             status  = CASE WHEN status = 'unread' THEN 'read' ELSE status END
       WHERE id = p_id;
    END IF;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.set_inbox_item_state(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_inbox_item_state(uuid, text)
  TO authenticated;

COMMENT ON FUNCTION public.set_inbox_item_state(uuid, text) IS
  'Owner/recipient-pinned state transitions for inbox_item (read|acted|archived). '
  'SECURITY DEFINER; authorization mirrors the SELECT policy (recipient of a '
  'targeted row, or an Owner of a broadcast row''s workspace). Same error for '
  'missing + foreign row (no existence oracle). Archive-guard blocks archiving an '
  'un-acted action_required item. acted_at is set-once/idempotent. The ONLY '
  'sanctioned authenticated write path (no write RLS policy exists).';

-- =====================================================================
-- 5. Retention — daily pg_cron sweep at 04:00 UTC. Deletes archived OR info
--    rows older than 90d, but NEVER an un-acted action_required row (hard
--    carve-out, defense-in-depth in the WHERE — mirrors the email statutory
--    carve-out). pg_cron-absent CI: guarded (mig 094/076/102 shape).
-- =====================================================================

DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'inbox_item_retention') THEN
    PERFORM cron.unschedule('inbox_item_retention');
  END IF;
  PERFORM cron.schedule(
    'inbox_item_retention',
    '0 4 * * *',
    $$DELETE FROM public.inbox_item
       WHERE created_at < now() - interval '90 days'
         AND (status = 'archived' OR severity = 'info')
         AND NOT (severity = 'action_required' AND acted_at IS NULL)$$
  );
EXCEPTION
  WHEN undefined_table THEN
    RAISE NOTICE 'mig 122: pg_cron not installed; inbox_item_retention sweep skipped';
  WHEN duplicate_object THEN NULL;
END $cron_block$;
