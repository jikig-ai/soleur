---
title: Scoped runtime authz/RLS-fuzz harness (T3MP3ST technique harvest)
type: feat
date: 2026-07-09
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 6256
branch: feat-t3mp3st-security-eval
pr: 6255
spec: knowledge-base/project/specs/feat-t3mp3st-security-eval/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-07-09-t3mp3st-security-eval-brainstorm.md
---

# ✨ feat: Scoped runtime authz/RLS-fuzz harness

## Overview

Build a small, **deterministic** harness that drives one tenant's authenticated identity
against another tenant's rows across every workspace-isolated RLS table, and asserts every
cross-tenant access is **denied at the RLS layer** — run against a **local disposable
Postgres (Supabase-CLI local stack) with the production migrations applied**. It borrows
T3MP3ST's authz/IDOR taxonomy as *concepts only* (no AGPL code) and fills the one real gap
the static stack (`security-sentinel`, `semgrep-sast`, `infra-security`) cannot cover:
**runtime exploitability of tenant isolation**. It doubles as the runtime proof of the
in-flight jti-deny work, which today `verify/068` only checks *statically*.

**Faithful mechanism (no JWT signing).** Supabase RLS is enforced at the DB by the
PERMISSIVE `is_workspace_member(workspace_id, auth.uid())` policies (mig `053:115`) — keyed
on `auth.uid()` = the JWT `sub` — plus the overlaid RESTRICTIVE `<table>_jti_not_denied`
policies (mig `068`). The harness reproduces a Supabase authenticated request **at the DB
layer** in a rolled-back transaction:

```sql
BEGIN;
  SET LOCAL ROLE authenticated;                          -- non-owner, no BYPASSRLS (Phase 0 asserts)
  SELECT set_config('request.jwt.claims',
    '{"sub":"<userB>","role":"authenticated","jti":"<jtiB>",
      "app_metadata":{"current_organization_id":"<orgB>"}}', true);  -- shape matches prod hook (mig 060)
  -- attacker dimension is sub=userB (NOT a member of wsA); RLS keys on auth.uid()
  SELECT count(*) FROM <table> <isolation_predicate for wsA>;   -- expect 0 (row exists — seeded)
  INSERT INTO <table> (...) VALUES (..., <wsA-owned>);          -- expect SQLSTATE 42501
ROLLBACK;
```

No signed JWT, no PostgREST, no network. This is strictly more adversarial than production
(it assumes a forged claim and leans entirely on the RLS backstop) and fully deterministic.

## Research Reconciliation — Spec vs. Codebase (post-review, verified against migration source)

| Claim | Reality (verified) | Plan response |
|---|---|---|
| Target set = "26 `*_jti_not_denied` tables incl. beta-CRM" | **False.** mig `068:227-249` `tenant_tables[]` has **21**; beta-CRM tables came via mig 126; there are **44** RLS-enabled tables and only 26 carry jti-deny. The isolation invariant is the PERMISSIVE `is_workspace_member` set, a different, wider set. | **Enumerate from the live `pg_policies` catalog** post-migration, anchored on the isolation set (`TO authenticated` PERMISSIVE policies referencing `is_workspace_member`/a tenancy predicate); jti-deny is an overlaid *dimension*, not the enumerator. |
| AC1: "grep mig 068 for table set" | Non-functional — mig 068 creates policies via `format('%I_jti_not_denied', t)` in a `DO` loop; the literals never appear in source (`git grep` returns 5 real names from migs 076/077/126 + a garbage `I_jti_not_denied`). | Catalog-driven derivation only; **no source grep** for the set. |
| FR2: "mint a valid authenticated JWT" | RLS is DB-layer; faithful reproduction is `set_config('request.jwt.claims', …)`. No JWT-minting exists in the test suite. | Claim-injection; signed-JWT descoped. |
| "swap workspace_id/org_id in the claim" is an attack | **Vacuous.** No RLS policy reads `current_organization_id`/`current_workspace_id`; RLS keys purely on `auth.uid()` = `sub` (mig 060 hook is the only reader). | Attacker dimension = **`sub`** (userB not a member of wsA). Claim-swap kept only as an *inert negative control* that must be shown to change nothing. |
| Uniform `WHERE workspace_id` template | Several target tables are not workspace-keyed: `users`→`auth.uid()=id`; `user_session_state`→`user_id`; `push_subscriptions`/`scope_grants`/`audit_*`/`action_sends`/`dsar_export_jobs`→user-keyed or parent-join; `message_attachments` object isolation lives in **`storage.objects`**. | Derive each table's **isolation predicate from its policy `qual`**, not a hardcoded column. |
| "local disposable Postgres" via docker + auth shim | A hand-written `auth` shim is a *second implementation of the exact surface under test* — the false-green vector (ADR-079 precedent). Supabase-CLI local provides the **real** `auth` schema + roles, all-local. | **Supabase-CLI-local only.** No shim. |
| verify/068 proves isolation | `verify/068_*.sql` is static; run by `run-verify.sh` against **prod** (`doppler -c prd`). | Harness stays off `verify/`; a *separate* read-only prod-parity catalog diff (below) is the only prod touch, and it is catalog introspection, not attack traffic. |

