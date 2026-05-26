-- 071_ux_audit_artifacts_bucket.down.sql

DROP POLICY IF EXISTS "ux-audit-bot tenant read/write" ON storage.objects;
DELETE FROM storage.buckets WHERE id = 'ux-audit-artifacts';
