-- Down for 082. MANUAL ROLLBACK ONLY — run-migrations.sh never auto-applies
-- *.down.sql. Re-adding NOT NULL FAILS if any draft-card row exists (they carry
-- NULL conversation_id/role/content). The guard below aborts BEFORE dropping
-- the discriminator CHECK so the rollback is all-or-nothing (no partial state
-- where the CHECK is gone but NOT NULL is not restored).

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.messages WHERE conversation_id IS NULL) THEN
    RAISE EXCEPTION
      'cannot restore NOT NULL: % draft-card rows exist (conversation_id IS NULL); purge or migrate them first',
      (SELECT count(*) FROM public.messages WHERE conversation_id IS NULL);
  END IF;
END $$;

ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_row_kind_chk;
ALTER TABLE public.messages ALTER COLUMN content         SET NOT NULL;
ALTER TABLE public.messages ALTER COLUMN role            SET NOT NULL;
ALTER TABLE public.messages ALTER COLUMN conversation_id SET NOT NULL;
