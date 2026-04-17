# Session State

## Plan Phase

- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-mtd-cost-pg-aggregate/knowledge-base/project/plans/2026-04-17-fix-mtd-cost-pg-aggregate-plan.md
- Status: complete
- Branch: feat-mtd-cost-pg-aggregate
- Worktree: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-mtd-cost-pg-aggregate
- Draft PR: #2501

### Errors

None — Phase 0 live probe revealed Option A (PostgREST aggregate) not viable on hosted Supabase (PGRST123 "Use of aggregate functions is not allowed"). Pivoted to Option B (RPC + migration).

### Decisions

- Option A rejected via live probe — Supabase pins `db-aggregates-enabled = false` project-wide as DoS protection.
- Option B selected: security-definer RPC `sum_user_mtd_cost(uid, since)` in new migration `027_mtd_cost_aggregate.sql`.
- Migration verification required post-merge per wg-when-a-pr-includes-database-migrations (service-role 200, anon 4xx).
- Parity test: hand-summed NUMERIC-exact fixtures, no new deps (avoid `cq-before-pushing-package-json-changes` round-trip).
- Security hardened beyond spec: REVOKE EXECUTE FROM PUBLIC after CREATE OR REPLACE, mirroring migration 017's `increment_conversation_cost`.

### Components Invoked

- skill: soleur:plan
- skill: soleur:deepen-plan
- Live PostgREST probe (curl + Doppler)
- gh issue view 2478 / gh pr view 2464
- Learning files: 2026-03-28, 2026-04-05, 2026-03-20
- knowledge-base/engineering/ops/runbooks/supabase-migrations.md
