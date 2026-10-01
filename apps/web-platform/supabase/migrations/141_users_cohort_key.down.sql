-- 141_users_cohort_key.down.sql (#8880)
--
-- Drops the cohort_key column added by 141_users_cohort_key.sql.
-- Safe to run any time: the column is write-only for the admin route and
-- read-only for analytics filtering; dropping it restores pre-migration
-- shape. Any rows with a set cohort_key lose only the tag.

BEGIN;

ALTER TABLE public.users DROP COLUMN IF EXISTS cohort_key;

COMMIT;
