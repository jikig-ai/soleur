# Tasks: Verify REPLICA IDENTITY FULL Migration

## Phase 1: Verification

- [ ] 1.1 Retrieve production Supabase credentials from Doppler (`prd` config)
- [ ] 1.2 Query `conversations` table via REST API to confirm table exists and RLS is active
- [ ] 1.3 Verify `REPLICA IDENTITY FULL` via SQL query (`relreplident = 'f'` in `pg_class`)

## Phase 2: Closure

- [ ] 2.1 Post verification results as comment on GitHub issue #1766
- [ ] 2.2 Close GitHub issue #1766 if both checks pass
- [ ] 2.3 If checks fail: investigate migration application status and document findings
