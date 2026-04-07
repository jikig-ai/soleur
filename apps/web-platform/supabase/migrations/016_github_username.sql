-- Add github_username column for email-only user identity resolution.
-- Used by detect-installation as a fallback when no Supabase GitHub identity exists.
-- No uniqueness constraint: multi-account model allows multiple Soleur accounts
-- to resolve to the same GitHub username.
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS github_username TEXT;

-- Prevent client-side updates to github_username via the anon-key Supabase client.
-- Only the service role (used by the OAuth callback route) should write this column.
-- Without this policy, any authenticated user could set github_username to a victim's
-- username and claim their GitHub App installation (installation takeover).
CREATE POLICY "Users cannot update github_username directly"
  ON public.users
  AS RESTRICTIVE
  FOR UPDATE
  USING (true)
  WITH CHECK (
    github_username IS NOT DISTINCT FROM (SELECT github_username FROM public.users WHERE id = auth.uid())
  );
