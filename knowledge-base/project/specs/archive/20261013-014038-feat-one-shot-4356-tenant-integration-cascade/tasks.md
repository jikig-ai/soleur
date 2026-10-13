---
plan: knowledge-base/project/plans/2026-05-22-fix-tenant-integration-cascade-4356-plan.md
issue: 4356
lane: cross-domain
brand_survival_threshold: single-user-incident
---

# Tasks — #4356 tenant-integration cascade fix

Derived from the deepened plan. Phases are sequenced; tasks within a phase can run in
parallel unless dependency-noted.

## Phase 0 — Preconditions (RED unverified)

- [ ] 0.1 `pwd` returns the worktree path.
- [ ] 0.2 `git branch --show-current` returns `feat-one-shot-4356-tenant-integration-cascade`.
- [ ] 0.3 `ls apps/web-platform/supabase/migrations/ | grep '^064'` returns nothing.
- [ ] 0.4 `gh pr view 4343 --json state --jq '.state'` returns `MERGED`.
- [ ] 0.5 Migration runner verified: `bash apps/web-platform/scripts/run-migrations.sh` (NOT `bun`, NO `--dry-run`). Schema-cache reload via `bash apps/web-platform/scripts/postgrest-reload-schema.sh`.
- [ ] 0.6 Sweep current state: `rg -lUn 'from\("(conversations|messages)"\)\s*\n?\s*\.insert\(' apps/web-platform/test/server/*.test.ts` returns ~15 files; only `template-authorizations-worm.test.ts` and `action-sends-worm.test.ts` should lack `workspace_id` per `grep -L workspace_id`.

## Phase 1 — Migration 064 (RED)

- [ ] 1.1 Create `apps/web-platform/supabase/migrations/064_anonymise_scope_grants_workspace_id_and_member_actions_grant.sql`:
  - Header comment citing #4356 + #4249 + the two failure classes.
  - `CREATE OR REPLACE FUNCTION public.anonymise_scope_grants(p_user_id uuid)` with body lifting mig 050:74-92 verbatim except SET clause:
    ```sql
    UPDATE public.scope_grants
       SET founder_id = NULL,
           workspace_id = NULL
     WHERE founder_id = p_user_id;
    ```
  - `SET search_path = public, pg_temp` retained on the SECURITY DEFINER fn (per `cq-pg-security-definer-search-path-pin-pg-temp`).
  - `REVOKE ALL ON FUNCTION public.anonymise_scope_grants(uuid) FROM PUBLIC, anon, authenticated;`
  - `GRANT EXECUTE ON FUNCTION public.anonymise_scope_grants(uuid) TO service_role;`
  - `GRANT SELECT ON public.workspace_member_actions TO service_role;` (additive; sibling-table parity with mig 037 / mig 036).
  - Header comment documents Shape 2 trigger implicit-permission of workspace_id (the CHECK constraint is the canonical guard).
- [ ] 1.2 Create `apps/web-platform/supabase/migrations/064_anonymise_scope_grants_workspace_id_and_member_actions_grant.down.sql`:
  - `CREATE OR REPLACE FUNCTION public.anonymise_scope_grants(p_user_id uuid)` with body reverted to mig 050's single-column NULL form.
  - `REVOKE SELECT ON public.workspace_member_actions FROM service_role;`
- [ ] 1.3 RED: run `cd apps/web-platform && bun test test/server/scope-grants/lifecycle.test.ts` — expect failure at line 268 (pre-apply).

## Phase 2 — Apply in DEV (GREEN partial)

- [ ] 2.1 `cd apps/web-platform && doppler run -c dev -- bash scripts/run-migrations.sh` — applies 064; expect `Applied: 064_anonymise_scope_grants_workspace_id_and_member_actions_grant.sql`.
- [ ] 2.2 `bash apps/web-platform/scripts/postgrest-reload-schema.sh` — reload PostgREST schema cache (`NOTIFY pgrst, 'reload schema'`).
- [ ] 2.3 Verify function body: `doppler run -c dev -- psql "$DATABASE_URL" -c "\sf public.anonymise_scope_grants"` shows both `founder_id = NULL` AND `workspace_id = NULL` in SET clause.
- [ ] 2.4 Verify table privileges: `doppler run -c dev -- psql "$DATABASE_URL" -c "\dp public.workspace_member_actions"` shows `r/service_role` (SELECT present); no UPDATE/INSERT/DELETE for service_role.

## Phase 3 — Worm-test fixture fixes (GREEN remainder)

- [ ] 3.1 Edit `apps/web-platform/test/server/template-authorizations-worm.test.ts`:
  - Line 79: change `.insert({ user_id: userId })` → `.insert({ user_id: userId, workspace_id: userId })` (solo-canary convention).
  - Lines 87-99: add `workspace_id: userId,` to messages.insert object.
