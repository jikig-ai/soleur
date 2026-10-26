---
title: "fix: tenant-integration red on main — session-sync UPDATE-deny asserts get 57014 (RLS InitPlan seq-scan) not 42501"
date: 2026-10-26
slug: fix-tenant-integration-session-sync-57014
branch: feat-one-shot-10764-tenant-integration-red
issue: 10764
type: bug
lane: single-domain
closes: 10764
---

## Overview

`Tenant integration (dev-Supabase)` (`.github/workflows/tenant-integration.yml`) is
deterministically red on main — issue #10764, filed by `check-red-on-main.sh`. Three
tests in `apps/web-platform/test/server/session-sync.tenant-isolation.test.ts` assert a
cross-tenant `UPDATE public.users` is denied and expect `error.code === "42501"`
(`insufficient_privilege`). They now receive `"57014"` (`query_canceled` /
statement_timeout) after ~8.2s each.

**Root cause (verified live against dev, not hypothesized):**

1. Migration `006_restrict_tc_accepted_at_update.sql` revoked table-level `UPDATE` on
   `public.users` from `authenticated`, leaving column-level `GRANT UPDATE (email)` — so a
   tenant UPDATE on any other column failed fast with `42501` at the privilege check.
2. On 2026-10-26T13:04:19Z, open PR #11180's `tenant-integration` run (id 40326344091)
   applied its unmerged migration `174_api_data_grants_snapshot.sql` to the shared dev
   project (`ALLOW_UNMERGED_DEV_APPLY=1`). That migration is a verbatim snapshot of prd's
   effective ACLs — and prd carries table-level `UPDATE` on `public.users` for all API
   roles (a "known deliberate snapshot wart" per the migration header + ADR-303). So dev
   gained the table-level grant → the UPDATE began **executing** instead of erroring.
3. The three RESTRICTIVE `FOR UPDATE` policies on `public.users` (migs `016`,
   `017_kb_sync_history`, `017_project_health_snapshot`) each embed a correlated
   self-subquery `… IS NOT DISTINCT FROM (SELECT <col> FROM public.users WHERE id =
   auth.uid())`. These plan as **InitPlans containing Seq Scans over `public.users`**,
   whose per-row filter additionally calls `is_jti_denied_from_jwt()` (SECURITY DEFINER,
   ~295k calls). Live `EXPLAIN ANALYZE` on dev (rolled back): **17,565 ms** — "InitPlan 4:
   Seq Scan on users, Rows Removed by Filter: 294,640". Dev's `public.users` holds
   ~294,646 rows (accumulated synthetic fixtures); prd holds ~18 — the landmine is
   invisible at prd scale.
4. Under the API role's ~8s `statement_timeout`, the statement is cancelled → `57014`.
   The 42501 expectation had masked this plan pathology because the privilege error fired
   before execution.

This is a real, production-shaped perf hazard, not just a test artifact: any reachable
`authenticated` UPDATE on `public.users` (e.g. the permitted `UPDATE (email)` self-update)
executes the same seq-scan InitPlan path when a candidate row exists.

## Research Insights

**Relevant file paths**

- `apps/web-platform/test/server/session-sync.tenant-isolation.test.ts:200-280` — the
  three failing assertions (`:254`, `:270`, `symmetric`), all accept the dual deny shape
  (`42501` error OR `data === []`) and re-verify via service-role read-back.
- `apps/web-platform/supabase/migrations/016_github_username.sql:11-20`,
  `017_kb_sync_history.sql:11-19`, `017_project_health_snapshot.sql:13-17` — the three
  RESTRICTIVE `FOR UPDATE` policies with correlated self-subqueries.
- `apps/web-platform/supabase/migrations/006_restrict_tc_accepted_at_update.sql` —
  `REVOKE UPDATE ON TABLE public.users FROM authenticated` + `GRANT UPDATE (email)`.
