---
lane: single-domain
requires_cpo_signoff: true
issue: 3981
pr: pending
branch: feat-one-shot-3981-byok-killswitch-atomicity
worktree: .worktrees/feat-one-shot-3981-byok-killswitch-atomicity
brand_survival_threshold: single-user incident
---

# Live-DB atomicity integration test for `record_byok_use_and_check_cap` (#3981)

## Enhancement Summary

**Deepened on:** 2026-05-18

**Verifications performed (deepen pass):**

- All cited PR/issue numbers resolved live via `gh`:
  `#3940` MERGED ("feat(runtime): PR-F Inngest trigger layer..."),
  `#3893` MERGED ("feat(ci): tenant-integration workflow..."),
  `#3981` OPEN (this issue), `#3934` OPEN (synthetic-fixture sweeper),
  `#3887` CLOSED (PR-E), `#3244` OPEN (umbrella).
- File existence on `main` verified: migration `046_runtime_cost_state.sql`,
  workflow `.github/workflows/tenant-integration.yml`, sibling test
  `audit-byok-use.tenant-isolation.test.ts` — all present on `main`.
- Migration line refs re-verified via `sed -n`: strict `>` predicate
  confirmed at line 227 (`IF v_paused_at IS NULL AND v_total > v_cap`),
  idempotent `IS NULL` guard on the UPDATE confirmed at line 231,
  default `runtime_cost_cap_cents = 2000` and nullable `runtime_paused_at`
  (no DEFAULT) confirmed at lines 55-56.
- Workflow path-filter glob re-verified at lines 36 and 42 of
  `.github/workflows/tenant-integration.yml`:
  `'apps/web-platform/test/server/**.tenant-isolation.test.ts'`.
- All cited AGENTS.md rule IDs verified ACTIVE:
  `hr-weigh-every-decision-against-target-user-impact`,
  `hr-gdpr-gate-on-regulated-data-surfaces`,
  `hr-dev-prd-distinct-supabase-projects`,
  `hr-menu-option-ack-not-prod-write-auth`,
  `cq-pg-security-definer-search-path-pin-pg-temp`,
  `cq-test-fixtures-synthesized-only`.
- Learning paths verified — corrected one path: the operator-surfaces
  learning is at
  `knowledge-base/project/learnings/best-practices/2026-04-29-docs-fix-verification-greps-must-span-operator-surfaces.md`
  (under `best-practices/` subdir), not at the top-level path the
  draft cited.
- `supabase-js` installed version pinned at **2.99.2** (`package.json`
  declares `^2.49.0`; `node_modules` resolves to 2.99.2). Per the
  supabase-js v2 contract each `.rpc()` returns an independent thenable
  fetch; `Promise.allSettled` over N `.rpc()` calls produces N
  independent HTTP requests against PostgREST, which the test relies
  on for true client-side parallelism.
- Sibling tenant-isolation test count on `main`: 15 files. The CI
  invocation `npm run test:ci -- test/server/ --project unit` picks
  up all 15 + this new file (16 total) — no name-collision risk.

### Key improvements over draft

1. **Learning-path correction** (Sharp Edges section): the operator-surfaces
   learning citation now points at the correct `best-practices/`
   subdirectory.
2. **Explicit supabase-js version pin** (Risks + Research Insights):
   2.99.2 confirmed against installed code, not training data.
3. **Confirmed concurrency observability via PostgREST sessions**:
   the parallel-RPC contract is now backed by a verified version-pin,
   not just a generic claim about "v2 supports this".
4. **GDPR gate output added** with explicit Article 30 carry-forward
   reasoning + TS-05 cleanup citation to #3934.

### New considerations discovered

- `service_role` bypasses RLS by default on Supabase — the
  `UPDATE users SET runtime_cost_cap_cents = 500 WHERE id = founder.id`
  in `beforeAll` succeeds without an explicit policy. This is the
  intended path (the cap is operator-managed); the test relies on it
  the same way `audit-byok-use.tenant-isolation.test.ts` relies on
  service-role for fixture observation.

## Overview

Adds a single tenant-isolation integration test that proves the
`record_byok_use_and_check_cap` plpgsql RPC (migration 046) is atomic under
concurrent BYOK ledger writes for the same founder. The RPC is the kill-switch
that closes the TOCTOU race left open by PR-F's v1 CTE form (Kieran P1.1
in plan `2026-05-17-feat-pr-f-inngest-trigger-layer-plan.md`); current
coverage is structural-only (statement-order regex assertions in
`test/supabase-migrations/046-runtime-cost-state.test.ts`). This test
gates the runtime invariant: under N concurrent calls at cap-boundary,
the `FOR UPDATE` lock on `public.users` serializes callers so that
cumulative cents increases monotonically by exactly the per-call cost,
`kill_tripped` fires deterministically on the first crossing, and
`runtime_paused_at` is stamped exactly once.

Scope is exactly one test file. No production code change. No workflow
change (the substrate landed in PR #3893 and recent runs are green on
`main`). The only new artifact is
`apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts`.

## User-Brand Impact

