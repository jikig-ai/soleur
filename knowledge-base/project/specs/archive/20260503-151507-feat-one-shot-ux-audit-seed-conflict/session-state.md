# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-ux-audit-seed-conflict/knowledge-base/project/plans/2026-05-03-fix-ux-audit-seed-conflict-plan.md
- Status: complete

### Errors
None. Both deepen-plan gates passed cleanly: Phase 4.5 (network-outage) does not apply (Postgres SQLSTATE error, not SSH/network); Phase 4.6 (User-Brand Impact) PASS — section present, threshold `none` with valid sensitive-path scope-out reason for the migration touching `apps/web-platform/supabase/migrations/`.

### Decisions
- Root cause confirmed via live prd repro: PostgREST + partial-index inference (hypothesis 2). Migration was applied; no Doppler drift.
- Fix path: migration 035 swaps the partial unique index for a non-partial one on `(user_id, session_id)`. 14 existing NULL `session_id` rows coexist under non-partial unique indexes (NULLS DISTINCT default).
- Lock the contract with a PostgREST inference contract test in `bot-fixture.test.ts`.
- Use `Ref #2584` and `Ref #2585` — post-merge follow-through issues; resolve only after operator dispatch + cron success.
- Originating defect (2026-04-18 prior plan asserted partial-index support without live probe) is documented as Sharp Edge + learning file.

### Components Invoked
- soleur:plan
- Context7 MCP (PostgREST, PostgreSQL 17 docs)
- Doppler CLI (verified prd / prd_scheduled / dev / prd_terraform configs)
- curl against prd Supabase REST (live 42P10 repro + NULL-session_id inventory)
- gh CLI (issue overlap check, #2584/#2585 follow-through context)
- soleur:deepen-plan
