# Tasks: feat-supabase-disk-io-budget

Derived from `knowledge-base/project/plans/2026-05-06-fix-supabase-disk-io-cron-realtime-plan.md`.
Issue: #3358. Draft PR: #3356. Brand-survival threshold: `single-user incident` (CPO sign-off required before /work).

## Phase 1: Tests First (TDD)

- [ ] 1.1 Create `apps/web-platform/test/supabase-migrations/038-039-disk-io-fix.test.ts` with the dual-`describe` structure from the plan (Phase 3). Tests must FAIL before any migration is written.
  - [ ] 1.1.1 `038` describe — assert `cron.unschedule('user_concurrency_slots_sweep')`, `cron.schedule(...)` with `*/15 * * * *`, AND a literal-shape assertion on the DELETE body (`delete from public.user_concurrency_slots where last_heartbeat_at < now() - interval '120 seconds'`).
  - [ ] 1.1.2 `039` describe — assert `ALTER PUBLICATION supabase_realtime DROP TABLE public.messages`, NOT-drop `public.conversations`, `pg_publication_tables` guard with `IF EXISTS`.
- [ ] 1.2 Run `bun test apps/web-platform/test/supabase-migrations/038-039-disk-io-fix.test.ts` — expect failures (the migration files do not exist yet).

## Phase 2: Migration 038 — slow `user_concurrency_slots_sweep`

- [ ] 2.1 Create `apps/web-platform/supabase/migrations/038_slow_user_concurrency_slots_sweep.sql` with the body specified in plan Phase 1.
- [ ] 2.2 Verify the file's text matches the test assertions: `bun test apps/web-platform/test/supabase-migrations/038-039-disk-io-fix.test.ts` — `038` describe block green, `039` still failing.
- [ ] 2.3 Pre-merge AC #5: `grep -r "user_concurrency_slots_sweep" apps/web-platform/supabase/migrations/` returns ONLY 029 + 038 (no sibling rename drift).

## Phase 3: Migration 039 — drop `public.messages` from `supabase_realtime`

- [ ] 3.1 Create `apps/web-platform/supabase/migrations/039_drop_messages_from_realtime_publication.sql` with the body specified in plan Phase 2.
- [ ] 3.2 Verify content tests pass: `bun test apps/web-platform/test/supabase-migrations/038-039-disk-io-fix.test.ts` — both describe blocks green.
- [ ] 3.3 Confirm `apps/web-platform/hooks/use-conversations.ts` is NOT touched (`git status` shows only the two `.sql` and the one `.test.ts` modified).

## Phase 4: PR readiness

- [ ] 4.1 `bun run typecheck` and `bun run lint` green from the worktree root.
- [ ] 4.2 Capture before-snapshot from prd via Supabase Management API (queries in plan Phase 4); paste into PR description under `## Before snapshot (2026-05-06)`.
- [ ] 4.3 Add `## Roll-back` section to PR description (copy from plan Roll-back section).
- [ ] 4.4 Verify PR body uses `Ref #3358` (NOT `Closes #3358`) per `classification: ops-only-prod-write`.
- [ ] 4.5 Apply `semver:patch` label.
- [ ] 4.6 Mark PR ready and request CPO sign-off on the User-Brand Impact section.
- [ ] 4.7 Run `/soleur:review` — expect `user-impact-reviewer` to pass; resolve any findings inline per `rf-review-finding-default-fix-inline`.

## Phase 5: Merge + post-merge verification (operator)

- [ ] 5.1 `gh pr merge 3356 --squash --auto`; poll until MERGED.
- [ ] 5.2 Confirm `web-platform-release.yml` `migrate` job applies 038 + 039 to prd.
- [ ] 5.3 Behavior verification (Management API):
  - `SELECT jobname, schedule FROM cron.job WHERE jobname = 'user_concurrency_slots_sweep';` → schedule = `*/15 * * * *`.
  - `SELECT schemaname, tablename FROM pg_publication_tables WHERE pubname = 'supabase_realtime' ORDER BY tablename;` → `public.conversations` PRESENT, `public.messages` ABSENT.
- [ ] 5.4 `SELECT pg_stat_statements_reset();` via Management API immediately after migrate completes.
- [ ] 5.5 +30 min: dashboard chat smoke-test (two-tab: send message in A, verify B's conversation list AND message body update within ~2s).
- [ ] 5.6 +24 hours: re-pull `pg_stat_statements` top 10 + Disk IO Budget gauge; append to PR description as after-snapshot.
- [ ] 5.7 +7 days: confirm Disk IO Budget gauge is recovering (climbing back), not just stable.
- [ ] 5.8 `gh issue close 3358` with a comment summarizing the deltas. Run compound to capture any post-merge learnings.
