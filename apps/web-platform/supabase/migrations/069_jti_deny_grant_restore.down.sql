-- Down migration for 069_jti_deny_grant_restore.sql.
--
-- Restores the (empirically unnecessary) GRANT EXECUTE TO authenticated
-- on `public.is_jti_denied(uuid)`. Only useful for migration-rollback
-- machinery; production should never need this — the empirical
-- verification proves the GRANT adds no policy-evaluation coverage.

GRANT EXECUTE ON FUNCTION public.is_jti_denied(uuid) TO authenticated;

-- Note: we do NOT restore mig 037's `COMMENT ON FUNCTION` text because
-- mig 068 didn't override it. The COMMENT we set in the up migration is
-- the canonical post-069 state and is replaced by the next migration
-- that re-comments the function (or stays in place if no such migration
-- lands).
