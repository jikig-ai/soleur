-- Add health_snapshot column to users table.
-- Stores the project scanner output (languages, frameworks, team structure)
-- written by the setup/route.ts server action after repo cloning.
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS health_snapshot jsonb DEFAULT NULL;

-- DEFENSE-IN-DEPTH: The column-level GRANT model (migration 006) already
-- prevents authenticated users from updating health_snapshot — only `email`
-- is in the GRANT list. This RESTRICTIVE policy is belt-and-suspenders:
-- if a future migration accidentally adds health_snapshot to the GRANT,
-- this policy still blocks client-side overwrites.
-- Service role bypasses RLS, so server writes are unaffected.
CREATE POLICY "Prevent client health_snapshot update" ON public.users
  AS RESTRICTIVE FOR UPDATE TO authenticated
  USING (
    health_snapshot IS NOT DISTINCT FROM (SELECT health_snapshot FROM public.users WHERE id = auth.uid())
  );
