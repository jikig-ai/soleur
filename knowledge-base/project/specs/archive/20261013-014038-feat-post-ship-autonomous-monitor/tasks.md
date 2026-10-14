# Tasks: Post-Ship Autonomous Monitor

## Phase 0: Prerequisites
- [x] 0.1 Verify `SENTRY_AUTH_TOKEN` exists in Doppler `prd` with `org:read` scope
- [x] 0.2 Live-test Sentry monitors API endpoint (must return HTTP 200)
- [x] 0.3 Verify `test-fix-loop` skill exists and is loadable

## Phase 1: Ship Phase 7 — CI auto-fix
- [x] 1.1 Read ship/SKILL.md lines 1215–1225 (current CI failure handler)
- [x] 1.2 Replace with test-fix-loop delegation: distinguish required-check-failure exit (PR OPEN) from CLOSED exit
- [x] 1.3 Add `fix_attempt_count` agent-level counter documentation (1 attempt, then escalate)
- [x] 1.4 Remove `gh pr reopen` — just push fix + re-queue auto-merge
- [x] 1.5 Document that DIRTY/merge-conflict handling is already in the poll block — not duplicated here

## Phase 2: Ship Phase 7 — postmerge chain
- [x] 2.1 Insert Step 3.8 before "4. Clean up worktree" (~line 1626): `skill: soleur:postmerge <PR-number>`
- [x] 2.2 Document advisory-only semantics: failures display but don't block cleanup

## Phase 3: Postmerge Phase 3.5 — Sentry cron monitor check
- [x] 3.1 Insert Phase 3.5 between Phase 3 (line 97) and Phase 4 (line 99)
- [x] 3.2 Implement cron monitor health query using `SENTRY_AUTH_TOKEN` with `SENTRY_API_TOKEN` fallback
- [x] 3.3 Add graceful degradation: warn and skip on missing token or API failure
- [x] 3.4 Update Phase 7 report template to include Sentry monitor results
- [x] 3.5 Update Phase 6 issue comment template to include Sentry monitor results

## Phase 4: Verification
- [x] 4.1 Verify Phase 7 poll block mirror (`merge-pr/SKILL.md §5.2`) is NOT affected
- [x] 4.2 Verify all AC criteria are met
- [x] 4.3 Run `bun test plugins/soleur/test/components.test.ts` to check skill description budget
