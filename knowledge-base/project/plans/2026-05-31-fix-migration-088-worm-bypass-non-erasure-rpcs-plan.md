---
title: "Migration 088 — privilege-free WORM bypass for the two non-erasure RPCs"
type: fix
issue: 4702
branch: feat-one-shot-migration-088-worm-bypass-non-erasure-rpcs
date: 2026-05-31
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Migration 088 — privilege-free WORM bypass for `purge_workspace_member_actions` + `revoke_template_authorization`

## Enhancement Summary

**Deepened on:** 2026-05-31
**Sections enhanced:** Risks & Mitigations (precedent-diff), Files to Create (test-helper edge cases)
**Gates run:** GDPR-gate (Phase 2.7, no findings), deepen-plan 4.4 (precedent-diff), 4.6 (User-Brand Impact present), 4.7 (Observability present, no SSH), 4.8 (no PAT-shaped vars)

### Key Improvements
1. Precedent-diff confirmed both target RPCs use the `AS $$` dollar-quote tag and `SECURITY DEFINER` — byte-identical to the mig 063/053 originals modulo the two bypass lines; the 087 `fnBlock` test helper handles `$$` (verified).
2. Confirmed the 087 `fnBlock` regex prefix `public\.${name}\s*\(` matches `purge_workspace_member_actions()` (zero-arg, empty parens) and `revoke_template_authorization(text, text)` (two-arg) — the new test can reuse it verbatim.
3. Confirmed the trigger functions need NO edits (087 §1.2/§1.5 already converted them); 088 is RPC-body-only, eliminating a redundant-CREATE drift risk.

### New Considerations Discovered
- The 087 forward migration uses a MIX of dollar-quote tags (`$fn$` for the anonymise RPCs, but the two target RPCs in 063/053 use `$$`). The new 088 test MUST keep the 087 `fnBlock` regex's `\$([A-Za-z_]*)\$ … \$\1\$` backreference form so it matches the `$$` (empty-tag) case — do not hard-code `$fn$`.
- `purge_workspace_member_actions` has no app-code call site (pg_cron only), so the "wired call site" Art-17-caller check is N/A; its liveness is the `cron.job_run_details` + `RAISE LOG audit_retention_purge` path, captured in Observability.

## Overview

