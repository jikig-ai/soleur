# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-01-fix-pending-invite-recovery-banner-public-users-column-plan.md
- Status: complete

### Errors
None. CWD verification passed; deepen-plan halt gates (4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-shaped) all passed. Planning artifacts committed and pushed.

### Decisions
- Root cause confirmed against live prod DB + worktree source: `getPendingInvitesForUser` (apps/web-platform/server/workspace-invitations.ts:74,128,136) embeds `raw_user_meta_data` on the `users` relationship, but `public.users` has no such column (auth.users-only) → PostgREST 42703 error on both query branches → empty result → recovery banner never renders → invite stays Pending. Shipped broken in PR #4713 (#4715).
- Fix: single-file (Option A) — drop `raw_user_meta_data` from select + type, derive `inviter_name = inviter?.email ?? "A team member"`.
- Regression test: existing mocks ignore the select arg (why it shipped green); new test captures + asserts the select string excludes auth-only columns and still embeds inviter email.
- Out of scope: redirect-precedence reorder, owner-delegation prompt.
- `Ref #4715` not `Closes` (issue already closed by #4713). Runner: vitest.

### Components Invoked
- soleur:plan, soleur:deepen-plan (via isolated general-purpose subagent)