**If this lands broken, the user experiences:** a silent regression in
the kill-switch RPC ships unobserved. The next time PR-F's caller path
is wired (production agent runner invoking `record_byok_use_and_check_cap`
inside `runWithByokLease`), a TOCTOU race at cap-boundary lets a user be
billed past their `runtime_cost_cap_cents` ceiling, OR an attacker
rapid-fires concurrent BYOK requests to drain the founder's per-hour
credit allowance before `runtime_paused_at` stamps.

**If this leaks, the user's money is exposed via:** unbounded Anthropic
API spend on the user's own BYOK key in the band between cap and
cap × N-concurrent. At default cap (2000 cents = $20/hr) with 10
concurrent in-flight calls each costing 100 cents, the worst-case spend
is $30 against a $20/hr cap — a 50% overage absorbed by the user
directly because BYOK = user-owned Anthropic billing.

**Brand-survival threshold:** single-user incident. A single instance
of cap-overage on a founder's BYOK key is a brand-survival event in
the alpha period: the BYOK contract is "we will not bill you past
your declared cap" and any breach is a per-user trust break.

**Three failure modes this test gates against** (per premise framing):

1. **TOCTOU regression.** A future RV rewrite of the RPC (e.g.,
   collapsing back to CTE form, dropping `FOR UPDATE`, switching
   `LANGUAGE plpgsql` → `LANGUAGE sql`) silently passes the structural
   test (which only pins statement order) and ships the race. This
   live-DB test is the only consumer that detects the regression
   pre-merge.
2. **Silent skip.** The test ships with a misconfigured gate (e.g.,
   `INTEGRATION_ENABLED` typo, filename outside the path-filter glob)
   and vitest reports green without running anything. The
   `describe.skipIf` pattern + filename `*.tenant-isolation.test.ts`
   suffix are load-bearing for the path filter at
   `.github/workflows/tenant-integration.yml:36,42`.
3. **Fixture leak.** A synthetic founder's `runtime_cost_cap_cents`
   override or `audit_byok_use` rows pollute concurrent CI runs from
   sibling tenant-isolation suites that share the same dev Supabase.
   Mitigated by per-test-run isolated founder (fresh
   `randomBytes(8).toString("hex")` email) — but the audit-row WORM
   trigger means rows cannot be deleted on teardown, so per-test
   data isolation comes from the per-test founder, not per-test
   cleanup.

## Research Insights

### Premise validation (corrections against feature description)

The feature description's RPC signature is **wrong**. Validated against
the actual migration at
`apps/web-platform/supabase/migrations/046_runtime_cost_state.sql:173-239`:

| Premise claim | Reality |
|---|---|
| `record_byok_use_and_check_cap(p_founder_id, p_user_id, p_jti, p_cost_cents, p_cap_cents)` | `record_byok_use_and_check_cap(p_invocation_id uuid, p_founder_id uuid, p_agent_role text, p_token_count int, p_unit_cost_cents int)` |
| Cap passed per-call | Cap lives on `public.users.runtime_cost_cap_cents` (mutable per-tenant; default 2000) |
| Cost = `p_cost_cents` | Cost = `token_count × unit_cost_cents` |
| "Exactly K succeed, rest rejected, no insert after threshold" | RPC appends `audit_byok_use` row FIRST on every call ("accounting is sacred"); `kill_tripped` is the signal; `runtime_paused_at` flips exactly once at first crossing. The caller (`runWithByokLease`, not yet wired) is responsible for refusing further calls after seeing `runtime_paused_at IS NOT NULL`. |
| "K = 5 out of 10 succeed" | All 10 calls insert audit rows. `kill_tripped` is true on the call where cumulative-after-INSERT exceeds cap. With cap=500, cost=100/call: calls 1-5 return `kill_tripped=false`, calls 6-10 return `kill_tripped=true`. |

### Cap-crossing arithmetic (load-bearing)

The RPC's threshold predicate is `v_total > v_cap` (STRICT greater-than)
at `046_runtime_cost_state.sql:227`. With cap=500, cost=100/call,
N=10 concurrent:

- Cumulative after each call (post-INSERT): 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000
- `kill_tripped`: false, false, false, false, **false** (500 not > 500), **true** (600 > 500), true, true, true, true
- First-trip call: call 6 (the first to observe cumulative=600)
- Total `audit_byok_use` rows inserted: exactly 10
- `runtime_paused_at` stamps: exactly once (idempotent UPDATE guarded by `IS NULL` at line 230)

### Path-filter compliance

`.github/workflows/tenant-integration.yml:36,42` triggers on:
`apps/web-platform/test/server/**.tenant-isolation.test.ts`

The filename MUST end in `.tenant-isolation.test.ts` to:
1. Trigger the workflow on its own PR.
2. Match the `npm run test:ci -- test/server/ --project unit` invocation
   at line 161 (vitest `unit` project's `include` covers `test/**/*.test.ts`
   per `vitest.config.ts:30`).

Filename: **`byok-kill-switch.atomicity.tenant-isolation.test.ts`**.

