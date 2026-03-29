-- 011_repo_connection.sql
-- Adds repository connection columns to the users table.
-- Idempotent: safe to run on both empty and populated databases.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS repo_url text,
  ADD COLUMN IF NOT EXISTS repo_provider text DEFAULT 'github',
  ADD COLUMN IF NOT EXISTS github_installation_id bigint,
  ADD COLUMN IF NOT EXISTS repo_status text DEFAULT 'not_connected'
    CHECK (repo_status IN ('not_connected', 'cloning', 'ready', 'error')),
  ADD COLUMN IF NOT EXISTS repo_last_synced_at timestamptz;
