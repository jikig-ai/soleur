-- 163_renormalize_repo_url.down.sql
-- Intentional no-op. The data backfill in 163_renormalize_repo_url.sql is not
-- reversible: the pre-image of a rewritten repo_url is not retained, and the
-- rewrite only moves a value to its canonical form. A rolled-back dev run
-- re-applies the up file unchanged.
SELECT 1;
