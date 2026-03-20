-- Add T&C version tracking column to users table.
--
-- Records which version of Terms & Conditions the user accepted.
-- NULL means the user has not yet accepted (or accepted before version tracking).
-- Combined with tc_accepted_at, this satisfies the ICO four-element consent
-- record requirement (identity, timing, document version, method).
--
-- The column is NOT added to the GRANT in migration 006 — it remains
-- server-write-only, same protection as tc_accepted_at.

ALTER TABLE public.users
  ADD COLUMN tc_accepted_version text;

COMMENT ON COLUMN public.users.tc_accepted_version IS
  'Semantic version of T&C the user accepted (e.g., "1.0.0"). NULL = not yet accepted or pre-version-tracking. Set exclusively by POST /api/accept-terms using service role client.';

-- Update handle_new_user() to include the new column (always NULL for new users,
-- consistent with server-side acceptance pattern from migration 007).
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (id, email, workspace_path, tc_accepted_at, tc_accepted_version)
  VALUES (
    new.id,
    new.email,
    '/workspaces/' || new.id::text,
    NULL,  -- server-side acceptance route sets the real timestamp
    NULL   -- server-side acceptance route sets the real version
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