The structural test at
`test/supabase-migrations/046-runtime-cost-state.test.ts:34-38` cites a
different name (`046-runtime-cost-state.atomicity.integration.test.ts`)
in commentary; that name does NOT match the path filter and is descriptive
only — we use the path-filter-compliant name.

### Pattern source: which sibling test to mirror

Two candidates exist in `apps/web-platform/test/server/`:

- **`audit-byok-use.tenant-isolation.test.ts`** — closest fit. Same
  underlying RPC family (`write_byok_audit` → `audit_byok_use` table),
  same WORM-trigger constraint making audit teardown impossible, same
  ON DELETE RESTRICT FK on `founder_id`, documents the single-orphan-row
  acceptance + scope-out to a synthetic-fixture sweeper (deferred-scope-out
  #3934 per `knowledge-base/legal/compliance-posture.md:99`).
- **`agent-runner.tenant-isolation.test.ts`** — broader pattern (two
  founders, multi-table seed), useful for the
  `assertSynthetic`/`SYNTHETIC_EMAIL_PATTERN`/`requireEnv` helper
  shape and beforeAll/afterAll timeout (`30_000`).

Plan adopts: helpers + skeleton from `audit-byok-use.tenant-isolation.test.ts`
(single founder, fewer moving parts) + 30 s timeouts from `agent-runner`.

### supabase-js concurrent RPC support

`supabase-js` v2 (`@supabase/supabase-js`) executes each `.rpc()` call
as an independent `fetch` against PostgREST. `Promise.all`/`Promise.allSettled`
over an array of `.rpc()` calls fires N independent HTTP requests in
parallel; PostgREST issues one Postgres session per request from its
connection pool. Each session enters the RPC transaction independently,
and Postgres-side row locking via `SELECT ... FOR UPDATE` is the
serialization point. This is the exact pattern the test needs: the
parallelism happens client-side, the serialization happens DB-side via
the lock, and the assertion observes the post-settlement state.

**Installed-version pin (deepen-verified):** `apps/web-platform/package.json`
declares `"@supabase/supabase-js": "^2.49.0"`; `node_modules` resolves
to **2.99.2**. The plan body assumes the v2 thenable contract for
`.rpc()`; any future major bump (v3) must re-verify the parallel-fetch
contract before this test is trusted.

### Connection-pooling note

`scripts/run-migrations.sh:9-70` prefers `DATABASE_URL_POOLER` for
migration apply, but PostgREST in front of supabase-js connects via
its own pooled connection. Concurrent `.rpc()` calls do NOT funnel
through a single pgbouncer connection in transaction mode in a way
that would mask the race — each PostgREST request is a separate
session. This is consistent with how the existing
`audit-byok-use.tenant-isolation.test.ts` makes service-role calls
and observes per-call state changes.

### Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open
--json number,title,body --limit 200` against the path `apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts` — file does not yet exist, no overlap.

## Files to Create

- `apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts`
  - Single new test file. ~180-220 LoC.
  - Structure mirrors `audit-byok-use.tenant-isolation.test.ts` skeleton.

## Files to Edit

None. The CI substrate is in place at
`.github/workflows/tenant-integration.yml` (added in PR #3893, recent
runs green). The path filter and `npm run test:ci -- test/server/`
invocation pick up the new file automatically once filename matches
the glob.

## Implementation Phases

### Phase 0 — Preconditions (verify before writing test)

P0.1. **Confirm migration is applied on dev.** Required for the test to
pass locally. Verify via:

```bash
doppler run -p soleur -c dev -- bash apps/web-platform/scripts/run-migrations.sh --bootstrap=skip
```

The CI workflow already runs this step at `tenant-integration.yml:140-147`,
so CI-side application is automatic. Local-dev preflight per the same
command.

P0.2. **Confirm `DOPPLER_TOKEN_DEV_SCHEDULED` is provisioned.** The
workflow asserts this at `tenant-integration.yml:83-91`. No new
provisioning required for this PR.

P0.3. **Verify supabase-js parallel RPC shape.** Read
`apps/web-platform/node_modules/@supabase/supabase-js/dist/main/index.d.ts`
(or the local `package.json` resolved version) to confirm `.rpc(name, args)`
returns a `Promise<{ data, error }>` that supports `Promise.allSettled` /
`Promise.all` over an array. This is standard supabase-js v2 contract; the
verification is a 30-second grep, not a research task.

P0.4. **Confirm cap arithmetic against the RPC's threshold predicate.**
Re-read `046_runtime_cost_state.sql:227` to confirm the predicate is
`v_total > v_cap` (strict, not `>=`). The expected results table in
"Cap-crossing arithmetic" above is derived from this exact predicate.

### Phase 1 — Write the test file (RED → GREEN)

P1.1. **Scaffold the file** with the standard tenant-isolation helpers
copied verbatim from `audit-byok-use.tenant-isolation.test.ts:21-66`:

- `INTEGRATION_ENABLED` gate (`process.env.TENANT_INTEGRATION_TEST === "1"`).
- `SYNTHETIC_EMAIL_PATTERN` regex (`/^tenant-isolation-[a-f0-9]{16}@soleur\.test$/`).
- `syntheticEmail()` + `assertSynthetic()` + `requireEnv()` helpers.
- `describe.skipIf(!INTEGRATION_ENABLED)` wrapper.

P1.2. **beforeAll fixture seed.** One synthetic founder (sufficient
for the atomicity test; no second founder needed for cross-tenant
checks):

```typescript
beforeAll(async () => {
  const url = requireEnv("SUPABASE_URL");
  requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
  const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  requireEnv("SUPABASE_JWT_SECRET");

  service = createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  assertSynthetic(founder.email);
  const { data, error } = await service.auth.admin.createUser({
    email: founder.email,
    password: randomBytes(16).toString("hex"),
    email_confirm: true,
  });
  expect(error, `createUser(${founder.email}) failed`).toBeNull();
  if (data.user?.id) founder.id = data.user.id;
  expect(founder.id).toBeTruthy();

  // Override the cap to 500 cents to force a deterministic crossing
  // at call 6 of N=10. Only touches the synthetic founder's row.
  const { error: capError } = await service
    .from("users")
    .update({ runtime_cost_cap_cents: 500 })
    .eq("id", founder.id);
  expect(capError, "set test cap to 500 cents").toBeNull();
}, 30_000);
```

P1.3. **afterAll teardown** with WORM-trigger acknowledgment:

```typescript
afterAll(async () => {
  // audit_byok_use rows for the synthetic founder are WORM-protected
  // (UPDATE/DELETE raises P0001 — see audit_byok_use_no_mutate trigger
  // at 037_audit_byok_use.sql). The founder_id FK is ON DELETE RESTRICT,
  // so auth.admin.deleteUser would 23503 with audit rows present. Mirrors
  // the orphan-row acceptance pattern documented in
  // audit-byok-use.tenant-isolation.test.ts afterAll: single per-run
  // orphan is acceptable for closed-preview alpha; long-running CI
  // nightlies should adopt the synthetic-fixture sweeper tracked as
  // deferred-scope-out #3934 (per compliance-posture.md PR-E entry).
  //
  // No-op teardown. Per-run isolation is guaranteed by the per-run
  // randomBytes-derived email in beforeAll, not by row cleanup.
}, 30_000);
```

P1.4. **The atomicity test.** Single test case (one
`Promise.allSettled` fan-out, multiple assertions on the settled
results). Single test is intentional: spinning 10 parallel RPCs is a
shared workload that produces one set of observations; splitting into
multiple `test()` blocks would re-do the workload and double the
dev-Supabase load.

```typescript
test("10 concurrent RPC calls at cap-boundary serialize via FOR UPDATE", async () => {
  const N = 10;
  const COST_CENTS = 100; // token_count=10 × unit_cost_cents=10
  const CAP_CENTS = 500;
  const FIRST_TRIP_CALL = 6; // first call where cumulative > cap

  const calls = Array.from({ length: N }, () =>
    service.rpc("record_byok_use_and_check_cap", {
      p_invocation_id: randomUUID(),
      p_founder_id: founder.id,
      p_agent_role: "test-atomicity",
      p_token_count: 10,
      p_unit_cost_cents: 10,
    }),
  );
  const settled = await Promise.allSettled(calls);

  // Invariant A: every call succeeds at the protocol level (no
  // RPC errors). The kill-switch is a signal in the return TABLE,
  // not a thrown error.
  for (const [i, result] of settled.entries()) {
    expect(result.status, `call ${i}: settled`).toBe("fulfilled");
    if (result.status === "fulfilled") {
      expect(result.value.error, `call ${i}: rpc error`).toBeNull();
      expect(result.value.data?.length, `call ${i}: row count`).toBe(1);
    }
  }

  // Collect cumulative_cents from every settled call. Sort
  // ascending — concurrent fire means we don't know the order
  // ahead of time; the contract is "every value from 100..N*100
  // appears exactly once".
  const cumulatives = settled
    .map((r) => r.status === "fulfilled" ? r.value.data![0].cumulative_cents : -1)
    .sort((a, b) => a - b);

  // Invariant B: cumulative_cents takes exactly {100, 200, ..., 1000}
  // with no duplicates and no gaps. A TOCTOU race would produce
  // duplicates (two callers reading the same pre-INSERT snapshot
  // and recording the same SUM) or skipped values; FOR UPDATE
  // serialization guarantees this monotone progression.
  const expectedCumulatives = Array.from({ length: N }, (_, i) => (i + 1) * COST_CENTS);
  expect(cumulatives).toEqual(expectedCumulatives);

  // Invariant C: kill_tripped is true on exactly N - (FIRST_TRIP_CALL - 1)
  // calls. With cap=500 and N=10, calls observing cumulative
  // 100/200/300/400/500 return kill_tripped=false (500 is NOT > 500),
  // and 600/700/800/900/1000 return kill_tripped=true.
  // Total true-count = 5. Pair (cumulative, kill_tripped) and assert
  // the boundary per call.
  const pairs = settled
    .map((r) => r.status === "fulfilled" ? r.value.data![0] : null)
    .filter((x): x is NonNullable<typeof x> => x !== null)
    .sort((a, b) => a.cumulative_cents - b.cumulative_cents);
  for (const pair of pairs) {
    const expectedTripped = pair.cumulative_cents > CAP_CENTS;
    expect(pair.kill_tripped, `at cumulative=${pair.cumulative_cents}`).toBe(expectedTripped);
  }

  // Invariant D: audit_byok_use row count for this founder equals N.
  // Accounting is sacred — all 10 calls insert, even the kill-tripped
  // ones. RLS-bypass via service-role for fixture observation only.
  const { data: rows, error: countError } = await service
    .from("audit_byok_use")
    .select("id", { count: "exact" })
    .eq("founder_id", founder.id)
    .eq("agent_role", "test-atomicity");
  expect(countError).toBeNull();
  expect(rows?.length).toBe(N);

  // Invariant E: runtime_paused_at is non-null AND was set within a
  // tight window. Exactly-one-stamp is guaranteed by the idempotent
  // UPDATE guard (runtime_paused_at IS NULL) at migration 046:230.
  // We observe the post-state: a single non-null timestamp.
  const { data: userRow, error: userError } = await service
    .from("users")
    .select("runtime_paused_at, runtime_cost_cap_cents")
    .eq("id", founder.id)
    .single();
  expect(userError).toBeNull();
  expect(userRow?.runtime_cost_cap_cents).toBe(CAP_CENTS);
  expect(userRow?.runtime_paused_at).not.toBeNull();
  const stampedAt = new Date(userRow!.runtime_paused_at!).getTime();
  expect(stampedAt).toBeGreaterThan(Date.now() - 60_000);
  expect(stampedAt).toBeLessThanOrEqual(Date.now() + 1_000);
}, 30_000);
```

P1.5. **Local verification.** Run with the exact CI invocation form
to prove byte-parity with workflow execution:

```bash
cd apps/web-platform
doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 \
  npm run test:ci -- test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts --project unit
```

Also run the skip-fast form to prove the gate works:

```bash
cd apps/web-platform
npm run test:ci -- test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts --project unit
# Expected: "1 skipped" (the describe.skipIf gate fires when env var unset)
```

### Phase 2 — Ship

P2.1. Commit + push. PR body uses `Closes #3981` (the issue is a
deferred test addition, not an ops-remediation — `Closes` is correct).
PR title: `test: live-DB atomicity for record_byok_use_and_check_cap kill-switch (#3981)`.

