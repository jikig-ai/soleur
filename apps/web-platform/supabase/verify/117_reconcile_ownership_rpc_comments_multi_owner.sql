-- Verify 117_reconcile_ownership_rpc_comments_multi_owner.sql.
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row fails CI
-- verify-migrations (and auto-closes any matching `follow-through` issue).
--
-- Locks the DURABLE multi-owner-by-design invariant (ADR-073 / #5756) — the
-- signature + grant + guard presence, NOT just comment prose:
--   (1) no single-owner-enforcing partial-UNIQUE index AND no UNIQUE/EXCLUDE
--       constraint on workspace_members;
--   (2) the at-least-one-owner guard is present in the 4-arg
--       update_workspace_member_role — both the RAISE *message* AND the
--       count(owner) <= 1 *predicate* are pinned (see KNOWN LIMIT (b));
--   (3) the FOUR owner-granting/minting RPCs locked HERE stay service_role-only
--       (the #4762 forgeable-override tenant-takeover lock): update_workspace_
--       member_role, create_workspace_invitation, accept_workspace_invitation,
--       and anonymise_organization_membership (the Art-17 erasure path that
--       re-points organizations.owner_user_id + promotes the oldest member to
--       owner — a 5th owner-minting vector, mig 081). The 5th owner-granting RPC,
--       transfer_workspace_ownership, is grant-locked separately in verify/092 —
--       FIVE owner-granting/minting RPCs are service_role-only in total;
--   (4) the old 3-arg update_workspace_member_role overload stays DROPped;
--   (5) (secondary/droppable) the transfer COMMENT is no longer single-owner-strict.
--
-- TWO KNOWN LIMITS (by design — recorded so a reader does not over-trust them):
--   (a) check 1 cannot see a single-owner rule re-introduced via a TRIGGER
--       (only constraints/indexes are visible); check 2 (the at-least-one-owner
--       guard) is the durable BEHAVIORAL backstop against a single-owner regression.
--   (b) check 2 matches the RAISE *message* ("cannot demote the last owner") AND
--       the count(owner) <= 1 *predicate* text (the 'count(' + '<= 1' fragments
--       of mig 094:227-230). Matching both means a future migration that keeps
--       the message while neutering the predicate (or vice-versa) flips bad>0;
--       the residual gap is only a predicate that is textually present but
--       semantically dead. The migration-shape test
--       (test/supabase-migrations/117-*.test.ts) pins the same predicate text.
--
-- TYPE NOTE: every UNION branch's `bad` MUST be INTEGER (a boolean/integer UNION
-- is rejected by Postgres — release-blocker once, #5474). All branches cast ::int.

-- (1a) No single-owner-enforcing partial-UNIQUE INDEX on workspace_members.
-- A plain CHECK is row-local and cannot enforce cross-row cardinality, so the
-- realistic vectors are a partial UNIQUE index (predicate mentions owner,
-- scoped by workspace_id) ...
SELECT 'no_single_owner_unique_index' AS check_name,
       (SELECT count(*) FROM pg_index i
          JOIN pg_class c ON c.oid = i.indrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public'
           AND c.relname = 'workspace_members'
           AND i.indisunique
           AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%owner%'
           AND pg_get_indexdef(i.indexrelid) ILIKE '%workspace_id%')::int AS bad
UNION ALL
-- (1b) ... and a UNIQUE/EXCLUDE CONSTRAINT mentioning owner.
SELECT 'no_single_owner_constraint',
       (SELECT count(*) FROM pg_constraint con
          JOIN pg_class c ON c.oid = con.conrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public'
           AND c.relname = 'workspace_members'
           AND con.contype IN ('u', 'x')
           AND pg_get_constraintdef(con.oid) ILIKE '%owner%')::int AS bad
UNION ALL
-- (2) At-least-one-owner guard present, PINNED to the 4-arg signature so a stale
-- overload cannot satisfy it. bad=1 if no 4-arg form carries BOTH the guard
-- RAISE message AND the count(owner) <= 1 predicate text (mig 094:227-230) — so
-- a future migration that keeps the message but neuters the predicate flips bad>0.
SELECT 'last_owner_guard_present_4arg',
       (CASE WHEN EXISTS (
         SELECT 1 FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public'
            AND p.proname = 'update_workspace_member_role'
            AND pg_get_function_identity_arguments(p.oid)
                = 'p_workspace_id uuid, p_user_id uuid, p_new_role text, p_caller_user_id uuid'
            AND pg_get_functiondef(p.oid) ILIKE '%cannot demote the last owner%'
            AND pg_get_functiondef(p.oid) ILIKE '%count(%'
            AND pg_get_functiondef(p.oid) ILIKE '%<= 1%'
       ) THEN 0 ELSE 1 END)::int AS bad
UNION ALL
-- (3a) update_workspace_member_role(4-arg) is NOT EXECUTE-able by authenticated.
SELECT 'update_role_4arg_not_granted_to_authenticated',
       (CASE WHEN has_function_privilege(
          'authenticated',
          'public.update_workspace_member_role(uuid, uuid, text, uuid)',
          'EXECUTE'
        ) THEN 1 ELSE 0 END)::int AS bad
UNION ALL
-- (3b) create_workspace_invitation(6-arg) is NOT EXECUTE-able by authenticated.
-- The canonical co-owner grant path; takes a forgeable p_caller_user_id (mig 085).
SELECT 'create_invitation_6arg_not_granted_to_authenticated',
       (CASE WHEN has_function_privilege(
          'authenticated',
          'public.create_workspace_invitation(uuid, text, text, text, text, uuid)',
          'EXECUTE'
        ) THEN 1 ELSE 0 END)::int AS bad
UNION ALL
-- (3c) accept_workspace_invitation(2-arg) is NOT EXECUTE-able by authenticated.
SELECT 'accept_invitation_2arg_not_granted_to_authenticated',
       (CASE WHEN has_function_privilege(
          'authenticated',
          'public.accept_workspace_invitation(uuid, uuid)',
          'EXECUTE'
        ) THEN 1 ELSE 0 END)::int AS bad
UNION ALL
-- (3d) anonymise_organization_membership(1-arg uuid) is NOT EXECUTE-able by
-- authenticated. The Art-17 erasure path (mig 081) re-points
-- organizations.owner_user_id to the oldest remaining member AND promotes that
-- member to owner (081:61-75) — a 5th owner-MINTING vector that belongs in the
-- grant-lock set (service_role-only at 081:93-96).
SELECT 'anonymise_org_membership_not_granted_to_authenticated',
       (CASE WHEN has_function_privilege(
          'authenticated',
          'public.anonymise_organization_membership(uuid)',
          'EXECUTE'
        ) THEN 1 ELSE 0 END)::int AS bad
UNION ALL
-- (4) The old 3-arg update_workspace_member_role(uuid, uuid, text) overload must
-- NOT reappear (symmetry with verify/092 check 3 — a recreated 3-arg
-- authenticated-granted overload is the same forge-class the 4-arg lock misses).
SELECT 'update_role_3arg_overload_dropped',
       (CASE WHEN EXISTS (
         SELECT 1 FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public'
            AND p.proname = 'update_workspace_member_role'
            AND pg_get_function_identity_arguments(p.oid)
                = 'p_workspace_id uuid, p_user_id uuid, p_new_role text'
       ) THEN 1 ELSE 0 END)::int AS bad
UNION ALL
-- (5) SECONDARY / DROPPABLE: the transfer COMMENT no longer asserts
-- "single-owner strict" (couples to migration 117's exact string — kept only as
-- a low-value confirmation that the migration ran).
-- Resolve the function oid via the catalog (pg_proc + pg_namespace, mirroring
-- checks 2/4) and read its comment with the catalog-pinned 2-arg
-- obj_description(p.oid, 'pg_proc') — NOT the deprecated single-arg regprocedure
-- form. bad=1 if the resolved transfer comment is still single-owner-strict.
SELECT 'transfer_comment_not_single_owner_strict',
       (CASE WHEN EXISTS (
         SELECT 1 FROM pg_proc p
           JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public'
            AND p.proname = 'transfer_workspace_ownership'
            AND pg_get_function_identity_arguments(p.oid)
                = 'p_workspace_id uuid, p_new_owner_user_id uuid, p_attestation_text text, p_caller_user_id uuid'
            AND obj_description(p.oid, 'pg_proc') ILIKE '%single-owner strict%'
       ) THEN 1 ELSE 0 END)::int AS bad;
