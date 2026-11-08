-- 186_legal_acceptance_hash_counts.down.sql
-- Hot-rollback safe: the migration added one read-only function and nothing else, so dropping it loses no data. The web
-- route GET /api/internal/legal-acceptance/[key]/counts then answers 503 (one store_failed event, stage counts) until the
-- code is reverted too. It touches nothing of migrations 184 and 185. (The migration runner never runs down files; this is
-- applied by hand: psql -v ON_ERROR_STOP=1 -f 186_legal_acceptance_hash_counts.down.sql.)

DROP FUNCTION IF EXISTS public.legal_acceptance_hash_counts(text);