P2.2. Verify the workflow fires on the PR (path-filter match).
Expected check: `Tenant integration (dev-Supabase) / tenant-integration`
appears in the PR's checks list. If the workflow does NOT fire, the
filename glob is wrong — fix before merge.

P2.3. After merge, the test continues running on every PR that
touches `apps/web-platform/test/server/**.tenant-isolation.test.ts`,
`apps/web-platform/server/**`, or `apps/web-platform/supabase/migrations/**`
(per the workflow's `paths` filter). No additional wiring required.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. File exists at
      `apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts`.
      Verify: `test -f apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts`.
- [ ] AC2. Filename matches the workflow path-filter glob.
      Verify: `git ls-files | grep -E '^apps/web-platform/test/server/.*\.tenant-isolation\.test\.ts$' | grep byok-kill-switch.atomicity`.
- [ ] AC3. Test is silently SKIPPED (correctly — vitest reports
      `1 skipped`, not `0 tests`) when `TENANT_INTEGRATION_TEST` is unset.
      Verify locally:
      `cd apps/web-platform && npm run test:ci -- test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts --project unit 2>&1 | grep -E 'skipped|passed'`.
- [ ] AC4. Test PASSES locally with the gate set + dev Doppler creds.
      Verify locally:
      `cd apps/web-platform && doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 npm run test:ci -- test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts --project unit`.
- [ ] AC5. Test invokes `service.rpc("record_byok_use_and_check_cap", {...})`
      with the FIVE-arg signature `(p_invocation_id, p_founder_id,
      p_agent_role, p_token_count, p_unit_cost_cents)`. Verify:
      `grep -nE 'p_invocation_id.*p_founder_id.*p_agent_role.*p_token_count.*p_unit_cost_cents' apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts | wc -l` returns ≥1.
- [ ] AC6. Test fans out N=10 concurrent RPC calls via
      `Promise.allSettled` (not sequential `await` in a loop).
      Verify: `grep -nE 'Promise\.allSettled' apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts`.
- [ ] AC7. Test asserts the FIVE invariants A–E from Phase 1 P1.4:
      protocol success per call (A), cumulative sorts to
      `[100, 200, ..., 1000]` (B), kill_tripped boundary at strict
      `cumulative > cap` per call (C), audit_byok_use row count = N (D),
      `runtime_paused_at` non-null + tight-window (E). Each invariant is
      a distinct `expect(...)` assertion.
      Verify counts: `grep -cE '^[[:space:]]*expect\(' apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts` returns ≥ 12 (4 fixture-seed + 8 invariant assertions, conservatively).
- [ ] AC8. Test seeds an isolated synthetic founder (fresh
      `randomBytes(8).toString("hex")@soleur.test`) per `beforeAll`.
      Verify: `grep -nE 'tenant-isolation-\$\{randomBytes\(8\)' apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts`.
- [ ] AC9. Test sets the synthetic founder's `runtime_cost_cap_cents`
      to 500 via service-role UPDATE on `public.users` (so the cap
      crossing is deterministic at call 6).
      Verify: `grep -nE 'runtime_cost_cap_cents.*500' apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts`.
- [ ] AC10. afterAll is a documented no-op (WORM-trigger + ON DELETE
      RESTRICT make audit-row + user-row teardown impossible; orphan-row
      is acceptable per the existing `audit-byok-use.tenant-isolation.test.ts`
      pattern). Verify: file contains an `afterAll` with a comment
      referencing the WORM-trigger orphan-row pattern AND #3934.
      `grep -nE '#3934|WORM|orphan' apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts`.
- [ ] AC11. Workflow `Tenant integration (dev-Supabase)` fires on this
      PR. Verify post-push: `gh pr checks <PR-N> | grep -i tenant-integration`.
- [ ] AC12. Workflow `Tenant integration (dev-Supabase)` GREEN on this
      PR. Verify post-push: `gh pr checks <PR-N> | grep -i tenant-integration | grep -v fail`.
- [ ] AC13. No other workflow on this PR turns red due to side effects
      of this file. Verify: `gh pr checks <PR-N>`.

### Post-merge (operator)

- [ ] AC14. (Automated by `/soleur:ship`) `gh pr merge --squash --auto`
      lands the PR; the issue auto-closes via `Closes #3981` in the PR body.

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| supabase-js coalesces N parallel `.rpc()` calls into 1 connection in transaction mode (pgbouncer), masking the race | Low | PostgREST in front of supabase-js issues 1 PG session per HTTP request; concurrency is observable. Existing tenant-isolation tests prove this in practice. |
| Dev Supabase rate-limits 10 concurrent service-role calls | Low | Service-role is unconstrained on dev; existing tests fan out similar parallelism (audit-byok-use does 2-founder seed + 5+ calls). |
| `runtime_paused_at` from a prior test run persists and the new run's `users` row inherits a non-null stamp | Zero | Per-run founder is freshly created in `beforeAll`. `runtime_paused_at` defaults to NULL on insert via `handle_new_user` trigger. |
| `audit_byok_use` rows from a prior failed run pollute the 1-hour SUM window for this founder | Zero | Fresh per-run founder ⇒ no historical rows. |
| Concurrent run of another `*.tenant-isolation.test.ts` suite locks `public.users` in a way that blocks this test | Low | Each test uses its own synthetic founder ⇒ `FOR UPDATE` locks are per-row and do not cross-contaminate. |
| WORM teardown leaves orphan audit rows on dev | Accepted | Per existing `audit-byok-use.tenant-isolation.test.ts` precedent; tracked under deferred-scope-out #3934 (synthetic-fixture sweeper). Do NOT file a duplicate. |
| Future RV rewrite of RPC breaks all 5 invariants — assertion message clarity matters for fast root-cause | Medium | Each `expect(...)` uses a contextual message arg (`expect(x, "call N: row count").toBe(1)`). |
| Test uses non-deterministic time-window assertion (Invariant E) and flakes on slow CI | Low | 60 s lookback window is generous; tenant-integration job timeout is 15 min total. |

### Research Insights (deepen pass)

**Parallel-RPC observability — verified empirically against installed code:**

- supabase-js 2.99.2 `.rpc()` returns a thenable that resolves to
  `{ data, error }`. Each `.rpc()` invocation is an independent
  `fetch()`; no client-side coalescing or queuing. `Promise.allSettled`
  therefore fans out N true HTTP requests.
- PostgREST in front of dev Supabase serves each request from its own
  PG session. Concurrency is observable at the DB layer; the
  `FOR UPDATE` lock at migration 046 line 198 is the serialization
  point.
- This is the same shape used by `audit-byok-use.tenant-isolation.test.ts`
  (single-RPC observations) and `agent-runner.tenant-isolation.test.ts`
  (multi-table seed + tenant-scoped client reads) — no novel client
  pattern introduced.

**Cap-crossing arithmetic — sanity-checked at strict `>` boundary:**

- Migration line 227: `IF v_paused_at IS NULL AND v_total > v_cap`
  (strict, not `>=`).
- Migration line 231: `runtime_paused_at IS NULL` guard makes the
  `UPDATE` idempotent (a second cap breach in the same hour does not
  re-stamp the timestamp).
- Result for cap=500, cost=100/call, N=10: cumulatives sort to
  `[100..1000]`; `kill_tripped` is the per-row `cumulative > 500`
  classifier; `runtime_paused_at` is stamped exactly once.

**Schema fixture contract:**

- `runtime_cost_cap_cents` is `int NOT NULL DEFAULT 2000` — the
  `handle_new_user` trigger inserting into `public.users` does NOT
  set this column, so the column DEFAULT applies to every new founder.
  The test's `UPDATE` to set the cap to 500 overrides the default for
  the synthetic founder only.
- `runtime_paused_at` is nullable timestamptz with no DEFAULT — initial
  state after `handle_new_user` is `NULL` for every new founder.
- service_role bypasses RLS by default on Supabase, so the `UPDATE`
  succeeds without an explicit policy (same precedent used by
  existing tenant-isolation tests for fixture observation).

**Edge cases identified — none load-bearing:**

- *Parallel suite contention.* Other tenant-isolation suites running
  in the same workflow run use their own synthetic founder. `FOR UPDATE`
  locks are per-row in Postgres; no cross-suite contention possible
  through this RPC.
- *Network jitter / dev-Supabase tail latency.* N=10 concurrent calls
  complete well under the 30 s per-test timeout in practice; if a
  pathological CI day pushes one call past 30 s, vitest will fail the
  test with a clean timeout signature rather than a confusing assertion
  failure.
- *Hour-window edge.* The RPC's SUM filter is `ts > now() - interval '1 hour'`.
  Per-run synthetic founder ⇒ no historical rows ⇒ no edge.

## Sharp Edges

- The test's correctness depends on the **strict** `>` predicate at
  `046_runtime_cost_state.sql:227`. A future RV that changes the
  predicate to `>=` would make `kill_tripped` fire one call earlier
  (at cumulative=500, call 5). The invariants table in P1.4 derives
  the expected pairs from `pair.cumulative_cents > CAP_CENTS`; this
  expression MUST mirror the migration's predicate exactly. If the
  migration ever flips to `>=`, the test must flip in lockstep.
- Filename suffix `.tenant-isolation.test.ts` is load-bearing for path
  filter + workflow invocation. `byok-kill-switch.atomicity.test.ts`
  (the issue body's first-draft suggestion) would NOT trigger
  `tenant-integration.yml` on this PR and the test would not run in CI.
- N=10, COST_CENTS=100, CAP_CENTS=500 are tuned together. Changing one
  without the others breaks the expected-cumulatives table. Keep the
  three as named constants at the top of the test for legibility.
- Per Sharp Edge `2026-05-12-plan-precondition-and-3-value-enum-gate-drift.md`:
  the assertion `pair.kill_tripped > pair.cumulative_cents > CAP_CENTS`
  is the boundary classifier. The test iterates EVERY pair and asserts
  the boundary explicitly — not a single spot-check on the 5th vs 6th
  call. This is the per-member enumeration the rule prescribes.
- Per Sharp Edge
  `knowledge-base/project/learnings/best-practices/2026-04-29-docs-fix-verification-greps-must-span-operator-surfaces.md`:
  the verification greps in AC5/AC6/AC7/AC9/AC10 are scoped to the
  test file specifically (the only operator-facing surface the test
  introduces). The single-file scope is correct here because the
  artifact is one file; nothing else carries the same semantic role.
- The `runtime_paused_at` tight-window assertion (`>= now - 60s`)
  trades flake-resistance for precision. The window must be wider
  than the actual fan-out latency (CI worst case ~10 s) but tight
  enough to reject a stale stamp from a prior fixture leak. 60 s is
  the calibrated middle.
- Per Sharp Edge `2026-05-16-rls-deny-tests-payload-must-type-validate-or-they-pass-for-wrong-reason.md`:
  the `service.rpc(...)` payload here uses real types
  (UUID for `p_invocation_id`, UUID for `p_founder_id`, etc.). A typo
  in one of the param names (e.g., `p_founder_uuid` instead of
  `p_founder_id`) would not type-error at supabase-js level and would
  surface as a Postgres "function ... does not exist" error at
  runtime. The AC5 grep pins the FIVE-arg shape against the migration's
  signature.
- Per Sharp Edge "atomic delivery for foundations PRs"
  (`2026-05-07-foundations-pr-must-not-declare-downstream-contracts.md`):
  this test is NOT a foundations-PR-declaring-a-downstream-contract.
  It is a passive observation test against an already-shipped migration.
  No downstream wiring required, no atomic-delivery concern.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)

**Status:** reviewed (carry-forward — no fresh CTO spawn needed for a
test-only change against an already-shipped substrate).

**Assessment:** This is a covered-substrate test addition. PR-F's
plan (`2026-05-17-feat-pr-f-inngest-trigger-layer-plan.md`) carried CTO
sign-off on the atomicity invariant; this PR adds the live-DB observation
without changing the substrate. The architectural concern is correctness
of the test's failure-mode coverage (TOCTOU + idempotent stamp +
strict-`>` boundary), which Phase 1 P1.4 explicitly enumerates.

