# Tasks: restrict RLS UPDATE policy on tc_accepted_at column

## Phase 1: Core Implementation

- [ ] 1.1 Create migration `apps/web-platform/supabase/migrations/006_restrict_tc_accepted_at_update.sql`
  - [ ] 1.1.1 `REVOKE UPDATE ON TABLE public.users FROM authenticated;` -- remove table-level UPDATE grant
  - [ ] 1.1.2 `GRANT UPDATE (email) ON TABLE public.users TO authenticated;` -- re-grant only user-safe columns
  - [ ] 1.1.3 Add comments documenting excluded columns and the rationale for each exclusion
  - [ ] 1.1.4 Add note about updating the GRANT when adding new columns to `public.users`

## Phase 2: Verification

- [ ] 2.1 Run verification query to confirm only `email` appears in `column_privileges` for `authenticated` with `UPDATE` type
- [ ] 2.2 Verify `handle_new_user()` trigger still sets `tc_accepted_at` (SECURITY DEFINER bypass)
- [ ] 2.3 Verify `ensureWorkspaceProvisioned()` INSERT fallback still works (service role + INSERT unaffected by UPDATE grants)
- [ ] 2.4 Verify Stripe webhook still updates `stripe_customer_id` and `subscription_status` (service role bypass)
- [ ] 2.5 Verify workspace API route still updates `workspace_path` and `workspace_status` (service role bypass)
- [ ] 2.6 Verify authenticated user cannot UPDATE `tc_accepted_at` via PostgREST
- [ ] 2.7 Verify authenticated user cannot UPDATE `stripe_customer_id` via PostgREST
- [ ] 2.8 Verify migration idempotency (run twice without error)