- [ ] 3.2 Edit `apps/web-platform/test/server/action-sends-worm.test.ts`:
  - Same shape at lines 85 and 94-105.
- [ ] 3.3 Run AC8 + AC9 + AC10 + AC11 locally:
  ```
  cd apps/web-platform && bun test \
    test/server/scope-grants/lifecycle.test.ts \
    test/server/template-authorizations-worm.test.ts \
    test/server/action-sends-worm.test.ts \
    test/server/workspace-member-actions.integration.test.ts \
    test/server/dsar-export-workspace-tables.integration.test.ts
  ```
  All exit 0.

## Phase 4 — Learning file update

- [ ] 4.1 Append `## Follow-up: #4356 expanded scope` section to `knowledge-base/project/learnings/2026-05-22-tenant-integration-runtime-failures-post-mig-059.md` documenting:
  - The 4 sibling failure classes (G/H/I/J) the deepen-pass grep missed.
  - Grep-scope fix: future sweeps drop `*.tenant-isolation.test.ts$` filter and scan `*.test.ts` under `apps/web-platform/test/server/`.
  - Contract-pair generalization: `anonymise_*` siblings for any table that gains NOT NULL or CHECK constraints must be enumerated alongside primary writer.
  - Sibling-table GRANT parity: WORM-table service_role SELECT is the canonical pattern (mig 037, 036); explicit REVOKE on workspace_member_actions (mig 063:80-81) was the outlier.

## Phase 5 — Sweep verification (AC13 + AC15)

- [ ] 5.1 Run the post-fix sweep:
  ```
  rg -lUn 'from\("(conversations|messages)"\)\s*\n?\s*\.insert\(' apps/web-platform/test/server/*.test.ts \
    | xargs -I{} sh -c 'grep -L "workspace_id" {} && echo "MISSING_WORKSPACE_ID: {}"'
  ```
  Expect zero MISSING lines.
- [ ] 5.2 `tsc --noEmit` exits 0: `cd apps/web-platform && bun run tsc --noEmit`.

## Phase 6 — PR submission + CI

- [ ] 6.1 `git add` ONLY: the 2 migration files, the 2 test file edits, the learning file, this tasks.md, the plan, spec stub. Never `git add -A`.
- [ ] 6.2 Commit with message `fix(tenant-integration): repair anonymise_scope_grants CHECK constraint + workspace_member_actions SELECT GRANT + 2 worm-test fixtures` and body referencing `Closes #4356, Ref #4249, Ref #4342, Ref #4343`.
- [ ] 6.3 Push branch; open PR. PR body MUST include the Brand-survival threshold callout (single-user incident) and CPO sign-off note.
- [ ] 6.4 Watch `gh pr checks <N> --watch` until `.github/workflows/tenant-integration.yml` job goes green (AC12).

## Phase 7 — Review + merge

- [ ] 7.1 Run `pr-review-toolkit:review-pr` — `user-impact-reviewer` is auto-invoked at single-user-incident threshold.
- [ ] 7.2 Address findings inline (default — `rf-review-finding-default-fix-inline`).
- [ ] 7.3 Mark ready; `gh pr merge <N> --squash --auto`.

## Phase 8 — Post-merge (operator)

- [ ] 8.1 Watch `web-platform-release.yml#migrate` job apply 064 in prd.
- [ ] 8.2 Prd verification via Supabase MCP (`mcp__plugin_supabase_supabase__execute_sql`):
  ```sql
  SELECT founder_id, workspace_id
  FROM scope_grants
  WHERE founder_id IS NULL
  LIMIT 5;
  ```
  Expect zero rows OR all rows with `workspace_id IS NULL`. If stale `workspace_id NOT NULL` rows exist (pre-fix Art. 17 attempts that left half-anonymised state), document via Art. 30 register addendum AND file follow-up issue for one-shot backfill.
- [ ] 8.3 `gh issue close 4356 --comment "Resolved by PR #<N>; lifecycle.test.ts:268 + 3 sibling tests now green."`.
- [ ] 8.4 `gh issue close 4249 --comment "Original lifecycle.test.ts symptom fully resolved by #4343 + #<N>."` (Optional — #4249 may have additional contexts).

## Phase 9 — Follow-up filings (Risks scope-outs)

- [ ] 9.1 File issue: "obs: add Sentry.captureException to account-delete.ts anonymise_scope_grants failure paths" (logs-only today; Sentry tagging gap noted in Risks).
- [ ] 9.2 File issue (only if pre-fix prd had affected rows per 8.2): "data: backfill scope_grants rows where founder_id IS NULL AND workspace_id IS NOT NULL".
