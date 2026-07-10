---
title: "fix(security): revoke residual anon/authenticated EXECUTE on service-role-only SECURITY DEFINER RPCs"
issue: 6306
type: fix
classification: security
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-07-11
---

# 🐛 fix(security): revoke residual anon/authenticated EXECUTE on service-role-only SECURITY DEFINER RPCs (#6306)

## Overview

`public.find_stuck_active_conversations(integer)` is a `SECURITY DEFINER` function whose EXECUTE
privilege is still held by `anon` **and** `authenticated`. Because its definer rights bypass base-table
RLS on `conversations`, any authenticated (or anonymous) caller can enumerate **every tenant's**
stuck-active `(conversation_id, user_id)` pairs — a cross-tenant information disclosure / IDOR primitive.

**Root cause (confirmed against `037_stuck_active_finder_rpc.sql:63-64`):** Supabase's default privileges
grant EXECUTE on every new `public` function to `anon`, `authenticated`, `service_role` at `CREATE` time.
Migration 037 ran only `revoke all on function … from public` — which removes the PUBLIC grant but leaves
the **explicit** `anon`/`authenticated` grants intact. Live `proacl`:
`{postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}`.

**Fix:** a forward-only grant-change migration (`128_*`) that revokes EXECUTE from `anon`, `authenticated`
(and defensively `PUBLIC`) on the affected functions, restoring 037's stated service-role-only intent —
plus a `verify/128_*.sql` sentinel asserting the deny state, mirroring the jti-deny sentinel class
(`verify/069_jti_deny_grant_restore.sql`). The migration also folds in the **sibling sweep** the issue
mandates: the identical `revoke-from-public`-only defect exists on the concurrency-slot RPCs.

**Precedent is well-established in the repo** — this migration is a mechanical application of the pattern
already used correctly by:
- `027_mtd_cost_aggregate.sql:67-69` (`REVOKE … FROM PUBLIC; FROM authenticated; FROM anon`),
- `116_worktree_write_lease.sql:203-205` (`revoke all … from public, anon, authenticated`),
- `069_jti_deny_grant_restore.sql` (the pure grant-change migration + verify-sentinel + down-migration shape this plan copies verbatim).

Migration `125_list_conversations_enriched.sql:172-179` documents the same DEFINER grant-hygiene rule in
its header ("GRANT hygiene inverts the DEFINER precedents (027/037 …)") — 037 is the one precedent that
got it wrong; this fix closes that gap.

## Research Reconciliation — Spec vs. Codebase

