\set ON_ERROR_STOP on
SET statement_timeout = '30s';
SET lock_timeout = '5s';
-- Must be the FIRST SQL after replacing only the application container.
SELECT codex_rehearsal.assert(codex_rehearsal.state()=(SELECT state FROM codex_rehearsal.snapshots WHERE label='before-application-replacement'),'every full public/auth/storage row and relation census retained');
-- Equality, including full rows, is authoritative; MD5 fields are diagnostics.
