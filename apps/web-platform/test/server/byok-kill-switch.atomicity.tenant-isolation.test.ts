/**
 * record_byok_use_and_check_cap atomicity — DB-layer integration test (#3981).
 *
 * Pins the Kieran P1.1 invariant added in PR-F #3940 / migration
 * 046_runtime_cost_state.sql: under N concurrent BYOK ledger writes
 * for the same founder at cap-boundary, the per-row `SELECT ... FOR UPDATE`
 * lock on `public.users` (line 198) serializes callers such that
 * `cumulative_cents` increases monotonically by exactly `token_count ×
 * unit_cost_cents`, `kill_tripped` flips deterministically on the first
 * call where cumulative > cap (strict `>` at line 227), and
 * `runtime_paused_at` is stamped exactly once (idempotent UPDATE guarded
 * by `runtime_paused_at IS NULL` at line 231).
 *
 * Structural-only coverage (statement-order regex assertions) already
 * lives at `test/supabase-migrations/046-runtime-cost-state.test.ts`.
 * This test is the live-DB complement: it gates against a future RV
 * rewrite that preserves statement order while losing the `FOR UPDATE`
 * lock or flipping the predicate to `>=`.
 *
 * Filename: `.tenant-isolation.test.ts` suffix is load-bearing for the
 * path filter at `.github/workflows/tenant-integration.yml:36,42`.
 * Without the suffix the workflow does not fire on this file's own PR.
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1. Requires `doppler run -p soleur -c dev`.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     npm run test:ci -- test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts --project unit
 *
 * Synthesized fixtures only (cq-test-fixtures-synthesized-only).
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import {
  createClient,
  type SupabaseClient,
} from "@supabase/supabase-js";
import { randomBytes, randomUUID } from "node:crypto";

const INTEGRATION_ENABLED = process.env.TENANT_INTEGRATION_TEST === "1";

const SYNTHETIC_EMAIL_PATTERN =
  /^tenant-isolation-[a-f0-9]{16}@soleur\.test$/;

function syntheticEmail(): string {
  return `tenant-isolation-${randomBytes(8).toString("hex")}@soleur.test`;
}

function assertSynthetic(email: string): void {
  if (!SYNTHETIC_EMAIL_PATTERN.test(email)) {
    throw new Error(
      `Refusing to touch non-synthetic email "${email}" — this test only ` +
        "manipulates tenant-isolation-*@soleur.test accounts.",
    );
  }
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`[byok-kill-switch] ${name} is required`);
  return value;
}

// Three constants tuned together — changing one without the others
// breaks the expected-cumulatives table. Kept named at the top for
// legibility per plan Sharp Edges.
const N = 10;
const COST_CENTS = 100; // p_token_count=10 × p_unit_cost_cents=10
const CAP_CENTS = 500;

describe.skipIf(!INTEGRATION_ENABLED)(
  "record_byok_use_and_check_cap atomicity (integration)",
  () => {
    let service: SupabaseClient;
    const founder = { id: "", email: syntheticEmail() };

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
      // at call 6 of N=10 at cost 100/call. Only touches the synthetic
      // founder's row; production caps are unchanged. service_role
      // bypasses RLS on Supabase by default — same precedent as
      // `audit-byok-use.tenant-isolation.test.ts` for fixture observation.
      const { error: capError } = await service
        .from("users")
        .update({ runtime_cost_cap_cents: CAP_CENTS })
        .eq("id", founder.id);
      expect(capError, "set test cap to 500 cents").toBeNull();
    }, 30_000);

    afterAll(async () => {
      // audit_byok_use rows for the synthetic founder are WORM-protected
      // (UPDATE/DELETE raises P0001 — see audit_byok_use_no_mutate trigger
      // at 037_audit_byok_use.sql), and the founder_id FK on audit_byok_use
      // is ON DELETE RESTRICT, so auth.admin.deleteUser(founder.id) would
      // 23503 with this run's audit rows present. Mirrors the orphan-row
      // acceptance pattern documented in
      // `audit-byok-use.tenant-isolation.test.ts` afterAll: single
      // per-run orphan is acceptable for closed-preview alpha; long-
      // running CI nightlies should adopt the synthetic-fixture sweeper
      // tracked as deferred-scope-out #3934 (per compliance-posture.md
      // PR-E entry). No duplicate scope-out filed.
      //
      // Per-run isolation is guaranteed by the per-run randomBytes-derived
      // email in beforeAll, not by row cleanup.
    }, 30_000);

    test(
      "N concurrent RPC calls at cap-boundary serialize via FOR UPDATE",
      async () => {
        // Fan out N true HTTP requests via Promise.allSettled. supabase-js
        // 2.99.2 .rpc() returns a thenable that resolves to {data, error};
        // each invocation is an independent fetch against PostgREST.
        // Concurrency happens client-side; serialization happens
        // DB-side via the SELECT ... FOR UPDATE lock at migration 046:198.
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

        // Invariant A — protocol success per call. The kill-switch
        // surfaces as a signal in the return TABLE (`kill_tripped`),
        // not as a thrown error. Every call must settle "fulfilled"
        // with `error: null` and one row of `{cumulative_cents,
        // kill_tripped}`.
        for (const [i, result] of settled.entries()) {
          expect(result.status, `call ${i}: settled`).toBe("fulfilled");
          if (result.status === "fulfilled") {
            expect(result.value.error, `call ${i}: rpc error`).toBeNull();
            expect(result.value.data?.length, `call ${i}: row count`).toBe(1);
          }
        }

        // Pair up (cumulative_cents, kill_tripped) and sort ascending
        // by cumulative. Concurrent fire means we don't know the
        // arrival order; the contract is "every value in
        // {100, 200, ..., N*100} appears exactly once".
        const pairs = settled
          .map((r) =>
            r.status === "fulfilled"
              ? (r.value.data as Array<{
                  cumulative_cents: number;
                  kill_tripped: boolean;
                }> | null)?.[0] ?? null
              : null,
          )
          .filter(
            (x): x is { cumulative_cents: number; kill_tripped: boolean } =>
              x !== null,
          )
          .sort((a, b) => a.cumulative_cents - b.cumulative_cents);
        expect(pairs.length, "all calls returned a row").toBe(N);

        // Invariant B — cumulative_cents takes exactly {100, 200, ..., N*100}
        // with no duplicates and no gaps. A TOCTOU race would produce
        // duplicates (two callers reading the same pre-INSERT snapshot
        // and recording the same SUM) or skipped values; FOR UPDATE
        // serialization guarantees this monotone progression.
        const cumulatives = pairs.map((p) => p.cumulative_cents);
        const expectedCumulatives = Array.from(
          { length: N },
          (_, i) => (i + 1) * COST_CENTS,
        );
        expect(cumulatives).toEqual(expectedCumulatives);

        // Invariant C — kill_tripped is true on EXACTLY ONE call, and
        // that call is the first to cross the cap. The migration's
        // predicate at 046:227 is `IF v_paused_at IS NULL AND v_total
        // > v_cap` — both clauses are load-bearing. Once the cap-
        // crossing call stamps `runtime_paused_at`, every subsequent
        // call observes the non-null timestamp inside its own
        // FOR-UPDATE-serialized critical section and returns
        // kill_tripped=false. With cap=500 and N=10 at cost=100/call,
        // five calls observe cumulative > cap (600, 700, 800, 900,
        // 1000), but only ONE of them — the call landing at cumulative
        // = CAP_CENTS + COST_CENTS (= 600) — sees `runtime_paused_at
        // IS NULL` and flips the flag.
        //
        // This is the atomicity signal: without FOR UPDATE, two or
        // more concurrent callers could pass the `v_paused_at IS NULL`
        // guard, each set kill_tripped=true, and the test would observe
        // multiple-trips. With FOR UPDATE serializing the read+UPDATE
        // cycle on the founder's users row, exactly one call wins.
        //
        // Per learning 2026-05-12-plan-precondition-and-3-value-enum-
        // gate-drift.md — each pair is asserted individually so a future
        // RV rewrite that drops either clause surfaces with a specific
        // message ("at cumulative=N").
        const tripCumulative = CAP_CENTS + COST_CENTS;
        for (const pair of pairs) {
          const expectedTripped = pair.cumulative_cents === tripCumulative;
          expect(
            pair.kill_tripped,
            `at cumulative=${pair.cumulative_cents}`,
          ).toBe(expectedTripped);
        }
        const trippedCount = pairs.filter((p) => p.kill_tripped).length;
        expect(
          trippedCount,
          "exactly one call wins the kill-switch flip",
        ).toBe(1);

        // Invariant D — audit_byok_use row count for this founder equals
        // N. Accounting is sacred: the RPC INSERTs the audit row FIRST
        // (migration 046 comment: "the audit row lands even when the
        // call kill-trips"), so all N calls produce an audit row, not
        // just the K=5 that returned kill_tripped=false. The future
        // production caller (`runWithByokLease`) is responsible for
        // refusing further work after observing kill_tripped — that
        // gate is outside this RPC's scope.
        const { data: rows, error: countError } = await service
          .from("audit_byok_use")
          .select("id")
          .eq("founder_id", founder.id)
          .eq("agent_role", "test-atomicity");
        expect(countError, "audit_byok_use count").toBeNull();
        expect(rows?.length, "audit row count == N").toBe(N);

        // Invariant E — runtime_paused_at is non-null AND was set within
        // a tight window. Exactly-one-stamp is guaranteed by the
        // idempotent UPDATE guard (`runtime_paused_at IS NULL`) at
        // migration 046:231; we observe the post-state. 60s lookback
        // is wider than worst-case CI fan-out latency (~10s) but tight
        // enough to reject a stale stamp from a prior fixture leak.
        const stampLowerBound = Date.now() - 60_000;
        const stampUpperBound = Date.now() + 1_000;
        const { data: userRow, error: userError } = await service
          .from("users")
          .select("runtime_paused_at, runtime_cost_cap_cents")
          .eq("id", founder.id)
          .single();
        expect(userError, "select users row").toBeNull();
        expect(
          userRow?.runtime_cost_cap_cents,
          "cap unchanged from beforeAll",
        ).toBe(CAP_CENTS);
        expect(
          userRow?.runtime_paused_at,
          "runtime_paused_at stamped",
        ).not.toBeNull();
        const stampedAt = new Date(
          userRow!.runtime_paused_at as string,
        ).getTime();
        expect(
          stampedAt,
          `stamp >= now - 60s (got ${new Date(stampedAt).toISOString()})`,
        ).toBeGreaterThan(stampLowerBound);
        expect(
          stampedAt,
          `stamp <= now + 1s (got ${new Date(stampedAt).toISOString()})`,
        ).toBeLessThanOrEqual(stampUpperBound);
      },
      30_000,
    );
  },
);
