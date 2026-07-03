---
title: "test(observability): live semantic/atomicity test for check_and_record_byok_delegation_use"
issue: 5938
ref: 5920
branch: feat-one-shot-5938-byok-delegation-atomicity-test
type: chore
lane: cross-domain # no spec.md present — defaulted to cross-domain (TR2 fail-closed)
brand_survival_threshold: none
created: 2026-07-03
---

# 🧪 test(observability): live semantic/atomicity test for `check_and_record_byok_delegation_use` (Ref #5920)

## Enhancement Summary

**Deepened on:** 2026-07-03

**Halt gates (all pass):** 4.6 User-Brand Impact present (threshold `none` +
inline reason; the single test-file path `apps/web-platform/test/server/…` does
NOT match the sensitive-path regex, so no scope-out bullet is even required).
4.7 Observability present (no runtime surface → 5-field schema N/A, documented).
4.8 no PAT-shaped variable. 4.9 no UI surface → skip.

**Precedent-diff (Phase 4.4):** the test mirrors the merged cap-RPC precedent
`byok-kill-switch.atomicity.tenant-isolation.test.ts` (#5920 / `b020ebecf`);
the load-bearing *difference* between the two RPCs is documented in Sharp Edges
(cap RPC returns a `kill_tripped` signal + always inserts → Invariant D expects
`N` audit rows; delegation RPC **throws** on breach + inserts only on pass →
invariant is `audit == K`). No novel pattern introduced.

**Verified load-bearing claims (Phase 4.45 verify-the-negative):**
1. Hourly/daily cap branches (084:449-454, 463-468) `RAISE` with **no** preceding
   `INSERT` → the over-cap call persists nothing → `audit == K` (admitted calls
   only). Confirmed against the RPC body.
2. `check_and_record_byok_delegation_use` does **not** call the resolver; the
   per-turn consent re-gate (084:404-425) fires **only if a withdrawal EXISTS**.
   Zero withdrawals seeded ⇒ re-gate is a no-op. Confirmed.
3. Cap predicate is single-clause strict `>` (`v_hourly_spent + v_this_cost >
   v_row.hourly_usd_cap_cents`, 084:449) — the `== cap` call passes; a `>=`
   regression makes it raise. This is the boundary the test pins.
4. `audit_byok_use.workspace_id` is **NOT NULL** (mig 055/059) — the daily
   isolation seed INSERT must carry the grantor's `workspace_id`. Seed columns:
   `{invocation_id, founder_id (grantor), workspace_id (grantor workspace),
   agent_role, token_count, unit_cost_cents, delegation_id, ts (now()−2h)}`;
   `attribution_shift_reason` NULL. Only UPDATE/DELETE are WORM-blocked (037);
   INSERT with explicit `ts` is allowed.

## Overview

Add a **live-DB semantic/atomicity test** for the BYOK delegation cap RPC
`check_and_record_byok_delegation_use` (migration
`084_byok_delegation_withdrawals.sql`, §7 lines 344-480), gated by
`TENANT_INTEGRATION_TEST=1` against dev Supabase.

The prior byok RPC body-marker drift guard (merged 2026-07-03, commit
`b020ebecf`, #5920) added a live *semantic* atomicity test only for the **cap**
RPC `record_byok_use_and_check_cap`
(`apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts`,
Invariant C). The **delegation** RPC's only live guards are:

1. the #5920 body-marker probe (asserts the RAISE strings
   `hourly_cap_exceeded` / `daily_cap_exceeded` and row `FOR UPDATE` are
   *present* — a necessary-not-sufficient tripwire; marker presence does not
   prove the `> v_row.<cap>_cap_cents` comparison is intact), and
2. a **partial** sequential hourly-cap test that already exists (see Research
   Reconciliation) — loose boundary, sequential-only, no self-diagnosis.

This plan adds the missing **strict-`>` boundary precision**, **daily-cap
marker coverage**, and **concurrency/FOR-UPDATE (no-TOCTOU-double-spend)**
proof, reusing the #5920 self-diagnosing pattern (embed the live
`pg_get_functiondef` body in the failing `expect()` message).

