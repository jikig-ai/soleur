-- 080_backfill_workspace_repo_from_users.sql
-- feat-workspace-repo-ownership (#4558, PR #4559) — copy GitHub repo
-- connection state from public.users to public.workspaces for SOLO
-- workspaces only. ADR-044. Applied in the same web-platform-release.yml
-- #migrate run as 079, kept a separate file for .down.sql granularity.
--
-- LAWFUL_BASIS: Art. 6(1)(b) contract — backfilling the repo connection
-- the user already established onto their own solo workspace. Co-membered
-- workspaces are SKIPPED (no Art. 6(1)(f) co-member access without owner
-- re-consent — CLO requirement).
--
-- SOLO-ONLY BY CONSTRUCTION: the w.id = u.id join only matches backfilled
-- solo workspaces (ADR-038 N2 — post-flag-flip workspaces use
-- gen_random_uuid(), so w.id never equals a u.id). Residual hole closed
-- below: a solo workspace whose owner later invited a co-member still has
-- w.id = u.id but member count > 1; the canary-owner-row + COUNT(*) = 1
-- guard SKIPs it (matching the 053 idempotency canary at 053:207-215).
--
-- users repo columns remain authoritative — NOT dropped here (a later
-- decommission migration drops them after a prod soak + the AC15 drift
-- reconciliation).
--
-- No re-normalization: users.repo_url was canonicalized by migration 031
-- (TS↔SQL parity asserted in test/repo-url-sql-parity.test.ts), so a
-- plain copy preserves the canonical form.

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
     AND w.repo_url IS NULL          -- idempotency: re-runs touch 0 rows
     AND u.repo_url IS NOT NULL      -- only users with a connected repo
     -- Canary owner-row: this workspace is the user's own solo workspace.
     AND EXISTS (
       SELECT 1 FROM public.workspace_members m
       WHERE m.workspace_id = w.id
         AND m.user_id      = w.id
         AND m.role         = 'owner'
     )
     -- Sole-member guard: never adopt a repo onto a co-membered workspace.
     AND (
       SELECT COUNT(*) FROM public.workspace_members m2
       WHERE m2.workspace_id = w.id
     ) = 1;

  GET DIAGNOSTICS v_rc = ROW_COUNT;
  RAISE NOTICE '[080-backfill workspace repo] % rows copied', v_rc;
END $$;

-- Audit pass: log solo workspaces that have a connected user-repo but were
-- SKIPPED because they have grown to >1 member. These require explicit
-- owner re-consent before the repo is adopted onto the shared workspace.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT w.id AS workspace_id
    FROM public.workspaces w
    JOIN public.users u ON u.id = w.id
    WHERE u.repo_url IS NOT NULL
      AND w.repo_url IS NULL
      AND EXISTS (
        SELECT 1 FROM public.workspace_members m
        WHERE m.workspace_id = w.id
          AND m.user_id      = w.id
          AND m.role         = 'owner'
      )
      AND (
        SELECT COUNT(*) FROM public.workspace_members m2
        WHERE m2.workspace_id = w.id
      ) > 1
  LOOP
    RAISE NOTICE '[080-backfill SKIP co-membered] workspace_id=% has a connected owner-repo but >1 member — owner re-consent required before repo adoption', r.workspace_id;
  END LOOP;
END $$;
