-- 013_repo_error.sql
-- Stores the error message when project setup fails.
-- Allows the UI to display what went wrong instead of a generic message.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS repo_error text;