Migration 087 (PR #4679, closed #4696) converted the entire GDPR Art. 17 account-delete saga from the
superuser-only `SET LOCAL session_replication_role = 'replica'` WORM bypass to the privilege-free
custom GUC `app.worm_bypass`. It explicitly deferred two **non-erasure** RPCs to follow-up #4702
(087.sql lines 57-59):

- `purge_workspace_member_actions()` — the pg_cron 7-year retention DELETE sweep (defined in mig 063).
- `revoke_template_authorization(text, text)` — the founder/auto-revoke UPDATE (defined in mig 053).

Both still issue `SET LOCAL session_replication_role = 'replica'` … `RESET session_replication_role`.
On managed Supabase the `postgres` role that owns these `SECURITY DEFINER` functions is **not** a
superuser, so that GUC raises `42501 permission denied to set parameter "session_replication_role"`
**before** the DML runs. Consequences:

- `purge_workspace_member_actions` is invoked by pg_cron and **never deletes anything** — the
  7-year retention sweep is silently a no-op, an Art. 5(1)(e) storage-limitation drift (audit PII
  accumulates past its lawful retention window indefinitely).
- `revoke_template_authorization` throws `42501` on every call that reaches the bypass — both the
  founder-initiated revoke (`/api/template-authorizations/revoke`) and the service-role auto-revoke
  side-effect (`is-template-authorized.ts`, reasons `expired`/`quota_exhausted`). Founders cannot
  withdraw a template authorization (Art. 7(3) "as easily withdrawable as given").

**The trigger functions are already fixed.** Migration 087 §1.2 rewrote
`template_authorizations_no_mutate()` and §1.5 rewrote `workspace_member_actions_no_mutate()` to honor
`current_setting('app.worm_bypass', true) = 'on'`. The triggers (`workspace_member_actions_no_delete`,
the `template_authorizations` no-update/no-delete pair) `EXECUTE FUNCTION` those same functions
(verified in mig 063 L133/L139 and mig 053 L181/L187). So **only the two RPC bodies need the swap** —
no trigger-function edits in 088.

Migration 088 mirrors 087 exactly: replace `SET LOCAL session_replication_role = 'replica'` with
`SET LOCAL app.worm_bypass = 'on'` and `RESET session_replication_role` with
`SET LOCAL app.worm_bypass = 'off'` (re-arm immediately after the single write), preserving every
other line of each RPC body verbatim (authz checks, reason-enum gate, `search_path`, grants, COMMENTs,
RAISE LOG). Add a migration-shape guardrail test mirroring
`test/supabase-migrations/087-worm-bypass-privilege-independence.test.ts`.

## Research Reconciliation — Spec vs. Codebase

| Cited claim (task description) | Reality (verified) | Plan response |
|---|---|---|
| Replace `session_replication_role` in the RPC bodies of `purge_workspace_member_actions` and `revoke_template_authorization` | Both RPCs still carry `SET LOCAL session_replication_role = 'replica'` … `RESET …` (purge: mig 063 body; revoke: mig 053 body). Neither was redefined by 087. | Re-CREATE both via `CREATE OR REPLACE` in 088 with `app.worm_bypass`. |
| Trigger functions already honor `app.worm_bypass` after 087 | Confirmed: 087 §1.2 `template_authorizations_no_mutate` + §1.5 `workspace_member_actions_no_mutate` both check `current_setting('app.worm_bypass', true) = 'on'`. Triggers `EXECUTE FUNCTION` those functions (mig 063 L133/L139, mig 053 L181/L187). | No trigger-function edits in 088. Down migration also leaves triggers untouched. |
| Guardrail test should assert neither **function** references `session_replication_role` | The two trigger functions never referenced it post-087 anyway; the live references are in the two **RPC** bodies. | Test asserts (a) the 088 forward migration nowhere references `session_replication_role`, and (b) each of the two RPCs sets `app.worm_bypass='on'`/`'off'` and keeps `search_path` pinned. Mirrors 087 test structure. |
| `purge` is "scheduled" / cron-invoked | mig 063 COMMENT: "pg_cron-invoked 7-year retention purge." Caller is pg_cron (no app-code call site). | Plan notes the cron path; verification is migration-shape + a DEV-only live probe (no PROD writes). |
| `revoke` has a single call path | TWO callers: `app/api/template-authorizations/revoke/route.ts` (authenticated founder, `reason='founder_revoked'`) and `server/templates/is-template-authorized.ts:180` (service-role auto-revoke, `reason='expired'`/`'quota_exhausted'`). Both reach the same bypassed UPDATE. | Preserve the full reason-enum gate + `auth.uid()` authz block verbatim; only swap the two bypass lines. Both callers benefit. |

## User-Brand Impact

**If this lands broken, the user experiences:** a founder clicks "revoke template authorization" and
gets a 500 (the `42501` surfaces as an RPC error at `/api/template-authorizations/revoke`); separately,
their audit-trail PII silently outlives its lawful 7-year retention window because the cron purge is a
permanent no-op.

**If this leaks, the user's data is exposed via:** the re-arm line is the single most security-load-
bearing statement — if `SET LOCAL app.worm_bypass = 'off'` were omitted, the `'on'` GUC would persist
for the rest of the transaction and any subsequent statement in that txn would silently bypass the WORM
trigger (audit-trail tamper surface). `SET LOCAL` is already txn-scoped, but the explicit re-arm
mirrors 087 and is pinned by the guardrail test.

**Brand-survival threshold:** single-user incident — a single founder's failed revoke (Art. 7(3)) or a
single user's over-retained audit PII (Art. 5(1)(e)) is a compliance-visible regression. CPO sign-off
required at plan time; `user-impact-reviewer` runs at review-time.

## Files to Create

- `apps/web-platform/supabase/migrations/088_worm_bypass_non_erasure_rpcs.sql`
  - Header comment block mirroring 087's structure: problem (42501 on the two deferred non-erasure
    RPCs), why the trigger functions are already correct (087 §1.2/§1.5), the fix (GUC swap only),
    scope (these two RPCs only), conventions (idempotent `CREATE OR REPLACE`, no outer
    `BEGIN/COMMIT`, `search_path` pinned per `cq-pg-security-definer-search-path-pin-pg-temp`, grants
    preserved by `CREATE OR REPLACE`). Cite #4702 and the 087 precedent.
  - **§1 `purge_workspace_member_actions()`** — re-CREATE verbatim from mig 063 EXCEPT:
    - `SET LOCAL session_replication_role = 'replica';` → `SET LOCAL app.worm_bypass = 'on';`
    - `RESET session_replication_role;` → `SET LOCAL app.worm_bypass = 'off';`
    - Keep `RETURNS int`, `SECURITY DEFINER`, `SET search_path = public, pg_temp`, the
      `DELETE … WHERE created_at < now() - interval '7 years'`, `GET DIAGNOSTICS`, the
      `RAISE LOG 'audit_retention_purge …'`, and `RETURN v_rows`.
    - Re-issue the existing `REVOKE ALL … FROM PUBLIC, anon, authenticated` and
      `GRANT EXECUTE … TO postgres` (defense-in-depth; `CREATE OR REPLACE` preserves them but
      re-stating mirrors 087's REVOKE pattern).
    - Refresh the `COMMENT ON FUNCTION` to cite `app.worm_bypass` + #4702 (drop the stale
      `session_replication_role` wording in the existing comment).
  - **§2 `revoke_template_authorization(text, text)`** — re-CREATE verbatim from mig 053 EXCEPT the
    same two bypass-line swaps. **Preserve verbatim:** the `v_founder_id := auth.uid()` + NULL check,
    the full 8-value `p_reason` enum gate, the `auth.uid() IS NOT NULL AND p_reason <> 'founder_revoked'`
    founder-attribution gate, `RETURNS integer`, `SECURITY DEFINER`, `search_path`, the
    `UPDATE … SET revoked_at=now(), revocation_reason=p_reason WHERE founder_id=v_founder_id AND
    template_hash=p_template_hash AND revoked_at IS NULL`, `GET DIAGNOSTICS`, `RETURN affected`.
    - Re-issue the existing `REVOKE ALL … FROM PUBLIC, anon, authenticated, service_role` and
      `GRANT EXECUTE … TO authenticated`.
    - Update the inline bypass comment (currently describes `session_replication_role` skipping BEFORE
      triggers) to describe `app.worm_bypass`; refresh the `COMMENT ON FUNCTION` if it names the old GUC
      (it does not — leave the Art. 7(3) prose intact).

