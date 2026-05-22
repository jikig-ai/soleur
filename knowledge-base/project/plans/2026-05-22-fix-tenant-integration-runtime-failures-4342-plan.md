---
type: bug-fix
classification: ci-recovery
lane: single-domain
issue: 4342
predecessor_pr: 4339
predecessor_issue: 4338
sibling_features:
  - 4225  # team-workspace (PR #4225, merged 2026-05-21) — introduced workspace_id columns + CHECK constraint at scope_grants
  - 4294  # DSAR departed-member coverage (PR #4294, merged 2026-05-22) — sibling of #4338, introduced 062 + WORM ledger + remove_workspace_member CREATE OR REPLACE
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
deepened_on: 2026-05-22
---

## Enhancement Summary

**Deepened on:** 2026-05-22
**Sections enhanced:** Research Reconciliation, User-Brand Impact, Open Code-Review Overlap, Failure Classes, Architecture Decision, Risks, Future Work
**Phases verified:** 4.6 (User-Brand Impact present), 4.7 (Observability skip valid — no `apps/*/server/` edits in this PR's scope), 4.8 (no PAT shapes)

### Key Improvements

1. **User-Brand Impact upgraded from `none` → `single-user incident`** after deepen-pass discovered a production caller of `grant_action_class` at `apps/web-platform/app/api/scope-grants/grant/route.ts:73` (reachable from UI `components/scope-grants/scope-grant-row.tsx:74`). Initial plan claim "no production callers" was wrong; corrected.
2. **`requires_cpo_signoff: true`** added per the single-user-incident threshold and `hr-weigh-every-decision-against-target-user-impact`.
3. **Massive blast-radius discovery (out-of-scope for this PR)**: Production INSERT sites for `conversations` (`ws-handler.ts:761`) and `messages` (`cc-dispatcher.ts:1411,1519`, `agent-runner.ts:435,2322`, `inngest/functions/github-on-event.ts:230`, `cfo-on-payment-failed.ts:224`, `api/internal/kb-drift-ingest/route.ts:137`) DO NOT pass `workspace_id`. Migration 059 set both columns to NOT NULL — every production INSERT will fail with 23502 if applied to prd. Status of prd-Supabase 059-application MUST be verified at /work Phase 0 before merging this PR; if 059 is live on prd, file an **immediate P0 follow-up issue** (`type/bug`, `priority/p0`) and consider whether this PR should expand to cover the production sites OR be merged narrow with the follow-up as a same-day fix.
4. **Failure-class enumeration sharpened**: 6 root-cause classes (A-F) explicitly mapped to single migration + 4-5 test files. No more "remove_workspace_member regressed return shape" hand-waving; the test was using a 3-arg call against a 2-arg RPC.
5. **AC verification commands tightened**: every grep AC now uses flag-based awk (not range-based — sharp-edge dodge) and `git ls-files | grep` for path verification (per `hr-when-a-plan-specifies-relative-paths-e-g`).

### New Considerations Discovered

- **Production conversation creation is broken** if migration 059 is live on prd. The tenant-integration test failures are CI canary signals for the same defect class. This PR fixes the canary; a follow-up must fix production.
- **`record_byok_use_and_check_cap` truly has no production callers** — only the migration definition and the integration test. Verified via `rg -rn "record_byok_use_and_check_cap" apps/web-platform/{server,app,lib}` returning zero non-test, non-migration matches.
- **Production caller of `grant_action_class`** (POST /api/scope-grants/grant) currently throws 500 (`{error: "rpc_failed"}`) for any user who clicks "Grant" in the scope-grants UI — IF prd has migration 059. The fix in this PR (migration 063 deriving workspace_id internally) resolves this without any production code change because the RPC API surface is unchanged.

# Fix tenant-integration runtime test failures post-PR #4339

## Overview

PR #4339 (#4338) restored the **migration-apply phase** of the `Tenant integration (dev-Supabase)` workflow to green by closing the schema-vs-ledger drift class. The next CI run (`gh run view 26288051420`) revealed a **second, orthogonal failure class** at the `Run tenant-isolation tests` step — runtime tests fail with check-constraint violations, PGRST signature-cache misses, permission-denied errors, and assertion mismatches.

This plan triages the secondary failure class. **A production user IS affected for the `grant_action_class` path** — `apps/web-platform/app/api/scope-grants/grant/route.ts:73` calls the RPC from the authenticated-user session via `components/scope-grants/scope-grant-row.tsx:74`. Any user clicking "Grant" in the scope-grants UI today (IF migration 059 has applied to prd) hits a 500 error (`{error: "rpc_failed"}`) and cannot complete the setting. `record_byok_use_and_check_cap` has zero production callers (verified) — only the integration test exercises it. The user-impact threshold is **single-user incident** for the grant path; brand-survival risk is bounded to "users cannot grant action tiers until migration 063 ships". The CI failures are the safety-net signals catching contract mismatch between (a) migration 051 `grant_action_class` body (no workspace_id INSERT), (b) migration 059's new `workspace_id NOT NULL` CHECK, and (c) test fixtures + service-role GRANT expectations.

**Out-of-scope discovery (deepen-pass):** Production also has uncovered INSERT sites on `conversations` (`ws-handler.ts:761`) and `messages` (6+ sites across cc-dispatcher, agent-runner, inngest functions) that DO NOT pass `workspace_id`. These are a separate P0 class — IF migration 059 is live on prd, these sites are ALL broken. The follow-up issue (filed at /work Phase 0 after verifying prd 059 state via Supabase MCP) tracks the production fix. This PR stays narrow on the CI surface + the `grant_action_class` RPC (which is fixable in a single migration without touching production code).

The fix is a single new migration `063_post_workspace_rpc_repair.sql` that updates **1 RPC body (`grant_action_class`) + 1 GRANT (`is_workspace_member` to service_role)** to the post-workspace-migration contract, plus 4 test-fixture updates (3 `conversations.insert` sites, 1 `record_byok_use_and_check_cap.rpc` call, DSAR assertion scoping), all merged atomically with PR-level test verification.

## Research Reconciliation — Issue Body vs. Codebase

The issue body lists 2 failure classes (scope_grants_workspace_id_check + remove_workspace_member). The actual CI log (`gh run view 26288051420 --log-failed`) shows **8+ distinct test failures across 6 root-cause classes**. The plan must cover the full class, not the subset named in the body.

| Issue-body claim | Reality (CI log + grep) | Plan response |
|---|---|---|
| "grant_action_class fixtures missing workspace_id" | RPC body at `051:284` does `INSERT INTO scope_grants (founder_id, action_class, tier)` — `workspace_id` is **not in the INSERT list at all**. No caller (test OR server) can supply it because the RPC ignores anything but `p_action_class` + `p_tier`. | Fix the **RPC** (read auth.uid()'s workspace via `is_workspace_member`-style lookup OR via `workspace_members.workspace_id WHERE user_id = v_founder_id AND workspace_id = v_founder_id AND role='owner'` per the migration-059 backfill predicate at `059:344-345`), NOT the fixtures. Identical predicate to the 059 backfill — consistent with the "solo-canary workspace_id = founder_id" invariant the post-workspace schema relies on. |
| "remove_workspace_member regressed return shape" | The RPC signature is `(p_workspace_id, p_user_id)` (per `062:272`) — but the test at `dsar-export-workspace-tables.integration.test.ts:108-112` calls it with a **3rd `p_actor_user_id` arg** that doesn't exist in the RPC body. The test has a fallback to direct DELETE, so this is harmless in DSAR; but `workspace-members.test.ts:106` calls `is_workspace_member` via **service-role** which migration 053:139 explicitly REVOKEs from service_role. | Fix the **GRANT** in a new migration `063` (`GRANT EXECUTE ON FUNCTION public.is_workspace_member(uuid, uuid) TO service_role`) so test fixtures using service-role can call the helper; AND fix the test's 3rd-arg call (drop `p_actor_user_id`) so it matches the canonical RPC signature. |
| "remove_workspace_member happy path" claim from issue body | Actual log: `permission denied for function is_workspace_member` (`workspace-members.test.ts:94`). The "happy path" test at line 113 uses **direct DELETE via service-role** (not the RPC) and asserts `data:still` has length 0 — that path PASSES. The failing test is `is_workspace_member returns true for an owner row` (line 88-96). | Recover via the GRANT fix above. The is_workspace_member-permission test is the canary; the remove_workspace_member happy path was a misdiagnosis in the issue body. |
| Not mentioned | `record_byok_use_and_check_cap` PGRST202: test calls with 5 args (`p_invocation_id, p_founder_id, p_agent_role, p_token_count, p_unit_cost_cents`); migration 061 dropped the 5-arg overload and replaced it with a 6-arg overload requiring `p_workspace_id`. | Update the test fixture (`byok-kill-switch.atomicity.tenant-isolation.test.ts:148-156`) to pass `p_workspace_id` (derive from the fixture's founder.id under the solo-canary invariant, OR via `service.from('workspace_members').select(workspace_id).eq(user_id, founder.id).eq(role, 'owner').single()`). |
| Not mentioned | `conversations.workspace_id NOT NULL` violation (`23502`) at `lookup-conversation-for-path.tenant-isolation.test.ts:93`. Migration 059 added `NOT NULL` to `conversations.workspace_id`; the test fixture INSERT at `lookup-conversation-for-path.tenant-isolation.test.ts:85-92` doesn't supply it. | Update the 3-site test fixture (`lookup-conversation-for-path.tenant-isolation.test.ts:85-92`, plus session-sync and ws-handler tenant-iso tests if they share the same pattern — verify via grep) to populate `workspace_id` per the solo-canary invariant (`workspace_id: user.id`). |
| Not mentioned | DSAR pre-state asserts `data.toHaveLength(1)` but actual is 2 (`dsar-export-workspace-tables.integration.test.ts:95`). | Fixture leak: `createSharedWorkspaceMembers` synthesizes Harry via `auth.admin.createUser`; the `handle_new_user` trigger provisions Harry's own solo backfill workspace_members row (`workspace_id = harry.id`); THEN the helper INSERTs Harry into Jean's workspace too. So `WHERE user_id = harry.id` returns 2 rows (own backfill + invited). Fix the assertion: filter by `workspace_id = fixture.workspaceId` (matches the fixture-shared workspace) before asserting length. |
| Not mentioned | DSAR post-removal asserts length 0 but actual is 1. | Same fixture-leak class: Harry's own solo backfill workspace_members row at `workspace_id = harry.id` is NOT removed by `remove_workspace_member(p_workspace_id = fixture.workspaceId, …)`. Same fix: scope the post-removal assertion to `workspace_id = fixture.workspaceId`. |
| Not mentioned | session-sync `afterAll: deleteUser(... ) failed: Database error deleting user`. | Downstream symptom: when `is_workspace_member` GRANT is missing AND `grant_action_class` workspace_id is absent, FK-RESTRICT pre-image rows accumulate that block `auth.admin.deleteUser`. Fixing classes (A) + (B) should resolve transitively; verify post-fix. |
| Not mentioned | ws-handler `TypeError: Cannot read properties of null (reading 'id')` at `ws-handler.tenant-isolation.test.ts:99`. | Same conversations.workspace_id NOT NULL violation — the upstream `service.from('conversations').insert(…).select('id').single()` returns `{data: null}` because the INSERT failed; the test then `convRow!.id` panics. Fix is identical to class (E). |

**Reconciliation conclusion:** issue #4342 understated the scope by ~3×. Six root-cause classes need fixing, not two. The fix surface is still small (1 migration + 4-6 test files), but the plan must enumerate all six.

## Failure Classes (ordered by fix-dependency)

The 6 classes group into:

1. **DB-side (one migration `063_post_workspace_rpc_repair.sql`):**
   - **A.** `grant_action_class` RPC body missing `workspace_id` in INSERT → 23514 CHECK violation. Fix: re-CREATE OR REPLACE the RPC at 6-arg shape (or re-derive workspace_id internally; see Architecture Decision below).
   - **B.** `is_workspace_member` GRANT does not include `service_role` → 42501 permission denied when tests call it via service-role. Fix: add `GRANT EXECUTE … TO service_role` (mirror 062:331 pattern that already grants `remove_workspace_member` to both `authenticated` AND inferentially-needed roles).

2. **Test-side (4 file edits):**
   - **C.** `record_byok_use_and_check_cap` test missing `p_workspace_id` → PGRST202. Fix in `byok-kill-switch.atomicity.tenant-isolation.test.ts:150`.
   - **D.** `conversations.insert` missing `workspace_id` in 3 tenant-iso tests → 23502 NOT NULL. Fix in `lookup-conversation-for-path.tenant-isolation.test.ts:85-92`, `session-sync.tenant-isolation.test.ts:*`, `ws-handler.tenant-isolation.test.ts:*` (exact line numbers per the grep in Phase 1.2).
   - **E.** DSAR pre/post-state assertions over-broad → filter by `workspace_id = fixture.workspaceId`. Fix in `dsar-export-workspace-tables.integration.test.ts:91-95` AND `:127-132`.
   - **F.** `remove_workspace_member` test passes 3rd arg `p_actor_user_id` that doesn't exist in the RPC signature → 42883 function not found OR silent fallback to direct DELETE (current test has the fallback; PASS but masks the real signature mismatch). Fix in `dsar-export-workspace-tables.integration.test.ts:108-112` to call with the canonical 2-arg shape.

## Research Insights (deepen-pass)

**Verified facts (deepen-pass empirical findings):**

- **Test runner:** `apps/web-platform/package.json` → `"test": "vitest"`, `"test:ci": "vitest run"`. Every AC test invocation uses `npx vitest run <path>` (or the package's `bun test:ci` if the harness uses bun-as-launcher). Verified via `jq -r '.scripts'`.
- **CI workflow triggers:** `tenant-integration.yml` runs on `pull_request` events touching `apps/web-platform/test/server/**.tenant-isolation.test.ts`, `apps/web-platform/server/**`, OR `apps/web-platform/supabase/migrations/**`. This PR's diff hits both globs (1 + 2 + 3); workflow runs automatically without manual `gh workflow run`. Source: `.github/workflows/tenant-integration.yml:31-41`.
- **Conversations INSERT sites in tenant-iso tests** (exhaustive enumeration via `grep -rnE '.insert' apps/web-platform/test/server/{lookup-conversation-for-path,api-usage,ws-handler}.tenant-isolation.test.ts`): 4 sites → `lookup-conversation-for-path:86`, `api-usage:90`, `ws-handler:92`, `ws-handler:186`. The plan's Files-to-Edit table reflects this exhaustive list.
- **grant_action_class call sites** (all): 13 sites in 4 test files + 1 production route (`app/api/scope-grants/grant/route.ts:73`). Production route is reached from `components/scope-grants/scope-grant-row.tsx:74` via authenticated session POST. No other production callers exist.
- **record_byok_use_and_check_cap call sites:** 1 test (`byok-kill-switch.atomicity.tenant-isolation.test.ts:150`). Zero production callers (verified via `rg -rn "record_byok_use_and_check_cap" apps/web-platform/{server,app,lib}`).
- **is_workspace_member migration grants** (053:139-140): `REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ... TO authenticated;`. Service_role explicitly REVOKEd. The migration-063 GRANT additive (`TO service_role`) is back-compat: `GRANT EXECUTE ... TO service_role` does not affect any other role's permissions.
- **Solo-canary invariant source:** Migration 059 backfill predicate at lines 344-347 — `UPDATE scope_grants SET workspace_id = m.workspace_id FROM workspace_members m WHERE m.user_id = g.founder_id AND m.workspace_id = g.founder_id AND m.role = 'owner'`. The `workspace_id = founder_id` clause is the structural invariant of the post-migration-059 schema for solo users; multi-workspace introduces NEW workspaces where this no longer holds, but for the migration-063 derivation in `grant_action_class` the predicate is unambiguous because `auth.uid()` IS the owner of the solo workspace.
- **package.json scripts.test** captured at deepen-pass: vitest harness; no `bunfig.toml` test pathIgnorePatterns in `apps/web-platform/` (no defense-in-depth filter masking discovery).

**Risk note (deepen-pass):**

- Migration 053:139-140 wrote `REVOKE ALL ... FROM service_role` for `is_workspace_member`. Granting EXECUTE TO service_role in migration 063 widens the access slightly. **Verification:** service_role can already SELECT directly from `workspace_members` (no RLS gate for service_role), so the function call is functionally equivalent in access pattern. The function is read-only, side-effect-free, and SECURITY DEFINER with a pinned search_path — no privilege-escalation surface introduced.

## Architecture Decision — How to fix `grant_action_class` (Class A)

Three options; the plan recommends **Option 2**.

### Option 1: Update RPC signature to `(p_action_class, p_tier, p_workspace_id)`

**Pro:** Explicit; caller controls which workspace receives the grant.
**Con:** Breaks the API of every existing TS caller (test fixtures) — all 13 sites would need an extra arg. Production has zero callers today, so the cost is purely in tests.

### Option 2: Re-derive `workspace_id` inside the RPC body from `v_founder_id` (RECOMMENDED)

Use the **solo-canary predicate** from migration 059's backfill (`059:344-347`):

```sql
SELECT workspace_id INTO v_workspace_id
FROM public.workspace_members
WHERE user_id = v_founder_id
  AND workspace_id = v_founder_id   -- solo-canary invariant from 059
  AND role = 'owner';

IF v_workspace_id IS NULL THEN
  RAISE EXCEPTION 'grant_action_class: no solo-workspace found for %', v_founder_id
    USING ERRCODE = 'P0002';  -- no_data_found
END IF;

INSERT INTO public.scope_grants (founder_id, action_class, tier, workspace_id)
     VALUES (v_founder_id, p_action_class, p_tier, v_workspace_id)
RETURNING id INTO v_grant_id;
```

**Pro:** Zero caller changes. The solo-canary invariant is the design contract per migration 059 — there's exactly one workspace per founder (their own solo backfill). Future multi-workspace support (where a founder is a member of N workspaces) requires a separate "active workspace" concept (already partially landed in migration 060 via `current_organization_jwt_hook`); the RPC can later widen to accept `p_workspace_id` with a default derived from JWT claims (see Future Work).
**Con:** Locks the RPC to the solo-workspace shape. Multi-workspace grant semantics need a future migration.

**Recommendation:** Option 2. Production has no callers, so we are NOT shipping a binding API contract; the API is internal-only and the test shape is the only consumer. The solo-canary derive matches the rest of the workspace-migration chain (mig 059 backfill, mig 058 invite RPC's owner-check). When multi-workspace lands, we'll add `p_workspace_id` as an optional arg with the same default.

### Option 3: Drop the CHECK constraint at `059:359` (REJECTED)

**Why rejected:** The CHECK constraint is the structural invariant the entire workspace-migration chain depends on. Dropping it for `scope_grants` would create a special case in an otherwise uniform "every workspace-scoped table has workspace_id NOT NULL when row is not anonymized" pattern, and would defeat the cross-tenant isolation that migration 059 was added to enforce.

## Hypotheses

(Network-outage checklist not applicable — no SSH, network, DNS, firewall, or handshake terms in the failure surface. CI failures are purely DB-contract failures inside a green workflow infrastructure.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1.** New migration file `apps/web-platform/supabase/migrations/063_post_workspace_rpc_repair.sql` exists and is `CREATE OR REPLACE`-only (no destructive DDL). Verify: `grep -cE '^(DROP|ALTER TABLE|TRUNCATE|DELETE FROM)' apps/web-platform/supabase/migrations/063_post_workspace_rpc_repair.sql` returns `0`.
- [ ] **AC2.** Migration 063 contains `CREATE OR REPLACE FUNCTION public.grant_action_class(text, text)` that derives `workspace_id` from `workspace_members` and INSERTs it into `scope_grants`. Verify: `grep -cE 'INSERT INTO public.scope_grants.*workspace_id' apps/web-platform/supabase/migrations/063_post_workspace_rpc_repair.sql` returns `>=1`.
- [ ] **AC3.** Migration 063 contains a `GRANT EXECUTE ON FUNCTION public.is_workspace_member(uuid, uuid) TO service_role` line. Verify: `grep -c 'GRANT EXECUTE.*is_workspace_member.*service_role' apps/web-platform/supabase/migrations/063_post_workspace_rpc_repair.sql` returns `1`.
- [ ] **AC4.** Down migration `063_post_workspace_rpc_repair.down.sql` exists and restores the pre-063 RPC body (verbatim copy from `051:256-295`) plus `REVOKE EXECUTE … FROM service_role`. Verify: `test -f apps/web-platform/supabase/migrations/063_post_workspace_rpc_repair.down.sql && grep -c "CREATE OR REPLACE FUNCTION public.grant_action_class" apps/web-platform/supabase/migrations/063_post_workspace_rpc_repair.down.sql` returns `1`.
- [ ] **AC5.** Migration 063 pins `SET search_path = public, pg_temp` per `cq-pg-security-definer-search-path-pin-pg-temp`. Verify: `grep -c 'SET search_path = public, pg_temp' apps/web-platform/supabase/migrations/063_post_workspace_rpc_repair.sql` returns `>=1` (one per CREATE OR REPLACE that has SECURITY DEFINER).
- [ ] **AC6.** Test `apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts:150` is updated to pass `p_workspace_id`. Verify: `grep -nE 'p_workspace_id' apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts` returns `>=1`.
- [ ] **AC7.** Test `apps/web-platform/test/server/lookup-conversation-for-path.tenant-isolation.test.ts:85-92` populates `workspace_id` in the conversations INSERT. Verify: `awk '/^[[:space:]]*\.from\("conversations"\)/,/expect\(error\)\.toBeNull/' apps/web-platform/test/server/lookup-conversation-for-path.tenant-isolation.test.ts | grep -c 'workspace_id'` returns `>=1`. (Awk range AND grep — flag-based form to dodge self-match per sharp-edge `2026-05-15-plan-ac-verification-commands-awk-self-match`.)
- [ ] **AC8.** All tenant-iso tests that INSERT into `conversations` populate `workspace_id`. Verify: `for f in $(rg -lE 'from\("conversations"\)\.insert' apps/web-platform/test/server/*.tenant-isolation.test.ts); do echo -n "$f: "; grep -cE 'workspace_id:' "$f"; done` reports `>=1` for every file. The enumeration (not just the named test) per sharp-edge `2026-04-18-test-mock-factory-drift-guard`.
- [ ] **AC9.** DSAR pre-state assertion at `dsar-export-workspace-tables.integration.test.ts:91-95` filters by `workspace_id = fixture.workspaceId`. Verify: `grep -nB2 'toHaveLength(1)' apps/web-platform/test/server/dsar-export-workspace-tables.integration.test.ts | head -10` shows the `.eq("workspace_id", fixture.workspaceId)` line above the assertion.
- [ ] **AC10.** DSAR post-removal assertion at `:127-132` filters by `workspace_id = fixture.workspaceId`. Same shape as AC9.
- [ ] **AC11.** Test `dsar-export-workspace-tables.integration.test.ts:108-112` calls `remove_workspace_member` with the canonical 2-arg shape (no `p_actor_user_id`). Verify: `grep -A3 'rpc..remove_workspace_member' apps/web-platform/test/server/dsar-export-workspace-tables.integration.test.ts | grep -c 'p_actor_user_id'` returns `0`.
- [ ] **AC12.** `bun run test-all` (or the package's actual `test` script per `package.json scripts.test`) passes locally for the **6 directly-affected test files** (lifecycle, template-authorizations-worm, action-sends-worm, cross-tenant-read-denied, workspace-members, byok-kill-switch atomicity, lookup-conversation-for-path tenant-iso, ws-handler tenant-iso, session-sync tenant-iso, dsar-export-workspace-tables). Verify: capture the test command from `apps/web-platform/package.json` `scripts.test` first (vitest vs bun test — per sharp-edge); run that exact form; assert exit code 0.
- [ ] **AC13.** No regressions: `apps/web-platform/scripts/test-all.sh` (whichever the repo uses) is green on the full suite. Pre-existing flakes documented per `wg-when-tests-fail-and-are-confirmed-pre`.
- [ ] **AC14.** Local migration smoke: `MIGRATION_SCHEMA_PRECONDITION_PROBE=1 bash apps/web-platform/scripts/run-migrations.sh` applies 063 cleanly against a freshly-reset dev/local Supabase (or under `dry-run-against-staging` per the workflow). The down migration round-trips cleanly: apply → down → apply.
- [ ] **AC15.** PR body uses `Closes #4342` (not `Ref` — there are no post-merge operator steps; the tenant-integration CI run on next push is the verification, handled automatically).
- [ ] **AC16.** PR body includes a link to predecessor PR #4339 and predecessor issue #4338 framing (this PR is the secondary cleanup pass).
- [ ] **AC17.** Branch passes `tenant-integration.yml` CI workflow on the PR (the workflow runs on `pull_request` events against `apps/web-platform/supabase/migrations/**` and `apps/web-platform/test/server/**`; verify both globs hit by this PR). If `pull_request` is not configured for tenant-integration, request a one-shot `gh workflow run tenant-integration.yml --ref <feature-branch>` post-push and report the run URL in the PR body. **Note:** `tenant-integration.yml` MUST exist on the default branch for `--ref` dispatch; verify with `gh workflow list | grep tenant-integration` at plan time.

### Post-merge (operator)

(None. Tenant-integration CI runs automatically on the next push to main after merge. No manual step required.)

## Files to Edit

| File | Change | Reason |
|---|---|---|
| `apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts` | Line 150: add `p_workspace_id: founder.id` (solo-canary) to the `rpc("record_byok_use_and_check_cap", {...})` call. | Class C — PGRST202 |
| `apps/web-platform/test/server/lookup-conversation-for-path.tenant-isolation.test.ts` | Line 86 (`service.from("conversations").insert`): add `workspace_id: user.id`. | Class D — 23502 |
| `apps/web-platform/test/server/api-usage.tenant-isolation.test.ts` | Line 90 (`service.from("conversations").insert`): add `workspace_id: user.id`. (Discovered at deepen-pass — not in initial issue body.) | Class D — 23502 |
| `apps/web-platform/test/server/ws-handler.tenant-isolation.test.ts` | Line 92 (`service.from("conversations").insert` seeding B's row) AND line 186 (RLS-deny INSERT test): add `workspace_id: user.id`. Line 92 is the root cause of `convRow null` panic at :99; line 186 is the spoof-attack test which needs `workspace_id` to reach the RLS WITH-CHECK gate (otherwise it fails at 23502 BEFORE RLS evaluates, masking the test's intent). | Class D — 23502 |
| `apps/web-platform/test/server/dsar-export-workspace-tables.integration.test.ts` | Lines 91-95: add `.eq("workspace_id", fixture.workspaceId)` to the pre-state SELECT. Lines 127-132: same for post-state SELECT. Lines 108-112: drop `p_actor_user_id` from the `rpc("remove_workspace_member", …)` call. | Class E + Class F |

**Note on session-sync:** Initial plan listed `session-sync.tenant-isolation.test.ts` as a Class-D candidate but deepen-pass grep (`grep -nE '\.insert' apps/web-platform/test/server/session-sync.tenant-isolation.test.ts`) returns no `.insert` lines. The `afterAll: deleteUser failed` test failure is a transitive symptom of the upstream Class A/B failures (FK-RESTRICT pre-image rows accumulating). The fix should resolve it without touching this file.

## Files to Create

| File | Purpose |
|---|---|
| `apps/web-platform/supabase/migrations/063_post_workspace_rpc_repair.sql` | Up migration: CREATE OR REPLACE `grant_action_class` with workspace_id derivation + `GRANT EXECUTE … is_workspace_member … TO service_role`. |
| `apps/web-platform/supabase/migrations/063_post_workspace_rpc_repair.down.sql` | Down migration: restore the pre-063 `grant_action_class` body (verbatim copy from `051:256-295`) + `REVOKE EXECUTE … FROM service_role`. |
| `knowledge-base/project/learnings/2026-05-22-tenant-integration-runtime-failures-post-mig-059.md` | Learning: "Adding a NOT-NULL `workspace_id` constraint without updating dependent RPC bodies + service-role GRANTs" — captures the multi-class shape and the issue-body-vs-reality 3× gap. |

## Implementation Phases

### Phase 0 — Preconditions (≤ 10 min)

1. `pwd` to confirm worktree path equals `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-4342-tenant-integration-runtime-failures`.
2. `git branch --show-current` returns `feat-one-shot-4342-tenant-integration-runtime-failures`.
3. `gh issue view 4342 --json state` returns `OPEN`.
4. `cat apps/web-platform/package.json | jq -r '.scripts.test'` to capture the actual test invocation (verified at deepen-pass: **`vitest`**). Cite the exact form in the work-log.
5. `awk '/^on:/,/^[a-z]+:[[:space:]]*$/' .github/workflows/tenant-integration.yml | head -30` to confirm `pull_request` triggers on `supabase/migrations/**` AND `test/server/**` paths (verified at deepen-pass: both globs hit by this PR; no `workflow_dispatch --ref` needed).
6. **Production migration state probe (NEW — deepen-pass requirement).** Query prd-Supabase via the Supabase MCP to determine whether migration 059 has been applied to production:
   ```
   mcp__plugin_supabase_supabase__authenticate (if not already)
   then query the prd project: SELECT filename, applied_at FROM public._schema_migrations
     WHERE filename LIKE '059_%' OR filename LIKE '062_%' ORDER BY applied_at;
   ```
   AND:
   ```
   SELECT to_regclass('public.workspaces') IS NOT NULL AS workspaces_exists,
          (SELECT is_nullable FROM information_schema.columns
             WHERE table_schema='public' AND table_name='conversations'
               AND column_name='workspace_id') AS conversations_workspace_nullable;
   ```
   **Disposition:**
   - **If migration 059 NOT applied to prd:** production is safe. Note in work-log; proceed with narrow CI-fix scope.
   - **If migration 059 IS applied to prd AND `conversations.workspace_id` is `NO` (NOT NULL):** production `createConversation` and 6+ `messages.insert` sites are CURRENTLY BROKEN. File a P0 follow-up issue **immediately** (`type/bug`, `priority/p0` if labels exist; else `bug` + `domain/engineering`) with title `P0: production conversation/message creation broken — workspace_id NOT NULL after mig 059 with no application-side population`. The follow-up enumerates: `apps/web-platform/server/ws-handler.ts:761` (conversations), `apps/web-platform/server/cc-dispatcher.ts:1411,1519` (messages), `apps/web-platform/server/agent-runner.ts:435,2322` (messages), `apps/web-platform/server/inngest/functions/github-on-event.ts:230` (messages), `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts:224` (messages), `apps/web-platform/app/api/internal/kb-drift-ingest/route.ts:137` (messages). The follow-up issue MUST also note that the fix shape for production differs from the CI-test fix (production resolves workspace_id from `userWorkspaces.get(userId)` or `getDefaultWorkspaceForUser` — the workspace-resolver already exists in `apps/web-platform/server/workspace-resolver.ts`; tests use the solo-canary). Cross-link both issues. Proceed with this PR as scoped (narrow CI fix); do NOT block on the production fix.
7. **Open code-review overlap re-check** (deepen-pass already returned None; re-run at /work time in case new issues landed): `gh issue list --label code-review --state open --limit 200 | wc -l` and re-run the overlap loop.

### Phase 1 — Reconciliation Grep (≤ 10 min)

1. **Enumerate every `conversations.insert` site in tenant-iso tests:**
   ```bash
   rg -lE 'from\("conversations"\)\.insert' apps/web-platform/test/server/ | grep -E '\.tenant-isolation\.test\.ts$'
   ```
   For each file, capture the line range of the INSERT and the surrounding fixture context. Add to `Files to Edit` if not already listed (treat this as the canonical list, not the issue body).

2. **Enumerate every `grant_action_class.rpc` site:** Already done in Plan Research (13 sites across 4 files). Re-confirm with the same `rg -nE 'rpc..grant_action_class' apps/web-platform/test/`. None need TS edits (RPC body change is back-compat for callers).

3. **Enumerate every `record_byok_use_and_check_cap.rpc` site:** Already 1 known site. Confirm with `rg -nE 'rpc..record_byok_use_and_check_cap' apps/web-platform/`.

4. **Enumerate every `is_workspace_member.rpc` site that uses service-role:** `rg -nE 'rpc..is_workspace_member' apps/web-platform/test/server/`. Confirm the GRANT fix covers all of them.

### Phase 2 — Migration 063 (CREATE OR REPLACE only) (≤ 30 min)

1. **TDD RED:** Run `bash apps/web-platform/scripts/test-all.sh` (or the script the package uses) — confirm at minimum the 4 failure classes (A, B, C, D, E, F → 8+ failures) are red. Capture the failure count.

2. **Write `063_post_workspace_rpc_repair.sql`:**
   - Block 1: `CREATE OR REPLACE FUNCTION public.grant_action_class(p_action_class text, p_tier text) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$ … $$;` — body derives `v_workspace_id` from the solo-canary predicate, INSERTs `workspace_id` alongside the existing columns. Preserve all REVOKE/GRANT lines verbatim from `051:292-295`.
   - Block 2: `GRANT EXECUTE ON FUNCTION public.is_workspace_member(uuid, uuid) TO service_role;` (one-liner; no REVOKE — additive).
   - Header comment: cite #4342, the 6 failure classes, and the migration-059 solo-canary invariant as the design constraint.

3. **Write `063_post_workspace_rpc_repair.down.sql`:**
   - Block 1: `CREATE OR REPLACE FUNCTION public.grant_action_class(…)` — verbatim copy of `051:256-295` (the pre-workspace body that does `INSERT … (founder_id, action_class, tier)` without workspace_id). Caveat: the down migration will fail CHECK constraint `scope_grants_workspace_id_check` on first INSERT post-down; that's acceptable — down migrations land us in a known-broken state that callers can re-up from. Document this in the file header.
   - Block 2: `REVOKE EXECUTE ON FUNCTION public.is_workspace_member(uuid, uuid) FROM service_role;`.

4. **Validate locally:** Apply against a fresh local Supabase (or `dry-run-against-staging`):
   ```bash
   psql "$DEV_SUPABASE_DB_URL" -f apps/web-platform/supabase/migrations/063_post_workspace_rpc_repair.sql
   ```
   Confirm no errors. Then re-derive the down + up round-trip.

5. **TDD GREEN (DB-side only):** Re-run failing tests for Classes A + B (the RPC fix). Expect 5 of the 8+ failures to now pass; tests still failing should be Classes C, D, E, F.

### Phase 3 — Test fixture updates (≤ 30 min)

1. **Class C fix** — `byok-kill-switch.atomicity.tenant-isolation.test.ts:150`:
   ```typescript
   service.rpc("record_byok_use_and_check_cap", {
     p_invocation_id: randomUUID(),
     p_founder_id: founder.id,
     p_workspace_id: founder.id,  // solo-canary
     p_agent_role: "test-atomicity",
     p_token_count: 10,
     p_unit_cost_cents: 10,
   });
   ```

2. **Class D fix** — every `conversations.insert` site in tenant-iso tests:
   ```typescript
   await service.from("conversations").insert({
     user_id: user.id,
     workspace_id: user.id,  // solo-canary per mig 059 backfill
     session_id: ...,
     context_path: ...,
     repo_url: ...,
     last_active: ...,
   });
   ```

3. **Class E fix** — DSAR pre-state at `:91-95`:
   ```typescript
   const { data } = await service
     .from("workspace_members")
     .select("workspace_id, user_id, role")
     .eq("user_id", harry.userId)
     .eq("workspace_id", fixture.workspaceId);  // ADDED
   expect(data).toHaveLength(1);
   ```
   And post-state at `:127-132`:
   ```typescript
   const { data: afterRows } = await service
     .from("workspace_members")
     .select("workspace_id, user_id")
     .eq("user_id", harry.userId)
     .eq("workspace_id", fixture.workspaceId);  // ADDED
   expect(afterRows).toHaveLength(0);
   ```

4. **Class F fix** — `dsar-export-workspace-tables.integration.test.ts:108-112`:
   ```typescript
   const { error: rmErr } = await service.rpc("remove_workspace_member", {
     p_workspace_id: fixture.workspaceId,
     p_user_id: harry.userId,
     // REMOVED: p_actor_user_id: owner.userId  (RPC signature is 2-arg)
   });
   ```
   The current test has a fallback to direct DELETE which masks this error — the fallback can stay as defense-in-depth, but the primary call should match the canonical signature.

5. **TDD GREEN (full):** Re-run all affected tests. Expect all 8+ failures to resolve. Capture pass count.

### Phase 4 — Test suite green (≤ 15 min)

1. Run the full `test-all.sh` (or equivalent per Phase 0.4) suite locally. Document any pre-existing flakes (per `wg-when-tests-fail-and-are-confirmed-pre`).
2. If a transient flake hits, re-run the specific file 3× and confirm pass; if 2/3 pass, treat as pre-existing.

### Phase 5 — Learning + commit + PR (≤ 30 min)

1. **Write learning** `knowledge-base/project/learnings/2026-05-22-tenant-integration-runtime-failures-post-mig-059.md` (date will be the actual commit date per sharp-edge re: prescribing exact dates):
   - Problem: NOT-NULL workspace_id constraint added in mig 059 without updating dependent RPC bodies (051 grant_action_class) or service-role grants (053 is_workspace_member). Issue body understated the failure surface by 3×.
   - Investigation: `gh run view --log-failed` enumerated 8+ failures across 6 classes; issue body listed 2. Plan-time grep against the actual log was load-bearing.
   - Pattern: when a migration adds a NOT-NULL constraint to a column on a table that has SECURITY DEFINER RPC writers, every CREATE OR REPLACE that writes to that table must be re-issued in the same migration (or an immediate follow-up) — the CHECK invariant and the RPC body are a contract pair.
   - Sharp edge: service-role grants ≠ authenticated grants. Tests that use service-role bypass RLS but still need EXECUTE on SECURITY DEFINER fns — 053's `REVOKE ALL FROM ... service_role` is correct security posture for prod, but tests need `GRANT EXECUTE … TO service_role` as an explicit additive line in a downstream migration.

2. **Commit + push.** Use `git add` with explicit file paths (no `-A`). Commit message convention from recent log: `fix(supabase): ...` or `fix(tenant-integration): ...`.

3. **Open PR.** Title: `fix(tenant-integration): grant_action_class workspace_id + service-role is_workspace_member GRANT + test fixture workspace_id (post-#4339)`. Body uses `Closes #4342`, links to predecessor PR #4339 + issue #4338, and includes the 6-class enumeration.

4. **Verify CI** — wait for `tenant-integration.yml` on the PR. Confirm green.

## Risks

- **R1.** Migration 063 lands but pre-existing `scope_grants` rows from prior CI runs still have `workspace_id IS NULL` (with `founder_id IS NOT NULL`) — the CHECK constraint is already in dev. Mitigation: those rows would have failed migration 059's ALTER ADD CONSTRAINT; if they don't exist now, they won't exist post-063. Verify pre-write with `SELECT count(*) FROM scope_grants WHERE founder_id IS NOT NULL AND workspace_id IS NULL` in the dev-Supabase Phase 1 grep. If any rows exist, file a follow-up issue for retroactive backfill (the constraint already gates this class, so any such rows would block ALTER and we'd already know).

- **R2.** A multi-workspace future requires `grant_action_class` to accept an explicit workspace target. Solution path: add a downstream migration that widens the RPC to `(p_action_class, p_tier, p_workspace_id uuid DEFAULT NULL)` and falls back to the solo-canary derivation when NULL. Tracked as a Future Work item (file as a GitHub issue if the workspace-roadmap PRs are imminent — per `wg-when-deferring-a-capability-create-a`).

- **R3.** `tenant-integration.yml` doesn't run on `pull_request` events. Verify in Phase 0.5 with `awk '/^on:/,/^[a-z]+:/' .github/workflows/tenant-integration.yml`. If `pull_request` is NOT a trigger, plan a `gh workflow run tenant-integration.yml --ref <feature-branch>` post-push.

- **R4.** The session-sync and ws-handler tenant-iso tests may have OTHER `conversations.insert` sites that the issue's log doesn't reveal because they fail-fast at the first one. The grep enumeration in Phase 1.1 is load-bearing; if Phase 4 reveals new fixture-side failures after Class D is fixed at the named sites, expand the file list.

- **R5.** The DSAR `remove_workspace_member` test's current fallback (direct DELETE when the RPC errors) MAY hide a regression after Phase 3.5: if the canonical 2-arg call succeeds (good), but the fallback test code path no longer fires, any regression in the RPC's WORM-ledger INSERT (which migration 062 added BEFORE the DELETE) would not be tested by this file. The DSAR test isn't WORM-specific so this is acceptable, but consider a follow-up that asserts the WORM ledger row appears after the RPC call.

## Open Code-Review Overlap

**Executed at deepen-plan time (2026-05-22):**

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
# 77 open code-review issues; queried each Files-to-Edit path:
for path in \
  apps/web-platform/supabase/migrations/063_post_workspace_rpc_repair.sql \
  apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts \
  apps/web-platform/test/server/lookup-conversation-for-path.tenant-isolation.test.ts \
  apps/web-platform/test/server/api-usage.tenant-isolation.test.ts \
  apps/web-platform/test/server/ws-handler.tenant-isolation.test.ts \
  apps/web-platform/test/server/dsar-export-workspace-tables.integration.test.ts; do
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

**Result: None.** Zero open code-review issues reference any of the 6 Files-to-Edit paths. Re-confirm at /work Phase 0 (new code-review issues may land between plan and PR creation).

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO) — escalated by deepen-pass due to user-facing API impact.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Single-domain bug fix in the supabase migrations + test fixtures surface. The migration-063 RPC change is back-compat at the API surface (`grant_action_class(text, text)` shape preserved; workspace_id derivation is internal). The blast radius is (a) CI tenant-integration green, (b) production scope-grants UI 500-error class restored to success, (c) follow-up audit of other workspace_id NOT NULL writer surfaces (sharp-edge above).

**Brainstorm-recommended specialists:** none (no brainstorm phase ran for this hotfix).

### Product (CPO)

**Status:** reviewed (deepen-pass)
**Tier:** ADVISORY → escalated to BLOCKING by deepen-pass per User-Brand Impact threshold = `single-user incident`.
**Assessment:** The fix restores a broken user-facing flow (scope-grants UI "Grant" → 500 error). No new UI/UX surface is introduced; no copy changes; the fix is an invariant restoration. **CPO sign-off requirement:** acknowledged at plan time per `requires_cpo_signoff: true` in frontmatter; review-time `user-impact-reviewer` will enumerate failure modes against the diff (handled by `plugins/soleur/skills/review/SKILL.md` conditional-agent block). No wireframes needed (no new UI). No copywriter needed (no new copy).
**Decision:** reviewed
**Agents invoked:** none at plan-time (no new UX/copy surface to spawn for); review-time `user-impact-reviewer` runs against the diff.
**Skipped specialists:** ux-design-lead (no UI), copywriter (no new copy), spec-flow-analyzer (no new user flow — restoration of broken existing flow).

## User-Brand Impact

**If this lands broken, the user experiences:** A 500 error in the scope-grants UI ("Grant" button → `{error: "rpc_failed"}`) preventing them from configuring action-class tier grants. Reachable via `apps/web-platform/components/scope-grants/scope-grant-row.tsx:74` → `apps/web-platform/app/api/scope-grants/grant/route.ts:73` → `supabase.rpc("grant_action_class", {p_action_class, p_tier})` → CHECK constraint violation 23514 (`scope_grants_workspace_id_check`). The CI tenant-integration gate ALSO stays red, blocking future PRs.

**If this leaks, the user's [data / workflow / money] is exposed via:** No data leakage path. The CHECK constraint, RLS policies, and workspace_id NOT NULL invariant all hold at the DB layer — a failed INSERT does not leak any data. The `is_workspace_member` GRANT to service_role widens an internal SECURITY DEFINER caller surface, but service_role already bypasses RLS, so this is not a new exposure axis.

**Brand-survival threshold:** `single-user incident`
**Reason:** Any individual user who attempts to configure scope-grant tiers via the UI today (IF migration 059 has applied to prd) hits a hard 500 error and cannot proceed. This is a per-user functional block — not a data-leak class — but it directly affects the user-perceived "trust this app to remember my settings" surface. CPO sign-off required because the affected user-flow is on the core BYOK trust-tier configuration path (one of the agent-native control planes). Plan-time mitigation: invoke `user-impact-reviewer` at review-time (handled by `plugins/soleur/skills/review/SKILL.md` conditional-agent block when `requires_cpo_signoff: true` is set in frontmatter).

**Additional disclosed failure modes (review-time amendment):**

- **Derive-NULL path:** a user whose solo `workspace_members` row is missing (theoretically only possible if `handle_new_user` failed at signup) sees the same opaque `{error: "rpc_failed"}` 500 from `app/api/scope-grants/grant/route.ts` — error is `23502` (NOT NULL on `scope_grants.workspace_id`) rather than `23514` (CHECK). User experience is identical to the original bug; recovery requires operator intervention (manually re-running the trigger). Acceptable because the trigger has been live since 053 with no known failures.
- **Rolling-deploy window:** the tenant-integration CI job runs against dev-Supabase only. After merge, the Next.js platform redeploys via Vercel auto-deploy on main, but mig 063 must be applied to prd-Supabase via the platform's migration runner. If 059 is already live on prd (per Phase 0.6 probe), the window between merge and prd-Supabase apply continues to surface 500s for any user clicking "Grant". Mitigation: prd-Supabase migration apply is the next CI step after Vercel deploy in the platform's existing release workflow; window is typically <10 min.
- **Out-of-scope production blast radius (cross-link):** if 059 is live on prd, production `conversations.workspace_id` and `messages.workspace_id` INSERTs at 7 named server sites (`ws-handler.ts:761`, `cc-dispatcher.ts:1411,1519`, `agent-runner.ts:435,2322`, `inngest/functions/github-on-event.ts:230`, `cfo-on-payment-failed.ts:224`, `api/internal/kb-drift-ingest/route.ts:137`) fail 23502 with full agent-output and chat-session collapse — a much broader user-facing failure mode than the scope-grants 500 this PR addresses. The Phase 0.6 probe mandates filing a P0 follow-up if 059 is confirmed live; this PR stays narrow on the CI surface intentionally because the production fix requires wiring `workspace-resolver.ts` into each call site (out-of-scope diff).

## Observability

(Not applicable for this scope — no new code-class files under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/` are created or modified. The migration files are SQL-only and the test files are test-only. Skipping the Observability schema per Phase 2.9 "pure-docs / fixtures-only" carve-out.)

## Infrastructure (IaC)

(Not applicable — no infrastructure surface touched. Supabase migrations are managed via the `apps/web-platform/scripts/run-migrations.sh` runner, which is already part of the established workflow per PR #4339. No new servers, services, vendors, secrets, DNS records, or persistent runtime processes are introduced. Phase 2.8 skip is legitimate.)

## Test Strategy

- **Unit/integration tests:** All test changes are to existing tenant-iso integration tests. No new test files are needed; the fix exercises the failing tests directly.
- **Test runner:** `apps/web-platform/package.json` `scripts.test` — confirm in Phase 0.4 whether it's `vitest` or `bun test`. Use that exact form in every AC verification (per sharp-edge re: package.json scripts.test).
- **Test selection:** Run the 6 directly-affected files (+ any additional `conversations.insert` files enumerated in Phase 1.1) for fast TDD cycles. Run the full `test-all.sh` once at the end for regression coverage.
- **CI verification:** `tenant-integration.yml` on the PR (the workflow is the canonical signal for this issue — local green ≠ dev-Supabase green because of PostgREST schema-cache timing and the schema-cache-stale skip path in `workspace-members.test.ts:67-74`).

## Future Work (Out of Scope)

- **Multi-workspace `grant_action_class`:** When a founder is a member of N workspaces (beyond their own solo backfill), the RPC needs an explicit `p_workspace_id` arg with the solo-canary as default. File as a separate issue; tracked under the team-workspace roadmap.
- **WORM ledger assertion in DSAR test:** Add an assertion that `workspace_member_removals` row exists after the `remove_workspace_member` RPC succeeds (Phase 3.4 R5).
- **Service-role GRANT audit:** Sweep every SECURITY DEFINER function in `apps/web-platform/supabase/migrations/` and confirm tests that call them via service-role have the corresponding GRANT. Filing as a follow-up issue would catch the next instance of this class.

## References

- Predecessor PR #4339 (merged 2026-05-22 — schema-vs-ledger drift fix)
- Predecessor issue #4338
- Sibling PR #4225 (team-workspace, merged 2026-05-21 — introduced migrations 053-060 + the workspace_id NOT NULL constraints)
- Sibling PR #4294 (DSAR departed-member coverage, merged 2026-05-22 — introduced migration 062 + remove_workspace_member CREATE OR REPLACE)
- Predecessor learning `knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md` (verified file path)
- Failing CI run: `gh run view 26288051420 --log-failed`
- Migration 048 (original `grant_action_class`) `apps/web-platform/supabase/migrations/048_scope_grants.sql:131`
- Migration 051 (current `grant_action_class` 4-tier widening) `apps/web-platform/supabase/migrations/051_action_class_widening_and_action_sends.sql:256`
- Migration 053 (`is_workspace_member` definition + GRANT) `apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql:116,139-140`
- Migration 059 (workspace_id NOT NULL + CHECK constraint) `apps/web-platform/supabase/migrations/059_workspace_keyed_rls_sweep.sql:62,359`
- Migration 059 backfill predicate (solo-canary invariant) `apps/web-platform/supabase/migrations/059_workspace_keyed_rls_sweep.sql:344-347`
- Migration 061 (`record_byok_use_and_check_cap` 6-arg signature) `apps/web-platform/supabase/migrations/061_byok_audit_workspace_id_rpcs.sql:81-152`
- Migration 062 (`remove_workspace_member` CREATE OR REPLACE) `apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql:272`

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Above section is filled; threshold `single-user incident` is justified by the production caller chain `components/scope-grants/scope-grant-row.tsx:74 → app/api/scope-grants/grant/route.ts:73`.
- **handle_new_user trigger interaction:** Migration 053 created a `handle_new_user` AFTER INSERT trigger on `auth.users` that auto-creates an `organizations` + `workspaces` + `workspace_members(owner)` triple for every new user. Tests calling `service.auth.admin.createUser` get this triple provisioned automatically — the solo-canary predicate `workspace_members WHERE user_id=v_founder_id AND workspace_id=v_founder_id AND role='owner'` finds exactly one row. **If the trigger ever changes** (e.g., to use random UUIDs for workspace_id instead of `user_id`), migration 063's derivation breaks. Track this dependency in the learning. Probe: `grep -nE 'handle_new_user' apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql | head -5`.
- **The 3-table CHECK constraint surface:** Migration 059 didn't only add the constraint to `scope_grants`. It also set `conversations.workspace_id NOT NULL` (059:62), `messages.workspace_id NOT NULL` (059:94), `kb_share_links.workspace_id NOT NULL` (059:146), AND `audit_github_token_use.workspace_id NOT NULL` (059:396). **Migration 063's fix scope is `grant_action_class` only**; every other RPC writer must be audited separately. The follow-up issue filed at Phase 0.6 (if mig 059 is live on prd) covers `conversations` and `messages`; `kb_share_links` and `audit_github_token_use` need separate verification.
- Production callers of `grant_action_class` and `record_byok_use_and_check_cap` MAY land between this plan and merge. If a PR adds a production caller of `record_byok_use_and_check_cap` before this one merges, the test fix in Class C must be cross-checked. Mitigation: this PR's `grant_action_class` change is back-compat (CREATE OR REPLACE preserves the 2-arg shape externally; new derivation is internal-only).
- The `dsar-export-workspace-tables.integration.test.ts:108` fallback to direct DELETE has been a silent escape valve that masked the canonical-signature mismatch. Removing the bogus 3rd arg (Class F) restores correctness but also tightens the test — if `remove_workspace_member` later regresses, the fallback will no longer save us. This is the right behavior; document in the learning.
- Migration `063` is `CREATE OR REPLACE` only — no destructive DDL. The down migration is a controlled regression to the pre-fix state, which IS broken (the CHECK constraint added by 059 still rejects inserts without workspace_id); document this caveat in the down-file header so future operators understand the down isn't a full restore.
- The solo-canary invariant (`workspace_id = founder_id` for the solo backfill workspace) is load-bearing across migrations 058-062 AND now 063. If the team-workspace roadmap changes this invariant (e.g., workspaces stop being identified by their owner's user_id), migration 063 must be widened in lockstep. Track in the learning.
