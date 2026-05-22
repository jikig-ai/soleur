---
title: "fix(tenant-integration): 4 cascade failure classes post-#4343 (anonymise_scope_grants + workspace_member_actions GRANT + worm-test fixtures)"
issue: 4356
predecessor_pr: 4343
predecessor_issue: 4342
root_symptom_issue: 4249
branch: feat-one-shot-4356-tenant-integration-cascade
lane: cross-domain
type: bug-fix
classification: regulated-data-write
brand_survival_threshold: single-user-incident
requires_cpo_signoff: true
created: 2026-05-22
deepened: 2026-05-22
---

## Enhancement Summary

**Deepened on:** 2026-05-22
**Sections enhanced:** 6 (Research Reconciliation, Files to Create, Acceptance Criteria, Implementation Phases, Risks, Sharp Edges)
**Verifications run:** PR/issue state live (#4343 MERGED, #4249 OPEN, #4342 CLOSED, #4356 OPEN); migration citations live; trigger Shape 2 re-read; account-delete cascade re-read; migration runner shape confirmed (bash script — no `--dry-run`); CHECK constraint comment (mig 059:355-357) confirms design intent ("Allow NULL when founder_id IS NULL" — anonymised rows SHOULD have both NULL).

### Key Improvements

1. **AC7 corrected.** The plan originally cited `bun run scripts/run-migrations.ts --dry-run`, which does not exist. Migration runner is `bash apps/web-platform/scripts/run-migrations.sh` (bash, not bun; no dry-run flag). Phase 2 step rewritten.
2. **Shape 2 trigger note made explicit.** The `scope_grants_no_mutate` trigger Shape 2 (mig 050:42-52) does NOT name `workspace_id` in its "unchanged-cols" list, so a workspace_id NULL transition is silently permitted. Risk: future maintainer reading Shape 2 may NOT realize workspace_id can also change under Shape 2. **Decision:** Plan now considers tightening Shape 2 to EXPLICITLY recognize the founder_id+workspace_id co-transition as an option, but defers it as scope-out (`Risks` updated). The CHECK constraint at row level remains the canonical guard.
3. **CI workflow citation corrected.** Originally referenced `tenant-integration.yml` only; on inspection the workflow is `.github/workflows/tenant-integration.yml`. Plan now uses the workflow file path directly in AC12.
4. **Sweep regex tightened.** AC13's `rg` form expanded to confirm post-fix state: `rg -lUn 'from\("(conversations|messages)"\)\s*\n?\s*\.insert\([^)]*\)' apps/web-platform/test/server/*.test.ts | xargs -I{} sh -c 'grep -L "workspace_id" {} && echo "MISSING: {}"'` returns ZERO `MISSING:` lines.
5. **Sibling-table GRANT pattern documented.** AC3 + Risks now explicitly cite the sibling-WORM-table parity argument: `audit_byok_use` (mig 037) and `audit_github_token_use` (mig 036) never REVOKE service_role SELECT — the design drift in mig 063_workspace_member_actions was the outlier, not the canonical pattern. Reversal is the parity restoration.
6. **Account-delete cascade observability gap noted.** `anonymise_scope_grants` failure is currently logged inline via `log.error` (account-delete.ts:306, 313) but NOT explicitly tagged in Sentry. Observability section's `liveness_signal` revised to acknowledge this is **structured logging, not Sentry**. Production exposure window is broader than the original assessment — operators must grep logs, not Sentry, for Art. 17 failures today. Scope-out (do NOT fold Sentry wiring into this PR per `wg-when-an-audit-identifies-pre-existing` — file as follow-up).

### New Considerations Discovered