- `apps/web-platform/supabase/migrations/088_worm_bypass_non_erasure_rpcs.down.sql`
  - Re-CREATE both RPCs with the original `session_replication_role` bypass bodies (copy the exact
    pre-088 bodies from mig 063 / mig 053), restoring `RESET session_replication_role`. Mirror 087's
    down structure. Header WARNING: forward-only reality — the down reinstates the prod-broken `42501`
    behavior and is for local rollback only, NOT a production remediation. No table/trigger DDL to
    revert (088 touches only these two function bodies).

- `apps/web-platform/test/supabase-migrations/088-worm-bypass-non-erasure-rpcs.test.ts`
  - Mirror 087's offline migration-shape test (vitest, `readFileSync` + comment strip). Pins:
    1. Forward migration nowhere references `session_replication_role` (`expect(executable).not.toMatch(/session_replication_role/i)`).
    2. For each of `["purge_workspace_member_actions", "revoke_template_authorization"]`: the function
       block sets `SET LOCAL app.worm_bypass = 'on'`, sets `SET LOCAL app.worm_bypass = 'off'` (re-arm),
       does NOT match `session_replication_role`, and keeps `search_path` pinned. Reuse 087's
       `fnBlock` regex helper (handles `$$`/`$fn$`/`$function$` tags) — but note both target RPCs use
       the `$$` dollar-quote tag (verified in mig 053/063), and `revoke_template_authorization` has a
       **two-arg signature** so the helper's `public\.${name}\s*\(` prefix already matches.
    3. List ↔ migration reconciliation: every `CREATE OR REPLACE FUNCTION public.<name>(` in the
       088 forward migration is in the declared 2-RPC set (regression guard mirroring 087's, so a future
       edit that reintroduces `session_replication_role` on a 3rd function cannot stay green).
    4. Down migration restores `session_replication_role` (`expect(downExecutable).toMatch(/session_replication_role/i)`).

