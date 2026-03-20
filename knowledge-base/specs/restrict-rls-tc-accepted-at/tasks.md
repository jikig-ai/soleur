# Tasks: restrict RLS UPDATE policy on tc_accepted_at column

## Phase 1: Investigation

- [ ] 1.1 Verify current grant model on `public.users` for the `authenticated` role (table-level vs column-level)
- [ ] 1.2 List all columns on `public.users` that authenticated users should be able to update

## Phase 2: Core Implementation

- [ ] 2.1 Create migration `apps/web-platform/supabase/migrations/006_restrict_tc_accepted_at_update.sql`
  - [ ] 2.1.1 Revoke table-level UPDATE on `public.users` from `authenticated` (if table-level grant exists)
  - [ ] 2.1.2 Grant column-level UPDATE on user-updatable columns (`email`, `workspace_path`, `workspace_status`, `stripe_customer_id`, `subscription_status`) to `authenticated`
  - [ ] 2.1.3 Ensure `tc_accepted_at` and `created_at` are excluded from the column-level grants
  - [ ] 2.1.4 Add comments explaining the security rationale and SECURITY DEFINER bypass

## Phase 3: Verification

- [ ] 3.1 Verify `handle_new_user()` trigger still sets `tc_accepted_at` (SECURITY DEFINER bypass)
- [ ] 3.2 Verify `ensureWorkspaceProvisioned()` fallback still works (service role bypass)
- [ ] 3.3 Verify authenticated users can still update allowed columns
- [ ] 3.4 Verify authenticated users cannot update `tc_accepted_at`
- [ ] 3.5 Verify migration idempotency (run twice without error)
