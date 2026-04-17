# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-kb-chat-ui-bundle-2347-followups/knowledge-base/project/plans/2026-04-17-fix-kb-chat-ui-bundle-2347-followups-plan.md
- Status: complete

### Errors
None.

### Decisions
- Reconciled post-#2347 refactor: kb-chat state/focus logic moved from `kb-chat-sidebar.tsx` to `kb-chat-content.tsx`. Fixes for #2384 5B and #2385 target the new location; issue line numbers are stale.
- Dropped re-fix of #2390 10D: the 23505 index-name disambiguation guard already shipped in `server/ws-handler.ts:295-300` via #2382. Plan replaces the fix with a regression/characterization test (AC9) per `rf-review-finding-default-fix-inline`.
- Dropped retroactive PR-body edit for #2390 10B: PR #2347 is already merged; folded verification + rollback SQL into the new runbook (Phase 6).
- Used existing runbook path `knowledge-base/engineering/ops/runbooks/supabase-migrations.md` (matches existing runbook convention) rather than the issue-suggested `knowledge-base/project/runbooks/`.
- Mandated `Sentry.captureException` for AC4 after deepen-pass confirmed `@sentry/nextjs` is wired client+server with existing call sites.
- Scope-out exception pattern applied: single themed PR bundles three `deferred-scope-out`-labeled review-origin issues, batched by theme per review-findings workflow.

### Components Invoked
- Bash, Read, Glob, Grep, Write, Edit
- Skill: soleur:plan
- Skill: soleur:deepen-plan
