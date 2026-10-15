-- verify/162_action_sends_message_id_cascade_null_carveout.sql
-- Post-apply sentinel for the #10254 WORM carve-out: the live schema must
-- carry the SET NULL FK, the nullable column, the row-level trigger, the
-- initiator-bound carve-out in action_sends_no_mutate, and the
-- anonymise_action_sends message_id hardening — not a stale apply.
-- Every check emits a row: CASE WHEN EXISTS(...) AND <cond> THEN 0 ELSE
-- 1 END, so a missing object reports bad=1 rather than an absent row
-- (anti-vacuity). Run-verify.sh fails the deploy on any bad=1.
-- Idempotent and read-only.

SELECT 'fk_message_id_set_null' AS check_name,
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_constraint
         WHERE conrelid = 'public.action_sends'::regclass
           AND conname = 'action_sends_message_id_fkey'
           AND confdeltype = 'n'
       ) THEN 0 ELSE 1 END::int AS bad
UNION ALL
SELECT 'message_id_nullable',
       CASE WHEN EXISTS (
         SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name = 'action_sends'
           AND column_name = 'message_id'
           AND is_nullable = 'YES'
       ) THEN 0 ELSE 1 END
UNION ALL
SELECT 'row_level_message_id_trigger',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_trigger t
         JOIN pg_proc p ON p.oid = t.tgfoid
         WHERE t.tgrelid = 'public.action_sends'::regclass
           AND t.tgname = 'action_sends_message_id_guard'
           AND t.tgtype = 23
           AND p.proname = 'action_sends_no_mutate'
       ) THEN 0 ELSE 1 END
UNION ALL
SELECT 'no_mutate_has_cascade_carveout',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_proc
         WHERE proname = 'action_sends_no_mutate'
           AND prosrc ILIKE '%to_jsonb(NEW)%'
           AND prosrc ILIKE '%NEW.message_id IS NULL%'
       ) THEN 0 ELSE 1 END
UNION ALL
SELECT 'no_mutate_has_initiator_check',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_proc
         WHERE proname = 'action_sends_no_mutate'
           AND prosrc ILIKE '%NOT EXISTS%'
           AND prosrc ILIKE '%public.messages%'
       ) THEN 0 ELSE 1 END
UNION ALL
SELECT 'no_mutate_row_level_gate',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_proc
         WHERE proname = 'action_sends_no_mutate'
           AND prosrc ILIKE '%TG_LEVEL%ROW%'
       ) THEN 0 ELSE 1 END
UNION ALL
SELECT 'no_mutate_worm_bypass_preserved',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_proc
         WHERE proname = 'action_sends_no_mutate'
           AND prosrc ILIKE '%app.worm_bypass%'
       ) THEN 0 ELSE 1 END
UNION ALL
SELECT 'anonymise_clears_message_id',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_proc
         WHERE proname = 'anonymise_action_sends'
           AND prosrc ILIKE '%message_id%NULL%'
       ) THEN 0 ELSE 1 END;
