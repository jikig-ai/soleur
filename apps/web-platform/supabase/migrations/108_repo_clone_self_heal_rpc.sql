-- 108_repo_clone_self_heal_rpc.sql
-- feat-one-shot-concierge-reconnect-self-heal-checkout — FIX 1a.
--
-- The Concierge dispatch readiness gate (#5394) dead-ends a workspace whose
-- repo_status='error' (or a stale 'cloning') BEFORE the on-disk self-heal can
-- re-clone. FIX 1a re-orders that gate: on the recoverable error branch the
-- dispatcher attempts ensureWorkspaceRepoCloned under an optimistic lock and
-- re-evaluates. But cc-dispatcher was deliberately migrated OFF the
-- service-role allowlist (PR-D), and `workspaces` has NO UPDATE RLS policy for
-- `authenticated` — every existing repo_status write goes through a service
-- client (workspace-repo-mirror.ts). A tenant-client UPDATE on `workspaces` is
-- silently RLS-filtered to zero rows, so the lock/status writes the dispatch
-- self-heal needs are dead-on-arrival.
--
-- Fix: two SECURITY DEFINER RPCs callable via the TENANT `.rpc()` with an
-- internal membership check, doing the lock + status writes server-side —
-- keeping cc-dispatcher off the service-role allowlist
-- (hr-write-boundary-sentinel-sweep-all-write-sites).
--
--   claim_repo_clone_lock(p_workspace_id uuid) RETURNS boolean
--     Optimistic lock. UPDATE workspaces -> 'cloning' WHERE the row is
--     recoverable: repo_status='error' OR (repo_status='cloning' AND
--     repo_last_synced_at < now() - interval '5 minutes'). The stale-cloning
--     arm is the DEAD-WINNER escape (a winner that died after error->cloning
--     but before failed->error would otherwise strand the row forever — the
--     `.neq('cloning')` terminal trap spec-flow P0-1 names). This is the ONLY
--     place a 'cloning'->'cloning' re-acquire is permitted, and only past the
--     5-minute staleness window so a LIVE /api/repo/setup clone (fresh
--     'cloning') is never disturbed. Returns FOUND (won/lost).
--
--   set_repo_status(p_workspace_id uuid, p_status text, p_error text) RETURNS void
--     Terminal write of 'ready'/'error'. Dual-writes BOTH
--     workspaces.repo_status (ADR-044 source of truth, the readiness gate's
--     status key) AND users.repo_error (the sanitized reason the gate unwraps
--     via parseErrorPayload — workspaces.repo_error is never written). Writing
--     both server-side means the TS mirrorRepoColsToSoloWorkspace
--     (service-role-only) is NOT needed on the dispatch path.
--
-- Precedent-diff: mirrors migration 079's resolve_workspace_installation_id /
-- set_current_workspace_id definer + 4-role REVOKE/GRANT shape and 083's
-- search_path pin. search_path = public, pg_temp (public first) per
-- cq-pg-security-definer-search-path-pin-pg-temp and the repo-wide
-- migration-rpc-grants.test.ts lint (which requires `public`; the bodies need
-- public.is_workspace_member / public.workspaces / public.users).
-- 4-role REVOKE (PUBLIC, anon, authenticated, service_role) then GRANT EXECUTE
-- TO authenticated, per
-- 2026-05-06-supabase-default-privileges-defeat-revoke-from-public.
--
-- DEPENDENCY: migration 053 (workspaces, is_workspace_member), 079 (repo_status
-- + repo_last_synced_at on workspaces), 013 (users.repo_error) must have
-- applied. No CREATE INDEX CONCURRENTLY / non-transactional DDL — the runner
-- wraps each file in a transaction.

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.workspaces') IS NULL THEN
    RAISE EXCEPTION '108: public.workspaces must exist (run 053/079 first)';
  END IF;
  IF to_regclass('public.users') IS NULL THEN
    RAISE EXCEPTION '108: public.users must exist (run earlier migrations first)';
  END IF;
END $$;

-- =====================================================================
-- 1. claim_repo_clone_lock — optimistic error/stale-cloning -> cloning
-- =====================================================================

CREATE OR REPLACE FUNCTION public.claim_repo_clone_lock(p_workspace_id uuid)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  -- is_workspace_member(NULL, …) and (…, NULL) both return FALSE, so a null
  -- arg or unauthenticated caller cannot acquire the lock.
  IF NOT public.is_workspace_member(p_workspace_id, auth.uid()) THEN
    RETURN false;
  END IF;

  -- Acquire ONLY a recoverable row:
  --   * repo_status='error'                         (the primary case), OR
  --   * repo_status='cloning' that is STALE         (dead-winner escape).
  -- A FRESH 'cloning' (a live /api/repo/setup clone, well within the window)
  -- is deliberately untouched — the loser honest-waits. This is NOT a
  -- `.neq('cloning')` predicate (which can never re-acquire a 'cloning' row and
  -- would strand a dead winner forever).
  --
  -- NULL repo_last_synced_at counts as stale. Every live clone-writer
  -- (/api/repo/setup AND this RPC) now stamps repo_last_synced_at = now() on its
  -- 'cloning' flip, so a fresh clone is never NULL. A NULL clock therefore only
  -- arises on a row stranded at 'cloning' before this migration's deploy (or any
  -- future writer that forgets to stamp) — those MUST stay recoverable, never
  -- permanently stuck. `NULL < now() - interval` is NULL (not TRUE), so the
  -- explicit `IS NULL` arm is required to reach them.
  UPDATE public.workspaces
     SET repo_status         = 'cloning',
         repo_last_synced_at = now()
   WHERE id = p_workspace_id
     AND (
       repo_status = 'error'
       OR (
         repo_status = 'cloning'
         AND (
           repo_last_synced_at IS NULL
           OR repo_last_synced_at < now() - interval '5 minutes'
         )
       )
     );

  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_repo_clone_lock(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_repo_clone_lock(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.claim_repo_clone_lock(uuid) IS
  'Membership-checked optimistic clone lock for the Concierge dispatch '
  'self-heal (FIX 1a). Flips workspaces.repo_status error|stale-cloning -> '
  'cloning (stamping repo_last_synced_at) and returns FOUND (won/lost). The '
  'stale-cloning arm (>5 min) is the dead-winner escape; a fresh cloning (live '
  '/api/repo/setup clone) is never disturbed. Callable via tenant .rpc() so '
  'cc-dispatcher stays off the service-role allowlist. ADR-044.';

-- =====================================================================
-- 2. set_repo_status — terminal ready/error dual-write
-- =====================================================================
--
-- Dual-writes workspaces.repo_status (source of truth) AND users.repo_error
-- (the sanitized reason the readiness gate reads — only `error` carries one).
-- On 'ready' the error is cleared and repo_last_synced_at is stamped. The
-- caller passes an ALREADY-sanitized reason (the self-heal frames
-- ensureWorkspaceRepoCloned's failure); this fn does not re-sanitize.

CREATE OR REPLACE FUNCTION public.set_repo_status(
  p_workspace_id uuid,
  p_status       text,
  p_error        text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF NOT public.is_workspace_member(p_workspace_id, v_user_id) THEN
    RAISE EXCEPTION 'caller is not a member of workspace %', p_workspace_id
      USING ERRCODE = '42501';
  END IF;

  IF p_status NOT IN ('ready', 'error') THEN
    RAISE EXCEPTION 'set_repo_status: p_status must be ready|error, got %', p_status
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.workspaces
     SET repo_status         = p_status,
         repo_last_synced_at = CASE WHEN p_status = 'ready' THEN now()
                                    ELSE repo_last_synced_at END
   WHERE id = p_workspace_id;

  -- Dual-write the reason the gate consumes. Today connect/disconnect is
  -- solo-only (workspace.id = user.id, ADR-038 N2), so the dispatching user
  -- IS the solo workspace owner; write their users.repo_error. On 'ready'
  -- clear it; on 'error' set the framed reason.
  -- SOLEUR-DEBT: this users.repo_error write targets the CALLER (auth.uid()),
  -- which equals the workspace owner only under the solo-only invariant. When
  -- shared-workspace repo flows land (#4560 / Phase 5) the readiness gate will
  -- read the OWNER's users.repo_error while a non-owner dispatcher writes their
  -- own row — a split-write. Re-target to the workspace owner (or move the reason
  -- onto workspaces.repo_error) before enabling shared repo-setup.
  -- upgrade-trigger: #4560 shared-workspace repo-setup
  UPDATE public.users
     SET repo_error = CASE WHEN p_status = 'ready' THEN NULL ELSE p_error END
   WHERE id = v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.set_repo_status(uuid, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_repo_status(uuid, text, text)
  TO authenticated;

COMMENT ON FUNCTION public.set_repo_status(uuid, text, text) IS
  'Membership-checked terminal write of the dispatch self-heal (FIX 1a). '
  'Dual-writes workspaces.repo_status (source of truth) AND users.repo_error '
  '(the sanitized reason the readiness gate reads). ready clears the error and '
  'stamps repo_last_synced_at; error sets the caller-framed reason. Callable '
  'via tenant .rpc() so cc-dispatcher stays off the service-role allowlist. '
  'ADR-044.';

COMMIT;

-- Tracking row written in the same transaction by run-migrations.sh
-- (canonical) or the Doppler+pg fallback applier.
