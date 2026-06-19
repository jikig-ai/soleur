# Tasks — fix(ci): Tenant integration (dev-Supabase) red on main (#5582)

Plan: `knowledge-base/project/plans/2026-06-19-fix-tenant-integration-ci-red-5582-plan.md`
Lane: single-domain · Domain: engineering · Threshold: single-user incident

## Phase 0 — Re-verify premises (verification claims decay)

- [ ] 0.1 Re-run multiline reader sweep `rg -nU 'from\("users"\)[\s\S]{0,400}?(workspace_path|repo_url|github_installation_id)' apps/web-platform/test` + `.eq/.in/.match` filter sweep; confirm/adjust the suite triage.
- [ ] 0.2 Confirm mig 064/074/084/102/104/107 on `origin/main` (anonymise RPCs exist on dev post-apply).
- [ ] 0.3 Re-extract `account-delete.ts` anonymise call order + per-RPC arg names (`p_user_id` vs `p_founder_id` vs `p_departing_user`).

## Phase 1 — Class 1: users-RLS-deny guards (stay on `users`)

- [ ] 1.1 `current-repo-url.tenant-isolation.test.ts` + `kb-route-helpers.tenant-isolation.test.ts`: delete `beforeAll` seeds that `UPDATE users` with dropped columns.
- [ ] 1.2 Retarget deny SELECT to surviving `users` column (`email`/`role`), `.eq("id", userB.id)`; preserve each suite's deny shape (current-repo-url `maybeSingle`→`error===null && data===null`; kb-route-helpers `single`→`PGRST116`). Update baseline read.
- [ ] 1.3 Update suite header comments to reflect `users` `auth.uid()=id` guard on surviving column; cite ADR-044.

## Phase 2 — Class 2: repo-state → `workspaces` + RPC

- [ ] 2.1 Move repo-state seeds to `service.from("workspaces").update({...}).eq("id", user.id)` (UPDATE the trigger-created row, never INSERT). Tenant reads of `repo_url`/`repo_status` via `aClient.from("workspaces")`.
- [ ] 2.2 `github_installation_id`: seed via service `workspaces.update`; deny/read via `aClient.rpc("resolve_workspace_installation_id", { p_workspace_id })` asserting seeded value (own) / `null` (B). NEVER tenant `select("github_installation_id")` (42501).
- [ ] 2.3 Align shared mock helpers `agent-runner-mocks.ts`, `share-mocks.ts`, `mock-supabase.ts` to post-mig-112 `workspaces` shape.
- [ ] 2.4 Update Class-2 test names/comments: deny is membership-scoped (workspaces), not `auth.uid()=id`.

## Phase 3 — Class 3: leave `conversations.repo_url`, drop broken `users` seed

- [ ] 3.1 `conversation-visibility.tenant-isolation.test.ts`: remove only the `service.from("users").update({ repo_url })` seed (~:80-83); keep `conversations.repo_url`.
- [ ] 3.2 `conversations-tools.tenant-isolation.test.ts`: verify all refs are on `conversations` (mig 029); no change expected.

## Phase 4 — Teardown FK-cascade parity + fail-loud

- [ ] 4.1 Expand `tenant-isolation-teardown.ts` `anonymiseSequence` to FK-RESTRICT parity with `account-delete.ts` (order from 0.3), correct per-RPC args (`p_founder_id` / `p_departing_user` / `p_user_id`).
- [ ] 4.2 Per-RPC fatality class: `restrict` → throw after loop / before `deleteUser`; `set-null`/`graceful` + missing-function (PGRST202/42883) → warn-and-continue (documented per `cq-silent-fallback-must-mirror-to-sentry`).
- [ ] 4.3 Keep `deleteUser` throw-on-non-"not found"; retry wrapper now only for transient.

## Phase 5 — Drift guard test

- [ ] 5.1 Create `test/server/teardown-anonymise-parity.test.ts`: source-grep both files; assert teardown RESTRICT-class set ⊇ account-delete RESTRICT-class set. Runs in default ci.yml.

## Phase 6 — Verify

- [ ] 6.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 6.2 `./node_modules/.bin/vitest run test/server/teardown-anonymise-parity.test.ts test/helpers/gotrue-retry.test.ts` + touched mock consumers.
- [ ] 6.3 Push; confirm `tenant-integration.yml` green on PR (`gh run list --workflow=tenant-integration.yml`), zero deleteUser retry warnings.

## Follow-up (file as issue)

- [ ] Make `tenant-integration.yml` a required check without blocking unrelated PRs (path-filter/skip-shim design). Re-eval after #5582 lands green. Milestone: Post-MVP / Later.