**Scope:** one new test file. No production code, schema, or migration changes.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality (verified) | Plan response |
| --- | --- | --- |
| "The delegation RPC has **no companion live semantic test**." | Partly stale. `byok-delegations.tenant-isolation.test.ts:537-594` (`AC-hourly-cap-exceeded`) already proves the RPC RAISEs `hourly_cap_exceeded` and writes exactly one audit row — but with a **loose** boundary (cost 4 passes, then cost 2 → 6 > 5 trips; the `== cap` call is never exercised), **sequential-only**, and **no** self-diagnosis. | Do NOT duplicate the existing hourly raise. Scope the new file to the genuine delta: (a) strict-`>` boundary (a call landing **exactly at cap passes**, `+1` over trips) for BOTH hourly and daily; (b) `daily_cap_exceeded` marker (existing test never trips daily); (c) concurrent N-call FOR UPDATE / no-double-spend; (d) `pg_get_functiondef` self-diagnosis. Reference the existing test in the header so a future reader sees the split. |
| "at the hourly/**daily** cap boundary … RAISEs `daily_cap_exceeded`" | The table CHECK `byok_delegations_hourly_le_daily` (064) forces `hourly ≤ daily`, and the RPC checks hourly **first** (084:449) then daily (084:463). With all calls in one hour, hourly always trips at-or-before daily → **daily can never trip in isolation from live calls alone.** | Isolate daily by **pre-seeding aged `audit_byok_use` rows** with `ts = now() − 2h` (inside the 24h daily window, outside the 1h hourly window). Verified insertable: `audit_byok_use.ts` is `timestamptz NOT NULL DEFAULT now()` and only UPDATE/DELETE are WORM-blocked (037); INSERT with an explicit `ts` + `delegation_id` is allowed and service_role bypasses RLS. See Sharp Edges. |
| RPC signature for `pg_get_functiondef` | `check_and_record_byok_delegation_use(uuid, uuid, int, int, uuid, text)` — confirmed 084:344-351 + REVOKE 084:482. | Use `'public.check_and_record_byok_delegation_use(uuid,uuid,int,int,uuid,text)'::regprocedure`. |
| porsager `postgres` devDep present | Confirmed `apps/web-platform/package.json:91` `"postgres": "^3.4.9"`. | Reuse the guarded diagnostic-connection pattern verbatim from the cap test. |

## User-Brand Impact

**If this lands broken, the user experiences:** a false-green CI signal — a
future RV rewrite that keeps the RAISE strings (so the #5920 marker probe stays
green) but silently flips `>` to `>=`, drops the `FOR UPDATE` lock, or
miscomputes the cap SUM would ship undetected. The guarded RPC enforces BYOK
delegation spend caps; a broken cap check bills the **grantor** for unbounded
grantee usage (ADR-040 threshold = unauthorized invoice).

**If this leaks, the user's data is exposed via:** N/A — test-only, reads the
RPC and writes synthetic `tenant-isolation-*@soleur.test` fixtures against dev
Supabase. No production data, no new processing activity, no user-facing
surface.