Two premises in the issue body are **stale** and reshape the plan (Phase 0.6 premise validation):

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "Un-baseline the `test.fails` entry in `test/rls-fuzz/rpc-cases.ts`" (AC4) | `test/rls-fuzz/` and `rpc-cases.ts` **do not exist**. The RLS/authz-fuzz harness (#6256) is **OPEN / not merged**. `find … -iname '*rpc-cases*'` returns nothing. | The un-baseline AC cannot be satisfied — there is no file to edit. **Re-scoped** to a cross-reference note: this fix's durable regression guard is the `verify/128` sentinel (always-on, deploy-time). When #6256's harness lands, its `rpc-cases.ts` entry for these RPCs MUST be a **normal denial assertion**, never a baselined `test.fails`. Recorded in `decision-challenges.md`; `/ship` posts a cross-ref comment to #6256. **Do NOT block this P1 fix on the unmerged harness.** |
| "Discovered by the harness (#6256, **ADR-103**)" | **ADR-103** is `ADR-103-dedicated-host-boot-heartbeats-require-guarded-reprovision-path.md` — unrelated to the fuzz harness. | Citation mis-numbered; harmless to the fix. Noted so the plan does not inherit a false ADR reference. No new ADR is authored (see §Architecture Decision). |

Everything else in the issue held: migration `037_stuck_active_finder_rpc.sql` exists with exactly the
described `revoke-from-public`-only shape; the `verify/` sentinel directory exists with the jti-deny
sentinels the issue cites as the pattern class; `#6256` and the harness are real (just not yet merged).

## User-Brand Impact

**If this lands broken, the user experiences:** an authenticated attacker enumerates other tenants'
`(conversation_id, user_id)` pairs, and — via the sibling slot RPCs — can `release`/`acquire`/`touch`
**another user's** concurrency slot, locking a free-tier user (cap=1) out of starting any conversation.

**If this leaks, the user's data/workflow is exposed via:** direct PostgREST RPC
(`POST /rest/v1/rpc/find_stuck_active_conversations`) callable by any `anon`/`authenticated` JWT, bypassing
`conversations` RLS through SECURITY DEFINER rights — a cross-tenant confidentiality break (GDPR Art. 5(1)(f))
and a denial-of-service IDOR on the slot RPCs.

**Brand-survival threshold:** single-user incident.

> CPO sign-off required at plan time before `/work` begins. `user-impact-reviewer` will be invoked at
> review-time (handled by the review skill's conditional-agent block). In this headless one-shot run the
> CPO framing is carried in this section; review-time enforcement remains the diff-shaped gate.

## Affected functions — sibling audit

Enumerated by scanning every `security definer` function in `apps/web-platform/supabase/migrations/*.sql`
whose only grant statement is `revoke … on function … from public`:

| Function (signature) | Migration | Current grant shape | Verdict |
|---|---|---|---|
| `find_stuck_active_conversations(integer)` | 037 | revoke public only → +service_role | **FIX (primary)** — cross-tenant read |
| `acquire_conversation_slot(uuid, uuid, integer, uuid)` | 093 (current 4-arg) | revoke public only → +service_role | **FIX** — write IDOR (slot theft) |
| `release_conversation_slot(uuid, uuid)` | 029 | revoke public only → +service_role | **FIX** — write IDOR (slot free) |
| `touch_conversation_slot(uuid, uuid)` | 029 | revoke public only → +service_role | **FIX** — write IDOR (heartbeat) |
| `release_slot_on_archive()` | 036 | revoke public only, `returns trigger` | **FIX (defense-in-depth)** — trigger fn, not RPC-exposable by PostgREST; low practical risk but same shape, revoke for uniformity |
| `acquire_conversation_slot(uuid, uuid, integer)` (3-arg) | 029 | — | **N/A** — dropped by `093:42` (`DROP FUNCTION IF EXISTS`) |
| `sum_user_mtd_cost(uuid, timestamptz)` | 027 | revoke public+authenticated+anon | SAFE (exemplar — the correct pattern) |
| `acquire/touch/release_worktree_lease(…)` ×3 | 116 | revoke public+anon+authenticated | SAFE (exemplar) |
| `list_conversations_enriched(…)` | 125 | revoke public+anon, **GRANT authenticated** | SAFE (intentionally authenticated-callable — different case) |

**Safety of revoking `anon`/`authenticated`:** every FIX target is invoked only by server-side code
through the **service-role** client — `server/concurrency.ts:1` (`createServiceClient`) for the slot RPCs
and `server/agent-runner.ts:117-118` (`createServiceClient`) for the finder reaper. `release_slot_on_archive`
runs as a trigger. No authenticated/anon caller path exists, so the revoke is behavior-preserving for
legitimate callers and closes the attacker path.

## Architecture Decision (ADR/C4)

**No ADR / C4 change.** This restores the *already-decided* service-role-only intent of migration 037; it
introduces no ownership/tenancy boundary move, no new substrate, no resolver/trust-boundary change. The
grant-hygiene rule is already recorded in `027`/`069`/`125` migration headers and
`cq-pg-security-definer-search-path-pin-pg-temp`. C4 completeness check: grant/privilege changes alter no
C4 element — no new external actor, external system, container, or access relationship (the affected RPCs
and their sole service-role caller are already modeled as internal server↔DB edges). "No C4 impact" is
therefore supported, not asserted blindly.

## Implementation Phases

### Phase 0 — Preconditions (re-verify at /work time)
1. Confirm the next free migration ordinal against `origin/main` (`ls …/migrations/ | grep -oE '^[0-9]+' | sort -n | tail -1`). `128` is **provisional** — a sibling PR may claim it; the migration runner rejects duplicate numbers, so re-check and renumber the migration + verify + down + test in the same edit if `128` is taken.
2. Re-confirm live `proacl` shape on the 5 targets is still `revoke-from-public`-only (guards against a sibling PR fixing one first).

### Phase 1 — Migration + down (`128_revoke_definer_rpc_residual_grants.sql`)
Model on `069_jti_deny_grant_restore.sql` verbatim (header prose → REVOKE block → `COMMENT ON FUNCTION`).
For each of the 5 FIX targets emit:
```sql
revoke execute on function public.<fn>(<args>) from anon, authenticated;
-- defense-in-depth (revoke-on-empty is a no-op):
revoke execute on function public.<fn>(<args>) from public;
```
Add a `COMMENT ON FUNCTION` on `find_stuck_active_conversations` documenting service-role-only intent + #6306.
`128_*.down.sql` restores the pre-fix grants (`grant execute … to anon, authenticated`) purely for
rollback machinery, mirroring `069_*.down.sql`.

### Phase 2 — Verify sentinel (`verify/128_definer_rpc_residual_grants_revoked.sql`)
Follow the `(check_name TEXT, bad INT)` contract enforced by `scripts/run-verify.sh`. `UNION ALL`:
- For each of the 5 targets: `has_function_privilege('anon', 'public.<fn>(<args>)', 'EXECUTE')` → `bad=1 if true`; same for `'authenticated'`; same for `'public'`.
- For the 4 non-trigger targets: `has_function_privilege('service_role', …)` → `bad=1 if false` (load-bearing regression guard — the service-role grant MUST survive, mirroring `verify/069` check (3)).
- Do NOT assert a service_role grant on `release_slot_on_archive()` (trigger fn needs none).

### Phase 3 — Migration content test (`test/supabase-migrations/128-revoke-definer-rpc-residual-grants.test.ts`)
Mirror the existing `036-release-slot-on-archive.test.ts` convention: source-grep assertions that migration 128
contains a `revoke execute … from anon, authenticated` line for each of the 5 functions, and that
`verify/128_*.sql` asserts `has_function_privilege(...'anon'...)` and `...'authenticated'...` for each.
(The runtime deny state is proven by the deploy-time verify sentinel; this test guards the migration
*content* in CI without needing a live stack.)

### Phase 4 — Cross-reference #6256 (no code)
Record in `specs/feat-one-shot-6306-rpc-grant-revoke/decision-challenges.md` that when the #6256 fuzz
harness lands, its `test/rls-fuzz/rpc-cases.ts` entry for `find_stuck_active_conversations` must be a plain
denial assertion (not a baselined `test.fails`). `/ship` renders this into the PR body and posts a cross-ref
comment on #6256.

## Files to Create
- `apps/web-platform/supabase/migrations/128_revoke_definer_rpc_residual_grants.sql`
- `apps/web-platform/supabase/migrations/128_revoke_definer_rpc_residual_grants.down.sql`
- `apps/web-platform/supabase/verify/128_definer_rpc_residual_grants_revoked.sql`
- `apps/web-platform/test/supabase-migrations/128-revoke-definer-rpc-residual-grants.test.ts`
- `knowledge-base/project/specs/feat-one-shot-6306-rpc-grant-revoke/decision-challenges.md` (Phase 4 note)

## Files to Edit
- None. (Issue AC4's `test/rls-fuzz/rpc-cases.ts` edit is re-scoped — the file does not exist; see Research Reconciliation.)

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `AC1` Migration `128_*.sql` revokes EXECUTE from `anon` and `authenticated` for all 5 audited functions (grep: 5 × `from anon, authenticated`).
- [ ] `AC2` Migration also revokes from `public` (defense-in-depth) for each target.
- [ ] `AC3` `128_*.down.sql` exists and restores the pre-fix `anon`/`authenticated` grants (rollback-only).
- [ ] `AC4` `verify/128_*.sql` emits, for each of the 5 targets, an `anon` deny check + an `authenticated` deny check + a `public` deny check (`bad=1` when the role still has EXECUTE), and for the 4 non-trigger targets a `service_role` grant-present check (`bad=1` when service_role LACKS EXECUTE).
- [ ] `AC5` `verify/128_*.sql` conforms to the `(check_name, bad)` two-column contract (`run-verify.sh` parses it; every row is `(TEXT, INT)`).
- [ ] `AC6` `128-revoke-definer-rpc-residual-grants.test.ts` passes: `cd apps/web-platform && ./node_modules/.bin/vitest run test/supabase-migrations/128-revoke-definer-rpc-residual-grants.test.ts`.
- [ ] `AC7` Typecheck clean: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] `AC8` No FIX target is reachable from any authenticated/anon caller path in `server/` (grep confirms `concurrency.ts` + `agent-runner.ts` use `createServiceClient`; documented in §sibling audit).
- [ ] `AC9` `find_stuck_active_conversations` carries a `COMMENT ON FUNCTION` documenting service-role-only intent + Ref #6306.
- [ ] `AC10` PR body uses `Closes #6306` (this fix is complete at merge — the migration auto-applies via `web-platform-release.yml#migrate`, and verify runs in the same pipeline; unlike ops-remediation, there is no post-merge operator write, so `Closes` is correct).

### Post-merge (pipeline-automated, no operator action)
- [ ] `PM1` `web-platform-release.yml#migrate` applies migration 128 on merge to main (path-filtered auto-apply — no operator SSH/CLI).
- [ ] `PM2` `verify-migrations` job runs `verify/128_*.sql` post-apply; all `bad=0` (deny state confirmed against prod).
- [ ] `PM3` `/ship` posts a cross-ref comment on #6256 recording the rls-fuzz un-baseline follow-up (Phase 4).

## Observability

```yaml
liveness_signal:
  what: verify/128 sentinel (has_function_privilege deny checks on 5 RPCs)
  cadence: every merge to main touching apps/web-platform/supabase/** (post-apply)
  alert_target: verify-migrations CI job (fails the release pipeline on bad>0)
  configured_in: .github/workflows/web-platform-release.yml (verify-migrations job) + apps/web-platform/scripts/run-verify.sh
error_reporting:
  destination: GitHub Actions annotations (::error::<file>/<check_name>: FAIL) — release job hard-fails, blocking deploy
  fail_loud: true
failure_modes:
  - mode: a future CREATE OR REPLACE / GRANT re-opens anon or authenticated EXECUTE
    detection: verify/128 anon+authenticated+public deny checks return bad=1
    alert_route: verify-migrations job failure → release pipeline red
  - mode: the fix accidentally revokes service_role EXECUTE (breaks the reaper / slot RPCs)
    detection: verify/128 service_role grant-present checks return bad=1
    alert_route: verify-migrations job failure → release pipeline red
logs:
  where: GitHub Actions run logs for the verify-migrations job (::group:: per verify file)
  retention: GitHub Actions default (90 days)
discoverability_test:
  command: "doppler run -c prd -- bash apps/web-platform/scripts/run-verify.sh   # runs verify/128 against prod, exit 1 on any bad>0 — NO ssh"
  expected_output: "ok 128_definer_rpc_residual_grants_revoked/<check_name> (bad=0) for every check; Verify summary: N passed, 0 failed"
```

## Domain Review

**Domains relevant:** none (backend security/DB tooling change; no Product/UI surface).

No files under `components/**`, `app/**/page.tsx`, or any UI-surface glob — the mechanical UI-surface
override does not fire. Product/UX Gate: NONE. Engineering-security is the implementing domain (default);
`user-impact-reviewer` is enrolled at review-time via the `single-user incident` threshold, not a domain
leader spawn.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` cross-referenced against `037_stuck_active_finder_rpc`,
`concurrency`, `find_stuck_active_conversations`, `acquire_conversation_slot`, and `rls-fuzz` returned zero
matches.

## GDPR / Compliance

Touches a `.sql` migration surface (regex trigger), but the change is **remediation** — it *closes* a
cross-tenant confidentiality gap (GDPR Art. 5(1)(f) integrity/confidentiality) and introduces **no new
processing activity, data flow, or external transfer**. No Article 30 register entry is added. Net compliance
posture improves. No Critical gdpr-gate finding is expected; full-skill invocation is low-value for a
defense-strengthening grant revoke.

## Test Scenarios
1. **Deny state (deploy-time):** after apply, `has_function_privilege('authenticated', 'public.find_stuck_active_conversations(integer)', 'EXECUTE')` → `false` (verify/128, bad=0).
2. **Service-role preserved:** `has_function_privilege('service_role', …)` → `true` for the 4 non-trigger RPCs — the reaper + slot flows keep working.
3. **Reaper regression:** `agent-runner-stuck-active-reaper.test.ts` + `agent-runner-reaper-cadence.test.ts` remain green (service-role path unchanged).
4. **Slot flows regression:** concurrency acquire/release/touch tests remain green (service-role client path unchanged).
5. **Migration content:** `128-revoke-definer-rpc-residual-grants.test.ts` fails if any FIX target is missing its `from anon, authenticated` revoke.

## Sharp Edges
- **Migration ordinal is provisional.** `128` may be claimed by a sibling PR in the one-shot pipeline; the migration runner rejects duplicate numbers. /work Phase 0 re-checks next-free against `origin/main` and renumbers migration + verify + down + test together if needed.
- **`CREATE OR REPLACE` does not reset privileges** — a later migration that re-`CREATE OR REPLACE`s any of these 5 functions will NOT re-grant anon/authenticated (grants persist across replace), so the fix is durable; but a *new* function with the same defect would slip past — the verify sentinel only covers these 5. (Broader class enforcement is the province of #6256's fuzz harness.)
- **`release_slot_on_archive()` returns `trigger`** — PostgREST does not expose trigger-returning functions as RPC endpoints and a direct call errors on absent `TG_*` context, so its practical disclosure risk is nil; it is included purely for shape-uniformity. Do NOT assert a `service_role` grant on it in verify/128.
- **`has_function_privilege` role-name literals:** PUBLIC is the lowercase literal `'public'` (per `verify/069` check (5)); use exact signatures incl. arg types (`(integer)`, `(uuid, uuid, integer, uuid)`) or the check silently no-ops on a signature mismatch.
- **Do not `Closes #6256`** — the rls-fuzz harness is a separate open issue; only cross-reference it.
- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6 — this one is filled with the concrete artifact/vector/threshold.

## Alternative Approaches Considered
| Approach | Verdict |
|---|---|
| Fix only `find_stuck_active_conversations` (issue's literal primary) | Rejected — the sibling slot RPCs share the identical defect and carry a *worse* (write IDOR) impact; a security fix that leaves known-identical siblings exposed is half a fix at `single-user incident` threshold. Issue AC explicitly mandates the sibling audit. |
| `ALTER DEFAULT PRIVILEGES` to stop future default grants | Rejected — does not remediate the 5 *existing* grants (the live exposure); orthogonal hardening better owned by #6256 / a dedicated migration-lint. Out of scope. |
| Block on #6256 to un-baseline rpc-cases.ts | Rejected — #6256 is unmerged; a P1 cross-tenant disclosure must not wait on an unrelated harness. The verify/128 sentinel is the durable guard; #6256 gets a cross-ref note. |
| TS integration test as the primary guard | Rejected — the `verify/*.sql` sentinel (deploy-time, runs against prod) is the canonical always-on guard for grant state, per the jti-deny precedent. The TS test guards migration *content* only. |
