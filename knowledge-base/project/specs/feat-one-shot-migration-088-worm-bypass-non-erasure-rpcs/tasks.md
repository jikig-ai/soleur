---
title: "Tasks — Migration 088 WORM bypass for non-erasure RPCs"
plan: knowledge-base/project/plans/2026-05-31-fix-migration-088-worm-bypass-non-erasure-rpcs-plan.md
issue: 4702
lane: cross-domain
---

# Tasks — Migration 088

## Phase 0 — Preconditions
- [ ] 0.1 Copy exact pre-088 `purge_workspace_member_actions()` body from `apps/web-platform/supabase/migrations/063_workspace_member_actions.sql` (the `AS $$ … $$;` block).
- [ ] 0.2 Copy exact pre-088 `revoke_template_authorization(text, text)` body from `apps/web-platform/supabase/migrations/053_template_authorizations.sql`.
- [ ] 0.3 Confirm 088 is the next free migration number (`ls apps/web-platform/supabase/migrations/ | grep '^08'` — 087 is highest).
- [ ] 0.4 Confirm vitest include glob `test/**/*.test.ts` covers the new test path.

## Phase 1 — RED (cq-write-failing-tests-before)
- [ ] 1.1 Write `apps/web-platform/test/supabase-migrations/088-worm-bypass-non-erasure-rpcs.test.ts` mirroring the 087 test (reuse the `fnBlock` regex helper verbatim — handles `$$`/`$fn$`).
  - [ ] 1.1.1 Assert forward migration nowhere matches `/session_replication_role/i`.
  - [ ] 1.1.2 Per RPC (`purge_workspace_member_actions`, `revoke_template_authorization`): block matches `SET LOCAL app.worm_bypass = 'on'`, matches `'off'` (re-arm), does NOT match `session_replication_role`, keeps `search_path` pinned.
  - [ ] 1.1.3 List↔migration reconciliation: every `CREATE OR REPLACE FUNCTION public.<name>(` in 088 forward is in the declared 2-RPC set.
  - [ ] 1.1.4 Down migration matches `/session_replication_role/i`.
- [ ] 1.2 Run the test → fails (migration files absent / ENOENT).

## Phase 2 — GREEN
- [ ] 2.1 Write `apps/web-platform/supabase/migrations/088_worm_bypass_non_erasure_rpcs.sql`:
  - [ ] 2.1.1 §1 `purge_workspace_member_actions()` — verbatim 063 body with the two bypass-line swaps (`'on'` / `'off'`); re-issue REVOKE + GRANT; refresh COMMENT to cite `app.worm_bypass` + #4702. NO authz block (matches 063).
  - [ ] 2.1.2 §2 `revoke_template_authorization(text, text)` — verbatim 053 body with the two bypass-line swaps; preserve the `auth.uid()` + 8-value reason-enum + founder-attribution gates; re-issue REVOKE + GRANT; update inline bypass comment.
  - [ ] 2.1.3 Header comment block mirroring 087 (problem, why triggers already correct, fix = GUC swap only, scope = these 2 RPCs, conventions).
- [ ] 2.2 Write `apps/web-platform/supabase/migrations/088_worm_bypass_non_erasure_rpcs.down.sql` — both RPCs restored to the original `session_replication_role` bodies; forward-only WARNING header.
- [ ] 2.3 Run the new test → green.
- [ ] 2.4 Run the 087 test → still green (no shared-function regression).

## Phase 3 — Full suite + lint
- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/supabase-migrations/`.
- [ ] 3.2 (Optional) DEV-only live probe with synthesized fixtures (never PROD; `hr-dev-prd-distinct-supabase-projects`).

## Phase 4 — Ship
- [ ] 4.1 PR body uses `Closes #4702`.
- [ ] 4.2 Pre-merge AC checklist (see plan `## Acceptance Criteria → Pre-merge`).
- [ ] 4.3 Post-merge: migration applied by `web-platform-release.yml#migrate`; verify read-only via Supabase MCP (function body no longer contains `session_replication_role`).
