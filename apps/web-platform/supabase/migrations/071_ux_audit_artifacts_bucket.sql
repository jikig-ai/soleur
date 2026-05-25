-- 071_ux_audit_artifacts_bucket.sql
-- TR9 PR-11 Phase 3 (issue #4464).
--
-- Private `ux-audit-artifacts` Storage bucket for monthly UX audit findings.
-- Path layout: ux-audit-artifacts/<run-iso-date>/findings.json
--              ux-audit-artifacts/<run-iso-date>/<screenshot>.png
--
-- RLS: only the ux-audit bot (looked up at migration time) can read/write.
-- Hardcoded UUID in the policy avoids a runtime subquery on auth.users,
-- which RLS policies on storage.objects cannot reliably access.
--
-- The bot must exist before this migration runs (bot-fixture.ts seed).

DO $$
DECLARE
  bot_id uuid;
BEGIN
  SELECT id INTO bot_id
    FROM auth.users
   WHERE email = 'ux-audit-bot@jikigai.com';

  IF bot_id IS NULL THEN
    RAISE EXCEPTION 'ux-audit-bot@jikigai.com not found in auth.users — run bot-fixture.ts seed first';
  END IF;

  INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  VALUES (
    'ux-audit-artifacts',
    'ux-audit-artifacts',
    false,
    10485760,
    ARRAY['image/png', 'application/json']
  );

  EXECUTE format(
    'CREATE POLICY "ux-audit-bot tenant read/write"
      ON storage.objects FOR ALL
      USING (bucket_id = ''ux-audit-artifacts'' AND auth.uid() = %L)
      WITH CHECK (bucket_id = ''ux-audit-artifacts'' AND auth.uid() = %L)',
    bot_id, bot_id
  );
END $$;
