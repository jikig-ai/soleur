-- Stop trusting client-supplied tc_accepted metadata.
-- T&C acceptance is now recorded by the server-side /api/accept-terms route.
-- New users always start with tc_accepted_at = NULL until they explicitly
-- accept terms on the /accept-terms page.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (id, email, workspace_path, tc_accepted_at)
  VALUES (
    new.id,
    new.email,
    '/workspaces/' || new.id::text,
    NULL  -- always NULL; server-side acceptance route sets the real timestamp
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON COLUMN public.users.tc_accepted_at IS
  'Timestamp when user accepted T&C via server-side /accept-terms page. NULL = not yet accepted. Set exclusively by POST /api/accept-terms using service role client.';
