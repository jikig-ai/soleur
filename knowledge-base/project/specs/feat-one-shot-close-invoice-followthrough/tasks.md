# Tasks: Close Invoice Recovery Follow-Through

Source: `knowledge-base/project/plans/2026-04-13-chore-close-invoice-recovery-followthrough-plan.md`

## Phase 1: Create Tracking Issues (#2099)

- [x] 1.1 Create issue: invoice.paid unconditional activation guard → #2102
- [x] 1.2 Create issue: banner dismiss sessionStorage → #2103
- [x] 1.3 Create issue: TOCTOU on WS subscription check → #2104
- [x] 1.4 Create issue: invoice endpoint rate limiting → #2105
- [x] 1.5 Close #2099 with comment listing the 4 new issue numbers

## Phase 2: Verify Migration 022 (#2100)

- [x] 2.1 Authenticate with Supabase (Management API via Doppler prd)
- [x] 2.2 Query `information_schema.check_constraints` for `users_subscription_status_check` — confirmed present
- [x] 2.3 Functional test: set `subscription_status = 'unpaid'` on a test row, verified success, restored
- [x] 2.4 Close #2100 with verification evidence comment

## Phase 3: Update Roadmap

- [x] 3.1 Update roadmap row 3.14 status from "Not started" to "Done"
- [x] 3.2 Update Current State section (synced all milestone counts from GitHub)
- [ ] 3.3 Commit and push all changes
