# Tasks: remediate fabricated tc_accepted_at timestamps (#934)

## Phase 1: Setup

- [ ] 1.1 Read existing migrations in `apps/web-platform/supabase/migrations/` to confirm numbering (next is `007`)
- [ ] 1.2 Read `005_add_tc_accepted_at.sql` to verify trigger logic for reference
- [ ] 1.3 Read `006_restrict_tc_accepted_at_update.sql` to confirm column grant model

## Phase 2: Core Implementation

- [ ] 2.1 Create `apps/web-platform/supabase/migrations/007_remediate_fabricated_tc_accepted_at.sql`
  - [ ] 2.1.1 Add header comment documenting bug origin (PR #898), fix (PR #927), GDPR rationale, and idempotency
  - [ ] 2.1.2 Add commented-out dry-run SELECT query joining `public.users` with `auth.users` on `id`, filtering `tc_accepted_at IS NOT NULL AND raw_user_meta_data->>'tc_accepted' IS DISTINCT FROM 'true'`
  - [ ] 2.1.3 Add UPDATE statement setting `tc_accepted_at = NULL` for rows matching the discriminator
  - [ ] 2.1.4 Verify UPDATE uses `FROM auth.users a WHERE public.users.id = a.id` join syntax (not a subquery) for clarity

## Phase 3: Verification

- [ ] 3.1 Run TypeScript type-check (`npx tsc --noEmit`) to confirm no regressions
- [ ] 3.2 Run test suite (`bun test`) to confirm no regressions
- [ ] 3.3 Verify migration file is valid SQL (no syntax errors)
- [ ] 3.4 Confirm idempotency: the UPDATE WHERE clause only matches rows with non-null `tc_accepted_at`, so a second run is a no-op

## Phase 4: Ship

- [ ] 4.1 Run `skill: soleur:compound` before commit
- [ ] 4.2 Commit with message: `fix(data): remediate fabricated tc_accepted_at timestamps (#934)`
- [ ] 4.3 Push and create PR with `Closes #934` in body
