# Session State

## Resume Prompt (one-shot #10254 / mig 162, in-flight)

- **Branch/worktree**: `feat-one-shot-10254-action-sends-message-id` at `/data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-10254-action-sends-message-id` (bare root is `/data/git-repositories/jikig-ai/soleur`; use `git -C` for commits). Draft PR **#10385** open.
- **Task**: implement ruled migration 162 for issue #10254 — `action_sends.message_id` nullable + `ON DELETE SET NULL` + row-level WORM carve-out (mirrors mig 161). Plan: `knowledge-base/project/plans/2026-10-15-fix-action-sends-message-id-erasure-plan.md`; checklist: `tasks.md` in this dir.
- **Gates passed**: plan+deepen (subagent bd14a6ac), technical-ruling-gate rc=0 (cto_spawns=1, agent afab5140), dual sign-off CPO (44a0175a) + user-impact-reviewer (aa2f5c27) both APPROVE. Pipeline tally: agent_rounds=2.
- **Committed**: plan + specs artifacts (commit on branch).
- **Done since (uncommitted)**: created `supabase/migrations/162_*.sql` + `.down.sql` + `supabase/verify/162_*.sql` + `test/supabase-migrations/162-*.test.ts`; removed `hasUndeletableActionSendsAnchor` + #10254 doc block from `test/helpers/tenant-isolation-teardown.ts`; removed `tolerate:` blocks + cleaned imports in `action-sends-worm.test.ts` + `template-authorizations-worm.test.ts`.
- **TODO**: (a) extend `test/server/account-delete.cascade.integration.test.ts` — seed scope_grants→messages→action_sends ancestors (pattern in `action-sends-worm.test.ts` `seedDraftMessage` + `grant_action_class` RPC, scope_grants via service-role), assert row survives with `message_id IS NULL`; (b) legal docs ×3 — `docs/legal/data-protection-disclosure.md` §2.3(r)+(t) + Last-Updated preamble (CPO conditions 1-3), `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` mirror, `knowledge-base/legal/article-30-register.md` ~344/421 (fix session_replication_role→app.worm_bypass, preserve transition-bound-not-role-bound wording); (c) `bash apps/web-platform/scripts/lint-migration-fk-preconditions.sh <162.sql>`; (d) commit all.
- **Then**: `soleur:review` → resolve findings (+ADR-267 fix-round) → `soleur:qa` → `soleur:compound` → `soleur:ship` → postmerge → `<promise>DONE</promise>`. node_modules absent (registry unreachable) — vitest runs CI-side.
- **Notes**: `#10254` assigned Phase 4 milestone; `action_sends.grant_id` descoped to #10379; depart_member greens confirmed on CI runs 38721345071/38734703094.

### Pipeline position update (post-work)
- Implementation committed + pushed: PR #10385, HEAD 482affd91c (12 files, +724/-97).
- Review panel armed (3 background seats): e6af6521 security-sentinel, 1897aaa9 code-quality, 97760956 data-integrity/cascade. Await findings → resolve ALL → ADR-267 fix-round if any → qa → compound → ship → postmerge → DONE.
- Known-verify gap to re-check if flagged: verify/162 tgtype value (should be 11 for BEFORE UPDATE ROW if 23 is wrong).