- `apps/web-platform/supabase/migrations/054_users_role_column.sql` — precedent: uses a
  `BEFORE UPDATE` trigger (`users_prevent_role_self_mutation`) rather than a policy
  subquery; its comment explicitly recommends triggers over WITH CHECK for column guards.
- `.github/workflows/tenant-integration.yml` — `ALLOW_UNMERGED_DEV_APPLY=1` applies a PR's
  unmerged migrations to the ONE shared dev project (documented hazard, #8049).
- `scripts/check-tom4-rls-posture.sh` — existing policy-model linter; keys on policy
  NAMES (preserved by this fix), not expression text.

**Premise Validation (Phase 0.6)**

- Issue #10764: OPEN, `ci/main-broken`, auto-closes on green verdict. ✓ held
- Cited files all exist on `origin/main`. ✓ held
- First red main run 40326599239 (12:57Z) tested after PR #11180's dev apply of
  migration 174 (13:04Z, run 40326344091); last green 10399a7 at 11:54Z. The four main
  commits between are docs/CI-only — no code change caused this. ✓ causal chain verified
- PR #9051 (tenant-isolation-teardown.ts): unmerged, unrelated to this failure mode.
- The claim "42501→57014 means the write isn't denied" refined: the write IS denied by
  RLS (0 rows reach UPDATE); it just takes 17s to be denied. Verified by live
  `EXPLAIN ANALYZE` under `SET ROLE authenticated` + `request.jwt.claims`.

**Property List (Phase 0.6b — what the ask actually requires)**

1. The `Tenant integration` check reports green on main (issue auto-closes).
2. A cross-tenant UPDATE on `users` is still verifiably denied (RLS-effective).
3. The fix must be posture-independent: green whether `authenticated` holds table-level
   UPDATE (prd wart / post-#11180) or only `UPDATE(email)` (mig-006 intent).
4. No mechanism beyond a migration + verification is needed — the test file already
   accepts both deny shapes.

**Cut List (Phase 0.6b)**

- *Test assertion widening to accept 57014* → buys property 1 at the price of property 2
  (a timed-out write is NOT proof of denial). Cut.
- *Manual `REVOKE UPDATE` on dev* → restores 42501 (property 1) but fights prd-parity,
  is a non-durable hand mutation of shared dev, and leaves the seq-scan landmine live.
  Cut as primary fix; acceptable only as an emergency unblock note.
- *Narrowing the users UPDATE grant via new migration* → tracked by PR #11180's own
  follow-up ("narrowing is tracked in the follow-up issue"); out of scope here. Cut.

**Institutional learnings that apply**

- `2026-06-15-tenant-integration-breakage-is-shared-dev-grant-drift-not-code-regression`:
  same class — shared-dev grant drift vs migration files; assert RLS-effective behavior,
  never raw grants. This test already follows it; the fix must keep it so.
- `2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations`: unmerged
  migrations applied to shared dev break main — exactly the 174 incident here.
- `2026-07-03-dev-apply-during-work-broke-shared-tenant-integration`: sibling-collision
  variant of the same shared-dev hazard.
- `2026-10-26-supabase-data-api-grant-flip-snapshot-remediation` (on PR #11180's branch):
  the grant-flip context motivating migration 174.

**Hypotheses (Phase 1.4 — "timeout" trigger fired)**

This is a Postgres `statement_timeout` (SQLSTATE 57014), not a network timeout. L3–L7
network layers (firewall/DNS/routing/sshd) are NOT implicated — verified by direct psql
reproduction of the hang inside a single SQL statement on dev (`is_jti_denied` startup
context under 8s timeout; 17.5s full run). No network hypothesis is needed.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality | Plan response |
|---|---|---|
| Issue: "42501→57014 = write NOT denied" | Write IS denied (RLS filters to 0 rows) but only after a ~17.5s seq-scan InitPlan | Fix the policy cost so the deny is fast |
| Context: "RLS/grant posture change on dev" | Confirmed: migration 174 applied to dev 13:04Z restored table-level UPDATE | Treat as expected (prd-faithful) posture, fix the pathological plan |
| Context: PR #9051 touches teardown helper | Adjacent only; no causal role | No action |

## Scope Check

- **Ask → plan mapping:** "make `Tenant integration (dev-Supabase)` green on main" →
  single deliverable: a migration removing the O(table) InitPlan from the `users` UPDATE
  path so the deny resolves as `42501` (narrow grant) or `[]` (wide grant) in <1s.
- **Item provenance:** every Files-to-Create/Edit entry is `ask`- or `evidence`-derived;
  the only `inferred` item is the verify fixture, which follows the repo's
  `supabase/verify/` convention.
- **Split assessment:** not needed — one tightly-scoped migration fix.
- **Non-goals:** narrowing the users UPDATE grant (PR #11180 follow-up), dev fixture
  bloat (~295k synthetic users — separate hygiene issue), cross-ref dev-apply race (#8049).

## Implementation Phases

### Phase 1 — Migration: make the three restrictive policies cheap

Create `apps/web-platform/supabase/migrations/NNN_users_restrictive_policy_subqueries.sql`
(NNN = next free prefix on `origin/main` at implementation time — currently ≥176; 164 is
in-flight on `feat-git-data-erasure-ledger-b1-8211`, 165–175 on
`feat-one-shot-codex-web-live-paths`, 174/175 on `feat-one-shot-supabase-public-grants`;
verify against `ls apps/web-platform/supabase/migrations/ | sort -n | tail` on a fresh
`origin/main` at work time):

1. For each guarded column, create a `plpgsql STABLE SECURITY INVOKER` function doing a
   **parameterized** primary-key lookup of the caller's own row value. plpgsql bodies are
   never inlined by the planner (a `LANGUAGE sql` function could inline right back into
   the same InitPlan seq-scan — this is load-bearing).

   ```sql
   CREATE OR REPLACE FUNCTION public.users_own_health_snapshot()
     RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER
     SET search_path = pg_catalog, public, pg_temp AS $$
   DECLARE v jsonb;
   BEGIN
     SELECT health_snapshot INTO v FROM public.users WHERE id = auth.uid();
     RETURN v;
   END $$;
   ```
   …and identically `users_own_github_username()` → `text`,
   `users_own_kb_sync_history()` → `jsonb`. Privileges: `REVOKE ALL … FROM PUBLIC` then
   `GRANT EXECUTE … TO authenticated` (service_role doesn't need them — bypasses RLS).
   These functions read only the caller's own row under INVOKER RLS (`auth.uid()=id`
   select policy), so they leak nothing.

2. `DROP POLICY IF EXISTS` + `CREATE POLICY` (same names — `check-tom4-rls-posture` keys
   on names) with the subquery replaced by the function call:

   - `"Prevent client health_snapshot update"` →
     `USING (health_snapshot IS NOT DISTINCT FROM public.users_own_health_snapshot())`
   - `"Users cannot update github_username directly"` →
     `USING (true) WITH CHECK (github_username IS NOT DISTINCT FROM public.users_own_github_username())`
   - `"Users cannot update kb_sync_history directly"` →
     `USING (true) WITH CHECK (kb_sync_history IS NOT DISTINCT FROM public.users_own_kb_sync_history())`

   Semantics are preserved exactly: each policy still requires the column value to equal
   the **caller's own row's** value — the function returns `auth.uid()`'s row, identical
   to the old subquery.

3. `NNN_users_restrictive_policy_subqueries.down.sql`: restores the three original
   subquery policies and drops the three functions.

4. `apps/web-platform/supabase/verify/NNN_users_restrictive_policy_subqueries.sql`
   (repo `verify/` convention): asserts the three functions exist, the three policies
   exist by name, and `pg_get_expr(polqual/polwithcheck)` references `users_own_` (not a
   bare `SELECT`).

**Why not a trigger?** `054`'s `users_prevent_role_self_mutation` precedent is the
alternative — a `BEFORE UPDATE` trigger comparing `NEW.<col> IS DISTINCT FROM OLD.<col>`.
Equivalent on every reachable path (the permissive policy pins `id = auth.uid()`, so OLD
is always the caller's own row). Chosen-primary is the function rewrite because it
preserves the policy expressions verbatim — smallest semantic delta, no trigger-order
coupling with `users_prevent_role_self_mutation`. Trigger variant recorded as
Alternative A below.

### Phase 2 — Verification (evidence-grade, same probe used to diagnose)

1. Run the migration against dev via the workflow's own path (the PR's
   `tenant-integration` run applies it under `ALLOW_UNMERGED_DEV_APPLY`) — OR locally:
   `doppler run -p soleur -c dev -- psql "$DATABASE_URL" -f <migration>` **in session
   mode (`:5432`), never the transaction-pooler `:6543`** (multi-statement DDL).
2. Re-run the exact reproducer under an 8s timeout; expected: `UPDATE 0` in <200ms:
   ```sql
   BEGIN; SET LOCAL ROLE authenticated;
   SELECT set_config('request.jwt.claims',
     '{"sub":"<any-real-users-id>","role":"authenticated","jti":"<uuid>"}', true);
   SELECT set_config('statement_timeout','8s',true);
   UPDATE public.users SET repo_last_synced_at='1999-01-01'::timestamptz
     WHERE id='<a-DIFFERENT-real-users-id>';   -- cross-tenant shape
   ROLLBACK;
   ```
   Pre-fix measured: 17,565ms → 57014. Post-fix expectation: <200ms, no InitPlan in
   `EXPLAIN` output for the UPDATE.
3. `cd apps/web-platform && doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1
   ./node_modules/.bin/vitest run test/server/session-sync.tenant-isolation.test.ts` →
   all green (deny shape = `[]` under the now-wider dev grant).
4. PR's own `tenant-integration` run green; after merge, re-run
   `check-red-on-main.sh "tenant-integration" --run-id <main run id> --report` → green
   verdict auto-closes #10764.

### Phase 3 — Follow-ups (file issues; not in scope for this PR)

- File an issue referencing this incident: **dev catalog-posture probe** — the
  migration-drift probe watches `_schema_migrations` rows, but grant/policy *catalog*
  drift (what actually broke) is unmeasured. Candidate: extend
  `scripts/check-tom4-rls-posture.sh` or the drift probe with an
  effective-privileges/policies snapshot for the isolation-surface tables.
- File/note under PR #11180's existing narrowing follow-up: link this incident as
  evidence for the `users` table-level-UPDATE narrowing.
- Consider a dev fixture-teardown sweep for the ~295k accumulated synthetic `users`
  rows (separate hygiene issue; not required for the fix).

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| **A. Function-in-policy rewrite (chosen)** | Smallest semantic delta; preserves policy names/expressions except the subquery; plpgsql kills inlining → parameterized PK lookup (~0.1ms/row-eval) |
| B. `BEFORE UPDATE` trigger per `users_prevent_role_self_mutation` precedent + drop 3 policies | Also correct (NEW vs OLD compare); rejected as primary: bigger mechanism change, trigger ordering coupling, and the health_snapshot policy is `USING`-shaped (row filter) not `WITH CHECK` — rewriting it as a trigger changes which statements are *candidates*, a subtler review surface |
| C. Manual `REVOKE UPDATE` on dev | Fastest unblock; non-durable (any future verbatim-grant snapshot re-opens it), diverges dev from prd, and leaves the 17s seq-scan reachable via `UPDATE (email)`. Emergency-only |
| D. Accept `57014` in the test | Legitimizes a non-denied/timed-out write; destroys the assertion's meaning. Rejected |

## Files to Create

- `apps/web-platform/supabase/migrations/NNN_users_restrictive_policy_subqueries.sql`
- `apps/web-platform/supabase/migrations/NNN_users_restrictive_policy_subqueries.down.sql`
- `apps/web-platform/supabase/verify/NNN_users_restrictive_policy_subqueries.sql`

## Files to Edit

- `apps/web-platform/test/server/session-sync.tenant-isolation.test.ts` — optional one-line
  comment at the dual-shape assertion noting the 57014 incident + this migration (no
  assertion change; the dual shape is already correct).

## Acceptance Criteria

- [ ] AC1: New migration applies cleanly to dev (verified by this PR's own
  `tenant-integration` run, or session-mode psql apply) and its `verify/` file passes.
- [ ] AC2: The cross-tenant `UPDATE public.users` reproducer completes in <1s under
  `statement_timeout='8s'` as `authenticated` — no `Seq Scan` InitPlan in its plan.
- [ ] AC3: `session-sync.tenant-isolation.test.ts` passes against dev (all three
  previously-failing assertions green via the `[]` shape; `42501` remains acceptable
  should the grant later be narrowed).
- [ ] AC4: `Tenant integration (dev-Supabase)` is green on this PR and on the first main
  run after merge; `check-red-on-main.sh` reports green → #10764 closes.
- [ ] AC5: Deny semantics preserved — the three policies keep their names and still
  require the guarded column to equal the caller's own row value (verified by the
  migration's `verify/` file + a manual `UPDATE` of `kb_sync_history` on own row with a
  *changed* value → still rejected).
- [ ] AC6: Follow-up issues filed per Phase 3.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI/test-infrastructure + database-internals fix.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — but a FALSE green
  would hide a cross-tenant write path; the actual merge risk is continued red blocking
  every PR's required `tenant-integration` context.
- **If this leaks, the user's [data] is exposed via:** n/a — this fix *strengthens* the
  isolation surface's fidelity; it changes deny mechanics, never loosens them.
- **Brand-survival threshold:** none
- `threshold: none, reason:` RLS-policy mechanics on a test isolation surface — no new
  processing, storage, or exposure; sensitive-path touch (migrations) is a deny-side fix.

## Observability

The failure surface IS the CI check — it already reports red loudly (this issue was
filed by it). The durable observability gap (catalog-posture drift invisible to the
ledger probe) is handled as a Phase-3 follow-up issue, not a new gate in this PR.

```yaml
liveness_signal:    # "Tenant integration (dev-Supabase)" check on main push / required PR context; alert = issue filed by check-red-on-main.sh
error_reporting:    # GitHub check conclusion + auto-filed ci/main-broken issue; fail_loud: yes
failure_modes:      # [{mode: cross-tenant deny regresses to timeout/error, detection: vitest assertion in session-sync.tenant-isolation.test.ts, alert_route: check-red-on-main.sh → GitHub issue}]
logs:               # GitHub Actions job log (retention: GH default)
discoverability_test:
  command:          # grep -c 'users_own_' apps/web-platform/supabase/migrations/*users_restrictive_policy_subqueries.sql
  expected_output:  # literal counts "3" (function definitions) — printed by grep -c
```

## Architecture Decision (ADR/C4)

None required. This changes the *mechanism* of an existing RLS column-guard (subquery →
function), not any ownership/tenancy boundary, substrate, or trust boundary. C4 check:
no new external actor, external system, container, or access relationship — the actors
(founder JWT, service role, Supabase project) and the deny relationship already exist in
`knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`; nothing this
plan changes would mislead a reader of the recorded architecture.

## Open Code-Review Overlap

None — `gh issue list --label code-review` bodies contain no reference to
`session-sync.tenant-isolation`, `tenant-isolation-teardown`, or migrations 016/017.

## Test Scenarios

- Cross-tenant UPDATE (`A→B`) on `users.repo_last_synced_at`, `users.kb_sync_history`:
  `[]` fast (<1s) under the dev grant posture.
- Self-update of `email` (the one granted column): still works, fast.
- Self-update of `kb_sync_history`/`github_username`/`health_snapshot` with a CHANGED
  value as `authenticated` on own row → still rejected (42501/RLS violation) — the
  policies' protective intent is unchanged.
- Down-migration restores subquery policies and drops functions (verified on local
  throwaway stack, not dev).