- **Migration 064 number is unambiguously available**, but the existence of two parallel `063_*` files (`063_post_workspace_rpc_repair.sql` from #4343 + `063_workspace_member_actions.sql` from #4231) is a workflow oddity. `run-migrations.sh` applies in filename-order — both 063_* files apply, in alpha order. Already verified safe pre-merge of #4343. Migration 064 lands AFTER both.
- **Trigger Shape 2 implicit permission of workspace_id changes** is correct behavior given the CHECK constraint, but the trigger comment at mig 050:38-41 ("with every other column unchanged") is misleading — workspace_id IS another column that the trigger silently permits to change. Either:
  - Document the implicit permission in mig 064's header comment (chosen), OR
  - Tighten Shape 2 to add `AND OLD.workspace_id IS NOT NULL AND NEW.workspace_id IS NULL` explicitly (scope-out — adds blast radius; CHECK constraint already enforces correctness).
- **Class J cascade scope.** Verified at `dsar-export-workspace-tables.integration.test.ts:162-167` — the test imports `deleteAccount` and asserts `result.success === true`. The current failure is `expected true to be false` (test line 167) because Class H makes `success: false`. The cascade is strict — fix Class H → Class J resolves with no independent code change. ALL DSAR/Art-17 tests that exercise deleteAccount() are therefore implicit beneficiaries.
- **Schema-cache reload.** The integration tests use `SCHEMA_CACHE_READY` gate (`workspace-member-actions.integration.test.ts:99, 117`). After mig 064 lands in dev, PostgREST needs a schema-cache reload (`NOTIFY pgrst, 'reload schema'`) before AC10 will pass — `run-migrations.sh` does NOT emit this NOTIFY by default. Phase 2 step now includes the reload command.


# fix(tenant-integration): 4 cascade failure classes post-#4343

## Overview

PR #4343 (merged `4d0888c3`) repaired the `grant_action_class` + `is_workspace_member` GRANT
contract pair and a subset of test-fixture `workspace_id` omissions. Its deepen-pass enumeration
greps were scoped to `*.tenant-isolation.test.ts$` only — four sibling failure classes (now
tracked in #4356) slipped past:

- **Class G — `seedDraftMessage` (worm-test fixtures).** Two helper functions in
  `template-authorizations-worm.test.ts` and `action-sends-worm.test.ts` insert into
  `conversations` / `messages` without `workspace_id` (NOT NULL since mig 059). Same defect class
  as #4343's Class D; the grep filter `*.tenant-isolation.test.ts$` excluded these two
  `*-worm.test.ts` files.

- **Class H — `anonymise_scope_grants` (RPC contract pair).** Mig 059 added
  `scope_grants_workspace_id_check` (CHECK `(founder_id IS NULL AND workspace_id IS NULL) OR
  (founder_id IS NOT NULL AND workspace_id IS NOT NULL)`, mig 059:358-360) but the Art. 17
  anonymise RPC at mig 050:74-92 still does `UPDATE scope_grants SET founder_id = NULL` only.
  The post-UPDATE row has `founder_id IS NULL AND workspace_id IS NOT NULL` → CHECK violates with
  `23514`. This is the same contract-pair pattern as #4343's Class A `grant_action_class`
  (NOT NULL + writer): writer was repaired, sibling writer (anonymise) was not.

- **Class I — `workspace_member_actions` (table GRANT).** Mig 063_workspace_member_actions.sql:80-81
  explicitly REVOKES `SELECT, INSERT, UPDATE, DELETE` on the table from service_role; the
  integration test at `workspace-member-actions.integration.test.ts:101-105` reads the table
  directly via service-role for trigger-emission verification. Test fails 42501. Sibling WORM
  table `audit_byok_use` (mig 037) does NOT REVOKE table privileges from service_role and is
  reachable for the same verification shape — the design intent for `workspace_member_actions`
  diverged without the test contract being updated.

- **Class J — `deleteAccount(harry).success = false` (cascade).** `account-delete.ts:300` invokes
  `anonymise_scope_grants` as step 3.82 of the deletion chain. Class H's 23514 propagates as
  `success: false` from `deleteAccount`. Resolved by fixing Class H; no independent fix.

The fix is one migration (064) repairing Class H + Class I, plus per-fixture inserts for
Class G. Class J is downstream of Class H.

## User-Brand Impact

**If this lands broken, the user experiences:** Article 17 erasure requests fail with a database
constraint violation — when a founder requests account deletion, `deleteAccount` reaches the
`anonymise_scope_grants` step, the CHECK constraint rejects the UPDATE, and the deletion chain
aborts. The founder's PII (scope_grants rows with `founder_id`) remains in the database
indefinitely.

**If this leaks, the user's data is exposed via:** scope_grants rows that should be NULL-anonymised
remain queryable by `founder_id` joined against `users.id`. The grant history (which action
classes, which tiers, when revoked) is per-founder identifiable PII under GDPR Art. 4(1). Until
Class H is fixed, every account deletion attempt LEAVES the PII intact while the rest of the
chain (auth.users delete, public.users anonymise, conversations/messages anonymise) succeeds —
the data subject is partially-deleted with the GDPR-regulated scope_grants slice retained.

**Brand-survival threshold:** `single-user incident`. One founder's failed Art. 17 erasure is a
notifiable supervisory-authority incident under GDPR Art. 33 (within 72h). Discovery is
operator-driven (test failures + Sentry on `anonymise_scope_grants threw`) — but production
account-delete callers do NOT trigger a Sentry route on this path today; the error is logged
inline. Fix-window is the open CI run already red; brand exposure begins the moment a real
founder hits the deleteAccount path.

CPO sign-off required at plan time before `/work` begins. `user-impact-reviewer` will be
invoked at review-time per `plugins/soleur/skills/review/SKILL.md` conditional-agent block.

## Research Reconciliation — Spec vs. Codebase

| Issue body claim | Reality | Plan response |
| --- | --- | --- |
| `anonymise_scope_grants` "re-INSERTs an anonymised row" | Mig 050:86-88 does an UPDATE (not INSERT). Error message "new row for relation" is Postgres's standard CHECK-on-UPDATE wording. | Fix is in UPDATE SET clause (NULL both columns) — no INSERT path to touch. |
| Issue enumerates only `template-authorizations-worm.test.ts` for Class G | `action-sends-worm.test.ts:84-99` has the SAME `seedDraftMessage` pattern (lines 84-105) missing `workspace_id`. | Plan folds in `action-sends-worm.test.ts` (paraphrase-without-verification save). |
| Migration number "064 (or next available)" | Next available is 064 (063 is duplicated: `063_post_workspace_rpc_repair.sql` from #4343 + `063_workspace_member_actions.sql` from #4231 — same number, parallel branches, OK in dev because Supabase tracks by filename hash; both apply). | Plan uses 064 unambiguously. |
| Class I fix as "GRANT SELECT TO service_role" | Sibling WORM tables (`audit_byok_use` mig 037) never REVOKE SELECT from service_role to begin with — so they're SELECTable by default. `workspace_member_actions` mig 063:80-81 EXPLICITLY revokes. The GRANT-back additively reverses the explicit revoke. | Plan uses `GRANT SELECT ON public.workspace_member_actions TO service_role;` — additive, idempotent. No INSERT/UPDATE/DELETE grant (those remain WORM-trigger-gated). |
| Class J independent | `account-delete.ts:300-313` shows step 3.82 invokes `anonymise_scope_grants` and ABORTS the deletion chain on failure. Class J is strictly downstream of Class H. | No independent fix; verify resolution after Class H lands. |

## Files to Edit

- `apps/web-platform/test/server/template-authorizations-worm.test.ts`
  - `seedDraftMessage` helper, line 79: add `workspace_id: userId` to `conversations.insert`.
  - `seedDraftMessage` helper, lines 87-99: add `workspace_id: userId` to `messages.insert`.
  - **Solo-canary convention:** `workspace_id = userId` matches mig 059's backfill predicate
    (`workspace_members WHERE user_id = founder_id AND workspace_id = founder_id AND role =
    'owner'`). Synthetic test users are seeded via the solo-workspace fixture path.

- `apps/web-platform/test/server/action-sends-worm.test.ts`
  - Same helper at lines 84-105 (also named `seedDraftMessage`, identical pattern). Same fix.
  - **Why folded in:** issue body enumerates only `template-authorizations-worm.test.ts`; both
    `*-worm.test.ts` files in `test/server/` share the helper shape. Sweep verified via `rg -lUn
    'from\("(conversations|messages)"\)\s*\n?\s*\.insert' apps/web-platform/test/server/` (15
    matches; 13 are `*.tenant-isolation.test.ts` already fixed by #4343; the 2 unfixed are these
    two worm-test files).

## Files to Create

- `apps/web-platform/supabase/migrations/064_anonymise_scope_grants_workspace_id_and_member_actions_grant.sql`
  - **Part 1 — Class H repair.** `CREATE OR REPLACE FUNCTION public.anonymise_scope_grants(uuid)`
    body changes the UPDATE to NULL both `founder_id` AND `workspace_id`:

    ```sql
    UPDATE public.scope_grants
       SET founder_id = NULL,
           workspace_id = NULL
     WHERE founder_id = p_user_id;
    ```

    No trigger change required: `scope_grants_no_mutate` Shape 2 (mig 050:42-52) only requires
    `founder_id` NULL transition + 6 named columns unchanged (action_class, tier, granted_at,
    created_at, revoked_at, revoked_reason); `workspace_id` is NOT in the unchanged list, so a
    workspace_id change to NULL alongside founder_id NULL still matches Shape 2 → trigger returns
    NEW. The CHECK constraint at mig 059:358-360 (`(founder_id IS NULL AND workspace_id IS NULL)
    OR (founder_id IS NOT NULL AND workspace_id IS NOT NULL)`) is satisfied because BOTH are NULL.

  - **Part 2 — Class I repair.** Single additive grant:

    ```sql
    GRANT SELECT ON public.workspace_member_actions TO service_role;
    ```

    No INSERT/UPDATE/DELETE grant — those remain blocked by the WORM trigger
    (`workspace_member_actions_no_update`, `_no_delete`, mig 063:129+). Read-only SELECT for
    service_role mirrors sibling WORM tables `audit_byok_use` (mig 037 — never revoked) and
    `audit_github_token_use` (mig 036).

  - **Search-path pin:** SECURITY DEFINER function MUST `SET search_path = public, pg_temp` per
    `cq-pg-security-definer-search-path-pin-pg-temp`. Already in mig 050:78.

- `apps/web-platform/supabase/migrations/064_anonymise_scope_grants_workspace_id_and_member_actions_grant.down.sql`
  - Reverts to mig 050's UPDATE body (single-column NULL) AND `REVOKE SELECT ON
    public.workspace_member_actions FROM service_role`.
  - **Down-migration policy:** issue body AC2 explicitly requires "includes down migration".

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Class G fix landed in both worm-test helpers.** `git diff main -- apps/web-platform/test/server/template-authorizations-worm.test.ts apps/web-platform/test/server/action-sends-worm.test.ts | grep -c 'workspace_id: userId'` returns ≥ 4 (two inserts × two files).
- [ ] **AC2 — Class H migration up exists and contains both-NULL UPDATE.** `grep -cE 'SET founder_id = NULL,?\s*workspace_id = NULL|SET workspace_id = NULL,?\s*founder_id = NULL' apps/web-platform/supabase/migrations/064_anonymise_scope_grants_workspace_id_and_member_actions_grant.sql` returns ≥ 1. (Alternation tolerates either column-order.)
- [ ] **AC3 — Class I GRANT additive in 064 up.** `grep -F 'GRANT SELECT ON public.workspace_member_actions TO service_role' apps/web-platform/supabase/migrations/064_anonymise_scope_grants_workspace_id_and_member_actions_grant.sql` returns exactly 1 hit.
- [ ] **AC4 — Down migration exists with both reverts.** `test -f apps/web-platform/supabase/migrations/064_anonymise_scope_grants_workspace_id_and_member_actions_grant.down.sql && grep -F 'REVOKE SELECT ON public.workspace_member_actions FROM service_role' apps/web-platform/supabase/migrations/064_anonymise_scope_grants_workspace_id_and_member_actions_grant.down.sql` returns 1 hit.
- [ ] **AC5 — SECURITY DEFINER search-path pin.** `awk '/CREATE OR REPLACE FUNCTION public\.anonymise_scope_grants/,/AS \$\$/' apps/web-platform/supabase/migrations/064_*.sql | grep -F 'SET search_path = public, pg_temp'` returns 1 hit. (Flag-based awk variant: see Sharp Edges — but here the range terminator `AS $$` cannot match `CREATE OR REPLACE FUNCTION` on the same line, so range form is safe.)
- [ ] **AC6 — TypeScript compiles.** `cd apps/web-platform && bun run tsc --noEmit` exits 0.
- [ ] **AC7 — Migration applies in DEV.** `cd apps/web-platform && doppler run -c dev -- bash scripts/run-migrations.sh` exits 0 and outputs `Applied: 064_anonymise_scope_grants_workspace_id_and_member_actions_grant.sql`. (Corrected from `bun run --dry-run` — no such flag; the runner is `bash`.) Schema-cache reload follows: `bash scripts/postgrest-reload-schema.sh` (NOTIFY pgrst). The reload is required before AC10 integration test runs.
- [ ] **AC8 — Lifecycle test passes against DEV after mig 064.** `bun test apps/web-platform/test/server/scope-grants/lifecycle.test.ts -t "anonymise_scope_grants"` exits 0 with the test at line 268 green. Also covers the original `#4249` symptom that #4343 didn't fix.
- [ ] **AC9 — Both worm tests pass.** `bun test apps/web-platform/test/server/template-authorizations-worm.test.ts apps/web-platform/test/server/action-sends-worm.test.ts` exits 0.
- [ ] **AC10 — workspace_member_actions integration test passes.** `bun test apps/web-platform/test/server/workspace-member-actions.integration.test.ts` exits 0.
- [ ] **AC11 — DSAR export test passes (Class J cascade).** `bun test apps/web-platform/test/server/dsar-export-workspace-tables.integration.test.ts -t "deleteAccount"` exits 0 with the test at line 167 green.
- [ ] **AC12 — `.github/workflows/tenant-integration.yml` workflow green on the fix PR.** `gh pr checks <PR-number> --json bucket,name --jq '.[] | select(.name | test("tenant-integration"))'` returns all entries with `"bucket":"pass"`. (Read from CI JSON, not regex against UI strings.)
- [ ] **AC13 — Sweep verification: every `test/server/*.test.ts` that inserts conversations/messages also names `workspace_id`.** Run:

  ```bash
  rg -lUn 'from\("(conversations|messages)"\)\s*\n?\s*\.insert\(' apps/web-platform/test/server/*.test.ts \
    | xargs -I{} sh -c 'grep -L "workspace_id" {} && echo "MISSING_WORKSPACE_ID: {}"' \
    | grep MISSING_WORKSPACE_ID
  ```

  Expected output: empty (no MISSING lines). If any file surfaces, it MUST be folded in or explicitly scoped out with a follow-up tracking issue (per `wg-when-an-audit-identifies-pre-existing` — do NOT silently widen scope without the issue).
- [ ] **AC14 — Predecessor learning updated (per #4356 AC).** `knowledge-base/project/learnings/2026-05-22-tenant-integration-runtime-failures-post-mig-059.md` contains a `## Follow-up: #4356 expanded scope` section enumerating Classes G/H/I/J + the grep-scope failure mode (`*.tenant-isolation.test.ts$` filter was too narrow).
- [ ] **AC15 — No `Closes #4249` in PR body; use `Closes #4356, Ref #4249`.** #4249 is the original symptom and #4343 already linked it as the parent trail; #4356 is the issue this PR closes. Verify via `gh pr view <PR-number> --json body --jq '.body' | grep -c '^Closes #4356'` returns 1 and `grep -c '^Closes #4249'` returns 0.

### Post-merge (operator)

- [ ] **AC16 — Migration applies in prd.** `web-platform-release.yml#migrate` job exits 0 against prd Supabase. (Mechanism per #4337 + existing release wiring; NOT a fresh workflow.)
- [ ] **AC17 — Verify in-place: SELECT founder_id, workspace_id FROM scope_grants WHERE founder_id IS NULL LIMIT 5 returns workspace_id IS NULL for every row.** Per `hr-no-dashboard-eyeball-pull-data-yourself`, automate via `mcp__plugin_supabase_supabase__execute_sql` against prd. Expected: 0 rows OR all rows have `workspace_id IS NULL`. (Pre-fix state had `workspace_id NOT NULL`; if any anonymised rows exist with stale `workspace_id`, document them as Art. 30 register addendum — but mig 059 backfill should have written workspace_id only for non-anonymised rows where founder_id was NOT NULL, so this should be 0 rows in prd. Verify, don't assume.)

## Hypotheses (not network-outage; gate skipped)

The network-outage hypothesis checklist does NOT apply — this is a DB-contract repair with no
SSH/firewall/DNS surfaces touched.

## Open Code-Review Overlap

`gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json` and `jq` against the planned file paths:

- `apps/web-platform/supabase/migrations/064_*.sql` — new file; no overlap by definition.
- `apps/web-platform/test/server/template-authorizations-worm.test.ts` — checked; no open code-review issue.
- `apps/web-platform/test/server/action-sends-worm.test.ts` — checked; no open code-review issue.

**Disposition:** None — no overlap.

## Domain Review

**Domains relevant:** Engineering (data integrity, CI), Compliance/Legal (GDPR Art. 17 erasure
path), Product (single-user-incident threshold). Marketing / Sales / Finance / Ops / Community
not relevant.

### Engineering

**Status:** reviewed (carry-forward — #4343 predecessor plan covers the contract-pair pattern).
**Assessment:** Same contract-pair gap class as #4343 Class A. Mitigation pattern is identical
(CREATE OR REPLACE the writer to match the schema constraint). No new architectural surfaces.

### Compliance/Legal (GDPR)

**Status:** reviewed.
**Assessment:** Art. 17 erasure path currently fails on a CHECK constraint, producing a
partially-deleted data subject with retained PII in `scope_grants`. Notifiable under Art. 33 if
discovered in prd. Fix restores Art. 17 contract. PA register: scope_grants is PA-13 (or
adjacent — verify exact PA-number against `knowledge-base/legal/article-30-register.md` at
/work-time, but do not file a new PA; the activity is unchanged, only the implementation is
repaired).

### Product/UX Gate

**Tier:** none (no UI change, no new user-facing surface). The deleteAccount flow's
user-observable shape (`success: true/false`) does not change — only the failure rate goes from
"reliably false on Art. 17 path" to "reliably true". No Product/UX subsection needed beyond
this domain finding.

## Infrastructure (IaC)

Not applicable — pure SQL migration + test fixture changes. No new servers, secrets, vendor
accounts, DNS records, TLS certs, or firewall rules. Migration deploys via existing
`web-platform-release.yml#migrate` job (same path #4343 used).

## Observability

This change touches `apps/web-platform/supabase/migrations/` and `apps/web-platform/test/`.
Migration apply path has observability via `web-platform-release.yml#migrate` job exit code +
GitHub Actions logs (retention: 90 days). The RPC `anonymise_scope_grants` is called from
`account-delete.ts:300-313` which has Sentry tagging at lines 306, 313 on failure.

```yaml
liveness_signal:
  what: anonymise_scope_grants RPC invocation succeeds (returns int row count)
  cadence: per account-delete request (rare; founder-initiated Art. 17)
  alert_target: structured logs (BetterStack / pino) — NOT Sentry (account-delete.ts:306, 313 use log.error, not Sentry.captureException)
  configured_in: apps/web-platform/server/account-delete.ts:300-313
error_reporting:
  destination: structured logs (log.error). Sentry capture is a pre-existing gap — scope-out, follow-up issue per Risks section.
  fail_loud: yes — account-delete aborts deletion chain on RPC failure; user sees "Account deletion failed" error
failure_modes:
  - mode: CHECK constraint violation 23514 (Class H regression)
    detection: log search for "anonymise_scope_grants failed" with err code 23514
    alert_route: BetterStack log query (existing); follow-up: add Sentry.captureException
  - mode: WORM trigger reject P0001 (Shape mismatch)
    detection: log search for "anonymise_scope_grants threw" with err code P0001
    alert_route: BetterStack log query (existing); follow-up: add Sentry.captureException
  - mode: workspace_member_actions read 42501 (Class I regression)
    detection: CI .github/workflows/tenant-integration.yml job red on PR
    alert_route: GitHub PR check (existing); no prd consumer reads the table directly today
logs:
  where: account-delete.ts log.error + Supabase Postgres logs (CHECK violations)
  retention: BetterStack 30 days (default tier) / Supabase 7 days (free tier)
discoverability_test:
  command: cd apps/web-platform && bun test test/server/scope-grants/lifecycle.test.ts -t "anonymise_scope_grants"
  expected_output: 1 passing, 0 failing — exit code 0
```

No new observability scaffold required — existing Sentry tagging on account-delete.ts covers the
Class H regression detection surface. Class I regression detection is CI-only (tenant-integration
workflow) until/unless a prd consumer exists for direct table SELECT (none today; reads route
through `list_workspace_member_actions` RPC).

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)

1. `pwd` returns the worktree path (already verified).
2. `git branch --show-current` returns `feat-one-shot-4356-tenant-integration-cascade`.
3. `ls apps/web-platform/supabase/migrations/ | grep '^064'` returns nothing (064 is available).
4. `gh pr list --state merged --base main --search 'is:pr base:main 4343' --json number,mergedAt` confirms #4343 is merged (base for the cascade).
5. Canonical migration runner is `bash apps/web-platform/scripts/run-migrations.sh` invoked via `doppler run -c dev -- bash scripts/run-migrations.sh` (verified during deepen-pass; `apps/web-platform/package.json` has no migration-related script entries, so the bash form is canonical). Schema-cache reload via `bash apps/web-platform/scripts/postgrest-reload-schema.sh` (also bash).
6. `rg -lUn 'from\("(conversations|messages)"\)\s*\n?\s*\.insert' apps/web-platform/test/server/*.test.ts` returns exactly 15 files; spot-check that 13 already have `workspace_id` (post-#4343) and only the 2 worm-test files are missing it. If a third missing-workspace-id file surfaces, halt and fold it into Files to Edit.

### Phase 1 — Migration 064 up + down (RED)

1. Write `064_anonymise_scope_grants_workspace_id_and_member_actions_grant.sql` with header comment citing #4356 + the two failure classes.
2. `CREATE OR REPLACE FUNCTION public.anonymise_scope_grants(uuid)` body lifts mig 050:74-92 verbatim, mutating only the SET clause (NULL both columns). `REVOKE` + `GRANT EXECUTE` lines are unchanged (idempotent).
3. `GRANT SELECT ON public.workspace_member_actions TO service_role;` (single line, additive).
4. Write `.down.sql` with the corresponding reverts.
5. RED check: run lifecycle test against current DEV state (pre-apply). Expect failure at line 268.

### Phase 2 — Apply migration in DEV (GREEN partial)

1. `cd apps/web-platform && doppler run -c dev -- bash scripts/run-migrations.sh` — applies 064.
2. `bash apps/web-platform/scripts/postgrest-reload-schema.sh` — reload PostgREST schema cache via `NOTIFY pgrst, 'reload schema'`. **Required** because mig 064 GRANTs a new privilege on `workspace_member_actions` AND replaces the function body — both are PostgREST-cached.
3. Verify function body in dev:
   ```
   doppler run -c dev -- psql "$DATABASE_URL" -c "\\sf public.anonymise_scope_grants"
   ```
   Expect output to contain `SET founder_id = NULL,` AND `workspace_id = NULL`.
4. Verify table privileges:
   ```
   doppler run -c dev -- psql "$DATABASE_URL" -c "\\dp public.workspace_member_actions"
   ```
   Expect `r/postgres,r/service_role` (SELECT for service_role present); INSERT/UPDATE/DELETE remain absent.

### Phase 3 — Worm-test fixture fixes (GREEN remainder)

1. Edit `template-authorizations-worm.test.ts:79` add `workspace_id: userId,`. Edit lines 87-99 (messages.insert) add `workspace_id: userId,`.
2. Edit `action-sends-worm.test.ts:85` and `:94-105` same way.
3. Run AC8 + AC9 + AC10 + AC11 locally; expect green.

### Phase 4 — Learning file update (AC14)

1. Append `## Follow-up: #4356 expanded scope` section to
   `knowledge-base/project/learnings/2026-05-22-tenant-integration-runtime-failures-post-mig-059.md`
   documenting:
   - The 4 sibling failure classes the deepen-pass grep missed.
   - The grep-scope fix: future sweeps must drop the `*.tenant-isolation.test.ts$` filter and
     scan `*.test.ts` under `apps/web-platform/test/server/` — `*-worm.test.ts` and
     `*.integration.test.ts` are common siblings.
   - The contract-pair generalization: `anonymise_*` sibling RPCs for any table that gains a
     NOT NULL or CHECK constraint MUST be enumerated alongside the primary writer.

### Phase 5 — CI + PR submission

1. `git add` planned files only (NEVER `git add -A`).
2. Commit per `commit-commands:commit` style; reference `Closes #4356, Ref #4249`.
3. Push, open PR, wait for `tenant-integration.yml` to go green (AC12).
4. CPO sign-off check: confirm CPO has reviewed the brand-survival threshold framing before
   marking PR ready (per `hr-weigh-every-decision-against-target-user-impact`).

### Phase 6 — Review + merge

1. Run `pr-review-toolkit:review-pr` to spawn user-impact-reviewer (auto-invoked due to
   single-user-incident threshold).
2. Address review findings inline.
3. Mark ready → squash-merge via `gh pr merge --squash --auto`.

### Phase 7 — Post-merge verification (operator)

1. Watch `web-platform-release.yml#migrate` job green on main.
2. Run AC17 prd verification SQL via Supabase MCP.
3. Close #4356 via `gh issue close 4356 --comment "Resolved by PR #<N>"`.

## Risks

- **Migration 064 idempotency on dev re-runs.** `CREATE OR REPLACE FUNCTION` is idempotent; the
  `GRANT SELECT` is also idempotent (re-grant is a no-op). Down migration's `REVOKE SELECT` is
  idempotent too. Risk: low.
- **Trigger Shape 2 silent break.** Theoretical concern: does adding `workspace_id = NULL` to
  the UPDATE break Shape 2's structural check? Verified above: Shape 2 only checks `founder_id`
  transition + 6 named columns (action_class, tier, granted_at, created_at, revoked_at,
  revoked_reason). `workspace_id` is NOT in that list, so a workspace_id change is silently
  permitted under Shape 2. The CHECK constraint at row level enforces both-NULL or both-NOT-NULL.
  Risk: low — but verify experimentally in Phase 2 with `\sf public.scope_grants_no_mutate`
  before relying on it.
- **Sibling table `workspace_member_actions` design intent (REVISITED post-deepen).** Mig 063:80-81
  deliberately REVOKEs service_role SELECT. The fix reverses this. The argument for reversal: the
  integration test expects direct SELECT for trigger-emission verification, AND the sibling WORM
  table `audit_byok_use` (mig 037) does not revoke (verified — no REVOKE statements against the
  table in mig 037). The argument against: the design comment at mig 063:72-75 says "all reads
  route through list_workspace_member_actions SECURITY DEFINER RPC". **Deepen verdict:** the design
  comment is aspirational, but the SAME PR's integration test directly reads the table — there is
  an internal contradiction between the migration's REVOKE and the test's expectation. The
  read-through-RPC pattern is also incompatible with simple trigger-emission verification (the RPC
  paginates and filters). Resolution: GRANT SELECT back (additive, INSERT/UPDATE/DELETE remain
  WORM-trigger-gated), and ALSO update mig 064's header comment to capture the design-intent
  reconciliation (the table is now "read-routed through RPC for production paths, directly SELECT-able
  by service_role for verification and admin tooling" — same shape as `audit_byok_use`). Alternative
  rejected: rewriting `workspace-member-actions.integration.test.ts` to call the RPC would mask the
  trigger-emission test contract behind RPC pagination semantics, weakening the WORM verification.
- **Sentry tagging gap on `anonymise_scope_grants` failures.** `account-delete.ts:306, 313` log via
  `log.error` (structured-log path, NOT Sentry). Production exposure window is broader than originally
  framed in the Brand-survival section — operators must grep structured logs, not Sentry, to detect
  Art. 17 failures today. Scope-out per `wg-when-an-audit-identifies-pre-existing`: file a follow-up
  issue to add Sentry capture at both call sites. The Class H DB-contract repair fully resolves the
  user-facing symptom; the observability gap is independent.
- **Shape 2 trigger implicit-permission documentation.** Mig 050's trigger Shape 2 silently permits
  `workspace_id` to change (column not enumerated in the unchanged-cols list, so the `AND NOT (X IS
  DISTINCT FROM Y)` predicate doesn't gate it). The CHECK constraint enforces the both-NULL invariant
  at row level, so the trigger's implicit permission is safe. **Mitigation:** mig 064's header comment
  cites this explicitly so a future maintainer reading mig 050 alone doesn't misread Shape 2 as
  blocking the workspace_id NULL transition.
- **`account-delete.ts` PII residue from prior failed deletions.** If any prd founder hit the
  Class H bug before this fix, their scope_grants rows remain non-anonymised. AC17 quantifies
  the exposure; remediation may require a one-shot backfill (rare path; document in PR body
  but do not bake into 064 — keep scope tight).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. Section is populated above.
- Migration 064 number collision check: 063 is duplicated (`063_post_workspace_rpc_repair.sql`
  + `063_workspace_member_actions.sql`). Supabase's `run-migrations.sh` keys by filename hash;
  parallel branches each filed under 063 is a known quirk but acceptable in dev. Migration 064
  must be the ONLY 064-prefixed file at merge time — re-verify with `ls migrations/ | grep
  '^064'` before push.
- The `seedDraftMessage` fix uses `workspace_id: userId` (solo-canary convention). This is correct
  for the synthetic test users seeded via the solo-workspace fixture, but it WOULD be incorrect
  for any multi-member workspace fixture. Verify the helper is only called with solo-canary
  fixtures via `grep -B5 'seedDraftMessage(' apps/web-platform/test/server/*-worm.test.ts` at
  Phase 0.6.

## References

- Issue #4356 (this PR resolves)
- Issue #4249 (original lifecycle.test.ts WORM failure, partially fixed in #4343, fully fixed
  here via Class H repair)
- Issue #4342 (predecessor — #4343 closed it)
- PR #4343 (predecessor — `4d0888c3`)
- PR #4225 (mig 059 — added CHECK constraint that Class H now respects)
- PR #4231 (mig 063_workspace_member_actions — added the table that Class I grants)
- Learning `knowledge-base/project/learnings/2026-05-22-tenant-integration-runtime-failures-post-mig-059.md` (predecessor; will be updated per AC14)
- Mig 048 (original `anonymise_scope_grants`)
- Mig 050 (PR-G `anonymise_scope_grants` body — structural-shape WORM bypass)
- Mig 059 (workspace-keyed RLS sweep — added CHECK constraint at :358-360)
- Mig 063_workspace_member_actions (table being repaired in Class I)
