-- 099_bash_autonomous_default_on_and_ack.sql
-- feat: Concierge Autonomous mode ON by default + first-run consent ack.
--
-- TWO concerns, both authz-relevant on a code-executing surface:
--
--   1. DEFAULT FLIP (forward-only). Flip workspaces.bash_autonomous column
--      DEFAULT false -> true so NEW workspaces are autonomous by construction.
--      The workspace-creation trigger (091:165) INSERTs without naming the
--      column, so flipping the column DEFAULT is SUFFICIENT — we do NOT
--      re-CREATE OR REPLACE that function (avoids re-deriving the 091 rename
--      logic).
--
--      ** NO bulk write to the toggle column ANYWHERE IN THIS MIGRATION. **
--      A bulk row-rewrite would silently enable auto-execution on workspaces
--      whose owners never consented — the GDPR/expectation violation this
--      consent model exists to avoid. Existing rows stored `false` STAY
--      `false`; even new default-ON workspaces are soft-gated on first auto-run
--      (the ack below is the consent record).
--
--   2. CONSENT ACK. Add workspaces.autonomous_disclosure_ack_at (nullable,
--      NULL = not yet acked = HOLD the first auto-run) plus member-read /
--      owner-write RPCs that are a VERBATIM STRUCTURAL MIRROR of 097's
--      get/set_workspace_bash_autonomous: SECURITY DEFINER, search_path pinned
--      to `public, pg_temp` (cq-pg-security-definer-search-path-pin-pg-temp),
--      REVOKE'd from PUBLIC/anon/authenticated/service_role, GRANT'd to
--      authenticated only, owner check via the R8 composite-key EXISTS pattern.

-- 1. DEFAULT FLIP (forward-only — no row-rewrite).
ALTER TABLE public.workspaces
  ALTER COLUMN bash_autonomous SET DEFAULT true;

COMMENT ON COLUMN public.workspaces.bash_autonomous IS
  'Concierge autonomous mode. NEW workspaces default ON (migration 099 flipped '
  'the column DEFAULT to true); EXISTING rows are unchanged (no backfill — '
  'silently enabling un-consented workspaces is a GDPR violation). Even '
  'default-ON workspaces are soft-gated on first auto-run via '
  'autonomous_disclosure_ack_at. Owner-only write via '
  'set_workspace_bash_autonomous; member read via get_workspace_bash_autonomous. '
  'Fail-closed false on read error.';

-- 2. CONSENT ACK column. Nullable, NO default: NULL = not yet acked = HOLD the
--    first auto-run (the safe direction for an approval-bypass surface).
ALTER TABLE public.workspaces
  ADD COLUMN IF NOT EXISTS autonomous_disclosure_ack_at timestamptz;

COMMENT ON COLUMN public.workspaces.autonomous_disclosure_ack_at IS
  'Per-workspace timestamp evidencing the owner saw + acknowledged the '
  'autonomous-mode residual-risk disclosure before the FIRST auto-run (the '
  'soft-gate consent record). NULL = not yet acked => the first non-blocked '
  'Bash command is HELD until the owner acks. Owner-only write via '
  'set_workspace_autonomous_ack; member read via get_workspace_autonomous_ack.';

-- READ: member-checked. NULL for non-member / unauthenticated (deny path),
-- mirroring get_workspace_bash_autonomous (097). The server read helper
-- resolveAutonomousAck treats NULL as fail-closed HOLD (the OPPOSITE boolean
-- direction from resolveBashAutonomous's `?? false`).
CREATE OR REPLACE FUNCTION public.get_workspace_autonomous_ack(p_workspace_id uuid)
  RETURNS timestamptz
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_value timestamptz;
BEGIN
  -- is_workspace_member(NULL, …) and (…, NULL) both return FALSE, so a null
  -- arg or unauthenticated caller falls through to RETURN NULL.
  IF NOT public.is_workspace_member(p_workspace_id, auth.uid()) THEN
    RETURN NULL;
  END IF;

  SELECT autonomous_disclosure_ack_at INTO v_value
  FROM public.workspaces
  WHERE id = p_workspace_id;

  RETURN v_value;
END;
$$;

REVOKE ALL ON FUNCTION public.get_workspace_autonomous_ack(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_workspace_autonomous_ack(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.get_workspace_autonomous_ack(uuid) IS
  'Member-checked read of workspaces.autonomous_disclosure_ack_at. NULL for '
  'non-members (deny path) — server resolveAutonomousAck treats NULL as '
  'fail-closed HOLD (not yet acked).';

-- WRITE: OWNER-only. Writing the consent ack is an ownership-grade decision
-- (mirrors set_workspace_bash_autonomous). Raises on a non-owner /
-- unauthenticated caller (authz violation, surfaced + mirrored). Idempotent:
-- COALESCE existing ack or set now(), so a re-ack never overwrites the original
-- consent timestamp.
--
-- ORTHOGONAL TO 097 (deliberate): this RPC writes ONLY the ack column. The
-- EXISTING-workspace opt-out prompt's "Keep autonomous on" branch flips the
-- toggle via the EXISTING owner-checked toggle RPC (097, untouched) and then
-- calls this RPC for the ack — two owner-checked calls. Keeping 099 free of any
-- write to the toggle column preserves the migration-test GDPR sentinel.
CREATE OR REPLACE FUNCTION public.set_workspace_autonomous_ack(
  p_workspace_id uuid
)
  RETURNS timestamptz
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_ack timestamptz;
BEGIN
  -- R8 composite-key invariant: owner check scopes by (p_workspace_id,
  -- auth.uid()) — a caller can only ack a workspace they own.
  IF NOT EXISTS (
    SELECT 1
    FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id      = auth.uid()
      AND role         = 'owner'
  ) THEN
    RAISE EXCEPTION 'not authorized: only a workspace owner may ack autonomous disclosure';
  END IF;

  UPDATE public.workspaces
  SET autonomous_disclosure_ack_at = COALESCE(autonomous_disclosure_ack_at, now())
  WHERE id = p_workspace_id
  RETURNING autonomous_disclosure_ack_at INTO v_ack;

  RETURN v_ack;
END;
$$;

REVOKE ALL ON FUNCTION public.set_workspace_autonomous_ack(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_workspace_autonomous_ack(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.set_workspace_autonomous_ack(uuid) IS
  'Owner-only write of workspaces.autonomous_disclosure_ack_at (idempotent '
  'COALESCE). Writes ONLY the ack column. "Keep autonomous on" flips the toggle '
  'via the EXISTING owner-checked toggle RPC then calls this for the ack (two '
  'owner-checked calls). Raises for non-owners.';