## Implementation Phases

### Phase 0 — Preconditions (verify before writing)
- `cat apps/web-platform/supabase/migrations/063_workspace_member_actions.sql` — copy the exact current
  `purge_workspace_member_actions()` body (lines around the `$$ … $$;` block) as the pre-088 baseline.
- `cat apps/web-platform/supabase/migrations/053_template_authorizations.sql` — copy the exact current
  `revoke_template_authorization(text, text)` body as the pre-088 baseline.
- Confirm 088 is the next free number: `ls apps/web-platform/supabase/migrations/ | grep '^08'`
  (087 is the highest — verified).
- Confirm vitest include glob covers the new test: `test/**/*.test.ts` (vitest.config.ts:44) matches
  `test/supabase-migrations/088-…test.ts` (087's test runs under the same glob — verified).

### Phase 1 — RED (cq-write-failing-tests-before)
- Write `088-worm-bypass-non-erasure-rpcs.test.ts`. Run it; it fails because the 088 migration files
  do not yet exist (`readFileSync` ENOENT) → red as required.

### Phase 2 — GREEN
- Write `088_worm_bypass_non_erasure_rpcs.sql` (both RPC re-CREATEs with the GUC swap).
- Write `088_worm_bypass_non_erasure_rpcs.down.sql` (both RPC re-CREATEs with the original
  `session_replication_role` bodies).
- Run the new test → green. Run the 087 test too (unchanged, must stay green).

### Phase 3 — Full suite + migration lint
- Run the web-platform vitest suite for the migration-shape directory:
  `./node_modules/.bin/vitest run test/supabase-migrations/` (from `apps/web-platform`).
- If the repo has a migration-apply DEV smoke path, exercise it DEV-only (see Observability
  `discoverability_test`). Never apply against PROD; never create synthetic rows on PROD
  (`hr-dev-prd-distinct-supabase-projects`).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `088_worm_bypass_non_erasure_rpcs.sql` exists; `grep -c session_replication_role` on it returns `0`.
- [ ] `grep -c "SET LOCAL app.worm_bypass = 'on'"` on the forward migration returns `2` (one per RPC).
- [ ] `grep -c "SET LOCAL app.worm_bypass = 'off'"` on the forward migration returns `2`.
- [ ] Each RPC block retains `SET search_path = public, pg_temp` (asserted by the test's per-RPC `search_path` check).
- [ ] `revoke_template_authorization` body still contains the 8-value `p_reason` enum gate and the
      `auth.uid() IS NOT NULL AND p_reason <> 'founder_revoked'` founder-attribution gate (diff shows
      only the two bypass lines + comment changed vs. mig 053 body).
- [ ] `purge_workspace_member_actions` body still contains the `created_at < now() - interval '7 years'`
      DELETE and the `RAISE LOG 'audit_retention_purge …'` line.
- [ ] `088_…down.sql` exists; `grep -c session_replication_role` returns `≥ 2` (both RPCs restored).
- [ ] New test file `088-worm-bypass-non-erasure-rpcs.test.ts` passes; the list↔migration reconciliation
      test reports zero uncovered functions.
- [ ] 087 test still passes (no regression on the shared trigger functions / shared assertions).
- [ ] PR body uses `Closes #4702`.

### Post-merge (operator)
- [ ] Migration 088 applied to PROD via the existing `web-platform-release.yml#migrate` job on merge to
      `main` (path-filtered on `apps/web-platform/**`). Automation: handled by the release pipeline — no
      separate operator apply step. Verify applied via `mcp__plugin_supabase_supabase__*` (read-only:
      confirm the function body no longer contains `session_replication_role`).

## Domain Review

**Domains relevant:** Engineering (CTO), Legal/Compliance (CLO), Product (CPO)

### Engineering (CTO)
**Status:** reviewed (carry-forward from 087 / inline)
**Assessment:** Pure RPC-body swap mirroring a merged, tested precedent (087). No trigger, table, index,
RLS, or grant changes. `SECURITY DEFINER` + pinned `search_path` preserved
(`cq-pg-security-definer-search-path-pin-pg-temp`). Idempotent `CREATE OR REPLACE`, Supabase-wrapped
transaction (no outer `BEGIN/COMMIT`). The deepen-plan precedent-diff gate (Phase 4.4) should diff the
088 RPC bodies against the 087 anonymise-RPC pattern and against the mig 063/053 originals to confirm
byte-identical bodies modulo the two bypass lines + comments.

### Legal/Compliance (CLO)
**Status:** reviewed (inline)
**Assessment:** Unblocks two compliance-load-bearing operations broken on PROD: Art. 5(1)(e)
storage-limitation (the 7-year purge currently no-ops, so audit PII over-retains) and Art. 7(3)
withdrawal-as-easy-as-consent (founder revoke currently 500s). gdpr-gate runs at Phase 2.7 (migration +
`.sql` surface).

### Product/UX Gate
**Tier:** none
**Decision:** N/A — no new user-facing page, flow, or component. The fix repairs an existing failing
API path (`/api/template-authorizations/revoke`) and a backend cron; no UI surface is created or
restyled.

## Infrastructure (IaC)

Skipped — no new infrastructure. Migration 088 edits two existing function bodies on an
already-provisioned Supabase project; it is applied by the existing `web-platform-release.yml#migrate`
job (path-filtered on `apps/web-platform/**`) on merge to `main`. No new server, secret, vendor, cron,
DNS, or TLS resource. The pg_cron schedule that invokes `purge_workspace_member_actions` already exists
(mig 063); 088 does not touch the cron.job entry.

## Observability

```yaml
liveness_signal:
  what: "purge_workspace_member_actions RAISE LOG 'audit_retention_purge table=workspace_member_actions deleted_count=%' fires non-zero after the next 7-year-old row exists; revoke succeeds (HTTP 200 at /api/template-authorizations/revoke)"
  cadence: "purge: pg_cron schedule (mig 063); revoke: per founder/auto-revoke call"
  alert_target: "Supabase Postgres logs (cron.job_run_details auto-captures purge runs); Sentry for revoke-route 5xx"
  configured_in: "mig 063 RAISE LOG (purge); apps/web-platform/app/api/template-authorizations/revoke/route.ts reportSilentFallback (revoke)"
error_reporting:
  destination: "Sentry (revoke route already wraps the RPC error and reports op=revoke_template_authorization); Postgres log for the purge 42501 (pre-fix) / success (post-fix)"
  fail_loud: true
failure_modes:
  - mode: "re-arm line dropped (app.worm_bypass leaks past the write)"
    detection: "guardrail test asserts SET LOCAL app.worm_bypass='off' present in each RPC block"
    alert_route: "CI test failure (blocks merge)"
  - mode: "purge still no-ops (session_replication_role left in body)"
    detection: "guardrail test: grep session_replication_role == 0 on forward migration"
    alert_route: "CI test failure"
  - mode: "revoke regression (reason-enum gate or authz block accidentally dropped during re-CREATE)"
    detection: "AC diff-check: body byte-identical to mig 053 modulo bypass lines"
    alert_route: "PR review + AC checklist"
logs:
  where: "Supabase Postgres logs (RAISE LOG audit_retention_purge); Sentry (revoke 5xx)"
  retention: "Supabase log retention (project default); Sentry retention"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/supabase-migrations/088-worm-bypass-non-erasure-rpcs.test.ts && ./node_modules/.bin/vitest run test/supabase-migrations/087-worm-bypass-privilege-independence.test.ts"
  expected_output: "both test files pass; 088 reports 2 RPCs covered with app.worm_bypass on/off and zero session_replication_role references"
```

## Test Scenarios

- **Offline migration-shape (primary, CI default):** the new vitest file (mirrors 087). Asserts the GUC
  swap, the re-arm, `search_path` pinning, zero `session_replication_role` in the forward migration, and
  list↔migration reconciliation. Runs without a live DB.
- **DEV-only live probe (optional, if a DEV Supabase apply path is wired):** apply 088 on DEV; insert a
  synthesized `workspace_member_actions` row with `created_at` > 7 years old (synthesized fixture only,
  `cq-test-fixtures-synthesized-only`), call `purge_workspace_member_actions()` as `postgres`/service
  role, assert `deleted_count = 1` and no `42501`. Call `revoke_template_authorization(<hash>,
  'founder_revoked')` as an authenticated test user on a synthesized authorization row, assert
  `revoked_at` set and no `42501`. **DEV only** — never on PROD (`hr-dev-prd-distinct-supabase-projects`).

## Risks & Mitigations

- **Risk: re-CREATE drops a line of the revoke authz/reason gate.** Mitigation: copy the exact pre-088
  body from mig 053 and change only the two bypass lines + the inline bypass comment; AC requires a
  diff-check confirming byte-identity modulo those lines.
- **Risk: the re-arm GUC line is omitted** (the security-load-bearing line per 087's test rationale).
  Mitigation: guardrail test pins `SET LOCAL app.worm_bypass = 'off'` per RPC.
- **Risk: down migration desync** — down must restore the *exact* pre-088 bodies. Mitigation: down test
  asserts `session_replication_role` is present; copy the pre-088 bodies verbatim into the down file.
- **Precedent diff (deepen-plan Phase 4.4 — performed):** the canonical WORM-bypass-RPC form is
  established by migration 087 §3 (nine anonymise RPCs). Side-by-side against the 088 targets:

  | Aspect | 087 anonymise RPCs (precedent) | 088 `purge` / `revoke` (this plan) | Match? |
  |---|---|---|---|
  | Bypass set | `SET LOCAL app.worm_bypass = 'on';` | same | yes |
  | Re-arm | `SET LOCAL app.worm_bypass = 'off';` (after the single write) | same | yes |
  | Security clause | `SECURITY DEFINER` | `SECURITY DEFINER` (both 063/053 originals are DEFINER — verified) | yes |
  | `search_path` | `SET search_path = public, pg_temp` | preserved verbatim | yes |
  | Dollar-quote tag | mix (`$fn$` and `$$`) | both targets use `$$` (verified in 063/053) | n/a (test helper handles both) |
  | DML scope | one UPDATE/DELETE between on/off | purge: one DELETE; revoke: one UPDATE | yes |

  No deviation from precedent. The only structural difference from the 087 RPCs is the **absence of an
  `auth.uid()` block in `purge`** (it is a service-role/postgres-only cron RPC, gated by its existing
  `GRANT EXECUTE … TO postgres` + `REVOKE … FROM PUBLIC, anon, authenticated`) — this matches the
  original mig 063 body and is correct; do NOT add an authz block. `revoke` keeps its existing
  `auth.uid()` + reason-enum gate. **No novel pattern; precedent is migration 087.**

## Open Code-Review Overlap

None (check ran against the 3 planned files; no open `code-review`-labeled issue names them).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or
  omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- Both target RPCs use the `$$` dollar-quote tag (not `$fn$`); the 087 `fnBlock` regex helper matches
  either, but when reusing it verify the non-greedy `$\1$` close still terminates on the function's own
  `$$;` and not a later one. `revoke_template_authorization` is two-arg — the helper's
  `public\.${name}\s*\(` prefix is signature-agnostic, so it matches.
- Do NOT touch the trigger functions in 088 — they were already converted by 087, and editing them here
  would create a redundant second `CREATE OR REPLACE` that the 087 test's list↔migration reconciliation
  does not cover (and is needless drift). 088 is RPC-body-only.
