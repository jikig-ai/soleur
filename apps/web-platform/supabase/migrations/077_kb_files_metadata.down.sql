-- 077_kb_files_metadata.down.sql
-- Reversal of 077_kb_files_metadata.sql

-- 1. Drop functions
DROP FUNCTION IF EXISTS public.set_kb_file_visibility(uuid, text);
DROP FUNCTION IF EXISTS public.kb_files_set_updated_at();

-- 2. Drop table (CASCADE drops policies + indexes + triggers)
DROP TABLE IF EXISTS public.kb_files CASCADE;
