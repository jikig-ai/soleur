-- Add github_username column for email-only user identity resolution.
-- Used by detect-installation as a fallback when no Supabase GitHub identity exists.
-- No uniqueness constraint: multi-account model allows multiple Soleur accounts
-- to resolve to the same GitHub username.
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS github_username TEXT;
