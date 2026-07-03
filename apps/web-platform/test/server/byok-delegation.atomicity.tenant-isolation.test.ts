/**
 * check_and_record_byok_delegation_use atomicity — DB-layer integration test
 * (#5938, Ref #5920).
 *
 * Pins the delegation cap RPC's *semantic* invariants that the #5920
 * dev-migration-drift body-marker probe cannot: marker presence
 * (`byok_delegations:hourly_cap_exceeded` / `daily_cap_exceeded` + the row
 * `FOR UPDATE`) is necessary-not-sufficient — a future RV rewrite could keep
 * the RAISE strings while flipping the strict `>` comparison to `>=`, dropping
 * the `FOR UPDATE` lock, or miscomputing the rolling cap SUM. This test is the
 * live-DB semantic authority for `check_and_record_byok_delegation_use`
 * (migration 084_byok_delegation_withdrawals.sql §7, cap checks at 449 / 463,
 * `FOR UPDATE` at 370).
 *
 * Scope split (see plan Research Reconciliation):
 *   - The cap-RPC precedent this mirrors is
 *     `byok-kill-switch.atomicity.tenant-isolation.test.ts` (#5920 / b020ebecf,
 *     Invariant C — the self-diagnosing FOR-UPDATE concurrency proof).
 *   - An EXISTING partial hourly test already proves the hourly RAISE loosely
 *     (`byok-delegations.tenant-isolation.test.ts:537` — cost 4 then cost 2 → 6
 *     > 5; the `== cap` call is never exercised, sequential-only, no
 *     self-diagnosis). This file does NOT duplicate it; it adds the genuine
 *     delta: strict-`>` boundary precision (a call landing *exactly at cap*
 *     passes, `+1` over trips) for BOTH hourly and daily, `daily_cap_exceeded`
 *     marker coverage (via aged-seed isolation), and the concurrent
 *     FOR-UPDATE / no-TOCTOU-double-spend proof.
 *
 * Load-bearing difference from the cap RPC (do NOT transfer its Invariant D):
 * `record_byok_use_and_check_cap` returns a `kill_tripped` signal row and
 * ALWAYS inserts an audit row (→ N audit rows). This RPC **throws** P0001 on a
 * cap breach and inserts ONLY on the pass path (084:449-454 / 463-468 RAISE
 * with no preceding INSERT), so the double-spend invariant is `audit == K`
 * (admitted calls only), NOT `N`.
 *
 * Filename: `.tenant-isolation.test.ts` suffix is load-bearing for the path
 * filter at `.github/workflows/tenant-integration.yml` — without it the heavy
 * suite never fires on this file's own PR and the test silently never runs live.
 *
 * Opt-in via TENANT_INTEGRATION_TEST=1. Requires `doppler run -p soleur -c dev`.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env TENANT_INTEGRATION_TEST=1 \
 *     npm run test:ci -- test/server/byok-delegation.atomicity.tenant-isolation.test.ts --project unit
 *
 * Synthesized fixtures only (cq-test-fixtures-synthesized-only). WORM-protected
 * rows accumulate as orphan rows per the closed-preview acceptance pattern
 * (mirrors the byok-kill-switch + byok-delegations precedents; long-running CI
 * adopts the synthetic-fixture sweeper deferred-scope-out #3934 — no duplicate
 * scope-out filed).
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { randomBytes, randomUUID } from "node:crypto";

const INTEGRATION_ENABLED = process.env.TENANT_INTEGRATION_TEST === "1";

const SYNTHETIC_EMAIL_PATTERN = /^tenant-isolation-[a-f0-9]{16}@soleur\.test$/;

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
  if (!value) throw new Error(`[byok-delegation-atomicity] ${name} is required`);
  return value;
}

// Cost/cap constants tuned together — changing one without the others breaks
// the boundary arithmetic (see plan Phase 1). The cap MUST be an exact multiple
// of the per-call cost; otherwise the `== cap` boundary call lands at a
// cumulative value the strict-`>` proof never exercises. Enforced via
// `expect(CAP_CENTS % COST_CENTS).toBe(0)` in beforeAll.
const COST_CENTS = 100; // p_token_count=10 × p_unit_cost_cents=10
const CAP_CENTS = 500;
const N = 10;
const K = CAP_CENTS / COST_CENTS; // = 5 calls admitted before the boundary trips

const DAILY_CEILING = 1_000_000; // table CHECK upper bound; "never trips" sentinel

// Per-call RPC token args producing exactly COST_CENTS.
const TOKEN_COUNT = 10;
const UNIT_COST_CENTS = 10;

interface SyntheticUser {
  id: string;
  email: string;
  workspaceId: string;
}

describe.skipIf(!INTEGRATION_ENABLED)(
  "check_and_record_byok_delegation_use atomicity (integration)",
  () => {
    let service: SupabaseClient;
    // Direct pg connection (porsager) used ONLY to self-diagnose a failure by
    // embedding the live pg_get_functiondef body in the failure message
    // (#5920). Dev-only, same credential class as the service_role usage
    // (DATABASE_URL_POOLER, present in the dev doppler env this test runs
    // under). Never touched on a green run.
    let sql: ReturnType<typeof postgres> | null = null;
    let grantor: SyntheticUser;

    async function createSyntheticUser(): Promise<SyntheticUser> {
      const email = syntheticEmail();
      assertSynthetic(email);
      const { data, error } = await service.auth.admin.createUser({
        email,
        password: randomBytes(16).toString("hex"),
        email_confirm: true,
      });
      expect(error, `createUser(${email}) failed`).toBeNull();
      const id = data.user?.id ?? "";
      expect(id).toBeTruthy();

      // handle_new_user (mig 053 §1.1.8) auto-creates a workspace +
      // workspace_members row for solo users. Read back the workspace_id so
      // grants target the correct workspace.
      const { data: wm, error: wmErr } = await service
        .from("workspace_members")
        .select("workspace_id")
        .eq("user_id", id)
        .limit(1)
        .maybeSingle();
      expect(wmErr, `workspace_members lookup for ${email}`).toBeNull();
      expect(wm?.workspace_id, `workspace_id for ${email}`).toBeTruthy();

      return { id, email, workspaceId: wm!.workspace_id as string };
    }

    async function addMember(workspaceId: string, userId: string): Promise<void> {
      // service-role bypasses RLS. workspace_members.role is NOT NULL CHECK IN
      // ('owner','member') per mig 053; 'member' is the canonical non-creator
      // role.
      const { error } = await service
        .from("workspace_members")
        .insert({ workspace_id: workspaceId, user_id: userId, role: "member" });
      expect(error, `addMember(${userId} → ${workspaceId})`).toBeNull();
    }

    // Create a FRESH grantee + a fresh delegation from `grantor` for each test.
    // A fresh grantee per test sidesteps the partial-unique on
    // (grantor, grantee, workspace) WHERE revoked_at IS NULL, and a distinct
    // delegation_id isolates each test's per-delegation cap SUM. NO acceptance
    // or withdrawal rows are seeded: the RPC's per-turn consent re-gate
    // (084:404) fires ONLY when a withdrawal exists, and check_and_record does
    // not call the resolver — so zero withdrawals = re-gate is a no-op.
    async function grantDelegation(
      hourlyCapCents: number,
      dailyCapCents: number,
    ): Promise<{ delegationId: string; grantee: SyntheticUser }> {
      const grantee = await createSyntheticUser();
      await addMember(grantor.workspaceId, grantee.id);
      const { data, error } = await service.rpc("grant_byok_delegation", {
        p_grantor_user_id: grantor.id,
        p_grantee_user_id: grantee.id,
        p_workspace_id: grantor.workspaceId,
        p_daily_usd_cap_cents: dailyCapCents,
        p_hourly_usd_cap_cents: hourlyCapCents,
        p_expires_at: null,
        p_actor_user_id: grantor.id,
      });
      expect(error, "grant_byok_delegation").toBeNull();
      const delegationId = data as unknown as string;
      expect(delegationId, "delegation id returned").toBeTruthy();
      return { delegationId, grantee };
    }

    // One RPC use at exactly COST_CENTS. supabase-js .rpc() resolves *fulfilled*
    // with { data, error } even on a P0001 RAISE (it does not reject) — the
    // pass/fail split lives in `.error`.
    function recordUse(delegationId: string, callerUserId: string, role: string) {
      return service.rpc("check_and_record_byok_delegation_use", {
        p_delegation_id: delegationId,
        p_invocation_id: randomUUID(),
        p_token_count: TOKEN_COUNT,
        p_unit_cost_cents: UNIT_COST_CENTS,
        p_caller_user_id: callerUserId,
        p_agent_role: role,
      });
    }

    // Fetch the live delegation-RPC body for a failure message. Guarded so a
    // fetch error NEVER masks the real assertion (returns a fallback string,
    // never throws). Signature matches migration 084:344-351 + REVOKE 084:482.
    async function fetchLiveDelegationRpcBody(): Promise<string> {
      if (!sql) {
        return "(live body unavailable: DATABASE_URL_POOLER unset)";
      }
      try {
        const rows = await sql<Array<{ def: string | null }>>`
          SELECT pg_get_functiondef(
            'public.check_and_record_byok_delegation_use(uuid,uuid,int,int,uuid,text)'::regprocedure
          ) AS def`;
        return rows[0]?.def ?? "(live body unavailable: no rows)";
      } catch (e) {
        return `(live body fetch failed: ${
          e instanceof Error ? e.message : String(e)
        })`;
      }
    }

    function diagBanner(body: string): string {
      return (
        "\n\n--- live pg_get_functiondef(public.check_and_record_byok_delegation_use) " +
        `— drift self-diagnosis (#5938) ---\n${body}`
      );
    }

    // audit_byok_use rows for this delegation: id + spend contribution.
    async function auditRowsFor(
      delegationId: string,
    ): Promise<Array<{ token_count: number; unit_cost_cents: number }>> {
      const { data, error } = await service
        .from("audit_byok_use")
        .select("token_count, unit_cost_cents")
        .eq("delegation_id", delegationId);
      expect(error, "audit_byok_use count").toBeNull();
      return (data ?? []) as Array<{
        token_count: number;
        unit_cost_cents: number;
      }>;
    }

    beforeAll(async () => {
      // Constants integrity — a future tuner that breaks
      // CAP_CENTS-is-multiple-of-COST_CENTS gets an immediate localized failure
      // rather than a confused boundary mismatch (mirrors the cap test).
      expect(
        CAP_CENTS % COST_CENTS,
        "CAP_CENTS must be an exact multiple of COST_CENTS",
      ).toBe(0);

      const url = requireEnv("SUPABASE_URL");
      requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
      const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
      requireEnv("SUPABASE_JWT_SECRET");

      service = createClient(url, serviceRoleKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });

      // Open the diagnostic pg connection if the pooler URL is available.
      // Optional: the failure-path fetch guards on `sql === null`. The Supabase
      // pooler presents a self-signed CA chain, so `rejectUnauthorized: false`
      // (dev-only, mirrors run-migrations.sh `sslmode=require`; no committed
      // code disables TLS verify on a prod runtime surface).
      const poolerUrl = process.env.DATABASE_URL_POOLER;
      if (poolerUrl) {
        sql = postgres(poolerUrl, {
          max: 1,
          idle_timeout: 5,
          ssl: { rejectUnauthorized: false },
        });
      }

      grantor = await createSyntheticUser();
    }, 60_000);

    afterAll(async () => {
      // audit_byok_use + byok_delegations rows for synthetic users are
      // WORM-protected (UPDATE/DELETE raises P0001) and identity FKs are ON
      // DELETE RESTRICT, so auth.admin.deleteUser would 23503 with this run's
      // rows present. Per-run isolation is guaranteed by the per-run
      // randomBytes-derived email, not by row cleanup (orphan-row acceptance,
      // deferred sweeper #3934 — no duplicate scope-out).
      if (sql) await sql.end({ timeout: 5 });
    }, 30_000);

    test(
      "Test A — hourly strict-`>` boundary: `== cap` passes, `+1` trips (sequential)",
      async () => {
        // Hourly cap = CAP_CENTS; daily set to the ceiling so it never trips.
        const { delegationId, grantee } = await grantDelegation(
          CAP_CENTS,
          DAILY_CEILING,
        );

        // Calls 1..K at COST_CENTS each: cumulative 100…500. Every one —
        // INCLUDING call K where cumulative reaches EXACTLY CAP_CENTS — must
        // pass. Call K is the load-bearing strict-`>` proof: a `>=` regression
        // would make it raise.
        const okErrors: Array<unknown> = [];
        for (let i = 0; i < K; i++) {
          const { error } = await recordUse(
            delegationId,
            grantee.id,
            "test-hourly-boundary",
          );
          okErrors.push(error);
        }

        // Call K+1 would reach CAP_CENTS + COST_CENTS (= 600) > cap → RAISE.
        const overCap = await recordUse(
          delegationId,
          grantee.id,
          "test-hourly-boundary",
        );

        const audit = await auditRowsFor(delegationId);

        const capCall = okErrors[K - 1]; // the `== cap` call
        const willFail =
          okErrors.some((e) => e !== null) ||
          overCap.error === null ||
          !/byok_delegations:hourly_cap_exceeded/.test(
            overCap.error?.message ?? "",
          ) ||
          audit.length !== K;
        const diag = willFail
          ? diagBanner(await fetchLiveDelegationRpcBody())
          : "";

        okErrors.forEach((error, i) => {
          expect(error, `call ${i + 1} (cumulative ${(i + 1) * COST_CENTS}) passes${diag}`).toBeNull();
        });
        expect(
          capCall,
          `the == cap call K (cumulative ${CAP_CENTS}) passes — strict-\`>\` proof${diag}`,
        ).toBeNull();
        expect(
          overCap.error,
          `call K+1 (would reach ${CAP_CENTS + COST_CENTS}) trips${diag}`,
        ).not.toBeNull();
        expect(overCap.error?.message, `hourly marker${diag}`).toMatch(
          /byok_delegations:hourly_cap_exceeded/,
        );
        // The RAISE path writes no audit row for the over-cap call → K rows.
        expect(audit.length, `audit count == K (admitted only)${diag}`).toBe(K);
      },
      60_000,
    );

    test(
      "Test B — daily strict-`>` boundary via aged-seed isolation (sequential)",
      async () => {
        // hourly == daily == CAP_CENTS (the table CHECK forces hourly ≤ daily).
        const { delegationId, grantee } = await grantDelegation(
          CAP_CENTS,
          CAP_CENTS,
        );

        // Pre-seed aged audit rows summing to CAP_CENTS − COST_CENTS (= 400)
        // with ts = now() − 2h: INSIDE the 24h daily window (084:461), OUTSIDE
        // the 1h hourly window (084:447). This is the ONLY way to load the
        // daily window while leaving the hourly window empty — with all live
        // calls in one hour, hourly (checked first, 084:449) always trips
        // at-or-before daily. audit_byok_use.ts is insertable (037; only
        // UPDATE/DELETE are WORM-blocked); workspace_id is NOT NULL (mig
        // 055/059) so the seed carries the grantor workspace.
        const agedTs = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
        const seedCount = (CAP_CENTS - COST_CENTS) / COST_CENTS; // = 4
        const seedRows = Array.from({ length: seedCount }, () => ({
          invocation_id: randomUUID(),
          founder_id: grantor.id, // normal accounting attributes to grantor
          workspace_id: grantor.workspaceId, // NOT NULL
          agent_role: "test-daily-seed",
          token_count: TOKEN_COUNT,
          unit_cost_cents: UNIT_COST_CENTS,
          delegation_id: delegationId,
          ts: agedTs,
        }));
        const { error: seedErr } = await service
          .from("audit_byok_use")
          .insert(seedRows);
        expect(seedErr, "aged-seed insert").toBeNull();

        // Live call 1: hourly-window spend = 0 + 100 = 100 ≤ 500 (ok); daily
        // spend = 400 (aged) + 100 = 500 ≤ 500 (ok, `== cap` boundary) → passes.
        const call1 = await recordUse(
          delegationId,
          grantee.id,
          "test-daily-boundary",
        );

        // Live call 2: hourly = 100 (call-1 live row) + 100 = 200 ≤ 500 (does
        // NOT trip); daily = 400 aged + 100 live + 100 = 600 > 500 → RAISE. The
        // error being the DAILY marker (not hourly) proves it is the daily
        // branch that raises and pins the strict-`>` daily boundary.
        const call2 = await recordUse(
          delegationId,
          grantee.id,
          "test-daily-boundary",
        );

        const willFail =
          call1.error !== null ||
          call2.error === null ||
          !/byok_delegations:daily_cap_exceeded/.test(
            call2.error?.message ?? "",
          ) ||
          /byok_delegations:hourly_cap_exceeded/.test(
            call2.error?.message ?? "",
          );
        const diag = willFail
          ? diagBanner(await fetchLiveDelegationRpcBody())
          : "";

        expect(
          call1.error,
          `live call 1 at daily == cap (${CAP_CENTS}) passes${diag}`,
        ).toBeNull();
        expect(call2.error, `live call 2 (daily would reach ${CAP_CENTS + COST_CENTS}) trips${diag}`).not.toBeNull();
        expect(call2.error?.message, `daily marker (not hourly)${diag}`).toMatch(
          /byok_delegations:daily_cap_exceeded/,
        );
        expect(
          call2.error?.message,
          `hourly branch did NOT raise (hourly at 200 ≤ ${CAP_CENTS})${diag}`,
        ).not.toMatch(/byok_delegations:hourly_cap_exceeded/);
      },
      60_000,
    );

    test(
      "Test C — concurrency / FOR UPDATE / no-TOCTOU-double-spend",
      async () => {
        // Hourly cap = CAP_CENTS; daily at the ceiling. Fan out N concurrent
        // uses (each a distinct invocation_id). Concurrency is client-side;
        // serialization is DB-side via the row `FOR UPDATE` at 084:370.
        const { delegationId, grantee } = await grantDelegation(
          CAP_CENTS,
          DAILY_CEILING,
        );

        const settled = await Promise.allSettled(
          Array.from({ length: N }, () =>
            recordUse(delegationId, grantee.id, "test-concurrency"),
          ),
        );

        // supabase-js .rpc() does not reject on a P0001 RAISE — every entry is
        // `fulfilled` with { data, error }; partition on `.error`.
        const errors = settled.map((r) =>
          r.status === "fulfilled" ? r.value.error : { message: "settled-rejected" },
        );
        const admitted = errors.filter((e) => e === null).length;
        const tripped = errors.filter(
          (e) => e !== null && /byok_delegations:hourly_cap_exceeded/.test(e.message ?? ""),
        ).length;

        const audit = await auditRowsFor(delegationId);
        const recordedSpend = audit.reduce(
          (sum, r) => sum + r.token_count * r.unit_cost_cents,
          0,
        );

        // Atomicity signal: without FOR UPDATE, concurrent callers reading the
        // same pre-INSERT SUM snapshot would each pass the cap check and INSERT
        // → `> K` audit rows and spend `> cap` (double-spend). With FOR UPDATE
        // serializing the read+INSERT critical section, exactly K are admitted.
        const willFail =
          admitted !== K ||
          tripped !== N - K ||
          audit.length !== K ||
          recordedSpend !== CAP_CENTS;
        const diag = willFail
          ? diagBanner(await fetchLiveDelegationRpcBody())
          : "";

        expect(
          settled.every((r) => r.status === "fulfilled"),
          `all ${N} calls settled fulfilled${diag}`,
        ).toBe(true);
        expect(admitted, `exactly K=${K} calls admitted${diag}`).toBe(K);
        expect(tripped, `exactly N−K=${N - K} calls raise the hourly marker${diag}`).toBe(
          N - K,
        );
        expect(audit.length, `audit count == K (no double-spend)${diag}`).toBe(K);
        expect(
          recordedSpend,
          `recorded spend == cap (${CAP_CENTS})${diag}`,
        ).toBe(CAP_CENTS);
      },
      60_000,
    );
  },
);