## User-Brand Impact

**If this lands broken, the user experiences:** a green harness that passes while a real
cross-tenant read/write path is open — one workspace's data reachable from another — shipped
undetected. A *false-green* isolation test is worse than none.

**If this leaks, the user's data is exposed via:** an unfaithful local schema (or a
vacuous/green-by-emptiness matrix) that certifies isolation production does not enforce.

**Brand-survival threshold:** single-user incident. `requires_cpo_signoff: true` — CPO
reviewed the approach at brainstorm Phase 0.5 (carry-forward). `user-impact-reviewer` runs at
PR review.

## Implementation Phases

### Phase 0 — Stand up local stack + faithfulness spike (riskiest; do first)
- `supabase start` (local Docker Supabase — real `auth` schema, GoTrue, roles) pinned to the **prod-matching** postgres/CLI image version; apply all migrations (`supabase db reset` / `run-migrations.sh` against the local DSN).
- Seed 2 synthetic workspaces (A, B), each 1 owner + `workspace_member` row (synthetic, `*@example.test`, fixed UUIDs).
- **Spike gate (must all hold before Phase 1):** inside a `SET LOCAL ROLE authenticated` txn, assert `current_user='authenticated'`, `NOT rolsuper`, `NOT rolbypassrls`, and that the `authenticated` role does **not own** the target tables (owner bypasses RLS unless `FORCE ROW LEVEL SECURITY`); confirm `auth.uid()`, `is_workspace_member`, and one `*_jti_not_denied` policy all *evaluate* (not error). Any failure ⇒ the local stack is unfaithful; stop.

### Phase 1 — Catalog-driven enumeration + per-table seeding
- Enumerate the target set from `pg_policies` on the migrated DB: tables with a `TO authenticated` PERMISSIVE policy referencing `is_workspace_member`/a tenancy predicate (the **isolation set**), union the `%_jti_not_denied` RESTRICTIVE set (the **jti dimension**). Extract each table's isolation-key predicate from the policy `qual`.
- For **each** target table: as `service_role`, seed exactly one tenant-A-owned row, and assert `service_role` reads `count=1` (proves the row exists and the attack query shape is valid) — the precondition that makes a later tenant-B `count=0` mean *denied*, not *empty*.

### Phase 2 — Core fuzz matrix (borrowed taxonomy, SQLSTATE-aware)
For each (table, op ∈ {SELECT, INSERT, UPDATE, DELETE}) under tenant-B claims (`sub=userB`):
- **SELECT:** assert tenant-B sees `count=0` of A's seeded row.
- **INSERT/UPDATE/DELETE (write-side USING vs WITH CHECK — the high-value class):** attempt to write/modify A's row; assert **SQLSTATE `42501`** (`new row violates row-level security policy`). **Any other SQLSTATE (23502/23503/23514/42703/…) = test ERROR (yellow), NOT a pass** — a constraint failure is not an RLS denial. After each write attempt, `service_role` re-reads and asserts A's row is unchanged/present.
- **jti dimension (two-sided):** on a seeded row, a **denied** `jti` ⇒ blocked; an **allowed** `jti` ⇒ permitted — same row, so a stuck-true/stuck-false extractor is falsified (runtime proof of verify/068).
- **Positive controls (must PASS — falsify a vacuously-green run):** tenant-A self-reads its own row; `service_role` bypasses.
- **Inert negative control:** the claim workspace/org swap changes zero RLS decisions — assert it is inert (documents that `sub` is the only lever).
- **Harness self-test (mutation control):** in a throwaway rolled-back txn, `DISABLE ROW LEVEL SECURITY` on one table and assert the harness reports **RED** — proves the harness can detect a real break.