**Brand-survival threshold:** none, reason: this change is a test that *guards*
a single-user-incident-class RPC; the test itself landing broken exposes no
user data and has no runtime surface — its worst failure is a missed drift
(caught additionally by the #5920 marker tripwire) or a false red.

## Implementation Phases

### Phase 0 — Preconditions (verify before writing)

- [x] Confirm the RPC regprocedure resolves live:
      `pg_get_functiondef('public.check_and_record_byok_delegation_use(uuid,uuid,int,int,uuid,text)'::regprocedure)`
      returns a body (dev, via `DATABASE_URL_POOLER`). Fixed at `<date>` in
      the deepen-plan research phase.
- [x] Confirm `audit_byok_use` accepts a service-role INSERT with an explicit
      backdated `ts` + `delegation_id` (needed for the daily-isolation seed).
- [x] Confirm the `unit` vitest project glob `test/**/*.test.ts`
      (`vitest.config.ts:44`) matches the new path.

### Phase 1 — New test file

Create `apps/web-platform/test/server/byok-delegation.atomicity.tenant-isolation.test.ts`.

**Header + gating (mirror the cap test):**
- `describe.skipIf(!INTEGRATION_ENABLED)` on `TENANT_INTEGRATION_TEST === "1"`.
- `.tenant-isolation.test.ts` suffix is **load-bearing** for the path filter in
  `.github/workflows/tenant-integration.yml` (detect-changes → heavy suite).
- Guarded porsager `postgres` diagnostic connection opened from
  `DATABASE_URL_POOLER` with `ssl: { rejectUnauthorized: false }` (dev-only,
  verbatim from the cap test), `null` when the URL is absent → fallback string.
- `fetchLiveDelegationRpcBody()` — guarded (never throws), returns the live
  `pg_get_functiondef` body or a fallback message. Embedded in failure
  messages ONLY on the doomed path (green runs never open the query).
- Synthesized fixtures only (`cq-test-fixtures-synthesized-only`); per-run
  isolation via `randomBytes`-derived email. Orphan-row `afterAll` acceptance
  pattern (WORM + ON DELETE RESTRICT), mirroring the cap + delegations tests
  (deferred sweeper #3934 — no duplicate scope-out).

**Fixture helper (`grantDelegation`):** reuse the merged pattern from
`byok-delegations.tenant-isolation.test.ts` — `createSyntheticUser` (grantor +
grantee, read back `workspace_members.workspace_id`), `addMember(grantee →
grantor workspace)`, then `service.rpc("grant_byok_delegation", {...})` with
per-test caps. Each test creates a **fresh delegation** (distinct
`delegation_id`) so the per-`delegation_id` cap SUM isolates tests. **No
acceptance or withdrawal rows** are seeded: the RPC's per-turn consent re-gate
(084:404) only fires when a withdrawal EXISTS, and `check_and_record` does not
call the resolver, so zero withdrawals = re-gate passes.

**Named constants (tuned together; assert `CAP_CENTS % COST_CENTS === 0` in
`beforeAll`, mirroring the cap test):** `COST_CENTS = 100`
(`token_count=10 × unit_cost_cents=10`), `CAP_CENTS = 500`, `N = 10`, so the
boundary passes at cumulative `== 500` (call 5) and trips at `600` (call 6);
`K = CAP_CENTS / COST_CENTS = 5` calls admitted.

### Phase 2 — Test cases

**Test A — hourly strict-`>` boundary (sequential).** Grant with
`hourly=CAP_CENTS`, `daily=1_000_000` (max ceiling, never trips). Fire calls
one at a time, awaiting each:
- Calls 1..K (cumulative 100…500) return `error === null` — including the
  **`== cap` call K** (cumulative exactly 500), which is the load-bearing
  strict-`>` proof (a `>=` regression would make call K raise).
- Call K+1 (would reach 600) returns a non-null error whose `message` matches
  `/byok_delegations:hourly_cap_exceeded/`.
- `audit_byok_use` count for the delegation `== K` (the RAISE path writes no
  audit row).
- On any mismatch, embed `fetchLiveDelegationRpcBody()` in the `expect()`
  message.

**Test B — daily strict-`>` boundary (sequential, aged-seed isolation).** Grant
with `daily=CAP_CENTS`, `hourly=CAP_CENTS` (CHECK forces `hourly ≤ daily`).
Pre-seed aged `audit_byok_use` rows (`ts = now() − 2h`, `delegation_id` set,
`workspace_id` = grantor workspace — the column is NOT NULL per mig 055/059,
`founder_id` = grantor) summing to `CAP_CENTS − COST_CENTS = 400` — inside the
24h window, outside the 1h window. Then:
- Live call 1: hourly-window spend `= 0 + 100 = 100 ≤ 500` (ok); daily-window
  spend `= 400 + 100 = 500 ≤ 500` (ok, `== cap` boundary) → passes.
- Live call 2: hourly `= 100 + 100 = 200 ≤ 500` (does NOT trip); daily
  `= 500 + 100 = 600 > 500` → error matches
  `/byok_delegations:daily_cap_exceeded/`. This proves it is the **daily**
  branch (not hourly) that raises, and the strict-`>` boundary for daily.
- Self-diagnosis embed on mismatch.

**Test C — concurrency / FOR UPDATE / no-TOCTOU-double-spend.** Grant with
`hourly=CAP_CENTS`, `daily=1_000_000`. Fan out `N=10` concurrent
`service.rpc("check_and_record_byok_delegation_use", …)` via
`Promise.allSettled` (each a distinct `invocation_id`; concurrency is
client-side, serialization is DB-side via `FOR UPDATE` at 084:370):
- Exactly `K = 5` calls settle with `error === null` (admitted).
- Exactly `N − K = 5` calls settle with an error matching
  `/byok_delegations:hourly_cap_exceeded/`.
- `audit_byok_use` count for the delegation `== K` and total recorded spend
  `== CAP_CENTS` — **the atomicity signal**: without `FOR UPDATE`, concurrent
  callers reading the same pre-INSERT SUM snapshot would each pass and INSERT,
  producing `> K` audit rows and spend `> cap` (double-spend).
- supabase-js `.rpc()` resolves *fulfilled* with `{data, error}` (does not
  reject); the pass/fail split lives in `.error`, so `allSettled` entries are
  all `fulfilled` — partition on `error === null`.
- Compute a single `willFail` predicate; embed `fetchLiveDelegationRpcBody()`
  in every failing `expect()` message on the doomed path only.

### Phase 3 — Verify

- [x] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (typecheck;
      NOT `npm run -w` — repo root declares no `workspaces`).
- [x] Gated skip path is green by default (no env):
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/byok-delegation.atomicity.tenant-isolation.test.ts --project unit`
      → suite reports `skipped` (describe.skipIf), does not error.
- [ ] Live run (deepen-plan / QA phase, dev Doppler):
      `cd apps/web-platform && doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 npm run test:ci -- test/server/byok-delegation.atomicity.tenant-isolation.test.ts --project unit`
      → Tests A/B/C pass.
- [ ] Deliberate-drift self-diagnosis smoke (optional, dev-only, ROLLBACK): in a
      `BEGIN; CREATE OR REPLACE FUNCTION … (flip `>` to `>=`); <run Test A>;
      ROLLBACK;` confirm the failure message contains the embedded live body.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] New file `apps/web-platform/test/server/byok-delegation.atomicity.tenant-isolation.test.ts`
      exists with the `.tenant-isolation.test.ts` suffix.
- [ ] Header references BOTH the cap-RPC precedent
      (`byok-kill-switch.atomicity.tenant-isolation.test.ts`) AND the existing
      partial hourly test (`byok-delegations.tenant-isolation.test.ts:537`) so
      the scope split is discoverable.
- [ ] Test A asserts the **`== cap` call passes** (strict-`>` proof) and call
      K+1 errors with `byok_delegations:hourly_cap_exceeded`; audit count `== K`.
- [ ] Test B trips `byok_delegations:daily_cap_exceeded` via aged-seed
      isolation, and asserts the hourly branch did NOT raise.
- [ ] Test C: exactly `K` calls admitted, `N−K` raise the hourly marker, and
      `audit_byok_use` count for the delegation `== K` (no double-spend).
- [ ] All three tests embed the live `pg_get_functiondef` body in the failing
      `expect()` message via a guarded fetch that never throws and never runs on
      a green path.
- [ ] `tsc --noEmit` clean; default (un-gated) run reports the suite `skipped`.
- [ ] `CAP_CENTS % COST_CENTS === 0` asserted in `beforeAll`.

### Post-merge (operator)
- None. The heavy suite runs automatically on the PR via
  `tenant-integration.yml` (detect-changes → tenant job) with dev-Supabase
  secrets; no separate operator step. `Automation: covered by tenant-integration.yml`.

## Observability

This change *is* an observability artifact (a semantic drift guard), but it adds
no runtime code/infra surface (Files-to-Edit is a single file under
`apps/web-platform/test/`, outside `server/`/`src/`/`infra/`), so the 5-field
runtime schema (Phase 2.9) does not apply. Discoverability of a drift:

- **Detection surface:** `tenant-integration.yml` job on the PR (and push-to-main
  / merge_group), failing red with the live `pg_get_functiondef` body inline in
  the CI log — no SSH, no manual pg introspection (the #5917 remediation cost
  this closes for the delegation RPC).
- **Complementary tripwire:** the #5920 dev-migration-drift body-marker probe
  (`byok-rpc-markers.json` already lists `check_and_record_byok_delegation_use`)
  remains the fast structural signal; this test is the semantic authority.

## Domain Review

**Domains relevant:** Engineering (advisory).

Test-only change with no user-facing surface, no schema/migration change, no new
infrastructure, and no new processing activity. It mirrors a merged precedent
(#5920 / `b020ebecf`) reviewed under the same threshold. The substantive
correctness lens (DB atomicity, `FOR UPDATE` serialization, strict-`>` boundary,
aged-seed daily isolation) is carried by the deepen-plan triad
(data-integrity-guardian + architecture-strategist + code-simplicity) invoked in
the next pipeline step.

No Product/UX surface (no files under `components/**`, `app/**/page.tsx`,
`app/**/layout.tsx`) → Product/UX Gate: NONE.

## GDPR / Compliance Gate

Skipped: the change touches no schema, migration, auth flow, or API route. It
reads the RPC and writes synthetic dev fixtures. `audit_byok_use` rows created
by the test are synthetic and covered by the existing orphan-acceptance /
deferred-sweeper posture (#3934). No new processing activity, no regulated-data
surface introduced.

## Infrastructure (IaC)

Skipped: no server, service, cron, secret, vendor, DNS, cert, or firewall
resource introduced. Pure test against already-provisioned dev Supabase.

## Sharp Edges

- **Daily-cap isolation is impossible from live calls alone** — the
  `byok_delegations_hourly_le_daily` CHECK (064) forces `hourly ≤ daily` and the
  RPC checks hourly first (084:449), so any spend that exceeds `daily` also
  exceeds `hourly` in a single-hour test window. The aged-seed
  (`ts = now() − 2h`) is the ONLY way to preload the 24h window while leaving the
  1h window empty. If a future migration adds an INSERT trigger to
  `audit_byok_use` or makes `ts` non-insertable, Test B must be re-approached
  (e.g., a test-only `clock_timestamp()` shim is NOT available — do not attempt).
- **The RAISE path writes no audit row for the over-cap call** (unlike the
  grace/consent/expired branches which INSERT-then-RAISE, then get rolled back
  by the RAISE anyway). So `audit count == K` (admitted calls only) is the
  correct double-spend invariant — do NOT expect `N` audit rows (that is the cap
  RPC's Invariant D, which does not transfer: `record_byok_use_and_check_cap`
  returns a signal row and always inserts; the delegation RPC throws and inserts
  only on pass).
- **supabase-js `.rpc()` does not reject on a P0001 RAISE** — it resolves
  fulfilled with `{data:null, error:{...}}`. `Promise.allSettled` entries are all
  `fulfilled`; partition on `.error`, not on `status`.
- **Do NOT set `hourly > daily`** to isolate daily — the grant RPC / table CHECK
  rejects it (`hourly_usd_cap_cents out of range`, SQLSTATE 22003, per the
  existing delegations test 214-227).
- **`.tenant-isolation.test.ts` suffix is load-bearing** — without it the
  `tenant-integration.yml` detect-changes filter never fires the heavy suite on
  this file's own PR, so it would silently never run live.
- A plan whose `## User-Brand Impact` section is empty or placeholder fails
  `deepen-plan` Phase 4.6 — it is filled above (threshold `none` with reason).

## References

- Migration: `apps/web-platform/supabase/migrations/084_byok_delegation_withdrawals.sql` §7 (lines 344-480), cap checks 449 / 463, `FOR UPDATE` 370.
- Precedent test (cap RPC): `apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts` (Invariant C, self-diagnosing fetch, guarded pg connection).
- Existing partial hourly test: `apps/web-platform/test/server/byok-delegations.tenant-isolation.test.ts:537-594`.
- Marker map: `byok-rpc-markers.json` (already lists the delegation RPC).
- Schema: `byok_delegations` 064:71 (caps + `hourly_le_daily` CHECK); `audit_byok_use` 037:31 (`ts` insertable, WORM UPDATE/DELETE only).
- Workflow: `.github/workflows/tenant-integration.yml` (detect-changes → tenant job).
- Prior commit: `b020ebecf` (#5920).
