-- 186_legal_acceptance_hash_counts.down.sql
-- The migration added one read-only function and nothing else, so dropping it loses no data. It touches nothing of
-- migrations 184 and 185. The migration runner never runs down files; this one is applied by hand, deliberately.
--
-- ROLLBACK IS BY CODE, NOT BY THIS FILE. Revert the code (the route GET /api/internal/legal-acceptance/[key]/counts, its
-- service wrapper and the helper script) and LEAVE migration 186 applied: the function is inert after a code revert
-- (service_role only, no caller). Deleting the migration file is not possible: the migration-immutability lint forbids
-- removing an on-main migration, so a literal git revert of the whole PR (which deletes the up file, this file and verify/186) fails
-- that lint: restore those three paths before committing. The legal documents are forward-fix only. See ADR-319, "Rollback".
--
-- To drop the function deliberately, BOTH steps are required, in this order, as the database owner:
--   1. psql -v ON_ERROR_STOP=1 -f 186_legal_acceptance_hash_counts.down.sql
--   2. DELETE FROM public._schema_migrations WHERE filename = '186_legal_acceptance_hash_counts.sql';
-- Without step 2 the runner still lists 186 as applied and will never re-create the function. Otherwise forward-fix with 187.
-- Until the code is reverted too, the route answers 503 (one store_failed event, stage counts).

DROP FUNCTION IF EXISTS public.legal_acceptance_hash_counts(text);
