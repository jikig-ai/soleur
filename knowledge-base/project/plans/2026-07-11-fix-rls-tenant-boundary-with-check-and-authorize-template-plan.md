---
title: "Fix two RLS/authz tenant-boundary findings — conversations/kb_files UPDATE WITH CHECK + authorize_template p_grant_id ownership guard"
type: fix
date: 2026-07-11
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issues: [6334, 6336]
found_by: 6307
adr: 111
---

# Fix RLS tenant-boundary: conversations/kb_files UPDATE WITH CHECK + authorize_template p_grant_id ownership guard (#6334, #6336)

## Overview

Two sibling P1 `type/security` findings surfaced by the runtime RLS/authz-fuzz harness (#6307, ADR-111). Both are DB-layer tenant-boundary gaps with concrete remediations already stated in the issue bodies, and both have a matching `test.fails` un-baseline contract in `apps/web-platform/test/rls-fuzz/` that goes RED the moment the fix lands (forcing the exposure out of the baseline). Ship both in **one PR**.

- **#6334** — `conversations` and `kb_files` UPDATE policies re-check only `user_id = auth.uid()` in their `WITH CHECK`; the row owner can `UPDATE … SET workspace_id = <other-ws>` and re-home the row into a workspace they are not a member of. Fix: add `AND public.is_workspace_member(workspace_id, auth.uid())` to each UPDATE `WITH CHECK`, mirroring the INSERT policy and the `kb_share_links` / `push_subscriptions` precedent.
- **#6336** — `public.authorize_template(p_template_hash, p_action_class, p_grant_id)` (SECURITY DEFINER) does not validate that `p_grant_id` belongs to the calling founder; a founder can back a `template_authorization` with another founder's `scope_grant`. Fix: before the INSERT, `RAISE 42501` if `p_grant_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.scope_grants WHERE id = p_grant_id AND founder_id = v_founder_id)`.

Both fixes are pure DDL migrations against already-provisioned surfaces (no new infrastructure). `cq-pg-security-definer-search-path-pin-pg-temp` applies to #6336 (the `authorize_template` `CREATE OR REPLACE` must keep `SET search_path = public, pg_temp`).

## Problem Statement / Motivation

The workspace-tenancy invariant — *"a row's `workspace_id` references a workspace you are a member of"* — is enforced on INSERT (mig 077 `kb_files_member_insert` includes `is_workspace_member`) and by the `is_workspace_member` PERMISSIVE isolation policies (mig 053), but was **dropped on the UPDATE write-side** for `conversations` (mig 075) and `kb_files` (mig 077), and is **not re-derived** for the caller-supplied `p_grant_id` resource reference inside the `authorize_template` SECURITY DEFINER writer (mig 053). A SECURITY DEFINER function bypasses base-table RLS, so any tenancy guarantee must be re-asserted in the function body — it is not inherited (learning `security-issues/2026-07-09-security-definer-rpc-bypasses-jti-rls-and-new-user-fk-table-trips-two-dsar-gates.md`).

Brand-survival threshold: **single-user incident** — this is ADR-111's own framing (a cross-tenant boundary crossing is a single-user data-boundary breach; a false-green isolation test is worse than none).

## Proposed Solution

Two focused migrations shipped in one PR, each with a `.down.sql` and a deploy-time `verify/` sentinel (mirroring the `verify/128` precedent the harness itself cites as the durable deploy-time proof), plus the two `test.fails` → passing un-baseline edits:

1. **`129_*` — RLS UPDATE WITH CHECK** (`#6334`): `DROP POLICY IF EXISTS … / CREATE POLICY …` re-creating `conversations_owner_update` and `kb_files_owner_update` with `WITH CHECK (user_id = auth.uid() AND public.is_workspace_member(workspace_id, auth.uid()))`. USING stays `user_id = auth.uid()` (owner still targets their own rows; the WITH CHECK gates the *new* `workspace_id`).
2. **`130_*` — authorize_template ownership guard** (`#6336`): `CREATE OR REPLACE FUNCTION public.authorize_template(...)` restoring the exact mig-053 body with the ownership guard inserted after the existing input validation and before the INSERT, preserving the `SET search_path = public, pg_temp` pin and re-stating the REVOKE/GRANT/COMMENT block.
3. **Un-baseline the two harness contracts** so they flip from `test.fails`-green to passing assertions.

## Technical Considerations

### Authoritative sources (verified against `origin` worktree)

- `conversations_owner_update` — the live authoritative UPDATE policy: `apps/web-platform/supabase/migrations/075_conversation_visibility.sql:67-70`. Nothing after 075 redefines it.
- `kb_files_owner_update` — live authoritative: `apps/web-platform/supabase/migrations/077_kb_files_metadata.sql:54-57`. `kb_files_member_insert` (`:46-51`) already includes `is_workspace_member` — the precedent to mirror.
- `is_workspace_member(p_workspace_id uuid, p_user_id uuid)` — `053_organizations_and_workspace_members.sql:115-137`; SECURITY DEFINER, `LANGUAGE plpgsql` (deliberately non-inlinable), search_path pinned; EXECUTE granted to `authenticated`. Callable from a policy predicate as `public.is_workspace_member(workspace_id, auth.uid())`.
- Correct precedents: `kb_share_links_workspace_member_all` (`059_workspace_keyed_rls_sweep.sql:148-153`, ALL WITH CHECK `is_workspace_member`) and `push_subscriptions_workspace_member_update` (`059_…:192-195`, UPDATE WITH CHECK `is_workspace_member`).
- Policy-redefinition idiom: `DROP POLICY IF EXISTS <name> ON public.<t>; CREATE POLICY <name> …`, `.down.sql` restores the prior definition verbatim (representative: `075` + `075…down.sql`; most recent `111_email_triage_items_workspace_shared.sql:223-227`). Migrations carry **no** top-level BEGIN/COMMIT — `run-migrations.sh` wraps each file `--single-transaction` (learning `build-errors/2026-05-25-migration-body-no-top-level-begin-commit.md`).
- `authorize_template` — sole definition `053_template_authorizations.sql:222-303`; SECURITY DEFINER, already pins search_path (`:229`), `v_founder_id uuid := auth.uid()` server-derived, GRANTed EXECUTE to `authenticated` (intentional — it is the founder's own first-send-IS-authorization writer). The vuln locus: `grant_id = p_grant_id` is inserted verbatim with no ownership re-check (only the FK `grant_id → scope_grants(id)` enforces existence, not ownership).
- `scope_grants` schema: `048_scope_grants.sql:14-29` (`id`, `founder_id`, `revoked_at` NULL = active; no `status` column). `template_authorizations` schema: `053_…:76-132` (`grant_id uuid NOT NULL` FK `scope_grants(id) ON DELETE RESTRICT`, `:106`; WORM append-only via `template_authorizations_no_mutate()`; sole writer is the RPC — no INSERT policy).
- CREATE-OR-REPLACE-modify + down precedent: `089_template_auto_revoke_carveout.sql` (up = replace) / `089…down.sql:14-88` (down = replace back to prior body, re-stating REVOKE/GRANT/COMMENT). The `130` down mirrors this — it is a *modify*, so it must CREATE-OR-REPLACE-restore, NOT `DROP FUNCTION`.

### Attack Surface Enumeration (security fixes)

**#6334 — UPDATE WITH CHECK tenancy-key hijack.** The canonical enumerator is the harness catalog `rowHijackTables()` (`test/rls-fuzz/catalog.ts:117-128`): PERMISSIVE UPDATE/ALL policies `TO authenticated` on `workspace_id`-carrying tables = `{conversations, kb_files, kb_share_links, push_subscriptions}`. Exactly two — `conversations`, `kb_files` — lack the `is_workspace_member` re-check (the other two are the correct precedent). Scope is closed by the catalog, not a hand-list; both fixed tables remain in the catalog set after the fix (still have UPDATE policies), so the `AC6` registry-equals-catalog gate stays satisfied.

- Path A — `conversations` UPDATE: only `visibility` is column-REVOKE'd (`075:38`), NOT `workspace_id`; the WITH CHECK is the **sole** gate on `workspace_id`. Fixed by this PR.
- Path B — `kb_files` UPDATE: `077:76` `REVOKE UPDATE(visibility, workspace_id) … FROM authenticated` *should* block the column write, yet the harness empirically observed the hijack **succeed** (it is baselined `test.fails`-green, which is only true if `hijack()` returned `leaked`). **The column REVOKE is not enforcing in the live catalog** (candidate cause: a broad table-level grant to `authenticated` overriding the column-level REVOKE, or the runner's default-privilege interaction). The WITH CHECK is therefore the load-bearing gate here too. `/work` Phase 0 MUST reproduce on the live local stack to confirm and record the root cause; the ineffective column REVOKE is captured as a downstream observation (candidate follow-up — see Alternatives), NOT expanded scope, because the WITH CHECK fully closes the vuln regardless of column-grant state.
- Unchecked-but-safe: `kb_share_links` / `push_subscriptions` already deny (precedent). No other `workspace_id` UPDATE surface exists per the catalog.

**#6336 — authorize_template p_grant_id ownership (downstream severity review, requested by the issue).** Every consumer of `template_authorizations.grant_id` was traced (SQL migrations + `server/` + `app/`):

- `server/templates/is-template-authorized.ts:115-121` — the send-gate predicate keys on `founder_id` + `template_hash`; **does not select `grant_id`, no join to `scope_grants`**.
- `app/api/dashboard/today/[id]/send/route.ts:144,189-197` → `server/scope-grants/is-granted.ts:43-51` — send-time authority (tier gate) is re-derived from `scope_grants` filtered `founder_id = auth.uid()` AND `revoked_at IS NULL`; `grant.id` is provably owned before it is ever forwarded to the RPC. Authority is **not** inherited from `template_authorizations.grant_id`.
- `server/dsar-export.ts:1062-1079` + `-allowlist.ts:203-209` — `grant_id` emitted as founder-scoped exported data only; no authority use.
- `server/account-delete.ts:345-378` — keys on `founder_id`; no `grant_id` read.
- **No join between `template_authorizations` and `scope_grants` exists anywhere.**

**Final severity verdict:** NOT a live cross-tenant privilege-escalation (no consumer trusts `grant_id` for tier/action-class authority). It is a **data-integrity / audit-attribution defect**: a founder can mint a `template_authorizations` row whose `founder_id` is theirs but whose `grant_id` points at another founder's grant. Two real side effects justify the defense-in-depth fix: (a) it corrupts the **GDPR Art. 5(2)** integrity/provenance of the consent record (`template_authorizations` is a processing-activity record), and (b) because both FKs are `ON DELETE RESTRICT`, a B-owned row referencing A's grant can interfere with A's `scope_grants` deletion/anonymisation cascade ordering. P1 stands; the un-baseline contract mandates the fix independent of severity.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / task) | Reality (verified) | Plan response |
|---|---|---|
| #6336 may be privilege-escalation "if any path trusts `grant_id`" | No consumer trusts `grant_id`; authority re-derived from `scope_grants WHERE founder_id=auth.uid()` (`is-granted.ts:43-51`) | Severity set to data-integrity/audit-attribution defect (Art. 5(2) + cascade); still fixed (defense-in-depth + un-baseline contract) |
| kb_files UPDATE WITH CHECK is the only gap; owner can re-home | Live-catalog leak confirmed, BUT `077:76` also column-REVOKEs `workspace_id` and it is not enforcing | WITH CHECK is load-bearing; `/work` Phase 0 reproduces + records why the column REVOKE is inert; ineffective REVOKE noted as candidate follow-up, not in-scope |
| authorize_template needs an ownership guard | Confirmed; fn already pins search_path; only `p_grant_id` unvalidated | Add guard, preserve pin; no grant-revocation (see Alternatives) |
| Un-baseline touches `KNOWN_EXPOSURES`/`HIJACK_EXPOSURES` | `HIJACK_EXPOSURES` (set literal) for #6334; #6336 is a **bespoke** `test.fails`, NOT in the `KNOWN_EXPOSURES` map; `rpc-cases.ts` EXCLUDED entry stays valid | Edit the set for #6334; flip `test.fails`→`test` for #6336; **no** `rpc-cases.ts` edit |
| Learning: "caller-override RPC must be service_role-only" | Applies to forgeable *identity*-override params (`p_caller`); here `founder_id` is server-derived from `auth.uid()`, `p_grant_id` is a resource ref | Ownership re-check, NOT a grant change (would break the legit authenticated send path) |

## User-Brand Impact

- **If this lands broken, the user experiences:** a founder's own conversation or KB file silently re-homed into a workspace they are not a member of (origin-workspace members lose visibility; target-workspace members gain read access to the owner's content — including a maliciously injected `kb_file`); and a consent-authorization record (`template_authorizations`) whose `grant_id` provenance points at another founder's grant.
- **If this leaks, the user's data / workflow is exposed via:** the `conversations` / `kb_files` UPDATE `WITH CHECK` tenancy-key hijack (#6334), and the `authorize_template` `p_grant_id` cross-founder reference (#6336) corrupting Art. 5(2) attribution of the consent ledger.
- **Brand-survival threshold:** `single-user incident`

CPO sign-off required at plan time before `/work` begins (headless pipeline — CPO covered by the Domain Review below; confirm at the plan-review gate). `user-impact-reviewer` will be invoked at review time (single-user-incident threshold).

## Observability

```yaml
liveness_signal:
  what:            "RLS/authz-fuzz merge gate — applies this PR's migrations to a disposable local Supabase stack and drives the row-hijack + authorize_template attacks; deploy-time verify/129+130 sentinels run against prod"
  cadence:         "per-PR (any change under apps/web-platform/supabase/migrations/** or test/rls-fuzz/**); per-deploy for verify sentinels"
  alert_target:    "PR check status (rls-authz-fuzz) — red blocks the PR; deploy verify failure blocks the web-platform-release migrate step"
  configured_in:   ".github/workflows/rls-authz-fuzz.yml (runs `bun run test:rls-fuzz`); apps/web-platform/scripts/run-verify.sh (verify/129,130); apps/web-platform/scripts/run-migrations.sh (apply)"

error_reporting:
  destination:     "GitHub Actions run (rls-authz-fuzz job + web-platform-release migrate/verify job) — no Sentry surface for DB migrations"
  fail_loud:       "rls-authz-fuzz job RED on any hijack/RPC leak, positive-control failure, or a still-green test.fails; run-verify.sh exits non-zero when a verify sentinel returns bad>0"

failure_modes:
  - mode:          "migration fails to apply (syntax, dollar-quote, precondition)"
    detection:     "run-migrations.sh non-zero in the rls-authz-fuzz job AND in the release migrate step"
    alert_route:   "PR author (red check) / release pipeline halt"
  - mode:          "fix regresses later (WITH CHECK or ownership guard removed)"
    detection:     "rls-authz-fuzz harness reds (un-baselined plain test asserts denied); verify/129|130 sentinel bad>0 at deploy"
    alert_route:   "PR author / release pipeline halt"
  - mode:          "un-baseline not performed (test.fails left in place)"
    detection:     "the test.fails goes RED in the same rls-authz-fuzz job on this PR (its body assertion now passes)"
    alert_route:   "PR author (red check)"

logs:
  where:           "GitHub Actions run logs: rls-authz-fuzz + web-platform-release (migrate+verify)"
  retention:       "GitHub default (90 days)"

discoverability_test:
  command:         "cd apps/web-platform && bun run test:rls-fuzz   # (RLS_FUZZ_LOCAL=1 against the ADR-111 local stack; no ssh)"
  expected_output: "row-hijack: conversations & kb_files WITH CHECK denies owner re-home to wsB; authorize_template denies tenant-B; all positive controls pass; 0 failures"
```

Affected-surface note (2.9.2): the DB is not a blind sandbox/container/cron surface — the RLS-fuzz harness IS the in-surface probe (it drives the actual migrated catalog under injected `authenticated` claims and discriminates SQLSTATE 42501). No separate probe required. Soak (2.9.1): no time-gated soak criterion — the merge gate is a hard binary. N/A.

## Files to Create

- `apps/web-platform/supabase/migrations/129_rls_update_with_check_workspace_member.sql` — `DROP POLICY IF EXISTS` + `CREATE POLICY` for `conversations_owner_update` and `kb_files_owner_update` with the `is_workspace_member` WITH CHECK.
- `apps/web-platform/supabase/migrations/129_rls_update_with_check_workspace_member.down.sql` — restore both WITH CHECKs to `user_id = auth.uid()` only.
- `apps/web-platform/supabase/migrations/130_authorize_template_grant_ownership_guard.sql` — `CREATE OR REPLACE FUNCTION public.authorize_template(...)` with the p_grant_id ownership guard; preserves `SET search_path = public, pg_temp`; re-states REVOKE/GRANT/COMMENT.
- `apps/web-platform/supabase/migrations/130_authorize_template_grant_ownership_guard.down.sql` — `CREATE OR REPLACE` restoring the exact mig-053 `authorize_template` body (no guard), re-stating REVOKE/GRANT/COMMENT (089.down idiom).
- `apps/web-platform/supabase/verify/129_rls_update_with_check_workspace_member.sql` — sentinel: `pg_policies.with_check ILIKE '%is_workspace_member%'` for both `conversations_owner_update` and `kb_files_owner_update` (bad>0 otherwise).
- `apps/web-platform/supabase/verify/130_authorize_template_grant_ownership_guard.sql` — sentinel: `pg_get_functiondef(...authorize_template...) ILIKE` contains the `scope_grants … founder_id = v_founder_id` ownership predicate (bad>0 otherwise).

> Migration numbers `129`/`130` are the next-free prefixes (verified free on this worktree). They are **provisional** — a sibling PR could claim them (the repo tracks migrations by full filename, so a duplicate prefix is valid but undesirable). `/work` Phase 0 re-checks next-free against `origin/main`; `/ship` re-verifies before merge.

## Files to Edit

- `apps/web-platform/test/rls-fuzz/rls-row-hijack.integration.test.ts:80` — remove `"conversations"` and `"kb_files"` from `HIJACK_EXPOSURES` (leave the set for future exposures, or empty it). Once removed, the loop's `else` branch (`:152-156`) runs a plain `test()` asserting the hijack is `denied` — which now passes. No other edit needed (the `HIJACK_TARGETS` registry and `AC6` catalog gate are unchanged).
- `apps/web-platform/test/rls-fuzz/rls-rpc.integration.test.ts:161` — change `test.fails(...)` → `test(...)` and retitle (drop "EXPOSURE (baselined, #6336): tenant-B CAN back…" → e.g. "authorize_template DENIES tenant-B backing an authorization with tenant-A's grant (#6336)"). The body assertion `expect(rowsUnderB, …).toBe(0)` is unchanged and now passes (the RPC raises 42501 for B). The paired positive control (`:181-189`, owner A authorizes with its own grant) must keep passing.
- **No edit** to `apps/web-platform/test/rls-fuzz/rpc-cases.ts` — `authorize_template` stays classified `EXCLUDED` (`:94`); its rationale (bespoke test) remains accurate, and AC8 stays satisfied (still one classification, still authenticated-EXECUTE definer fn).
- **No edit** to `apps/web-platform/test/rls-fuzz/catalog.ts` — both fixed tables remain in `rowHijackTables()`.

## Implementation Phases

### Phase 0 — Reproduce on the live local stack (precondition)
- Stand up the ADR-111 local disposable Supabase stack (`supabase start` with `[db.migrations] enabled = false`, then `run-migrations.sh` over `docker exec psql`), or rely on the `rls-authz-fuzz` CI gate as the authoritative verifier.
- Run `bun run test:rls-fuzz` pre-fix; confirm the two `test.fails` contracts are green (exposures reproduce). For `kb_files`, record the live catalog state that lets the `workspace_id` UPDATE succeed despite `077:76` (introspect `information_schema.role_column_grants` / `has_column_privilege('authenticated','public.kb_files','workspace_id','UPDATE')`) so the downstream observation is fact, not inference.
- Re-verify `129`/`130` are the next-free migration prefixes against `origin/main`.

### Phase 1 — #6334 RLS UPDATE WITH CHECK (migration 129 + down + verify)
- Author `129_*.sql` (both policies), `129_*.down.sql`, `verify/129_*.sql`. Qualify `public.is_workspace_member`. No top-level BEGIN/COMMIT.

### Phase 2 — #6336 authorize_template ownership guard (migration 130 + down + verify)
- Author `130_*.sql` (`CREATE OR REPLACE` with the guard after input validation, before the INSERT; keep `SET search_path = public, pg_temp`; re-state REVOKE/GRANT/COMMENT), `130_*.down.sql` (restore mig-053 body), `verify/130_*.sql`.

### Phase 3 — Un-baseline + verify green
- Apply the two test edits (Files to Edit). Re-run `bun run test:rls-fuzz`; confirm both contracts now pass as plain assertions and all positive controls remain green. Run `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `pg_policies` for `conversations_owner_update` and `kb_files_owner_update` each have `with_check ILIKE '%is_workspace_member%'` AND retain `user_id = auth.uid()` (verify sentinel `129` returns bad=0 for both).
- [ ] `authorize_template` raises SQLSTATE `42501` when `p_grant_id` references a `scope_grants` row not owned by `auth.uid()`, and still succeeds for the owner (verify sentinel `130` bad=0; harness positive control at `rls-rpc…:181-189` green).
- [ ] `authorize_template` still declares `SECURITY DEFINER` and `SET search_path = public, pg_temp` (cq-pg-security-definer-search-path-pin-pg-temp).
- [ ] `rls-row-hijack.integration.test.ts`: `HIJACK_EXPOSURES` no longer contains `conversations`/`kb_files`; the plain `test()` asserts each denies re-home to wsB and passes; `AC6` catalog-registry gate still green.
- [ ] `rls-rpc.integration.test.ts`: the `#6336` case is a plain `test()` (no `.fails`), asserting tenant-B creates 0 rows; passes.
- [ ] `rls-authz-fuzz` CI gate is GREEN on the PR (applies both migrations to a fresh stack, drives all attacks + positive controls). This is the merge gate — must be green before ready.
- [ ] `.down.sql` for both migrations restores the prior definition (policy WITH CHECK reverts to `user_id = auth.uid()`; `authorize_template` reverts to the mig-053 body).
- [ ] `tsc --noEmit` clean for `apps/web-platform`.
- [ ] `rpc-cases.ts` and `catalog.ts` unchanged (documented no-edit).

### Post-merge (deploy — automated, no operator step)
- [ ] `web-platform-release` migrate step applies `129`/`130` to prod; `run-verify.sh` runs `verify/129` + `verify/130` (both bad=0) against the deployed DB. Failure halts the release pipeline (no manual verification required).

## Test Scenarios

### Regression (the un-baseline contracts)
- Given owner A holds a `conversations` row in wsA and is a non-member of wsB, when A runs `UPDATE conversations SET workspace_id = wsB`, then it is denied (SQLSTATE 42501) — `rls-row-hijack` plain test.
- Given the same for `kb_files`, when A re-homes to wsB, then denied.
- Given tenant-B and A's real `scope_grant` (`ctx.scopeGrantA`), when B calls `authorize_template('…','general.attack', A's grant_id)`, then 0 `template_authorizations` rows are created for B (raise 42501) — `rls-rpc` plain test.

### Positive controls (must stay green)
- Given owner A, when A updates a non-tenancy column on its own `conversations`/`kb_files` row, then it succeeds (1 row).
- Given owner A and A's own grant, when A calls `authorize_template` with `scopeGrantA`, then a non-null id returns.
- Given owner A, when A re-reads its poisoned definer-getter values, then they return A's seeded values (harness self-test unaffected).

### Edge cases
- `p_grant_id IS NULL`: the guard's `IS NOT NULL` short-circuits (no ownership check); the pre-existing `grant_id NOT NULL` FK still rejects a NULL insert as today (behavior unchanged).
- Idempotent re-authorize (unique_violation branch) path in `authorize_template` unchanged.

## Alternative Approaches Considered

| Option | Verdict | Reason |
|---|---|---|
| Also add `AND revoked_at IS NULL` to the authorize_template ownership guard | Deferred (not in this PR) | The issue's primary remediation is ownership-only; the legit `isGranted` path already filters `revoked_at IS NULL` upstream, so a revoked grant never reaches the RPC. Adding it widens semantics beyond the security property. deepen-plan/plan-review may escalate. |
| Make `authorize_template` service_role-only (REVOKE FROM authenticated) | Rejected | The "caller-override RPC must be service_role-only" learning applies to forgeable *identity*-override params; here `founder_id` is server-derived from `auth.uid()` and `p_grant_id` is a resource ref. The fn is *designed* to be the founder's own authenticated writer (called from the send path). Revoking would break the legit flow. Ownership re-check is the correct minimal fix. |
| Re-assert `REVOKE UPDATE(workspace_id) ON kb_files FROM authenticated` in migration 129 | Candidate follow-up (not in-scope) | The `077:76` column REVOKE is empirically inert in the live catalog (root cause recorded in Phase 0). The WITH CHECK fully closes the vuln regardless; re-asserting the column defense is a separate hardening. If Phase 0 shows a systemic broad-grant override, file a follow-up issue with the finding. |
| One combined migration for both fixes | Rejected | Two distinct surfaces (RLS policies vs RPC body); separate migrations + verify sentinels are cleaner and match the one-concern-per-migration convention. Still one PR. |
| Skip `verify/` sentinels (rely on the RLS-fuzz PR gate only) | Rejected | The RLS-fuzz gate is PR/local-only; it does not run against prod. At the single-user-incident threshold, the deploy-time `verify/` sentinel is the prod-facing durable proof the fix actually landed (the `verify/128` precedent the harness itself cites). |

## Domain Review

**Domains relevant:** Engineering (CTO), Legal/Compliance (CLO). Product: none (no UI surface — pure DB migration + test edits; the mechanical UI-surface override did not fire).

CTO and CLO domain-leader assessments were requested in parallel (see below). Product/UX Gate: **skipped — NONE** (no `components/**`, `app/**/page.tsx`, or user-facing surface in Files to Create/Edit).

### GDPR / Compliance (Phase 2.7)
Regulated-data surface touched (`.sql` migrations, RLS, a SECURITY DEFINER auth writer) → gate fires. Assessment: both changes are **net-positive hardening** of tenant data-boundary and consent-record integrity. #6336 strengthens **Art. 5(2)** accountability/integrity of `template_authorizations` (a processing-activity record) by preventing cross-founder `grant_id` provenance corruption; #6334 strengthens tenant isolation of `conversations`/`kb_files` (personal + workspace content). No new processing activity, no new data category, no lawful-basis change → no Critical findings expected. The CLO assessment carries the compliance lens (Art. 5(2), Art. 30 register touch-point). deepen-plan / review-phase `security-sentinel` + `data-integrity-guardian` provide the diff-time depth.

## Architecture Decision (ADR/C4)

**No new architectural decision.** These fixes **restore** the already-recorded mig-053 workspace-membership tenancy invariant to the UPDATE write-side and the SECURITY DEFINER writer — they do not create, reverse, or extend an architectural decision. The finding itself is documented by ADR-111 (the RLS/authz-fuzz harness). No ADR is authored or amended.

**C4 views: no impact** (completeness mandate satisfied). Checked all three model files:
- `model.c4` — the Supabase store (`supabaseDb`, "conversation sessions"/BYOK) and the beta-CRM store are modeled at store granularity; per-table RLS policies and the `scope_grants`/`template_authorizations` tables are **not** C4 elements. External actors `founder` and `betaContact` are present; no new actor is introduced.
- `views.c4` — no view includes a per-table or per-policy element that changes.
- `spec.c4` — element-type/tag spec; no data-boundary element affected.
No new **external human actor**, **external system/vendor**, **container/data-store**, or **actor↔surface access relationship** is added — the fix *tightens enforcement* of an existing owner→store relationship (prevents re-homing / cross-founder reference) within the already-modeled `supabaseDb` boundary. Hence no `.c4` edit and no `view include` change.

## Dependencies & Risks

- **Dollar-quote nesting** in `130_*.sql` (function body inside a migration): use a distinct outer tag if any nested `$$` appears (learning `bug-fixes/2026-05-27-…dollar-quote…`). `authorize_template`'s body uses `$$…$$`; keep the migration free of a conflicting outer `$$`.
- **Down-migration correctness**: `130.down` is a *replace-back* (089.down idiom), NOT a DROP — a DROP would break `template_authorizations` writes on rollback.
- **kb_files column-REVOKE mystery** (Phase 0): must be reproduced and root-caused, not assumed; the WITH CHECK fix is robust either way.
- **RLS-fuzz gate must be a blocking check**: confirm the PR cannot be marked ready/merged while `rls-authz-fuzz` is red (single-user-incident threshold). `/ship` gates on required checks.
- **No `verify/068` count impact**: the change modifies existing `owner_update` policies' WITH CHECK; it adds/removes no `jti_not_denied` policy, so the `verify/068` count sentinel + its drift test are unaffected.

## References & Research

### Internal
- Policies: `075_conversation_visibility.sql:55-74`, `077_kb_files_metadata.sql:46-76`, `059_workspace_keyed_rls_sweep.sql:148-153,192-195`.
- `is_workspace_member`: `053_organizations_and_workspace_members.sql:115-137`.
- `authorize_template` + schemas: `053_template_authorizations.sql:76-132,222-303`; `048_scope_grants.sql:14-29,131-201`.
- CREATE-OR-REPLACE-modify + down idiom: `089_template_auto_revoke_carveout.sql` / `.down.sql:14-88`.
- Consumers: `server/templates/is-template-authorized.ts:115-121`, `server/scope-grants/is-granted.ts:43-51`, `app/api/dashboard/today/[id]/send/route.ts:144,189-197`, `server/dsar-export.ts:1062-1079`, `server/account-delete.ts:345-378`.
- Harness: `test/rls-fuzz/{catalog.ts,rpc-cases.ts,rls-row-hijack.integration.test.ts,rls-rpc.integration.test.ts}`; `.github/workflows/rls-authz-fuzz.yml`; `package.json` `test:rls-fuzz`.
- Verify precedent: `apps/web-platform/supabase/verify/128_*.sql`, `116_*.sql`; runner `scripts/run-verify.sh`.
- ADR-111: `knowledge-base/engineering/architecture/decisions/ADR-111-runtime-authz-rls-fuzz-harness.md`.
- Learnings: `security-issues/2026-07-09-security-definer-rpc-bypasses-jti-rls-and-new-user-fk-table-trips-two-dsar-gates.md`; `security-issues/2026-07-10-supabase-default-privileges-defeat-revoke-from-public.md`; `integration-issues/2026-04-18-supabase-migration-concurrently-forbidden.md`; `build-errors/2026-05-25-migration-body-no-top-level-begin-commit.md`; `best-practices/2026-07-02-membership-authz-bind-to-substrate-not-conflating-resolver.md`; `best-practices/2026-07-08-verify-sentinel-hardcoded-count-breaks-on-new-counted-object.md`.

### Related Work
- Issues: #6334, #6336 (this PR). Found by #6307 (harness Phase 5 + Phase 7). Harness origin #6256. Sibling closed: #6318 (mig 128).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold fails `deepen-plan` Phase 4.6. This plan sets `single-user incident` with concrete artifact + vector — fill any deepen-plan additions the same way.
- The #6336 un-baseline is a **bespoke** `test.fails`, not a `KNOWN_EXPOSURES` map entry — do NOT edit `rpc-cases.ts` looking for it. The only #6336 test edit is dropping `.fails` at `rls-rpc.integration.test.ts:161`.
- Do NOT DROP+CREATE `authorize_template` in the `130` up/down — it must be `CREATE OR REPLACE` both ways (a DROP severs the `authenticated` GRANT and breaks the send path until re-granted).
