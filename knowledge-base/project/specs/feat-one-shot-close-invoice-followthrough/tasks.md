# Tasks: Close Invoice Recovery Follow-Through

Source: `knowledge-base/project/plans/2026-04-13-chore-close-invoice-recovery-followthrough-plan.md`

## Phase 1: Create Tracking Issues (#2099)

- [ ] 1.1 Create issue: invoice.paid unconditional activation guard
  - `gh issue create --title "fix(billing): guard invoice.paid handler to only restore from past_due/unpaid" --label code-review --milestone "Post-MVP / Later" --body "..."`
- [ ] 1.2 Create issue: banner dismiss sessionStorage
  - `gh issue create --title "fix(billing): use sessionStorage for payment warning banner dismiss" --label code-review --milestone "Post-MVP / Later" --body "..."`
- [ ] 1.3 Create issue: TOCTOU on WS subscription check
  - `gh issue create --title "fix(billing): address TOCTOU window in WebSocket subscription cache" --label code-review --milestone "Post-MVP / Later" --body "..."`
- [ ] 1.4 Create issue: invoice endpoint rate limiting
  - `gh issue create --title "fix(billing): add application-level rate limiting to invoice endpoint" --label code-review --milestone "Post-MVP / Later" --body "..."`
- [ ] 1.5 Close #2099 with comment listing the 4 new issue numbers

## Phase 2: Verify Migration 022 (#2100)

- [ ] 2.1 Authenticate with Supabase (MCP or REST API via Doppler prd)
- [ ] 2.2 Query `information_schema.check_constraints` for `users_subscription_status_check`
- [ ] 2.3 Functional test: set `subscription_status = 'unpaid'` on a test row, verify success, restore
- [ ] 2.4 Close #2100 with verification evidence comment

## Phase 3: Update Roadmap

- [ ] 3.1 Update roadmap row 3.14 status from "Not started" to "Done"
- [ ] 3.2 Update Current State section (remove #1079 from remaining list)
- [ ] 3.3 Commit and push all changes