### Phase 2b — SECURITY DEFINER RPC bypass + storage.objects (full-coverage, operator-selected)
- **SECURITY DEFINER RPC dimension.** Enumerate from the catalog every function that is `SECURITY DEFINER` AND `GRANT EXECUTE … TO authenticated` (e.g. `append_kb_sync_row` @053, `set_repo_status…` @113, the `workspace_repo_ownership` fns @079). For each, classify definer-vs-invoker (invoker fns like `list_conversations_enriched` @125 are RLS-safe — exclude). Drive each definer fn with **tenant-B claims + tenant-A parameters** (`p_workspace_id = wsA`, `p_repo_url` of A, etc.) and assert denial/empty — a definer fn that trusts a caller-supplied tenancy param instead of re-deriving `is_workspace_member(param, auth.uid())` is a cross-tenant bypass invisible to base-table RLS. Fail if any definer fn granted to `authenticated` has no case (catalog-driven, self-tracking).
- **`storage.objects` attachment isolation.** `message_attachments` object isolation lives in `storage.objects` RLS (folder-prefix `(storage.foldername(name))[1] = auth.uid()::text`, mig `068_attachments_workspace_shared:117`). Seed a tenant-A object; assert tenant-B cannot SELECT/UPDATE/DELETE it via `storage.objects`, SQLSTATE-aware as in Phase 2.

### Phase 3 — Prod-parity catalog diff + deterministic report
- **Prod-vs-local security-catalog parity diff** (highest-leverage faithfulness safeguard): read-only introspection — `pg_policies` qual/with_check per table, `relrowsecurity`/`relforcerowsecurity`, table grants to `anon`/`authenticated`, role attributes (`rolsuper`/`rolbypassrls`), and `pg_get_functiondef()` of `auth.uid`/`auth.jwt`/`is_workspace_member`/the jti-deny helpers — captured from prod via the **existing `run-verify.sh` `doppler -c prd` psql path** (ordinary catalog reads, NOT attack traffic) and diffed against the local DB. **Any diff = red.** Converts "we hope local is faithful" into a checked invariant.
- Emit a per-`(table, op, verdict)` report; **one** leaked access or positive-control failure = hard FAIL naming the offending table/op; exit non-zero.

### Phase 4 — CI wiring (full-coverage, operator-selected)
- Add `.github/workflows/rls-authz-fuzz.yml`: on PRs touching `apps/web-platform/supabase/migrations/**` (and manual dispatch), spin up the Supabase-CLI local stack in the runner, run `test:rls-fuzz` + the parity diff, fail the check on any leak/parity drift. Local-only DSN (allowlist enforced); zero real credentials; the parity diff's prod catalog read uses the CI Doppler `prd`-scoped read (same path as `run-verify.sh`). This is the automated merge gate (restores `liveness_signal`).

## Files to Create
- `apps/web-platform/test/rls-authz-fuzz.integration.test.ts` — the vitest harness (`pg` against local DSN; `SET LOCAL ROLE` + `set_config` per case; SQLSTATE-aware; catalog-driven set incl. the RPC + storage.objects dimensions; gated behind `RLS_FUZZ_LOCAL=1` + a **local-allowlisted** DSN).
- `apps/web-platform/test/rls-fuzz-global-setup.ts` — vitest `globalSetup`: `supabase start`/`db reset` + apply migrations + seed synthetic tenants (folds the former standalone setup script).
- `apps/web-platform/scripts/rls-parity-check.ts` — the prod-vs-local catalog parity diff (read-only prod introspection via the run-verify doppler path).
- `.github/workflows/rls-authz-fuzz.yml` — CI merge gate on migration-touching PRs (Supabase-CLI local stack in the runner).
- `knowledge-base/engineering/architecture/decisions/ADR-103-runtime-authz-rls-fuzz-harness.md`.

