-- verify/160_dsar_export_audit_pii_cascade_null_carveout.sql
-- Post-apply sentinel for the #9994 WORM carve-out: the live function
-- body must carry the initiator-bound cascade gate, not a stale body
-- (the dev project ran an out-of-band apply during development of this
-- migration — this probe is what proves the landed body is the file's).
-- Each row returns bad=1 on drift; run-verify.sh fails the deploy if any
-- bad=1. Idempotent and read-only.

SELECT 'no_mutate_has_cascade_carveout' AS check_name,
       CASE WHEN prosrc ILIKE '%to_jsonb(NEW)%'
              AND prosrc ILIKE '%user_id IS NULL%' THEN 0 ELSE 1 END::int AS bad
  FROM pg_proc WHERE proname = 'dsar_export_audit_pii_no_mutate'
UNION ALL
SELECT 'no_mutate_has_initiator_check',
       CASE WHEN prosrc ILIKE '%NOT EXISTS%'
              AND prosrc ILIKE '%auth.users%' THEN 0 ELSE 1 END
  FROM pg_proc WHERE proname = 'dsar_export_audit_pii_no_mutate'
UNION ALL
SELECT 'no_mutate_worm_bypass_preserved',
       CASE WHEN prosrc ILIKE '%app.worm_bypass%' THEN 0 ELSE 1 END
  FROM pg_proc WHERE proname = 'dsar_export_audit_pii_no_mutate';
