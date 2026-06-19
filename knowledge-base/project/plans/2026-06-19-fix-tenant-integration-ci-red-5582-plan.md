---
title: "fix(ci): Tenant integration (dev-Supabase) red on main — users 42703 + GoTrue deleteUser 500s"
issue: 5582
type: fix
date: 2026-06-19
branch: feat-one-shot-5582-tenant-isolation-ci
lane: single-domain
domain: engineering
priority: p1-high
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# 🐛 fix(ci): Tenant integration (dev-Supabase) red on main — users-table `42703` + GoTrue `deleteUser` 500s

## Enhancement Summary

**Deepened on:** 2026-06-19
**Sections enhanced:** Overview premise, AC scope, Files to Edit, Implementation Phase 4, Sharp Edges.
**Verification passes:** verify-the-negative (10/10 load-bearing premises CONFIRMED against source via grep), precedent-diff (account-delete.ts cascade), architecture-strategist review.

### Key improvements from deepen pass
1. **P1 scope gap closed.** Three additional dropped-column-bug files outside `test/server/` (`conversations-rail-cross-tenant.integration.test.ts`, `dsar-export-cross-tenant.integration.test.ts`, `mu1-integration.test.ts`) — gated behind `SUPABASE_DEV_INTEGRATION`/`MU1_INTEGRATION`, so **dormant** w.r.t. the current red `tenant-integration.yml` signal, but they make a broad AC1 grep unsatisfiable and carry the same latent `42703` drift. Folded into scope (Phase 7) + AC1 scope clarified.
2. **AC7/Phase 4.2 tightened.** A `PGRST202`/`42883` on a **RESTRICT-class** RPC is now **fatal** (it almost always means an arg-name typo — `p_founder_id`/`p_departing_user` vs `p_user_id` — which `withGoTrueRetry` would otherwise mask as a transient deleteUser 500). Genuinely-absent-on-dev functions stay graceful only for the documented graceful-degrade RPC (`anonymise_workspace_invitations`).
3. **AC8 fatality-class derivation.** The drift guard derives each RPC's RESTRICT-vs-SET-NULL fatality class from the **FK-defining migration**, not the plan's hand-labeled snapshot.
4. **Synthetic-email literal corrected** from `*@example.test` to the real teardown boundary pattern `tenant-isolation-<16hex>@soleur.test` (`tenant-isolation-teardown.ts:13-14`).
5. **Drift-guard design decision recorded:** keep the source-grep parity test (AC8); do NOT import a canonical RPC list from `server/account-delete.ts` into the test helper (account-delete's anonymise calls are interleaved with control flow — no clean array exists; a `test/→server/` import would over-couple and breach the test-only boundary).

### Verified facts (deepen pass, all CONFIRMED)
- `workspaces.github_installation_id` REVOKE'd from `authenticated`, absent from re-GRANT (`079:88-91`) → tenant `select` yields `42501`, not RLS deny. `repo_url`/`repo_status` ARE re-GRANTed (`079:89-91`).
- `resolve_workspace_installation_id` membership-checked DEFINER, returns NULL on deny, `GRANT EXECUTE TO authenticated` (`079:103-127`).
- `conversations.repo_url` exists (`029:19`), NOT dropped by mig 112.
- `users.email`/`users.role` survive mig 112 (`001:8`, `054`).
- `handle_new_user` INSERTs `workspaces(id=NEW.id) ON CONFLICT DO NOTHING` (`112:77-79`) → seeds UPDATE, not INSERT.
- `account-delete.ts` arg divergence: `anonymise_audit_github_token_use{p_founder_id}` (`:434`), `anonymise_departed_user_across_workspaces{p_departing_user}` (`:563`); all others `p_user_id`.
- Teardown has exactly 8 RPCs, missing `anonymise_email_triage_items` (`tenant-isolation-teardown.ts:68-75`).
- `anonymise_email_triage_items` (`account-delete.ts:925`, step 3.97) precedes `auth.admin.deleteUser` (`:1040`, step 4) — the precedent the teardown mirrors.
- anonymise RPCs are idempotent `UPDATE…WHERE` returning `{data:0,error:null}` on no-op (e.g. `anonymise_email_triage_items` mig 102:406-412) → fail-loud is SAFE for empty synthetic users.

## Overview

The **Tenant integration (dev-Supabase)** workflow (`.github/workflows/tenant-integration.yml`) has been red on `main` since ~2026-06-17 22:38 UTC. It is **not a required check** (path-filtered, by design — the path filter is load-bearing to avoid burning dev-Supabase rate budget on ~95% of PRs), so PRs keep auto-merging while the cross-tenant isolation guarantee goes **unverified in CI**.

There are **two independent root causes**, both confirmed against the codebase (not just the issue prose):

1. **`42703 undefined_column` on `users` reads/writes.** Migration **112** (`112_drop_legacy_users_repo_columns.sql`, PR #5508, commit `dbf0e89d0`) **dropped** `users.{workspace_path, repo_url, github_installation_id}` (ADR-044 PR-2b; these columns moved to the `workspaces` table in mig 079). Multiple `*.tenant-isolation.test.ts` suites + shared test helpers still `SELECT`/`UPDATE` these dropped columns on `users`. The **louder** failure is the seed `UPDATE users` in `beforeAll` — it throws `42703` before any assertion runs.

2. **GoTrue admin `deleteUser` → `500 unexpected_failure` storm.** The teardown helper `apps/web-platform/test/helpers/tenant-isolation-teardown.ts` mass-deletes synthetic users, but its `anonymiseSequence` carries only **8** anonymise RPCs while production `server/account-delete.ts` runs **~23** before `auth.admin.deleteUser()`. The teardown is frozen at a pre-migration-064 snapshot. Each missing RPC behind an `ON DELETE RESTRICT` FK to `users` (notably `anonymise_email_triage_items`, `email_triage_items.user_id REFERENCES users(id) ON DELETE RESTRICT`, mig 102) blocks the auth-delete → opaque GoTrue `500`. `withGoTrueRetry` then burns 5× retries on a **deterministic** FK block and ends in the same 500.

**This is a test-code + test-helper fix only.** No production code change, no migration, no infra. Dev schema is already correct (mig 112 applied); the fix is to stop referencing the dropped columns and to bring teardown into FK-cascade parity.

> **Premise refinement (vs. issue body):** the issue bisected the regression window to `4b106af5..0b5fa272` and named #5494 (`feat(email-triage): shared workspace inbox`, mig 111). The `42703` column-drop is actually from **mig 112 / #5508 (`dbf0e89d0`)**, which the issue lists as one of the "subsequent merges." #5494/mig 111 broadened `email_triage_items` to workspace grain but did not drop the `users` columns. Both findings still resolve under this single plan.

## Research Reconciliation — Spec/Issue vs. Codebase

| Issue/initial claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "test schema drifted; the column the test SELECTs no longer exists" | Confirmed: mig 112 (`dbf0e89d0`) drops `users.{workspace_path, repo_url, github_installation_id}`; columns live on `workspaces` (mig 079). | Rewrite suites/helpers off the dropped `users` columns. |
| "4 affected suites" | **10** suites + 3 shared helpers reference the dropped columns; they split into **3 repair classes** (not a binary). | Triage every suite into Class 1/2/3 (see Implementation). |
| "mirror production read paths (move reads to `workspaces`)" | `workspaces.github_installation_id` is **REVOKE'd** from `authenticated` (mig 079:88-89); readable only via `resolve_workspace_installation_id(p_workspace_id)` definer RPC. A tenant `select("github_installation_id")` on `workspaces` returns **`42501` (permission denied for column)**, NOT an RLS row-deny. | `github_installation_id` deny test must call the RPC and assert **NULL**, not assert PGRST116. |
| "move users-RLS guards to `workspaces`" | `workspaces` RLS is **membership-scoped** (`workspaces_select_for_members`, zero-rows deny), categorically different from the `users` `auth.uid() = id` policy. | **Class 1** users-RLS guards STAY on `users`; retarget the SELECT to a still-existing `users` column (`email`/`role`). |
| (implicit) "all `repo_url` references move to `workspaces`" | `conversations.repo_url` (mig 029) still exists and is unrelated to the drop. | **Class 3** suites keep `conversations.repo_url`; only remove the broken `users.repo_url` seed. |
| issue names only `anonymise_email_triage_items` missing | Teardown also misses ~12 other anonymise RPCs vs. `account-delete.ts`; two use **non-`p_user_id` args** (`anonymise_audit_github_token_use(p_founder_id)`, `anonymise_departed_user_across_workspaces(p_departing_user)`). | Bring teardown to full parity with correct per-RPC arg names; add a drift guard. |
| "deleteUser 500 = dev GoTrue/Auth in a bad state" | The 500 is a **deterministic FK RESTRICT block** (missing anonymise), not a transient Auth-backend outage. `withGoTrueRetry` masks it as 5× transient retries. | Fix root cause (anonymise parity); promote RESTRICT-class anonymise failures to a thrown error so a future regression is red, not a buried warn. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing *directly* (these are CI tests, not runtime code) — but the cross-tenant isolation property (one founder's JWT cannot read another founder's `users`/repo/session-sync/email-triage rows) is **unverified in CI** while the suite is red. A real RLS regression could ship undetected behind a "red-for-environment-reasons" suite that nobody distinguishes from a genuine isolation break.

**If this leaks, the user's data is exposed via:** a future cross-tenant RLS regression merging unnoticed because the only live verification (`tenant-integration.yml`) was red/ignored — Founder A reading Founder B's `repo_url`, `github_installation_id` (a connection credential), KB workspace path, or statutory email-triage items.

(Synthetic users are the teardown's boundary-guarded pattern `tenant-isolation-<16hex>@soleur.test`, `tenant-isolation-teardown.ts:13-14` — NOT `@example.test`.)

**Brand-survival threshold:** single-user incident — the suites are the live safety net for tenant isolation; their blast radius on regression is a single-founder trust breach. (CPO sign-off required at plan time; `user-impact-reviewer` invoked at review-time per review/SKILL.md.)

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — no dropped `users` columns referenced in any in-scope test/helper.** Multiline-aware sweep `rg -nU 'from\("users"\)[\s\S]{0,400}?(workspace_path|repo_url|github_installation_id)' apps/web-platform/test` returns **0** across the FULL `apps/web-platform/test` tree (this fix folds in the 3 dormant `test/*.integration.test.ts` files per Phase 7, so the grep is satisfiable at full scope — not narrowed to `test/server/`). `conversations.repo_url` and `workspaces.repo_url` are explicitly allowed (they are on different tables). Note: `test/ws-handler-cc-pdf-breadcrumb.test.ts:37-38` only *comments* the word `workspace_path` (a mock-doc note, no `.from("users")` read) — exclude comment-only matches.
- [x] **AC2 — Class-1 users-RLS guards still assert on `users`.** `current-repo-url.tenant-isolation.test.ts` and `kb-route-helpers.tenant-isolation.test.ts` keep a SELECT on `users` against `userB.id` and assert deny, retargeted to a surviving column (`email` or `role`). Each suite **preserves its existing deny shape** (current-repo-url: `error===null && data===null` via `maybeSingle`; kb-route-helpers: `error.code==='PGRST116'` via `single`). Grep proof: both files still contain `.from("users")` in the deny test.
- [x] **AC3 — `github_installation_id` deny via RPC, not column SELECT.** Any test that previously asserted a tenant deny on `github_installation_id` now calls `aClient.rpc("resolve_workspace_installation_id", { p_workspace_id: userB.id })` and asserts the result is `null` (membership deny == not-connected by design); the baseline calls it for the user's own workspace and asserts the seeded value. No test does `select("github_installation_id")` against `workspaces` with a tenant client.
- [x] **AC4 — Class-2 repo-state seeds `UPDATE` the auto-created `workspaces` row.** Seeds use `service.from("workspaces").update({...}).eq("id", user.id)` (the mig-053 `handle_new_user` trigger pre-creates `workspaces(id = users.id)`; `INSERT` would PK-collide). Verified: each Class-2 suite's `beforeAll` no longer writes the dropped `users` columns.
- [x] **AC5 — Class-3 suites untouched except the broken seed.** `conversations-tools.tenant-isolation.test.ts` and `conversation-visibility.tenant-isolation.test.ts` retain their `conversations.repo_url` reads/inserts; only the broken `service.from("users").update({ repo_url })` seed in `conversation-visibility` (~`:80-83`) is removed.
- [x] **AC6 — teardown `anonymiseSequence` reaches FK-RESTRICT parity with `account-delete.ts`.** The sequence includes every `RESTRICT`-FK anonymise RPC production calls, with **correct per-RPC arg names** (`anonymise_audit_github_token_use` → `{ p_founder_id }`, `anonymise_departed_user_across_workspaces` → `{ p_departing_user }`, all others `{ p_user_id }`). Verify via a parity test (AC8).
- [x] **AC7 — RESTRICT-class anonymise failures fail loudly; arg-typo is fatal.** Teardown promotes a non-tolerable error from a RESTRICT-class anonymise RPC to a **thrown** error (so a future regression is a red test), while SET-NULL-class (`anonymise_audit_github_token_use`, `anonymise_workspace_activity`) stays warn-and-continue. **`PGRST202`/`42883` on a RESTRICT-class RPC is FATAL** (it almost always means an arg-name typo — `p_founder_id`/`p_departing_user` vs `p_user_id` — which `withGoTrueRetry`'s `TRANSIENT_DELETE_RE` would otherwise mask as a transient deleteUser 500, `gotrue-retry.ts:36`). The graceful-degrade-on-missing-function exception is scoped to the ONE production-documented case (`anonymise_workspace_invitations`, mirroring `account-delete.ts`'s explicit branch) — NOT a blanket policy.
- [x] **AC8 — drift guard with derived fatality class.** A source test (`test/server/teardown-anonymise-parity.test.ts` or an extended components/source test) asserts the teardown's RESTRICT-class RPC set ⊇ the set of `anonymise_*` RPCs `account-delete.ts` calls behind a RESTRICT FK. The RESTRICT-vs-SET-NULL **fatality class for each RPC is derived from the FK-defining migration** (`grep "REFERENCES.*users" + ON DELETE` in `supabase/migrations/`), NOT from a hand-labeled list — so a mislabel cannot codify a wrong fatality. Runs in default `ci.yml` (pure source/migration grep, no dev Supabase).
- [x] **AC9 — `tsc` + default test suite green.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes; `./node_modules/.bin/vitest run test/server/teardown-anonymise-parity.test.ts` (and the gotrue-retry unit test) pass.

### Post-merge (operator / CI)

- [ ] **AC10 — tenant-integration.yml green.** The `Tenant integration (dev-Supabase)` workflow run on this PR (it triggers because the PR touches `apps/web-platform/test/server/**.tenant-isolation.test.ts`) passes all 4 named suites with `error: null`/`PGRST116` denies and zero `withGoTrueRetry[deleteUser:…] retryable error` warnings. **This is the only authoritative green signal** — the default `ci.yml test-webplat` job runs without `TENANT_INTEGRATION_TEST=1` and `describe.skipIf`-skips these suites. `Automation:` the workflow runs automatically on the PR; verify via `gh run list --workflow=tenant-integration.yml`.

## Out of Scope (with tracking)

- **Making `tenant-integration.yml` a required check.** A path-filtered required check shows "Expected — Waiting" and blocks every PR that doesn't touch the filtered paths (GitHub treats a never-running required check as pending-forever). Making it required needs its own path-filter/required-check design (remove the filter → rate-budget cost, or a skip-shim that reports success). **File a follow-up issue** with re-eval criteria: "after #5582 lands green, design a required-check shim that does not block unrelated PRs." Milestone: `Post-MVP / Later`.
- **Full globalSetup refactor of the tenant-isolation suites** (brainstorm `2026-05-19-tenant-isolation-globalsetup-brainstorm.md`, Variant C founder-pool) — deliberately parked there; this fix does not depend on it.

## Implementation Phases

### Phase 0 — Re-verify premises at work time (verification claims decay)

0.1. Re-run the multiline reader sweep (claims in this plan are >0h but schema is mutable):
`rg -nU 'from\("users"\)[\s\S]{0,400}?(workspace_path|repo_url|github_installation_id)' apps/web-platform/test` and `git grep -nE "\.(eq|in|match)\([\"']?(workspace_path|repo_url|github_installation_id)" -- 'apps/web-platform/test'`. Confirm the file set matches the triage below; if a new suite appears, classify it.
0.2. Confirm mig 102/104/107 and the byok migrations are on `origin/main` (RPCs exist on dev after the workflow's "Apply migrations to dev" step). `ls apps/web-platform/supabase/migrations/ | grep -E '^(102|104|107|064|074|084)'`.
0.3. Re-extract `account-delete.ts`'s anonymise call order + per-RPC arg names (`grep -noE "anonymise_[a-z_]+" server/account-delete.ts` and the `{ p_* }` lines) — the parity list must be derived from current code, not this plan's snapshot.

### Phase 1 — Class 1: users-RLS-deny guards (keep on `users`)

Files: `test/server/current-repo-url.tenant-isolation.test.ts`, `test/server/kb-route-helpers.tenant-isolation.test.ts`.

1.1. Remove every seed `service.from("users").update({ repo_url | workspace_path | github_installation_id })` in `beforeAll` (these throw `42703`). The deny test needs no particular column value on B — RLS denies the row regardless.
1.2. Retarget the deny SELECT from the dropped columns to a surviving `users` column (`email` or `role`), keeping `.eq("id", userB.id)` and each suite's existing assertion shape (current-repo-url: `maybeSingle` → `error===null && data===null`; kb-route-helpers: `single` → `error.code==='PGRST116'`). Update the baseline ("A reads own row") to SELECT the same surviving column.
1.3. Update suite header comments to say the guard is on the surviving `users` column (the property is `users` `auth.uid()=id` RLS, unchanged). The repo-state semantics moved to `workspaces`; cite ADR-044.

### Phase 2 — Class 2: repo-state seed/read → `workspaces` + RPC

Files: `test/server/session-sync.tenant-isolation.test.ts`, `test/server/agent-runner.tenant-isolation.test.ts`, `test/server/kb-document-resolver.tenant-isolation.test.ts`, `test/server/ws-handler.tenant-isolation.test.ts`, `test/server/lookup-conversation-for-path.tenant-isolation.test.ts`, `test/server/tenant-jwt-rls-deny.tenant-isolation.test.ts` (verify each in Phase 0 — only those that actually seed/read dropped columns).

2.1. Move repo-state seeds to `service.from("workspaces").update({ repo_url, repo_status, ... }).eq("id", user.id)` (UPDATE the trigger-created row; never INSERT). For `repo_url`/`repo_status` reads, mirror production: tenant `aClient.from("workspaces").select("repo_url")` (these columns ARE re-GRANTed to `authenticated`).
2.2. For `github_installation_id`: seed via `service.from("workspaces").update({ github_installation_id })`; read/deny via `aClient.rpc("resolve_workspace_installation_id", { p_workspace_id })` asserting the seeded value (own) / `null` (B). Do NOT `select("github_installation_id")` with a tenant client (`42501`).
2.3. Update shared helpers that mock these reads: `test/helpers/agent-runner-mocks.ts` (already comments the ADR-044 cutover; ensure the mock returns `workspaces.repo_url` shape), `test/helpers/share-mocks.ts`, `test/helpers/mock-supabase.ts` — align the mocked user/workspace fixture so unit consumers see the post-mig-112 shape.
2.4. Update test names/comments to state the deny is **membership-scoped** (workspaces) where applicable, not `auth.uid()=id`.

### Phase 3 — Class 3: leave `conversations.repo_url`, drop broken `users` seed

Files: `test/server/conversations-tools.tenant-isolation.test.ts`, `test/server/conversation-visibility.tenant-isolation.test.ts`.

3.1. In `conversation-visibility`, remove only the `service.from("users").update({ repo_url })` seed (~`:80-83`). Leave all `conversations.repo_url` inserts/reads intact.
3.2. Confirm `conversations-tools` references are all on `conversations` (mig 029) — no change expected; verify in Phase 0.

### Phase 4 — Teardown FK-cascade parity + fail-loud + drift guard

File: `test/helpers/tenant-isolation-teardown.ts`.

4.1. Expand `anonymiseSequence` to include the missing RESTRICT-class RPCs in `account-delete.ts` production order, each with its correct arg shape:
`anonymise_dsar_export_audit_pii {p_user_id}`, `anonymise_scope_grants {p_user_id}` (present), `anonymise_action_sends {p_user_id}` (present), `anonymise_template_authorizations {p_user_id}` (present), `anonymise_tc_acceptances {p_user_id}` (present), `anonymise_audit_github_token_use {p_founder_id}` (SET NULL — non-fatal), `anonymise_workspace_member_attestations {p_user_id}` (present), `anonymise_workspace_invitations {p_user_id}` (graceful-degrade), `anonymise_departed_user_across_workspaces {p_departing_user}`, `anonymise_workspace_member_removals {p_user_id}` (present), `anonymise_workspace_members {p_user_id}` (present), `anonymise_organization_membership {p_user_id}`, `anonymise_workspace_member_actions {p_user_id}` (present), `anonymise_workspace_activity {p_user_id}` (SET NULL — non-fatal), `anonymise_byok_delegations {p_user_id}`, `anonymise_byok_delegation_acceptances {p_user_id}`, `anonymise_byok_delegation_withdrawals {p_user_id}`, `anonymise_email_triage_items {p_user_id}`, `anonymise_email_suppression {p_user_id}`, `anonymise_outbound_sends {p_user_id}`, `anonymise_routine_runs {p_user_id}`. (Final order/membership derived from Phase 0.3, not this snapshot.)
4.2. Change the loop to carry a per-RPC fatality class: `restrict` (throw on real error after the loop, before `deleteUser` — these are the 500 causes), `set-null`/`graceful` (warn-and-continue). A missing-function error (`PGRST202`/`42883`) is tolerated for all (dev may lack a mid-flight migration), matching production's `anonymise_workspace_invitations` graceful branch — documented inline per `cq-silent-fallback-must-mirror-to-sentry`.
4.3. After parity, if `deleteUser` STILL 500s post-`withGoTrueRetry`, the helper throws (it already throws on non-"not found" — keep). The retry wrapper now only fires for genuinely transient errors.

### Phase 5 — Drift guard test

5.1. Add `test/server/teardown-anonymise-parity.test.ts` (or extend an existing source-grep test): read both `tenant-isolation-teardown.ts` and `account-delete.ts`, grep `anonymise_*` invocations, and assert the teardown's RESTRICT-class set ⊇ account-delete's RESTRICT-class set. Derive each RPC's fatality class (RESTRICT vs SET NULL) from the FK-defining migration (`grep -E "REFERENCES.*\busers\b" + ON DELETE` in `supabase/migrations/`), not a hand-labeled constant. Pure source/migration grep — runs in default CI, no dev Supabase. This makes the 8-vs-23 reopening a red test.

### Phase 7 — Dormant same-class fixes (P1 scope gap from deepen review)

Three `apps/web-platform/test/*.integration.test.ts` files carry the identical dropped-column bug but are gated behind `SUPABASE_DEV_INTEGRATION=1` / `MU1_INTEGRATION=1` (NOT `TENANT_INTEGRATION_TEST`), so they are **not** in the current red `tenant-integration.yml` signal — yet they make AC1's full-tree grep unsatisfiable and carry latent `42703` drift. Fix mechanically (same as Class 2/3):

7.1. `test/conversations-rail-cross-tenant.integration.test.ts:124-125` — `service.from("users").update({ repo_url })` → seed `workspaces.repo_url` via UPDATE on the trigger-created row (`.eq("id", u.id)`), or remove if the test only needs RLS deny.
7.2. `test/dsar-export-cross-tenant.integration.test.ts:98-101` — `service.from("users").upsert({ ..., workspace_path: "" })` → drop the `workspace_path` field (column gone; the upsert seeds the user row, which the trigger already creates — verify whether the upsert is even needed post-trigger).
7.3. `test/mu1-integration.test.ts:161-162, :215` — `select("workspace_path")` + `AC2_HAS_REPO_URL`/`AC2_HAS_INSTALL_ID` gating blocks → read from `workspaces` (repo_url/repo_status via tenant select; github_installation_id via `resolve_workspace_installation_id`).
7.4. Exclude `test/ws-handler-cc-pdf-breadcrumb.test.ts:37-38` — comment-only mention of `workspace_path`, no `users` read; no change.

### Phase 6 — Verify

6.1. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
6.2. `./node_modules/.bin/vitest run test/server/teardown-anonymise-parity.test.ts test/helpers/gotrue-retry.test.ts` (and any unit consumers of the touched mock helpers).
6.3. Push; let `tenant-integration.yml` run on the PR; confirm green + zero deleteUser retry warnings (AC10).

## Files to Edit

- `apps/web-platform/test/server/current-repo-url.tenant-isolation.test.ts` (Class 1)
- `apps/web-platform/test/server/kb-route-helpers.tenant-isolation.test.ts` (Class 1)
- `apps/web-platform/test/server/session-sync.tenant-isolation.test.ts` (Class 2)
- `apps/web-platform/test/server/agent-runner.tenant-isolation.test.ts` (Class 2)
- `apps/web-platform/test/server/kb-document-resolver.tenant-isolation.test.ts` (Class 2 — verify in Phase 0)
- `apps/web-platform/test/server/ws-handler.tenant-isolation.test.ts` (Class 2 — verify)
- `apps/web-platform/test/server/lookup-conversation-for-path.tenant-isolation.test.ts` (Class 2 — verify)
- `apps/web-platform/test/server/tenant-jwt-rls-deny.tenant-isolation.test.ts` (Class 2 — verify)
- `apps/web-platform/test/server/conversation-visibility.tenant-isolation.test.ts` (Class 3 — remove broken `users` seed only)
- `apps/web-platform/test/server/conversations-tools.tenant-isolation.test.ts` (Class 3 — verify untouched)
- `apps/web-platform/test/helpers/tenant-isolation-teardown.ts` (Phase 4)
- `apps/web-platform/test/helpers/agent-runner-mocks.ts` (Phase 2.3)
- `apps/web-platform/test/helpers/share-mocks.ts` (Phase 2.3 — verify)
- `apps/web-platform/test/helpers/mock-supabase.ts` (Phase 2.3 — verify)
- `apps/web-platform/test/conversations-rail-cross-tenant.integration.test.ts` (Phase 7 — dormant `SUPABASE_DEV_INTEGRATION` gate)
- `apps/web-platform/test/dsar-export-cross-tenant.integration.test.ts` (Phase 7 — dormant `SUPABASE_DEV_INTEGRATION` gate)
- `apps/web-platform/test/mu1-integration.test.ts` (Phase 7 — dormant `MU1_INTEGRATION` gate)

## Files to Create

- `apps/web-platform/test/server/teardown-anonymise-parity.test.ts` (Phase 5 drift guard) — OR fold the assertion into an existing source-grep test if one covers helpers.

## Open Code-Review Overlap

None — no open `code-review`-labeled issues touch these test/helper files at plan time (verify at /work with the two-stage `gh issue list --json` + standalone `jq --arg` pattern over the Files-to-Edit list).

## Hypotheses

The issue text reads "SSH/connectivity"-adjacent (the `500` symptom), but the network-outage L3→L7 checklist does **not** apply: the `deleteUser` 500 is a **deterministic Postgres FK `RESTRICT` block** surfaced through GoTrue's opaque admin error, not a firewall/DNS/sshd connectivity failure. Verified by reading the FK definition (mig 102:10 `ON DELETE RESTRICT`) and the missing anonymise RPC in teardown. No firewall/egress-IP step is warranted.

## Domain Review

**Domains relevant:** none (single-domain engineering: CI test + test-helper code).

No cross-domain implications — pure test/CI fix. No UI surface (no `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` in Files to Create/Edit → Product/UX Gate does not fire). No new infrastructure, no vendor, no secret, no migration → Infra-as-Code gate (2.8) skipped. No regulated-data **surface** change (tests read/anonymise synthetic `tenant-isolation-<16hex>@soleur.test` users only; no new processing activity, schema, auth flow, or API route) → GDPR gate (2.7) skipped. No architectural decision created or changed (the fix *consumes* ADR-044's already-decided users→workspaces relocation; it neither extends nor reverses it) → ADR/C4 gate (2.10) skipped.

## Observability

This is test-code + test-helper only; it adds no production server/infra surface (Files to Edit are all under `apps/web-platform/test/`). Observability gate (2.9) is satisfied by the CI signal itself:

```yaml
liveness_signal:   "Tenant integration (dev-Supabase) workflow run on PR + push to main; cadence = every PR touching tenant-isolation tests/server/migrations; alert_target = GitHub Actions red/green + ship post-deploy verify; configured_in = .github/workflows/tenant-integration.yml"
error_reporting:   "destination = GitHub Actions job log (vitest --reporter=verbose) + the teardown's thrown RESTRICT-class anonymise error and deleteUser 500 surface as a failed step; fail_loud = yes (Phase 4.2 promotes RESTRICT-class anonymise failures from console.warn to throw)"
failure_modes:
  - { mode: "dropped-column 42703 regression", detection: "tenant-integration.yml suite failure", alert_route: "GitHub Actions red on PR" }
  - { mode: "teardown RPC drift reopens (new anonymise_* migration)", detection: "teardown-anonymise-parity.test.ts source-grep diff", alert_route: "default ci.yml test-webplat red" }
  - { mode: "deleteUser 500 storm reappears", detection: "withGoTrueRetry warnings in job log + thrown teardown error", alert_route: "tenant-integration.yml red" }
logs:              "where = GitHub Actions run logs (tenant-integration.yml, ci.yml); retention = GitHub default (90d)"
discoverability_test:
  command: "gh run list --workflow=tenant-integration.yml --limit 5 --json conclusion,headSha"
  expected_output: "latest run conclusion = success after the fix merges"
```

## Test Scenarios

- Class-1 deny on `users` (email/role): A reads own row (baseline pass); A's JWT denied B's row (PGRST116 / null per suite shape).
- Class-2 `repo_url` deny via membership-scoped `workspaces` RLS; `github_installation_id` deny via `resolve_workspace_installation_id` → NULL.
- Class-3 `conversations.repo_url` isolation unchanged and still green.
- Teardown: synthetic user with seeded `email_triage_items` (and byok/routine) rows deletes cleanly (no 500, no retry warnings).
- Drift guard: artificially remove an RPC from teardown → `teardown-anonymise-parity.test.ts` goes red.
- Missing-function tolerance: a RESTRICT-class RPC absent on dev → graceful skip (documented), not a hard teardown crash.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold fails `deepen-plan` Phase 4.6. (Filled above: threshold `single-user incident`.)
- **`github_installation_id` is the trap of this fix.** It is REVOKE'd from `authenticated` on `workspaces` (mig 079:88-89). Migrating its deny test to a tenant `select("github_installation_id")` yields `42501` (grant error), not isolation deny — a green-but-wrong test. Use `resolve_workspace_installation_id` → NULL.
- **Membership-scoped deny ≠ `auth.uid()=id` deny.** `workspaces` denies non-members by returning zero rows; `users` denies via `auth.uid()=id`. Keep Class-1 guards on `users` or the `users` RLS policy loses all regression coverage.
- **Seed must UPDATE, not INSERT** the `workspaces` row (mig-053 `handle_new_user` trigger pre-creates `workspaces(id = users.id)`; INSERT PK-collides).
- **Teardown arg names diverge:** `anonymise_audit_github_token_use(p_founder_id)`, `anonymise_departed_user_across_workspaces(p_departing_user)` — the rest are `p_user_id`. A wrong arg name yields `PGRST202`, which warn-and-continue would swallow, leaving the FK unbroken and the 500 storm invisible. Carry per-RPC arg shapes.
- **`withGoTrueRetry` masks deterministic FK blocks.** It retries "Database error deleting user" 5×; on a missing-anonymise FK every retry hits the same wall. The root-cause fix (parity) is what removes it — do not "fix" by raising the retry budget.
- **Authoritative green is `tenant-integration.yml` only.** The default `ci.yml test-webplat` runs without `TENANT_INTEGRATION_TEST=1` and `skipIf`-skips these suites — a green `ci.yml` proves nothing about this fix.
- **`PGRST202` on a RESTRICT-class RPC is an arg-name typo, not a missing function — make it fatal.** Routing ALL `PGRST202` to graceful-degrade (the naive teardown shape) re-buries exactly the arg-name bug (`p_founder_id`/`p_departing_user` ≠ `p_user_id`) that leaves the FK unbroken and the deleteUser 500 masked by `withGoTrueRetry`. Only `anonymise_workspace_invitations` has a production-documented graceful-degrade branch; scope the exception to it.
- **Phase 7 files are dormant, not part of the current red signal.** They are gated by `SUPABASE_DEV_INTEGRATION`/`MU1_INTEGRATION`, so fixing them does not change the `tenant-integration.yml` green criterion — but skipping them leaves AC1's full-tree grep red and the latent `42703` drift in place. Fold them in.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Re-add the dropped `users` columns / revert mig 112 | Reverses a deliberate ADR-044 PR-2b decommission; the columns are intentionally gone. Tests must follow the schema, not the reverse. |
| Patch only `anonymise_email_triage_items` (the one named in the issue) | Leaves ~12 other RESTRICT-FK RPCs missing; the next synthetic user with a byok/routine/suppression row 500s again. Full parity + drift guard is the durable fix. |
| Move Class-1 users-RLS guards wholesale to `workspaces` | Destroys the `users` `auth.uid()=id` regression coverage (workspaces deny is membership-scoped). |
| Raise `withGoTrueRetry` budget to absorb the 500s | Masks a deterministic FK block; burns more dev-Supabase budget; never goes green. |
| Make `tenant-integration.yml` a required check in this PR | Path-filtered required checks block unrelated PRs (pending-forever). Needs its own design — deferred to a tracking issue. |
