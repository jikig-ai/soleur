-- 098_workspace_logos.down.sql
-- Reverses 098_workspace_logos.sql for the objects SQL can drop, in order:
--   policies -> function -> column.
--
-- The Storage bucket row and its objects are NOT removed here. Supabase
-- installs a platform trigger `protect_objects_delete` (storage.protect_delete)
-- that BLOCKS `DELETE FROM storage.objects` AND `DELETE FROM storage.buckets`
-- with "Direct deletion from storage tables is not allowed. Use the Storage
-- API instead." (verified against DEV 2026-06-04). Bucket-creating migrations
-- 019/042 likewise ship no SQL bucket teardown for this reason; 071's
-- `DELETE FROM storage.buckets` is a dormant bug that would fail if ever run.
--
-- Rollback of the bucket + its objects is therefore an operator/Storage-API
-- step (rarely needed — a down of a forward-only additive feature). The empty
-- bucket is harmless if left: no column references it once logo_path is
-- dropped, and the route is gone after a code rollback.

DROP POLICY IF EXISTS "Workspace members read workspace logo objects" ON storage.objects;
DROP POLICY IF EXISTS "Workspace owners write logo objects only (insert)" ON storage.objects;
DROP POLICY IF EXISTS "Workspace owners write logo objects only (update)" ON storage.objects;
DROP POLICY IF EXISTS "Workspace owners write logo objects only (delete)" ON storage.objects;

DROP FUNCTION IF EXISTS public.is_workspace_owner(uuid, uuid);

ALTER TABLE public.workspaces DROP COLUMN IF EXISTS logo_path;
