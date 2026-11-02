-- 180_approval_request.sql
-- #4672 slice 1 (HITL approval queue): durable, action-bound approval requests.
--
-- A gated slice-1 tool call creates ONE approval_request row (service-role RPC), the workspace Owner decides it
-- later in the product (decide_approval, authenticated, actor = auth.uid()), and the agent's next identical
-- proposal consumes the approved row exactly once (consume_approval, one atomic conditional UPDATE). Nothing
-- executes server-side on approve. ADR-307 records the decision; plan:
-- knowledge-base/project/plans/2026-10-27-feat-durable-action-bound-approval-requests-plan.md.
--
-- Numbering: 179 is held by an unmerged sibling worktree (179_codex_dsar_column_grants) and is free on both
-- origin/main (latest 178) and the shared DEV ledger, so this migration takes 180 (renumbered from the plan's 179).
--
-- Why a new table and not action_sends: action_sends.grant_id is NOT NULL (FK to scope_grants), tier_at_send is a
-- four-value CHECK and the pure-reject trigger covers send-shaped columns; an approval exists BEFORE any send.
--
-- Audit design: the row itself is the audit record. Identity, hash, tool, expiry, decision (who/when), the
-- consume/expire markers and the revoke pair are write-once and the status machine is forward-only apart from one
-- Owner-initiated step, approved -> rejected ("revoke", an UNCONSUMED approval withdrawn; it only reduces
-- authority). The raw action text (canonical_action) is the only part erased on the 30-day schedule. Erasure
-- (Art. 17): the user columns are nulled; the rows of a PERSONAL workspace (workspaces.id = users.id, the workspace
-- row itself survives account erasure by design, mig 065/162) are DELETED once that workspace has no member left
-- (anonymise_approval_request, guarded by the app.approval_erase GUC + a memberless workspace); a workspace that
-- still has members keeps its record. No second WORM table (plan Cut List).
--
-- action_sha256 is an HMAC-SHA-256 computed IN THE APP with a server-held key (never in the database); the column
-- is an opaque 64-hex string here.
--
-- Why the grant differs between the RPCs: decide_approval is granted to `authenticated` because its authority is the
-- NON-forgeable auth.uid() of the caller (the HTTP route calls it with the user JWT, the WebSocket handler with the
-- tenant client minted for the socket's verified user). Every other RPC takes caller-supplied ids and trusts the
-- platform that calls it, so it is granted to `service_role` ONLY (rule: a forgeable caller param and TO
-- service_role are a matched pair, see 2026-06-01-caller-override-rpc-needs-service-role-only-grant.md).
--
-- Transaction wrapping: NO top-level BEGIN/COMMIT (run-migrations.sh wraps body + the _schema_migrations INSERT).

-- =====================================================================
-- 0. Preconditions
-- =====================================================================

DO $$ BEGIN
  IF to_regclass('public.workspaces') IS NULL
     OR to_regclass('public.users') IS NULL
     OR to_regclass('public.conversations') IS NULL
     OR to_regclass('public.inbox_item') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.workspaces/users/conversations/inbox_item must exist before 180';
  END IF;
  IF to_regprocedure('public.is_workspace_owner(uuid, uuid)') IS NULL
     OR to_regprocedure('public.is_workspace_member(uuid, uuid)') IS NULL
     OR to_regprocedure('public.is_jti_denied_from_jwt()') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: is_workspace_owner/is_workspace_member/is_jti_denied_from_jwt must exist before 180';
  END IF;
  -- create_approval_request writes its inbox row with ON CONFLICT (workspace_id, dedup_key) WHERE dedup_key IS NOT NULL.
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
     WHERE schemaname = 'public' AND tablename = 'inbox_item'
       AND indexdef LIKE '%UNIQUE%'
       AND indexdef LIKE '%(workspace_id, dedup_key)%'
       AND indexdef LIKE '%dedup_key IS NOT NULL%'
  ) THEN
    RAISE EXCEPTION 'Precondition failed: the unique partial index on public.inbox_item (workspace_id, dedup_key) WHERE dedup_key IS NOT NULL must exist before 180';
  END IF;
END $$;

-- =====================================================================
-- 1. Table
-- =====================================================================
-- RETENTION: canonical_action (the action text: email bodies, recipients, repository names) is nulled 30 days after
-- the terminal state by sweep_approvals(). The metadata row (hash, tool, status, actor ids, timestamps) is kept as the
-- accountability record for outward actions taken on a user's behalf, and its three user columns are anonymised on
-- erasure (ON DELETE SET NULL carve-out below, plus anonymise_approval_request); the rows of a personal workspace
-- with no member left are deleted outright on erasure. The Art. 30 entry names this purpose (legal task of the
-- same PR, CLO-owned).
--
-- conversation_id deliberately has NO foreign key: the audit row must outlive the conversation (a conversation delete
-- cascade would otherwise be a DELETE the write-once trigger has to admit). create_approval_request validates the
-- conversation exists in the workspace and is not archived; decide_approval treats a missing or archived
-- conversation as closed.

CREATE TABLE IF NOT EXISTS public.approval_request (
  id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  -- The workspace-cascade DELETE is admitted by the guard trigger. A personal workspace row is NOT deleted when its
  -- user is erased (mig 065/162), so the cascade never fires for it: anonymise_approval_request deletes those rows.
  workspace_id          uuid        NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  -- LAWFUL_BASIS: legitimate interest (Art. 6(1)(f)) - an accountable record of which user's session asked for an
  -- outward action. Anonymised (SET NULL) on erasure; Art. 30 entry in the legal task of this PR.
  requested_by_user_id  uuid        NULL REFERENCES public.users(id) ON DELETE SET NULL,
  -- LAWFUL_BASIS: legitimate interest (Art. 6(1)(f)) - an accountable record of which workspace Owner decided the
  -- request. Anonymised (SET NULL) on erasure.
  decided_by            uuid        NULL REFERENCES public.users(id) ON DELETE SET NULL,
  -- LAWFUL_BASIS: legitimate interest (Art. 6(1)(f)) - an accountable record of which workspace Owner withdrew an
  -- approval that had not been used yet. Anonymised (SET NULL) on erasure; set once, with approved -> rejected.
  revoked_by            uuid        NULL REFERENCES public.users(id) ON DELETE SET NULL,
  conversation_id       uuid        NOT NULL,
  tool_name             text        NOT NULL CHECK (tool_name IN (
                          'mcp__soleur_platform__email_send',
                          'mcp__soleur_platform__email_reply',
                          'mcp__soleur_platform__email_suppress',
                          'mcp__soleur_platform__github_push_branch',
                          'mcp__soleur_platform__create_pull_request',
                          'mcp__soleur_platform__github_trigger_workflow',
                          'mcp__soleur_platform__kb_share_create',
                          'mcp__soleur_platform__workspace_set_autonomous'
                        )),
  action_sha256         text        NOT NULL CHECK (action_sha256 ~ '^[0-9a-f]{64}$'),
  -- LAWFUL_BASIS: performance of the user's own request (Art. 6(1)(b)) - the exact action the Owner is asked to
  -- approve, shown only to Owners. Free-form user content that can contain any category of data; erasable: nulled
  -- 30 days after the terminal state and on erasure. Never placed in a notification or an LLM prompt.
  canonical_action      jsonb       NULL,
  status                text        NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending', 'approved', 'rejected', 'expired', 'consumed')),
  expires_at            timestamptz NOT NULL,
  decided_at            timestamptz NULL,
  consumed_at           timestamptz NULL,
  expired_at            timestamptz NULL,
  revoked_at            timestamptz NULL,
  unanswered_flagged_at timestamptz NULL,
  created_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT approval_request_expiry_after_create CHECK (expires_at > created_at),
  CONSTRAINT approval_request_decided_pairing
    CHECK ((status IN ('pending', 'expired')) OR decided_at IS NOT NULL),
  CONSTRAINT approval_request_pending_undecided
    CHECK (status <> 'pending' OR decided_at IS NULL),
  CONSTRAINT approval_request_consumed_pairing
    CHECK ((status = 'consumed') = (consumed_at IS NOT NULL)),
  CONSTRAINT approval_request_expired_pairing
    CHECK ((status = 'expired') = (expired_at IS NOT NULL)),
  -- A revoke is an approved -> rejected step: decided_at/decided_by keep the approval facts, the revoke is its own pair.
  CONSTRAINT approval_request_revoked_pairing
    CHECK ((revoked_at IS NULL OR status = 'rejected') AND (revoked_by IS NULL OR revoked_at IS NOT NULL))
);

COMMENT ON TABLE public.approval_request IS
  'Durable, action-bound approval requests (#4672 slice 1). One row per exact action (action_sha256 = HMAC-SHA-256, '
  'keyed in the app, over the full canonical input). Owner-only SELECT; every write goes through the approval RPCs '
  '(write-once trigger, forward-only status machine plus the Owner revoke approved -> rejected). canonical_action is '
  'scrubbed 30 days after the terminal state; the metadata row is the audit record, deleted on erasure for a personal '
  'workspace with no member left.';

-- A live (pending or approved) request is unique per (conversation, action hash): create is idempotent on it.
CREATE UNIQUE INDEX IF NOT EXISTS approval_request_live_uniq
  ON public.approval_request (conversation_id, action_sha256)
  WHERE status IN ('pending', 'approved');

-- The request count shown on the card header is a count over ALL statuses of one (conversation, hash).
CREATE INDEX IF NOT EXISTS approval_request_conv_hash_idx
  ON public.approval_request (conversation_id, action_sha256);

-- Cron sweep: due rows and unanswered rows are scanned by (status, expires_at) over live rows only.
CREATE INDEX IF NOT EXISTS approval_request_sweep_idx
  ON public.approval_request (status, expires_at)
  WHERE status IN ('pending', 'approved');

CREATE INDEX IF NOT EXISTS approval_request_workspace_created_idx
  ON public.approval_request (workspace_id, created_at DESC);

-- Pending-request caps (create_approval_request: 20 per workspace) and the 10-minute notification coalescing read.
CREATE INDEX IF NOT EXISTS approval_request_ws_pending_idx
  ON public.approval_request (workspace_id)
  WHERE status = 'pending';

-- 30-day text scrub (sweep_approvals): bounded, index-driven scan over rows that still hold text.
CREATE INDEX IF NOT EXISTS approval_request_scrub_idx
  ON public.approval_request ((COALESCE(consumed_at, expired_at, revoked_at, decided_at)))
  WHERE canonical_action IS NOT NULL AND status IN ('rejected', 'expired', 'consumed');

-- The three user FKs are ON DELETE SET NULL (Art. 17); without an index each user delete seq-scans the table.
CREATE INDEX IF NOT EXISTS approval_request_requested_by_idx
  ON public.approval_request (requested_by_user_id) WHERE requested_by_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS approval_request_decided_by_idx
  ON public.approval_request (decided_by) WHERE decided_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS approval_request_revoked_by_idx
  ON public.approval_request (revoked_by) WHERE revoked_by IS NOT NULL;

-- =====================================================================
-- 2. RLS and Data API grants (ADR-303)
-- =====================================================================
-- Owner SELECT only. NO INSERT/UPDATE/DELETE policy and no write grant: every write is an approval RPC.
-- The api roles are revoked explicitly (Supabase default privileges would otherwise re-grant) and the one
-- intended surface is granted back: authenticated SELECT (the landing page reads the row through RLS).
-- service_role holds NO table privilege: it reaches the table only through the RPCs.

ALTER TABLE public.approval_request ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.approval_request FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.approval_request TO authenticated;

DROP POLICY IF EXISTS approval_request_owner_select ON public.approval_request;
CREATE POLICY approval_request_owner_select ON public.approval_request
  FOR SELECT TO authenticated
  USING (
    public.is_workspace_owner(workspace_id, auth.uid())
  );

-- RESTRICTIVE jti-deny (068/126 shape): a revoked-but-unexpired JWT is refused at the policy boundary.
DROP POLICY IF EXISTS approval_request_jti_not_denied ON public.approval_request;
CREATE POLICY approval_request_jti_not_denied ON public.approval_request
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT public.is_jti_denied_from_jwt())
  WITH CHECK (NOT public.is_jti_denied_from_jwt());