## Files to Edit
- `apps/web-platform/package.json` — add `test:rls-fuzz` (vitest run on the harness, local DSN only) and `rls:parity` scripts. Runner is **vitest** (`./node_modules/.bin/vitest run`), typecheck `tsc --noEmit` (NOT `npm run -w`).
- (No edits to `run-migrations.sh`, `run-verify.sh`, `verify/068_*.sql` — consumed read-only; clear of overlap #3364.)

## Acceptance Criteria

### Pre-merge (PR — all local/CI-verifiable, no operator steps)
- [ ] AC1: Target set derived from the live `pg_policies` catalog (isolation set ∪ jti-deny set); harness FAILs if any `TO authenticated` workspace-isolated table has no attack case. No source-grep for the set.
- [ ] AC2: Per table, `service_role` sees `count=1` of the seeded A-row (precondition), THEN tenant-B (`sub=userB`) sees `count=0`; write ops raise SQLSTATE `42501`; any non-42501 SQLSTATE fails the case as a test ERROR.
- [ ] AC3: Positive controls PASS — tenant-A self-read `count=1`; `service_role` bypass. Guards against vacuous green.
- [ ] AC4: jti two-sided — denied jti blocked AND allowed jti permitted on the same seeded row.
- [ ] AC5: Mutation self-test — `DISABLE ROW LEVEL SECURITY` on one table (rolled back) makes the harness report RED.
- [ ] AC6: Prod-parity catalog diff passes (local policies/grants/role-attrs/auth-fn-defs match prod); any diff fails the run.
- [ ] AC7: DSN guard is a **fail-closed allowlist** — host ∈ {`localhost`,`127.0.0.1`,`::1`, known CI service host}; parse-host membership check (no DNS lookup); unit-tested; refuses any other host.
- [ ] AC8: **RPC bypass** — every `SECURITY DEFINER` fn `GRANT EXECUTE TO authenticated` has a case driving tenant-B claims + tenant-A params, asserting denial/empty; catalog-derived, fails on any uncovered definer fn (invoker fns excluded with rationale).
- [ ] AC9: **storage.objects** — a tenant-A object is not SELECT/UPDATE/DELETE-able by tenant-B via `storage.objects` (SQLSTATE-aware).
- [ ] AC10: **CI gate** — `.github/workflows/rls-authz-fuzz.yml` runs the harness + parity diff on migration-touching PRs; red on any leak/drift; local-only DSN in CI.
- [ ] AC11: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes; `./node_modules/.bin/vitest run test/rls-authz-fuzz.integration.test.ts` green against the local stack.
- [ ] AC12: `ADR-103-*.md` exists with the decision + `## Alternatives Considered` (incl. rejected shim + rejected grep-mig-068 derivation); no C4 view change (enumeration below). No deferred blind spots (full coverage).
- [ ] AC13: Zero real credentials in the harness env (synthetic only); no AGPL source copied.

## Architecture Decision (ADR/C4)

### ADR
- **Create ADR-103** (in-scope `/work` task, not deferred): "Runtime authz/RLS-fuzz harness on a Supabase-CLI-local disposable stack." Decision: catalog-driven, SQLSTATE-aware claim-injection at the DB layer against a provider-detached local Supabase stack; prod-parity catalog diff as the faithfulness gate. `## Alternatives Considered`: (a) hosted Supabase dev integration test — rejected (brainstorm guardrail); (b) docker + hand-written `auth` shim — rejected (ADR-079 anti-pattern: reimplements the surface under test); (c) signed-JWT full-stack via local PostgREST — rejected (nondeterministic, tests PostgREST not the RLS invariant); (d) grep-mig-068 table derivation — rejected (dynamic `format()` loop; non-functional). Full coverage (RPC + storage.objects + CI) selected — no deferred blind spots to record. Ordinal ADR-103 provisional; `/ship` re-checks origin/main.

### C4 views
- **No C4 impact** — enumerated against `model.c4`/`views.c4`/`spec.c4`: adds no external human actor, no external system/vendor (all-local disposable Postgres), no product-boundary data store (ephemeral test DB; modeled `supabase`/`crmStore` unchanged), no production access-relationship. Like the existing test suite, it is outside the system boundary. Actors checked & unchanged: founder, emailSender, betaContact, contributor, connectedRepoPlugin. (Verified against live model by architecture-strategist.)

### Sequencing
- ADR authored in the same PR (status: accepted). No soak gate.

## Observability

```yaml
liveness_signal:    { what: "rls-authz-fuzz CI check result", cadence: "on PRs touching apps/web-platform/supabase/migrations/** + manual dispatch", alert_target: "check RED (blocks merge)", configured_in: ".github/workflows/rls-authz-fuzz.yml + package.json test:rls-fuzz" }
error_reporting:    { destination: "vitest report + non-zero exit", fail_loud: true }
failure_modes:
  - { mode: "cross-tenant leak", detection: "report lists a non-42501/non-DENIED (table,op); exit non-zero", alert_route: "run RED" }
  - { mode: "vacuous green (unfaithful stack / unseeded table)", detection: "positive control or service_role count=1 precondition fails; parity diff fails", alert_route: "run RED" }
  - { mode: "harness pointed at non-local DSN", detection: "AC7 allowlist guard hard-errors pre-query", alert_route: "run aborts" }
  - { mode: "harness cannot detect a real break", detection: "mutation self-test (AC5) does not go RED", alert_route: "run RED" }
logs:               { where: "vitest per-case report (local) / CI job log (once wired)", retention: "GitHub default" }
discoverability_test: { command: "cd apps/web-platform && RLS_FUZZ_LOCAL=1 ./node_modules/.bin/vitest run test/rls-authz-fuzz.integration.test.ts", expected_output: "all cases PASS; 0 leaks; parity diff clean (NO ssh)" }
```

## Scope (v1 — full coverage, operator-selected 2026-07-09)
The review surfaced three coverage expansions beyond base-table isolation. The operator chose
to include **all three** in v1 (no deferred blind spots):
1. **SECURITY DEFINER RPC bypass** — Phase 2b, AC8.
2. **`storage.objects` attachment isolation** — Phase 2b, AC9.
3. **GitHub Actions CI merge gate** — Phase 4, AC10.

## Domain Review
**Domains relevant:** Engineering, Product, Legal (carry-forward from brainstorm `## Domain Assessments`).
### Engineering (CTO) — reviewed
GO-NARROW; borrow taxonomy not code; local disposable stack the only safe + only available target. Riskiest = local `auth` faithfulness → addressed by CLI-only + Phase 0 spike + prod-parity diff.
### Product (CPO) — reviewed
Runtime proof of the isolation work already prioritized; keep minimal/deterministic. `requires_cpo_signoff` satisfied by brainstorm carry-forward.
### Legal (CLO) — reviewed
Internal-only, AGPL-clean (concepts not code); local provider-detached target avoids provider-ToS exposure; the parity diff is read-only catalog introspection via the existing prod-verify path (not attack traffic), consistent with the guardrail.
### Product/UX Gate
**Tier:** none — no UI surface (no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx` in Files to Create).

## GDPR / Compliance Gate
**Considered (single-user-incident trigger).** N/A — processes only synthesized fixtures (`cq-test-fixtures-synthesized-only`) on a local disposable Postgres; reads RLS DDL + synthetic rows; zero real personal data; the parity diff reads prod *catalog metadata* (policy text, grants — not row data). No Article 30 entry.

## Open Code-Review Overlap
Three open `code-review` issues loosely match; all **acknowledge** (different subsystems): **#3364** (run-migrations role guard — consumed read-only), **#4254** (hosted tenant-iso fixture drift — our harness controls its own local seed), **#3272** (byok authTagLength — unrelated).

## Risks & Mitigations
- **Unfaithful local schema → false green (single-user-incident).** Mitigation: Supabase-CLI-local (real `auth`); Phase 0 spike (non-owner/non-super/FORCE-RLS + eval checks); **prod-parity catalog diff** (AC6) as the checked invariant; image-version pin.
- **Vacuous green (empty table / wrong role).** Mitigation: per-table `service_role` count=1 precondition (AC2), positive controls (AC3), mutation self-test (AC5).
- **Constraint error mis-scored as denial.** Mitigation: SQLSTATE 42501 discrimination (AC2).
- **Harness pointed at hosted Supabase.** Mitigation: fail-closed allowlist (AC7).
- **Coverage drift / new tenant table.** Mitigation: catalog-driven set (AC1) fails on any uncovered isolated table; catalog-driven RPC set (AC8) fails on any uncovered definer fn.
- **RPC bypass (definer trusts caller param).** Mitigation: Phase 2b RPC dimension (AC8) drives every authenticated-granted definer fn with tenant-B claims + tenant-A params.
- **No deferred blind spots** — full coverage selected; RPC + storage.objects + CI all in v1.

## Test Scenarios
1. Cross-tenant SELECT denied (count=0 with seeded A-row) for every isolated table (AC1/AC2).
2. Write-side (INSERT/UPDATE/DELETE) raises 42501; non-42501 fails as error; A-row unchanged after (AC2).
3. Positive controls pass; claim-swap inert (AC3).
4. jti two-sided (AC4). 5. Mutation self-test goes RED (AC5). 6. Parity diff clean (AC6). 7. DSN allowlist rejects a hosted host (AC7).

## Sharp Edges
- A plan whose `## User-Brand Impact` is empty/placeholder fails `deepen-plan` Phase 4.6 — this one is filled (single-user incident).
