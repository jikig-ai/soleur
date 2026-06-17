-- 110_workspace_repo_error_and_comember_reconcile.sql
-- feat-adr-044-team-write-cutover (#5462, Phase 1) — the schema +
-- data precondition for the connect-time WRITE relocation (users.* ->
-- workspaces.*) that PR-2b's column drop (#5437) depends on. ADR-044.
--
-- This file is additive + reversible (.down.sql drops the new column). It is
-- applied by web-platform-release.yml #migrate BEFORE the code cutover deploy,
-- mirroring the 079/080 -> 081 ordering. Supabase wraps each migration file in
-- ONE transaction; no explicit BEGIN/COMMIT and no CONCURRENTLY (mirror 079/080).
--
-- ---------------------------------------------------------------------------
-- LAWFUL_BASIS (GDPR Art. 6) — co-membered SKIP backlog is NOT auto-adopted:
--   * SOLO rows: Art. 6(1)(b) contract — re-keying the repo_error reason onto
--     the user's OWN solo workspace (workspace_id == user_id, ADR-038 N2). No
--     new processing of another data subject's data.
--   * CO-MEMBERED rows: auto-copying the owner's users.repo_url onto a
--     co-membered workspace would process co-member repo access WITHOUT a fresh
--     Art. 6(1)(a) invite attestation (workspace_member_attestations, mig 058).
--     PA-17(c)(2) + 2026-05-counsel-review-4558.md (call B1) establish the
--     Art. 6(1)(a) basis "never operates retroactively." So this migration does
--     NOT auto-drain the mig-080 co-membered SKIP backlog. Those rows are a
--     LAWFUL CARRIED RESIDUAL cleared only when the owner re-connects the repo
--     from within the team-workspace context (the owner-gated write path THIS
--     PR's Phase 3 implements — a re-connect re-establishes the connection under
--     a fresh attestation). hr-gdpr-gate-on-regulated-data-surfaces.
-- ---------------------------------------------------------------------------

DO $$
BEGIN
  IF to_regclass('public.workspaces') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.workspaces must exist before 110 (apply migration 079 first)';
  END IF;
END $$;

-- =====================================================================
-- 1. repo_error column on public.workspaces
-- =====================================================================
--
-- repo_error is a SANITIZED reason string (setup/route.ts builds it as
-- JSON.stringify({code, message: sanitizeGitStderr(...), timestamp}); the
-- GitHub App token never reaches stderr — askpass via env, GIT_TERMINAL_PROMPT=0).
-- It is NOT a credential, so it joins the `authenticated` read set below.

ALTER TABLE public.workspaces
  ADD COLUMN IF NOT EXISTS repo_error text;

-- =====================================================================
-- 2. Extend the non-credential column-level GRANT to include repo_error
-- =====================================================================
--
-- Supabase grants TABLE-level SELECT to `authenticated` by default; adding a
-- column does NOT auto-add it to the column-level grant mig 079:89 installed.
-- The only way to extend the allowed-column set is to REVOKE the table-level
-- SELECT and RE-GRANT the full explicit non-credential column list (NOT a
-- partial column grant, which is a no-op while a broader grant exists). RLS
-- (workspaces_select_for_members) still gates which ROWS are visible.
-- `github_installation_id` stays OUT of this list — the credential is readable
-- only via resolve_workspace_installation_id (SECURITY DEFINER, mig 079).
-- service_role keeps its default grant (trusted server context).

REVOKE SELECT ON public.workspaces FROM authenticated;
GRANT SELECT (id, organization_id, name, created_at,
              repo_url, repo_provider, repo_status, repo_last_synced_at,
              repo_error)
  ON public.workspaces TO authenticated;

-- =====================================================================
-- 3. SOLO backfill: re-key users.repo_error -> workspaces.repo_error
-- =====================================================================
--
-- Mirror mig-080's solo-only join (w.id = u.id) + canary-owner-row +
-- sole-member COUNT(*) = 1 guard + the `WHERE w.repo_error IS NULL`
-- idempotency guard. Runs from the still-authoritative `users` snapshot BEFORE
-- the write cutover deploys (Phase 1 before Phase 2-3 per the release ordering).

DO $$
DECLARE
  v_rc int;
BEGIN
  UPDATE public.workspaces w
     SET repo_error = u.repo_error
    FROM public.users u
   WHERE w.id = u.id
     AND w.repo_error IS NULL        -- idempotency: re-runs touch 0 rows
     AND u.repo_error IS NOT NULL    -- only users with an error reason set
     -- Canary owner-row: this workspace is the user's own solo workspace.
     AND EXISTS (
       SELECT 1 FROM public.workspace_members m
       WHERE m.workspace_id = w.id
         AND m.user_id      = w.id
         AND m.role         = 'owner'
     )
     -- Sole-member guard: never adopt onto a co-membered workspace.
     AND (
       SELECT COUNT(*) FROM public.workspace_members m2
       WHERE m2.workspace_id = w.id
     ) = 1;

  GET DIAGNOSTICS v_rc = ROW_COUNT;
  RAISE NOTICE '[110-backfill workspace repo_error] % rows re-keyed', v_rc;
END $$;

-- =====================================================================
-- 4. Re-run the mig-080 SOLO repo-connection backfill (drift convergence)
-- =====================================================================
--
-- A solo workspace that became correctly-provisioned AFTER mig-080 ran (e.g. a
-- repo connected before its solo workspace existed) may still diverge from the
-- `users` snapshot. Re-key the SOLO rows so the PR-2b drift gate (verify/110)
-- reaches 0 for sole-member workspaces. Co-membered rows are DELIBERATELY left
-- alone (the COUNT(*) = 1 guard) — they are the lawful carried residual cleared
-- by owner re-connect (header). Fan-out keying is (github_installation_id,
-- repo_url) per ADR-044; the w.id = u.id join is already org-scoped (a solo
-- workspace shares the owner's org), so this never crosses an organization
-- boundary.

DO $$
DECLARE
  v_rc int;
BEGIN
  UPDATE public.workspaces w
     SET repo_url               = u.repo_url,
         repo_provider          = u.repo_provider,
         github_installation_id = u.github_installation_id,
         repo_status            = u.repo_status,
         repo_last_synced_at    = u.repo_last_synced_at
    FROM public.users u
   WHERE w.id = u.id
     AND u.repo_url IS NOT NULL
     -- Re-key only rows that still diverge (idempotent: converged rows skip).
     AND (
       w.repo_url               IS DISTINCT FROM u.repo_url
       OR w.github_installation_id IS DISTINCT FROM u.github_installation_id
       OR w.repo_status            IS DISTINCT FROM u.repo_status
       OR w.repo_last_synced_at    IS DISTINCT FROM u.repo_last_synced_at
     )
     -- Canary owner-row + sole-member guard (SOLO-ONLY, lawful Art. 6(1)(b)).
     AND EXISTS (
       SELECT 1 FROM public.workspace_members m
       WHERE m.workspace_id = w.id
         AND m.user_id      = w.id
         AND m.role         = 'owner'
     )
     AND (
       SELECT COUNT(*) FROM public.workspace_members m2
       WHERE m2.workspace_id = w.id
     ) = 1;

  GET DIAGNOSTICS v_rc = ROW_COUNT;
  RAISE NOTICE '[110-reconcile solo repo cols] % rows re-keyed', v_rc;
END $$;

-- =====================================================================
-- 5. Audit: log the carried co-membered residual (NOT drained)
-- =====================================================================
--
-- Surface (do not mutate) the co-membered SKIP backlog so the apply log records
-- the lawful carried residual that owner re-connect (Phase 3) clears.

DO $$
DECLARE
  v_carried int;
BEGIN
  SELECT COUNT(*) INTO v_carried
    FROM public.workspaces w
    JOIN public.users u ON u.id = w.id
   WHERE u.repo_url IS NOT NULL
     AND (
       SELECT COUNT(*) FROM public.workspace_members m2
       WHERE m2.workspace_id = w.id
     ) > 1;
  RAISE NOTICE '[110-audit] % co-membered workspaces carry an un-re-connected repo residual (lawful; cleared by owner re-connect)', v_carried;
END $$;