-- =====================================================================
-- 3. Write-once / forward-only guard trigger
-- =====================================================================
-- Allowed-write matrix:
--   INSERT  : only through an approval RPC (GUC app.approval_rpc = 'on'), status 'pending', undecided.
--   UPDATE  : (a) the Art. 17 SET NULL cascade of requested_by_user_id / decided_by / revoked_by (no GUC: it runs
--                 inside GoTrue's transaction), bound to an actually-deleted parent user and to every other column
--                 unchanged (to_jsonb-minus compare, drift-proof, mig 162 shape);
--             (b) the text scrub / anonymise path (GUC app.approval_scrub = 'on'): canonical_action -> NULL (terminal
--                 rows only) and the three user columns -> NULL, every other column unchanged;
--             (c) a state transition through an approval RPC (GUC app.approval_rpc = 'on') obeying the matrix below.
--   DELETE  : (i) the workspace-cascade (parent workspace already gone); (ii) the Art. 17 erasure of a personal
--                 workspace: GUC app.approval_erase = 'on' (set only inside anonymise_approval_request) AND no
--                 workspace_members row left for OLD.workspace_id. Never otherwise.
-- Terminal states (rejected, expired, consumed) have no outgoing transition. The only non-forward step is the
-- Owner revoke, approved -> rejected, which sets revoked_at/revoked_by once and only on an unconsumed row.

CREATE OR REPLACE FUNCTION public.approval_request_guard()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_rpc   boolean := COALESCE(current_setting('app.approval_rpc', true), '') = 'on';
  v_scrub boolean := COALESCE(current_setting('app.approval_scrub', true), '') = 'on';
  v_erase boolean := COALESCE(current_setting('app.approval_erase', true), '') = 'on';
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NOT v_rpc THEN
      RAISE EXCEPTION 'approval_request: writes go through the approval RPCs; INSERT rejected' USING ERRCODE = 'P0001';
    END IF;
    IF NEW.status <> 'pending' OR NEW.decided_at IS NOT NULL OR NEW.decided_by IS NOT NULL
       OR NEW.consumed_at IS NOT NULL OR NEW.expired_at IS NOT NULL OR NEW.unanswered_flagged_at IS NOT NULL
       OR NEW.revoked_at IS NOT NULL OR NEW.revoked_by IS NOT NULL THEN
      RAISE EXCEPTION 'approval_request: a new request must be pending and undecided' USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    -- Workspace-cascade carve-out: the RI action fires after the parent workspace row is gone.
    IF NOT EXISTS (SELECT 1 FROM public.workspaces WHERE id = OLD.workspace_id) THEN
      RETURN OLD;
    END IF;
    -- Art. 17 erasure of a personal workspace (anonymise_approval_request only): the GUC is set only inside that
    -- function and the workspace must have no member left, so a team workspace's history can never be deleted here.
    IF v_erase
       AND NOT EXISTS (SELECT 1 FROM public.workspace_members WHERE workspace_id = OLD.workspace_id) THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'approval_request: DELETE rejected' USING ERRCODE = 'P0001';
  END IF;

  -- UPDATE ------------------------------------------------------------------------------------------------------
  -- (a) Art. 17 SET NULL cascade carve-out (no GUC). Cheap column checks first; the jsonb compare last.
  IF (NEW.requested_by_user_id IS DISTINCT FROM OLD.requested_by_user_id
      OR NEW.decided_by IS DISTINCT FROM OLD.decided_by
      OR NEW.revoked_by IS DISTINCT FROM OLD.revoked_by)
     AND (NEW.requested_by_user_id IS NOT DISTINCT FROM OLD.requested_by_user_id
          OR (OLD.requested_by_user_id IS NOT NULL AND NEW.requested_by_user_id IS NULL
              AND NOT EXISTS (SELECT 1 FROM public.users WHERE id = OLD.requested_by_user_id)))
     AND (NEW.decided_by IS NOT DISTINCT FROM OLD.decided_by
          OR (OLD.decided_by IS NOT NULL AND NEW.decided_by IS NULL
              AND NOT EXISTS (SELECT 1 FROM public.users WHERE id = OLD.decided_by)))
     AND (NEW.revoked_by IS NOT DISTINCT FROM OLD.revoked_by
          OR (OLD.revoked_by IS NOT NULL AND NEW.revoked_by IS NULL
              AND NOT EXISTS (SELECT 1 FROM public.users WHERE id = OLD.revoked_by)))
     AND (to_jsonb(NEW) - 'requested_by_user_id' - 'decided_by' - 'revoked_by')
         = (to_jsonb(OLD) - 'requested_by_user_id' - 'decided_by' - 'revoked_by')
  THEN
    RETURN NEW;
  END IF;

  -- (b) Text scrub / anonymise path (GUC-gated).
  IF v_scrub
     AND (NEW.canonical_action IS NOT DISTINCT FROM OLD.canonical_action
          OR (NEW.canonical_action IS NULL AND OLD.status IN ('rejected', 'expired', 'consumed')))
     AND (NEW.requested_by_user_id IS NOT DISTINCT FROM OLD.requested_by_user_id OR NEW.requested_by_user_id IS NULL)
     AND (NEW.decided_by IS NOT DISTINCT FROM OLD.decided_by OR NEW.decided_by IS NULL)
     AND (NEW.revoked_by IS NOT DISTINCT FROM OLD.revoked_by OR NEW.revoked_by IS NULL)
     AND (to_jsonb(NEW) - 'canonical_action' - 'requested_by_user_id' - 'decided_by' - 'revoked_by')
         = (to_jsonb(OLD) - 'canonical_action' - 'requested_by_user_id' - 'decided_by' - 'revoked_by')
  THEN
    RETURN NEW;
  END IF;

  -- (c) State transition through an approval RPC.
  IF NOT v_rpc THEN
    RAISE EXCEPTION 'approval_request: writes go through the approval RPCs; UPDATE rejected' USING ERRCODE = 'P0001';
  END IF;

  -- Identity columns are write-once.
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.workspace_id IS DISTINCT FROM OLD.workspace_id
     OR NEW.conversation_id IS DISTINCT FROM OLD.conversation_id
     OR NEW.tool_name IS DISTINCT FROM OLD.tool_name
     OR NEW.action_sha256 IS DISTINCT FROM OLD.action_sha256
     OR NEW.expires_at IS DISTINCT FROM OLD.expires_at
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.requested_by_user_id IS DISTINCT FROM OLD.requested_by_user_id
     OR NEW.canonical_action IS DISTINCT FROM OLD.canonical_action THEN
    RAISE EXCEPTION 'approval_request: write-once column changed' USING ERRCODE = 'P0001';
  END IF;

  -- Status machine: forward-only, plus the Owner revoke (approved -> rejected).
  IF NEW.status IS DISTINCT FROM OLD.status
     AND (OLD.status, NEW.status) NOT IN (
       ('pending', 'approved'),
       ('pending', 'rejected'),
       ('pending', 'expired'),
       ('approved', 'consumed'),
       ('approved', 'expired'),
       ('approved', 'rejected')
     ) THEN
    RAISE EXCEPTION 'approval_request: illegal status transition % -> %', OLD.status, NEW.status USING ERRCODE = 'P0001';
  END IF;

  -- decided_at / decided_by are set once, together with a pending -> approved|rejected transition.
  IF OLD.decided_at IS NOT NULL AND (NEW.decided_at IS DISTINCT FROM OLD.decided_at OR NEW.decided_by IS DISTINCT FROM OLD.decided_by) THEN
    RAISE EXCEPTION 'approval_request: decision is write-once' USING ERRCODE = 'P0001';
  END IF;
  IF OLD.decided_at IS NULL AND (NEW.decided_at IS NOT NULL OR NEW.decided_by IS NOT NULL) THEN
    IF OLD.status <> 'pending' OR NEW.status NOT IN ('approved', 'rejected')
       OR NEW.decided_at IS NULL OR NEW.decided_by IS NULL THEN
      RAISE EXCEPTION 'approval_request: a decision is recorded only with pending -> approved|rejected' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- revoked_at / revoked_by are set once, together, and only with approved -> rejected; that transition requires them.
  IF (NEW.revoked_at IS DISTINCT FROM OLD.revoked_at OR NEW.revoked_by IS DISTINCT FROM OLD.revoked_by)
     AND (OLD.revoked_at IS NOT NULL OR OLD.status <> 'approved' OR NEW.status <> 'rejected'
          OR NEW.revoked_at IS NULL OR NEW.revoked_by IS NULL) THEN
    RAISE EXCEPTION 'approval_request: revoked_at/revoked_by are write-once with approved -> rejected' USING ERRCODE = 'P0001';
  END IF;
  IF OLD.status = 'approved' AND NEW.status = 'rejected' AND (NEW.revoked_at IS NULL OR NEW.revoked_by IS NULL) THEN
    RAISE EXCEPTION 'approval_request: a revoke records revoked_at and revoked_by' USING ERRCODE = 'P0001';
  END IF;

  -- consumed_at / expired_at are set once with their own transition.
  IF NEW.consumed_at IS DISTINCT FROM OLD.consumed_at
     AND (OLD.consumed_at IS NOT NULL OR OLD.status <> 'approved' OR NEW.status <> 'consumed') THEN
    RAISE EXCEPTION 'approval_request: consumed_at is write-once with approved -> consumed' USING ERRCODE = 'P0001';
  END IF;
  IF NEW.expired_at IS DISTINCT FROM OLD.expired_at
     AND (OLD.expired_at IS NOT NULL OR NEW.status <> 'expired') THEN
    RAISE EXCEPTION 'approval_request: expired_at is write-once with the expiry transition' USING ERRCODE = 'P0001';
  END IF;

  -- unanswered_flagged_at: set once, only while the request is still pending.
  IF NEW.unanswered_flagged_at IS DISTINCT FROM OLD.unanswered_flagged_at
     AND (OLD.unanswered_flagged_at IS NOT NULL OR OLD.status <> 'pending' OR NEW.status <> 'pending') THEN
    RAISE EXCEPTION 'approval_request: unanswered_flagged_at is write-once and only while pending' USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION public.approval_request_guard()
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.approval_request_guard() IS
  'Write-once, forward-only guard for approval_request (#4672). INSERT and state changes only through the approval '
  'RPCs (app.approval_rpc); text scrub only through app.approval_scrub; Art. 17 SET NULL cascade and workspace-cascade '
  'DELETE carve-outs bound to an already-deleted parent (mig 162 shape); the personal-workspace erasure DELETE only '
  'under app.approval_erase with no member left.';

DROP TRIGGER IF EXISTS approval_request_guard ON public.approval_request;
CREATE TRIGGER approval_request_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.approval_request
  FOR EACH ROW
  EXECUTE FUNCTION public.approval_request_guard();

-- =====================================================================
-- 4. inbox_item.source widening (ADR-085 reserved approval_required for #4672)
-- =====================================================================
-- The whole migration runs in ONE transaction (run-migrations.sh), so the ACCESS EXCLUSIVE lock taken by the ADD
-- CONSTRAINT is held through the VALIDATE scan; inbox_item is small, so the stall is short. NOT VALID + VALIDATE is
-- kept so the validation is a separate, explicit step, not to shorten the lock.
-- The CHECK is not found by NAME: EVERY CHECK on inbox_item that references `source` is dropped (a differently named
-- legacy CHECK would otherwise keep rejecting approval_required), then the one widened CHECK is added.

DO $$
DECLARE
  c record;
BEGIN
  FOR c IN
    SELECT conname
      FROM pg_constraint
     WHERE conrelid = 'public.inbox_item'::regclass
       AND contype = 'c'
       AND pg_get_constraintdef(oid) ~ '\ysource\y'
  LOOP
    EXECUTE format('ALTER TABLE public.inbox_item DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

ALTER TABLE public.inbox_item
  ADD CONSTRAINT inbox_item_source_check
  CHECK (source IN ('task_completed', 'system', 'approval_required'))
  NOT VALID;
ALTER TABLE public.inbox_item VALIDATE CONSTRAINT inbox_item_source_check;

-- =====================================================================
-- 5. Internal helper: settle the linked inbox item
-- =====================================================================
-- Called only by the definer RPCs below (nobody else has EXECUTE). 'acted' = the Owner decided (out of the
-- action_required count, acted_at is the single global resolution signal); 'fyi' = the request expired
-- (demoted to an info row; the 90 day inbox retention then applies). The lookup is by (workspace_id, dedup_key) so it
-- uses the inbox_item_dedup_key_uniq index.

CREATE OR REPLACE FUNCTION public.approval_request_inbox_settle(p_workspace_id uuid, p_approval_id uuid, p_mode text)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_mode = 'acted' THEN
    UPDATE public.inbox_item
       SET acted_at = COALESCE(acted_at, now()),
           read_at  = COALESCE(read_at, now()),
           status   = CASE WHEN status = 'archived' THEN status ELSE 'read' END
     WHERE workspace_id = p_workspace_id
       AND source = 'approval_required'
       AND dedup_key = p_approval_id::text;
  ELSIF p_mode = 'fyi' THEN
    UPDATE public.inbox_item
       SET severity = 'info'
     WHERE workspace_id = p_workspace_id
       AND source = 'approval_required'
       AND dedup_key = p_approval_id::text
       AND severity = 'action_required';
  ELSE
    RAISE EXCEPTION 'approval_request_inbox_settle: invalid mode' USING ERRCODE = '22023';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.approval_request_inbox_settle(uuid, uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;

-- =====================================================================
-- 6. create_approval_request (service_role)
-- =====================================================================
-- Idempotent on the live unique index. Writes the inbox item in the SAME transaction (content-free title; ids only
-- in source_ref). Returns {approval, created, request_count, notify, expires_at}. A live row that is overdue is
-- expired first, so an expired-but-unswept row can never wedge the unique index.
-- Caps (pending, unexpired rows only; an idempotent re-ask of an existing live request is exempt): 5 per
-- conversation (AP429) and 20 per workspace (AP430). A bound, not an invariant: a concurrent race can overshoot by
-- at most the in-process pending-gate limit; no advisory lock.
-- `notify` is true only for a NEW request when no other pending request of the workspace was created in the last
-- 10 minutes (the card and the inbox row are always created; only the push/email nudge is coalesced).

CREATE OR REPLACE FUNCTION public.create_approval_request(
  p_workspace_id uuid,
  p_conversation_id uuid,
  p_requested_by uuid,
  p_tool_name text,
  p_action_sha256 text,
  p_canonical_action jsonb,
  p_ttl_seconds integer DEFAULT 86400
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_conv    record;
  v_row     public.approval_request%ROWTYPE;
  v_created boolean := false;
  v_notify  boolean := false;
  v_count   bigint;
  v_stale   record;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'approval: service role only' USING ERRCODE = '42501';
  END IF;
  PERFORM set_config('app.approval_rpc', 'on', true);

  IF p_action_sha256 IS NULL OR p_action_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'approval: invalid action hash' USING ERRCODE = '22023';
  END IF;
  IF p_canonical_action IS NULL OR jsonb_typeof(p_canonical_action) <> 'object' THEN
    RAISE EXCEPTION 'approval: canonical action must be a json object' USING ERRCODE = '22023';
  END IF;
  IF p_ttl_seconds IS NULL OR p_ttl_seconds < 60 OR p_ttl_seconds > 172800 THEN
    RAISE EXCEPTION 'approval: ttl out of range' USING ERRCODE = '22023';
  END IF;

  SELECT c.workspace_id, c.archived_at INTO v_conv
    FROM public.conversations c
   WHERE c.id = p_conversation_id;
  IF NOT FOUND OR v_conv.workspace_id IS DISTINCT FROM p_workspace_id THEN
    RAISE EXCEPTION 'approval: conversation not found in workspace' USING ERRCODE = '22023';
  END IF;
  IF v_conv.archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'approval: conversation closed' USING ERRCODE = 'P0001';
  END IF;
  IF NOT public.is_workspace_member(p_workspace_id, p_requested_by) THEN
    RAISE EXCEPTION 'approval: requester is not a workspace member' USING ERRCODE = '42501';
  END IF;

  -- Expire an overdue live request for the same action so it cannot block the unique index.
  FOR v_stale IN
    UPDATE public.approval_request
       SET status = 'expired', expired_at = now()
     WHERE conversation_id = p_conversation_id
       AND action_sha256 = p_action_sha256
       AND status IN ('pending', 'approved')
       AND expires_at <= now()
    RETURNING id, workspace_id
  LOOP
    PERFORM public.approval_request_inbox_settle(v_stale.workspace_id, v_stale.id, 'fyi');
  END LOOP;

  -- Pending caps, only for a request that would be NEW (no live row for this exact action).
  IF NOT EXISTS (
    SELECT 1 FROM public.approval_request
     WHERE conversation_id = p_conversation_id
       AND action_sha256 = p_action_sha256
       AND status IN ('pending', 'approved')
  ) THEN
    IF (SELECT count(*) FROM public.approval_request
         WHERE conversation_id = p_conversation_id AND status = 'pending' AND expires_at > now()) >= 5 THEN
      RAISE EXCEPTION 'approval: too many pending requests' USING ERRCODE = 'AP429';
    END IF;
    IF (SELECT count(*) FROM public.approval_request
         WHERE workspace_id = p_workspace_id AND status = 'pending' AND expires_at > now()) >= 20 THEN
      RAISE EXCEPTION 'approval: too many pending requests' USING ERRCODE = 'AP430';
    END IF;
  END IF;

  INSERT INTO public.approval_request
    (workspace_id, requested_by_user_id, conversation_id, tool_name, action_sha256, canonical_action, status, expires_at)
  VALUES
    (p_workspace_id, p_requested_by, p_conversation_id, p_tool_name, p_action_sha256, p_canonical_action,
     'pending', now() + make_interval(secs => p_ttl_seconds))
  ON CONFLICT (conversation_id, action_sha256) WHERE status IN ('pending', 'approved') DO NOTHING
  RETURNING * INTO v_row;

  IF FOUND THEN
    v_created := true;
    -- Content-free by design (ADR-085): a static title and ids only. The deep link is built at render.
    INSERT INTO public.inbox_item (workspace_id, user_id, severity, source, title, source_ref, dedup_key)
    VALUES (p_workspace_id, NULL, 'action_required', 'approval_required', 'An action needs your approval',
            jsonb_build_object('approvalId', v_row.id, 'conversationId', p_conversation_id), v_row.id::text)
    ON CONFLICT (workspace_id, dedup_key) WHERE dedup_key IS NOT NULL DO NOTHING;

    v_notify := NOT EXISTS (
      SELECT 1 FROM public.approval_request x
       WHERE x.workspace_id = p_workspace_id
         AND x.status = 'pending'
         AND x.id <> v_row.id
         AND x.created_at > now() - interval '10 minutes'
    );
  ELSE
    SELECT * INTO v_row
      FROM public.approval_request
     WHERE conversation_id = p_conversation_id
       AND action_sha256 = p_action_sha256
       AND status IN ('pending', 'approved');
    IF NOT FOUND THEN
      -- The live row changed state between the conflict and the read (a concurrent consume or expiry): retry.
      RAISE EXCEPTION 'approval: concurrent change, retry' USING ERRCODE = '40001';
    END IF;
  END IF;

  SELECT count(*) INTO v_count
    FROM public.approval_request
   WHERE conversation_id = p_conversation_id
     AND action_sha256 = p_action_sha256;

  RETURN jsonb_build_object('approval', to_jsonb(v_row), 'created', v_created, 'request_count', v_count,
                            'notify', v_notify, 'expires_at', v_row.expires_at);
END;
$$;

REVOKE ALL ON FUNCTION public.create_approval_request(uuid, uuid, uuid, text, text, jsonb, integer)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_approval_request(uuid, uuid, uuid, text, text, jsonb, integer)
  TO service_role;

-- =====================================================================
-- 7. decide_approval (authenticated; actor = auth.uid())
-- =====================================================================
-- Outcomes: decided | unchanged (the SAME decider repeats the SAME decision) | already_decided (a DIFFERENT Owner
-- repeats the decision already recorded) | conflict (the opposite decision is already recorded, or the request was
-- already used; the current row is returned: the loser of a two-Owner race) | revoked (an Owner denied an APPROVED,
-- unconsumed request: approved -> rejected) | expired (overdue; flipped inline, never recorded as approved: the cron
-- is the backstop, not the authority) | closed (conversation archived or gone, PENDING requests only; nothing
-- recorded). Missing row and non-owner raise the SAME error (no existence oracle); the Owner check runs BEFORE the
-- row lock, so a non-owner holding an approval id can never lock the row.

CREATE OR REPLACE FUNCTION public.decide_approval(
  p_id uuid,
  p_decision text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_row    public.approval_request%ROWTYPE;
  v_ws     uuid;
  v_ok     boolean;
  v_closed boolean;
  v_same   boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'approval: authenticated callers only' USING ERRCODE = '42501';
  END IF;
  IF public.is_jti_denied_from_jwt() THEN
    RAISE EXCEPTION 'approval: token denied' USING ERRCODE = '42501';
  END IF;
  IF p_decision IS NULL OR p_decision NOT IN ('approve', 'deny') THEN
    RAISE EXCEPTION 'approval: invalid decision' USING ERRCODE = '22023';
  END IF;
  PERFORM set_config('app.approval_rpc', 'on', true);

  -- Owner check first, WITHOUT a lock: the same error for a missing row and a non-owner; the Owner role is
  -- re-checked at decision time (an Owner who left or lost the role is refused).
  SELECT workspace_id INTO v_ws FROM public.approval_request WHERE id = p_id;
  v_ok := FOUND AND COALESCE(public.is_workspace_owner(v_ws, auth.uid()), false);
  IF NOT v_ok THEN
    RAISE EXCEPTION 'approval: not authorized' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row FROM public.approval_request WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'approval: concurrent change, retry' USING ERRCODE = '40001';
  END IF;

  -- Already expired (by the sweep or an earlier overdue flip), including an approved-then-expired row.
  IF v_row.status = 'expired' THEN
    RETURN jsonb_build_object('outcome', 'expired', 'approval', to_jsonb(v_row) - 'canonical_action');
  END IF;

  -- Overdue live row (pending or approved): flip to expired inline; never record or keep an overdue approval.
  IF v_row.status IN ('pending', 'approved') AND v_row.expires_at <= now() THEN
    UPDATE public.approval_request
       SET status = 'expired', expired_at = now()
     WHERE id = v_row.id
    RETURNING * INTO v_row;
    PERFORM public.approval_request_inbox_settle(v_row.workspace_id, v_row.id, 'fyi');
    RETURN jsonb_build_object('outcome', 'expired', 'approval', to_jsonb(v_row) - 'canonical_action');
  END IF;

  -- Already used: no decision can change it.
  IF v_row.status = 'consumed' THEN
    RETURN jsonb_build_object('outcome', 'conflict', 'approval', to_jsonb(v_row) - 'canonical_action');
  END IF;

  -- Already denied (or revoked): idempotent for a repeated deny, a conflict for an approve.
  IF v_row.status = 'rejected' THEN
    v_same := p_decision = 'deny';
    RETURN jsonb_build_object(
      'outcome', CASE
                   WHEN NOT v_same THEN 'conflict'
                   WHEN COALESCE(v_row.revoked_by, v_row.decided_by) IS NOT DISTINCT FROM auth.uid() THEN 'unchanged'
                   ELSE 'already_decided'
                 END,
      'approval', to_jsonb(v_row) - 'canonical_action');
  END IF;

  -- Approved and unconsumed: a repeated approve is idempotent; a deny REVOKES the approval (approved -> rejected).
  -- The closed-conversation refusal below does not apply: withdrawing an approval only reduces authority.
  IF v_row.status = 'approved' THEN
    IF p_decision = 'approve' THEN
      RETURN jsonb_build_object(
        'outcome', CASE WHEN v_row.decided_by IS NOT DISTINCT FROM auth.uid() THEN 'unchanged' ELSE 'already_decided' END,
        'approval', to_jsonb(v_row) - 'canonical_action');
    END IF;
    UPDATE public.approval_request
       SET status = 'rejected', revoked_at = now(), revoked_by = auth.uid()
     WHERE id = v_row.id
       AND status = 'approved'
    RETURNING * INTO v_row;
    IF NOT FOUND THEN
      -- Lost the race to a consume (cannot happen under the row lock; kept as the safe reading).
      SELECT * INTO v_row FROM public.approval_request WHERE id = p_id;
      RETURN jsonb_build_object('outcome', 'conflict', 'approval', to_jsonb(v_row) - 'canonical_action');
    END IF;
    -- The inbox item was already settled by the approve; nothing to repeat.
    RETURN jsonb_build_object('outcome', 'revoked', 'approval', to_jsonb(v_row) - 'canonical_action');
  END IF;

  -- Pending. A closed (archived or deleted) conversation refuses the decision and records nothing.
  SELECT (c.archived_at IS NOT NULL) INTO v_closed
    FROM public.conversations c
   WHERE c.id = v_row.conversation_id;
  IF NOT FOUND OR v_closed THEN
    RETURN jsonb_build_object('outcome', 'closed', 'approval', to_jsonb(v_row) - 'canonical_action');
  END IF;

  UPDATE public.approval_request
     SET status = CASE WHEN p_decision = 'approve' THEN 'approved' ELSE 'rejected' END,
         decided_by = auth.uid(),
         decided_at = now()
   WHERE id = v_row.id
     AND status = 'pending'
  RETURNING * INTO v_row;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'approval: concurrent change, retry' USING ERRCODE = '40001';
  END IF;

  PERFORM public.approval_request_inbox_settle(v_row.workspace_id, v_row.id, 'acted');

  RETURN jsonb_build_object('outcome', 'decided', 'approval', to_jsonb(v_row) - 'canonical_action');
END;
$$;

REVOKE ALL ON FUNCTION public.decide_approval(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.decide_approval(uuid, text)
  TO authenticated;

-- =====================================================================
-- 8. consume_approval (service_role): the single place an approval becomes a release
-- =====================================================================
-- One atomic conditional UPDATE. Besides status/expiry/hash/conversation, the PRINCIPALS are re-checked inside the
-- same statement (cannot be raced): the decider must STILL be an Owner and the requester STILL a member of the
-- workspace. An erased user (NULL column) makes the predicate false, so the row is not consumable (fail closed).
-- The reason on a miss is derived by a second, NON-authoritative read.

CREATE OR REPLACE FUNCTION public.consume_approval(
  p_id uuid,
  p_hash text,
  p_conversation uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_id  uuid;
  v_row public.approval_request%ROWTYPE;
  v_reason text;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'approval: service role only' USING ERRCODE = '42501';
  END IF;
  PERFORM set_config('app.approval_rpc', 'on', true);

  UPDATE public.approval_request
     SET status = 'consumed', consumed_at = now()
   WHERE id = p_id
     AND status = 'approved'
     AND expires_at > now()
     AND action_sha256 = p_hash
     AND conversation_id = p_conversation
     AND public.is_workspace_owner(workspace_id, decided_by)
     AND public.is_workspace_member(workspace_id, requested_by_user_id)
  RETURNING id INTO v_id;

  IF v_id IS NOT NULL THEN
    RETURN jsonb_build_object('consumed', true, 'reason', 'ok');
  END IF;

  SELECT * INTO v_row FROM public.approval_request WHERE id = p_id;
  v_reason := CASE
    WHEN NOT FOUND THEN 'not_found'
    WHEN v_row.status = 'consumed' THEN 'already_consumed'
    WHEN v_row.status <> 'approved' THEN 'not_approved'
    WHEN v_row.expires_at <= now() THEN 'expired'
    WHEN NOT COALESCE(public.is_workspace_owner(v_row.workspace_id, v_row.decided_by), false) THEN 'decider_not_owner'
    WHEN NOT COALESCE(public.is_workspace_member(v_row.workspace_id, v_row.requested_by_user_id), false) THEN 'requester_not_member'
    WHEN v_row.conversation_id IS DISTINCT FROM p_conversation THEN 'wrong_conversation'
    WHEN v_row.action_sha256 IS DISTINCT FROM p_hash THEN 'hash_mismatch'
    ELSE 'unknown'
  END;
  RETURN jsonb_build_object('consumed', false, 'reason', v_reason);
END;
$$;

REVOKE ALL ON FUNCTION public.consume_approval(uuid, text, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.consume_approval(uuid, text, uuid)
  TO service_role;

-- =====================================================================
-- 9. get_approval_status / list_live_approvals (service_role reads)
-- =====================================================================
-- get_approval_status returns a fixed scalar projection (no action text, no user ids), not to_jsonb of the whole row:
-- the gate polls it on a timer.

CREATE OR REPLACE FUNCTION public.get_approval_status(p_id uuid)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.approval_request%ROWTYPE;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'approval: service role only' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_row FROM public.approval_request WHERE id = p_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object(
    'id', v_row.id,
    'workspace_id', v_row.workspace_id,
    'conversation_id', v_row.conversation_id,
    'tool_name', v_row.tool_name,
    'action_sha256', v_row.action_sha256,
    'status', v_row.status,
    'expires_at', v_row.expires_at,
    'decided_at', v_row.decided_at,
    'consumed_at', v_row.consumed_at,
    'expired_at', v_row.expired_at,
    'revoked_at', v_row.revoked_at,
    'unanswered_flagged_at', v_row.unanswered_flagged_at,
    'created_at', v_row.created_at);
END;
$$;

REVOKE ALL ON FUNCTION public.get_approval_status(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_approval_status(uuid)
  TO service_role;

-- Live (pending or approved, unexpired) requests of one conversation, for the card re-send on session attach.
CREATE OR REPLACE FUNCTION public.list_live_approvals(p_conversation uuid)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'approval: service role only' USING ERRCODE = '42501';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(
             jsonb_build_object(
               'approval', to_jsonb(a),
               'request_count', (SELECT count(*) FROM public.approval_request x
                                  WHERE x.conversation_id = a.conversation_id AND x.action_sha256 = a.action_sha256))
             ORDER BY a.created_at)
      FROM public.approval_request a
     WHERE a.conversation_id = p_conversation
       AND a.status IN ('pending', 'approved')
       AND a.expires_at > now()
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.list_live_approvals(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_live_approvals(uuid)
  TO service_role;

-- =====================================================================
-- 10. sweep_approvals (service_role; one 5-minute cron step)
-- =====================================================================
-- (1) expire due live rows (an approved row past expiry becomes expired with decided_at kept = 'unconsumed'),
-- (2) flag pending rows older than 15 minutes ONCE (unanswered_flagged_at), (3) null canonical_action 30 days after
-- the terminal state. Every step is a conditional UPDATE guarded by a write-once marker, so a second run finds
-- nothing. Steps (1) and (2) are bounded to 500 rows and the scrub (3) to 500 rows per call (index-driven,
-- approval_request_scrub_idx); a backlog is finished by the following ticks. Returns the rows the cron must notify
-- about and the number of rows scrubbed.

CREATE OR REPLACE FUNCTION public.sweep_approvals()
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_expired  jsonb := '[]'::jsonb;
  v_flagged  jsonb := '[]'::jsonb;
  v_scrubbed integer := 0;
  r record;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'approval: service role only' USING ERRCODE = '42501';
  END IF;
  PERFORM set_config('app.approval_rpc', 'on', true);

  FOR r IN
    WITH due AS (
      SELECT id FROM public.approval_request
       WHERE status IN ('pending', 'approved') AND expires_at <= now()
       ORDER BY expires_at
       LIMIT 500
       FOR UPDATE SKIP LOCKED
    ), done AS (
      UPDATE public.approval_request a
         SET status = 'expired', expired_at = now()
        FROM due
       WHERE a.id = due.id
      RETURNING a.id, a.workspace_id, a.tool_name, a.decided_at
    )
    SELECT * FROM done
  LOOP
    PERFORM public.approval_request_inbox_settle(r.workspace_id, r.id, 'fyi');
    v_expired := v_expired || jsonb_build_object(
      'id', r.id, 'workspace_id', r.workspace_id, 'tool_name', r.tool_name,
      'reason', CASE WHEN r.decided_at IS NULL THEN 'unanswered' ELSE 'unconsumed' END);
  END LOOP;

  FOR r IN
    WITH due AS (
      SELECT id FROM public.approval_request
       WHERE status = 'pending' AND unanswered_flagged_at IS NULL
         AND created_at < now() - interval '15 minutes'
       ORDER BY created_at
       LIMIT 500
       FOR UPDATE SKIP LOCKED
    ), done AS (
      UPDATE public.approval_request a
         SET unanswered_flagged_at = now()
        FROM due
       WHERE a.id = due.id
      RETURNING a.id, a.workspace_id, a.tool_name
    )
    SELECT * FROM done
  LOOP
    v_flagged := v_flagged || jsonb_build_object('id', r.id, 'workspace_id', r.workspace_id, 'tool_name', r.tool_name);
  END LOOP;

  PERFORM set_config('app.approval_scrub', 'on', true);
  UPDATE public.approval_request
     SET canonical_action = NULL
   WHERE id IN (
     SELECT id FROM public.approval_request
      WHERE canonical_action IS NOT NULL
        AND status IN ('rejected', 'expired', 'consumed')
        AND COALESCE(consumed_at, expired_at, revoked_at, decided_at) < now() - interval '30 days'
      ORDER BY COALESCE(consumed_at, expired_at, revoked_at, decided_at)
      LIMIT 500
      FOR UPDATE SKIP LOCKED
   );
  GET DIAGNOSTICS v_scrubbed = ROW_COUNT;
  PERFORM set_config('app.approval_scrub', 'off', true);

  RETURN jsonb_build_object('expired', v_expired, 'flagged', v_flagged, 'scrubbed', v_scrubbed);
END;
$$;

REVOKE ALL ON FUNCTION public.sweep_approvals()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.sweep_approvals()
  TO service_role;

-- =====================================================================
-- 11. anonymise_approval_request (service_role; Art. 17, called from account-delete step 5.16)
-- =====================================================================
-- Expires the user's live requests, then nulls the user's side of every row: requested_by_user_id and the action
-- text where the user was the requester; decided_by / revoked_by where the user was the decider / revoker.
-- Then, ONLY when the workspace whose id equals the user's id (the personal workspace; the workspace row survives
-- erasure by design, so the table's cascade never fires for it) has NO member left (the saga's step 5.7 has already
-- removed the membership), DELETES every approval_request row of that workspace and its approval_required inbox
-- rows. A workspace that still has members keeps its record. The delete is admitted by the guard trigger only under
-- app.approval_erase with a memberless workspace. Returns the number of rows touched or deleted.

CREATE OR REPLACE FUNCTION public.anonymise_approval_request(p_user_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  affected integer;
  deleted  integer := 0;
  v_stale  record;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'approval: service role only' USING ERRCODE = '42501';
  END IF;
  PERFORM set_config('app.approval_rpc', 'on', true);

  FOR v_stale IN
    UPDATE public.approval_request
       SET status = 'expired', expired_at = now()
     WHERE requested_by_user_id = p_user_id
       AND status IN ('pending', 'approved')
    RETURNING id, workspace_id
  LOOP
    PERFORM public.approval_request_inbox_settle(v_stale.workspace_id, v_stale.id, 'fyi');
  END LOOP;

  PERFORM set_config('app.approval_scrub', 'on', true);
  UPDATE public.approval_request
     SET requested_by_user_id = CASE WHEN requested_by_user_id = p_user_id THEN NULL ELSE requested_by_user_id END,
         decided_by           = CASE WHEN decided_by = p_user_id THEN NULL ELSE decided_by END,
         revoked_by           = CASE WHEN revoked_by = p_user_id THEN NULL ELSE revoked_by END,
         canonical_action     = CASE WHEN requested_by_user_id = p_user_id THEN NULL ELSE canonical_action END
   WHERE requested_by_user_id = p_user_id
      OR decided_by = p_user_id
      OR revoked_by = p_user_id;
  GET DIAGNOSTICS affected = ROW_COUNT;
  PERFORM set_config('app.approval_scrub', 'off', true);

  IF NOT EXISTS (SELECT 1 FROM public.workspace_members WHERE workspace_id = p_user_id) THEN
    PERFORM set_config('app.approval_erase', 'on', true);
    DELETE FROM public.approval_request WHERE workspace_id = p_user_id;
    GET DIAGNOSTICS deleted = ROW_COUNT;
    PERFORM set_config('app.approval_erase', 'off', true);
    DELETE FROM public.inbox_item WHERE workspace_id = p_user_id AND source = 'approval_required';
  END IF;

  RETURN affected + deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_approval_request(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.anonymise_approval_request(uuid)
  TO service_role;