**Product (CPO):** flagged via brand-survival threshold `single-user
incident` — see Product/UX Gate below.

### Product/UX Gate

**Tier:** advisory (no new UI; no new user-facing surface; threshold-driven sign-off only).

**Decision:** CPO sign-off required at plan-time per Section 2.6 Step 3
(brand-survival threshold = `single-user incident`). The sign-off
question for CPO: "A test-only PR pinning the atomicity of the
kill-switch RPC. The RPC itself shipped in PR-F #3940 with prior CPO
sign-off. Does adding the test surface introduce new product risk?"
Expected answer: no — the test is the closing of a deferred-scope-out
(#3981) and reduces residual risk by gating against future regression.

**Agents invoked:** none at plan-time (single-domain, test-only).
**Skipped specialists:** ux-design-lead (no UI), copywriter (no copy).
**Pencil available:** N/A.
**`user-impact-reviewer`** WILL be invoked at `/soleur:review` time
per the brand-survival threshold contract.

#### Findings

No new product risk. The test is observation-only against an already-shipped substrate.

## Infrastructure (IaC)

Skip — no new infrastructure. The CI substrate (workflow + Doppler
token + dev migration apply) is already provisioned via PR #3893.
The PR is a single new test file under `apps/web-platform/test/server/`.

## GDPR / Compliance Gate

Test surface touches `audit_byok_use` (Art. 30 accountability records)
and `public.users` writes (the `runtime_cost_cap_cents` UPDATE on the
synthetic founder). All writes are dev-only against synthetic
fixtures matching `tenant-isolation-[a-f0-9]{16}@soleur.test`.

**No new processing activity.** This is a test against an existing
processing record (PR-F audit RPC). No Article 30 update required.

**TS-05 cleanup carry-forward.** WORM trigger + ON DELETE RESTRICT
make audit row + synthetic user teardown impossible in dev. Tracked
as deferred-scope-out **#3934** (synthetic-fixture sweeper) per
`knowledge-base/legal/compliance-posture.md:99`. Do NOT file a
duplicate; this test inherits the same orphan-row acceptance pattern
as `audit-byok-use.tenant-isolation.test.ts`.

**DL-04 DSAR-regression probe.** Not applicable — synthetic emails
match the allowlist regex; no production data path touched.

**Advisory disclaimer:** This gate output is advisory-only per
AGENTS.md `hr-gdpr-gate-on-regulated-data-surfaces`. The actual
compliance posture amendment (or non-amendment) is operator-owned;
this section captures the analysis at plan time.

## Test Strategy

**Single test file, single test function.** The fan-out workload
(10 concurrent RPC calls) produces one observation set; splitting
into multiple `test()` blocks would re-run the workload and double
dev-Supabase load. All 5 invariants are observed against the same
settled set.

**Vitest project:** `unit` (the test file lives in `test/server/**`
which matches the `unit` project's `include: ["test/**/*.test.ts", ...]`
per `vitest.config.ts:30`). NOT `component` (no .tsx, no DOM).

**Local invocation:**

```bash
cd apps/web-platform
doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 \
  npm run test:ci -- test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts --project unit
```

**CI invocation** (automatic via path filter on
`.github/workflows/tenant-integration.yml`):

```bash
doppler run -p soleur -c dev_scheduled -- env TENANT_INTEGRATION_TEST=1 \
  npm run test:ci -- test/server/ --project unit --reporter=verbose
```

**Skip-fast verification** (proves the gate works — no Doppler
required):

```bash
cd apps/web-platform
npm run test:ci -- test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts --project unit
# Expected: vitest reports "1 skipped"
```

## Out of Scope / Non-Goals

- **NOT wiring `record_byok_use_and_check_cap` to a production caller.**
  That wiring lives in `runWithByokLease` and is the subject of a
  later PR (PR-G or follow-on).
- **NOT extending the path filter on `tenant-integration.yml`.** The
  filename suffix `.tenant-isolation.test.ts` matches the existing
  glob; no workflow edit required.
- **NOT adding a synthetic-fixture sweeper.** Already tracked at #3934.
- **NOT testing the operator-driven reset path** (the `runtime_paused_at`
  unset path was scoped out of PR-F per migration 046's comment at
  line 61: "Reset path lives outside PR-F (operator-driven for alpha).").
- **NOT testing per-tenant cap override beyond the synthetic founder.**
  The test sets the cap to 500 on the test founder only; production
  caps are unchanged.
- **NOT validating supabase-js v2 client wiring against the RPC TABLE
  return shape via TypeScript types.** The test reads `result.value.data![0]`
  with index-based access and `as` cast at the cumulative_cents /
  kill_tripped property level; deeper type wiring lives in
  `lib/types/supabase.ts` (generated types) and is its own concern.

## Issue Linkage

- Closes #3981.
- Refs #3940 (PR-F substrate that introduced the RPC).
- Refs #3893 (CI substrate workflow `tenant-integration.yml`).
- Refs #3934 (synthetic-fixture sweeper — orphan-row carry-forward).

## Communication

After merge, the test contributes to:

- `compliance-posture.md` PR-E entry (no edit required — already
  captures the atomicity invariant under "Active Items").
- `knowledge-base/project/learnings/` — only if a session error
  surfaces a non-obvious gotcha (e.g., supabase-js parallelism mode,
  pgbouncer behavior). No pre-emptive learning file.

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-18-test-byok-killswitch-atomicity-tenant-isolation-plan.md
Branch: feat-one-shot-3981-byok-killswitch-atomicity.
Worktree: .worktrees/feat-one-shot-3981-byok-killswitch-atomicity/.
Issue: #3981. PR: pending.
Plan reviewed (deepen-plan + multi-agent), implementation next.
```
