/**
 * check_and_record_byok_delegation_use atomicity — DB-layer integration test
 * (#5938, Ref #5920; rewritten for the return-status contract by #7829).
 *
 * Pins the delegation cap RPC's *semantic* invariants that the #5920
 * dev-migration-drift body-marker probe cannot: marker presence
 * (`refusal_reason := '<reason>'`, the audit INSERT, and the row `FOR UPDATE`)
 * is necessary-not-sufficient — a future rewrite could keep every marker while
 * flipping the strict `>` comparison to `>=`, dropping the `FOR UPDATE` lock,
 * miscomputing the rolling cap SUM, or writing the refusal row and then losing
 * it. This test is the live-DB semantic authority for
 * `check_and_record_byok_delegation_use` (migration
 * `137_byok_cap_breach_audit_row.sql`, anchored on the `SELECT * INTO v_row …
 * FOR UPDATE` lock and the two `INTO v_hourly_spent` / `INTO v_daily_spent`
 * window SUMs).
 *
 * WHAT MIGRATION 137 CHANGED, AND WHY THIS FILE HAD TO BE INVERTED.
 *
 * Before 137 the RPC signalled a refusal with `RAISE EXCEPTION
 * 'byok_delegations:<reason>'`. An unhandled plpgsql RAISE aborts its own
 * transaction, and the function declares no `EXCEPTION WHEN` handler — so the
 * `audit_byok_use` row each refusal branch inserted immediately beforehand was
 * rolled back with it. No refusal has ever been ledgered, including the three
 * branches that visibly INSERT first (#7829). 137 makes the refusal a RETURNED
 * value: `RETURNS TABLE(refusal_reason text)`, `NULL` = admitted, and every
 * refusal commits its grantee-attributed row inside the same row lock.
 *
 * The old `audit == K` invariant therefore INVERTS into a PARTITION, and the
 * old assertion was never the discriminator it looked like: `N` calls at a
 * fixed cost writing one row each makes `rows === K` / `spend === K × COST`
 * true by fixture construction, and it held even against an RPC that ignored
 * caps entirely. What discriminates is
 *   - `rows WHERE attribution_shift_reason IS NULL === K`, summing to
 *     `CAP_CENTS` (the original no-double-spend / TOCTOU proof, preserved), and
 *   - `rows WHERE attribution_shift_reason = '<cap reason>' === N − K`.
 * `rows === N` is a derived consequence, never the load-bearing assertion.
 *
 * Scope split (see plan Research Reconciliation):
 *   - The cap-RPC precedent this mirrors is
 *     `byok-kill-switch.atomicity.tenant-isolation.test.ts` (#5920 / b020ebecf,
 *     Invariant C — the self-diagnosing FOR-UPDATE concurrency proof).
 *   - A partial hourly test lives in `byok-delegations.tenant-isolation.test.ts`
 *     (`AC-hourly-cap-exceeded`); this file does NOT duplicate it. The genuine
 *     delta here is strict-`>` boundary precision for BOTH windows, daily-branch
 *     coverage via aged-seed isolation, the concurrent FOR-UPDATE proof, the
 *     window-SUM include-vs-exclude discriminator, the `ON CONFLICT` replay
 *     dedupe, the grantee/grantor attribution split, and the caller identity pin.
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
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
// Imported, NOT mirrored: a hand-written copy of a fail-CLOSED classifier
// drifted fail-OPEN here, and this is the only artifact that sees the real
// PostgREST wire shape. `readRefusalReason` is a pure function.
import { readRefusalReason } from "@/server/cost-writer";

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
const COST_CENTS = 100; // the WHOLE TURN's cost, carried in unit_cost_cents alone
const CAP_CENTS = 500;
const N = 10;
const K = CAP_CENTS / COST_CENTS; // = 5 calls admitted before the boundary trips

const DAILY_CEILING = 1_000_000; // table CHECK upper bound; "never trips" sentinel

// Per-call RPC token args. Migration 137 (ADR-208 Decision 3) made the window
// `SUM(au.unit_cost_cents)` and the per-turn increment
// `v_this_cost := p_unit_cost_cents`, so `unit_cost_cents` carries the WHOLE
// TURN's cost and `token_count` does NOT enter the arithmetic at all — it is
// ledger metadata. Production agrees: `cost-writer.ts` writes
// `Math.round(costDelta * 100)` into `unit_cost_cents`.
//
// TOKEN_COUNT is deliberately > 1 and deliberately NOT a factor of the cost, so
// a regression to the old `p_token_count * p_unit_cost_cents` product is
// DETECTABLE here rather than silently rescaling every boundary in this file.
const TOKEN_COUNT = 10;
const UNIT_COST_CENTS = COST_CENTS;

/** The five values migration 137's widened CHECK admits, plus NULL. */
const HOURLY_REASON = "hourly_cap_exceeded";
const DAILY_REASON = "daily_cap_exceeded";

/**
 * Dispatch floor for this file (see the "case floor" case at the bottom).
 * Update this deliberately, in the same commit that adds or removes a
 * `test(...)`; a silent drop means a scenario — a control, most dangerously —
 * stopped running while the suite stayed green.
 */
const EXPECTED_TEST_CASES = 9;

interface SyntheticUser {
  id: string;
  email: string;
  workspaceId: string;
}

interface AuditRow {
  invocation_id: string;
  founder_id: string | null;
  attribution_shift_reason: string | null;
  token_count: number;
  unit_cost_cents: number;
}

interface UseResult {
  invocationId: string;
  error: { message?: string; code?: string } | null;
  data: unknown;
  refusalReason: string | null;
  admitted: boolean;
}

/**
 * Classify the RPC payload — using PRODUCTION's classifier, not a copy of it.
 *
 * This file previously carried a hand-written MIRROR under a docstring saying
 * "keep the two in sync". They were already out of sync, in the one direction
 * that matters: production is fail-CLOSED (three-state `RefusalRead`, an
 * unparsed shape is `unreadable`), while the mirror had no `unreadable` state
 * at all and returned null — i.e. ADMITTED — for every shape it did not
 * recognise. `undefined`, `null`, `[]`, `[7]`, `[{refusal_reason:42}]`,
 * `[{something_else:"x"}]` and a two-row reply all classified as admitted here
 * and as unreadable in production.
 *
 * That mattered more than an ordinary drift, because THIS is the only artifact
 * that observes the real PostgREST/supabase-js wire shape. The offline matrix
 * in `cost-writer.test.ts` pins fail-closed against synthetic payloads; if the
 * live shape were ever a form production rejects, the mirror could not fail on
 * it. Duplicating a fail-closed classifier as a fail-open one is worse than not
 * mirroring at all — so it is imported.
 */
function readRefusalReasonLive(data: unknown): string | null {
  const read = readRefusalReason(data);
  if (read.kind === "unreadable") {
    throw new Error(
      `PostgREST returned a shape production classifies as UNREADABLE (${read.detail}). ` +
        "This is the wire-shape mismatch the offline matrix cannot observe.",
    );
  }
  return read.kind === "refused" ? read.reason : null;
}

function spendOf(rows: AuditRow[]): number {
  // Mirrors migration 137's corrected delegation windows: SUM(unit_cost_cents).
  // `unit_cost_cents` holds the WHOLE TURN's cost, so the old product was
  // cents-times-tokens (ADR-208 Decision 3).
  return rows.reduce((sum, r) => sum + r.unit_cost_cents, 0);
}

function admittedRows(rows: AuditRow[]): AuditRow[] {
  return rows.filter((r) => r.attribution_shift_reason === null);
}

function refusedRows(rows: AuditRow[], reason: string): AuditRow[] {
  return rows.filter((r) => r.attribution_shift_reason === reason);
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
    // or withdrawal rows are seeded: the RPC's per-turn consent re-gate fires
    // ONLY when a withdrawal exists, and check_and_record does not call the
    // resolver — so zero withdrawals = re-gate is a no-op.
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

    /**
     * One RPC use. Defaults to exactly COST_CENTS; `costCents` varies the cost
     * for the heterogeneous-cost discriminator (T5b) and `invocationId` pins it
     * for the `ON CONFLICT` replay (T7).
     *
     * Returns the invocation id so a row can be identified by IDENTITY rather
     * than by `ts` ordering — refusal and pass rows can share a millisecond,
     * and `ts` ordering would silently pick the wrong one.
     *
     * supabase-js `.rpc()` resolves *fulfilled* with `{ data, error }`; since
     * mig 137 a refusal is a fulfilled call carrying `refusal_reason`, and
     * `error` is reserved for the branches that still RAISE (22023, P0002,
     * P0001 anonymised, 42501 caller_not_grantee).
     */
    async function recordUse(
      delegationId: string,
      callerUserId: string,
      role: string,
      opts: { costCents?: number; invocationId?: string } = {},
    ): Promise<UseResult> {
      // `unit_cost_cents` IS the turn cost since migration 137 — no division by
      // TOKEN_COUNT. The previous form sent `costCents / TOKEN_COUNT`, which
      // made every call cost a tenth of what each assertion in this file
      // claimed, so no cap boundary was ever reached.
      const costCents = opts.costCents ?? COST_CENTS;
      const invocationId = opts.invocationId ?? randomUUID();
      const { data, error } = await service.rpc(
        "check_and_record_byok_delegation_use",
        {
          p_delegation_id: delegationId,
          p_invocation_id: invocationId,
          p_token_count: TOKEN_COUNT,
          p_unit_cost_cents: costCents,
          p_caller_user_id: callerUserId,
          p_agent_role: role,
        },
      );
      const refusalReason = error ? null : readRefusalReasonLive(data);
      return {
        invocationId,
        error,
        data,
        refusalReason,
        admitted: error === null && refusalReason === null,
      };
    }

    // Fetch the live delegation-RPC body for a failure message. Guarded so a
    // fetch error NEVER masks the real assertion (returns a fallback string,
    // never throws). Signature matches mig 137's CREATE + REVOKE/GRANT block.
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
        `— drift self-diagnosis (#5938/#7829) ---\n${body}`
      );
    }

    /** `diagBanner` only when the scenario is about to fail (never on green). */
    async function diagIf(willFail: boolean): Promise<string> {
      return willFail ? diagBanner(await fetchLiveDelegationRpcBody()) : "";
    }

    // audit_byok_use rows for this delegation. `founder_id`,
    // `attribution_shift_reason` and `invocation_id` are load-bearing: the
    // partition, the attribution split and the identity-based row lookup all
    // read them.
    async function auditRowsFor(delegationId: string): Promise<AuditRow[]> {
      const { data, error } = await service
        .from("audit_byok_use")
        .select(
          "invocation_id, founder_id, attribution_shift_reason, token_count, unit_cost_cents",
        )
        .eq("delegation_id", delegationId);
      expect(error, "audit_byok_use read").toBeNull();
      return (data ?? []) as AuditRow[];
    }

    /** Row count for ONE invocation id — the `ON CONFLICT` dedupe surface. */
    async function rowCountForInvocation(invocationId: string): Promise<number> {
      const { count, error } = await service
        .from("audit_byok_use")
        .select("invocation_id", { count: "exact", head: true })
        .eq("invocation_id", invocationId);
      expect(error, "audit_byok_use count by invocation_id").toBeNull();
      return count ?? 0;
    }

    beforeAll(async () => {
      // Constants integrity — a future tuner that breaks
      // CAP_CENTS-is-multiple-of-COST_CENTS gets an immediate localized failure
      // rather than a confused boundary mismatch (mirrors the cap test).
      expect(
        CAP_CENTS % COST_CENTS,
        "CAP_CENTS must be an exact multiple of COST_CENTS",
      ).toBe(0);
      // N must exceed K, else the concurrency partition expects ≤0 refusals and
      // proves nothing (localized guard, like the multiple check above).
      expect(N, "N must exceed K to exercise the cap boundary").toBeGreaterThan(K);
      // ADR-208 Decision 3, pinned in both directions. The equality alone is not
      // enough: it would still hold if someone reintroduced the product with
      // TOKEN_COUNT === 1, so assert that the OLD product does NOT equal the
      // cost and that TOKEN_COUNT is big enough for the difference to bite.
      expect(UNIT_COST_CENTS, "one call costs unit_cost_cents alone").toBe(COST_CENTS);
      expect(
        TOKEN_COUNT,
        "TOKEN_COUNT must exceed 1 or a product regression is invisible here",
      ).toBeGreaterThan(1);
      expect(
        TOKEN_COUNT * UNIT_COST_CENTS,
        "the retired `token_count * unit_cost_cents` product must NOT equal the turn cost",
      ).not.toBe(COST_CENTS);

      const url = requireEnv("SUPABASE_URL");
      const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

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
    }, 60_000);

    test(
      "T6 — hourly below / at / above: the `== cap` call PASSES, `+1` refuses and LEDGERS",
      async () => {
        // Hourly cap = CAP_CENTS; daily set to the ceiling so it never trips.
        const { delegationId, grantee } = await grantDelegation(
          CAP_CENTS,
          DAILY_CEILING,
        );

        // Calls 1..K at COST_CENTS each: cumulative 100…500. Every one —
        // INCLUDING call K where cumulative reaches EXACTLY CAP_CENTS — must be
        // admitted. Call K is the load-bearing strict-`>` proof: a `>=`
        // regression would refuse it. `CAP_CENTS % COST_CENTS === 0` (asserted
        // in beforeAll) is what makes that boundary reachable at all.
        const below: UseResult[] = [];
        for (let i = 0; i < K; i++) {
          below.push(
            await recordUse(delegationId, grantee.id, "test-hourly-boundary"),
          );
        }

        // Call K+1 would reach CAP_CENTS + COST_CENTS (= 600) > cap → refused.
        const overCap = await recordUse(
          delegationId,
          grantee.id,
          "test-hourly-boundary",
        );

        const rows = await auditRowsFor(delegationId);
        const passed = admittedRows(rows);
        const refused = refusedRows(rows, HOURLY_REASON);

        const willFail =
          below.some((r) => !r.admitted) ||
          overCap.refusalReason !== HOURLY_REASON ||
          passed.length !== K ||
          spendOf(passed) !== CAP_CENTS ||
          refused.length !== 1;
        const diag = await diagIf(willFail);

        below.forEach((r, i) => {
          expect(
            r.error,
            `call ${i + 1} (cumulative ${(i + 1) * COST_CENTS}) raises nothing${diag}`,
          ).toBeNull();
          expect(
            r.refusalReason,
            `call ${i + 1} (cumulative ${(i + 1) * COST_CENTS}) is admitted${diag}`,
          ).toBeNull();
        });
        expect(
          below[K - 1].refusalReason,
          `the == cap call K (cumulative ${CAP_CENTS}) is admitted — strict-\`>\` proof${diag}`,
        ).toBeNull();

        // Above: refused as a RETURNED value, never as an exception.
        expect(
          overCap.error,
          `call K+1 must not RAISE — refusal is a returned value since mig 137${diag}`,
        ).toBeNull();
        expect(
          overCap.refusalReason,
          `call K+1 (would reach ${CAP_CENTS + COST_CENTS}) returns the hourly reason${diag}`,
        ).toBe(HOURLY_REASON);

        // THE PARTITION. `rows.length === N` is derived from these two, not a
        // load-bearing assertion: the fixture forces one row per call.
        expect(
          passed.length,
          `admitted partition (attribution_shift_reason IS NULL) === K=${K}${diag}`,
        ).toBe(K);
        expect(
          spendOf(passed),
          `admitted spend === cap (${CAP_CENTS}) — no double-spend${diag}`,
        ).toBe(CAP_CENTS);
        expect(
          refused.length,
          `refused partition (reason = ${HOURLY_REASON}) === 1${diag}`,
        ).toBe(1);
        expect(rows.length, `derived total === K + 1${diag}`).toBe(K + 1);
      },
      120_000,
    );

    test(
      "T9 — attribution: the refused row carries the GRANTEE, the preceding pass carries the GRANTOR",
      async () => {
        const { delegationId, grantee } = await grantDelegation(
          CAP_CENTS,
          DAILY_CEILING,
        );

        const passes: UseResult[] = [];
        for (let i = 0; i < K; i++) {
          passes.push(await recordUse(delegationId, grantee.id, "test-attribution"));
        }
        const refusal = await recordUse(delegationId, grantee.id, "test-attribution");

        const rows = await auditRowsFor(delegationId);
        // Identify BOTH rows by RETURNED INVOCATION ID. `ts` ordering is not
        // safe: the pass and the refusal can land in the same millisecond, and
        // an ordering-based lookup would silently assert against the wrong row.
        const lastPassId = passes[K - 1].invocationId;
        const passRow = rows.find((r) => r.invocation_id === lastPassId);
        const refusalRow = rows.find((r) => r.invocation_id === refusal.invocationId);

        const willFail =
          !passRow ||
          !refusalRow ||
          passRow.founder_id !== grantor.id ||
          passRow.attribution_shift_reason !== null ||
          refusalRow.founder_id !== grantee.id ||
          refusalRow.attribution_shift_reason !== HOURLY_REASON;
        const diag = await diagIf(willFail);

        expect(
          passRow,
          `the preceding passing row exists for invocation ${lastPassId}${diag}`,
        ).toBeDefined();
        expect(passRow!.founder_id, `pass row attributes to the GRANTOR${diag}`).toBe(
          grantor.id,
        );
        expect(
          passRow!.attribution_shift_reason,
          `pass row carries a NULL reason${diag}`,
        ).toBeNull();

        // ADR-045: cost follows the party who continued past the boundary. The
        // refusal row's founder_id is a durable BILLING assertion — it enters
        // the grantee's Art. 15 export.
        expect(
          refusalRow,
          `the refused row EXISTS for invocation ${refusal.invocationId} — ` +
            `the whole point of #7829 (a RAISE would have rolled it back)${diag}`,
        ).toBeDefined();
        expect(
          refusalRow!.founder_id,
          `refused row attributes to the GRANTEE${diag}`,
        ).toBe(grantee.id);
        expect(
          refusalRow!.attribution_shift_reason,
          `refused row carries the cap reason${diag}`,
        ).toBe(HOURLY_REASON);
        expect(
          // The row's cost IS `unit_cost_cents` (ADR-208 Decision 3) — the same
          // expression migration 137's windows sum. Reading the retired product
          // here would report 10x the real spend on a billing assertion.
          refusalRow!.unit_cost_cents,
          `refused row records the REAL spend (${COST_CENTS}) — money already moved${diag}`,
        ).toBe(COST_CENTS);
      },
      120_000,
    );

    test(
      "T5b — the window SUM INCLUDES the rows it refused (heterogeneous cost)",
      async () => {
        // THE include-vs-exclude discriminator. Uniform per-call cost cannot
        // separate the two: once the window is over cap, every subsequent
        // uniform call breaches either way. Heterogeneous cost splits them.
        //
        //   K−1 calls at COST (400) → admitted, window = 400
        //   one call at 2×COST (200): 400 + 200 = 600 > 500 → refused, and it
        //     LEDGERS a 200-cent row, so the window becomes 600
        //   one call at COST (100):
        //     INCLUDE → 600 + 100 = 700 > 500 → refused   ← the correct answer
        //     EXCLUDE → 400 + 100 = 500 ≤ 500 → ADMITTED  ← the cap leak
        //
        // That single call's disposition is the whole decision (plan Decision 2:
        // excluding freezes the numerator and lets every turn that fits under
        // `cap − frozen` pass forever).
        const { delegationId, grantee } = await grantDelegation(
          CAP_CENTS,
          DAILY_CEILING,
        );

        const fills: UseResult[] = [];
        for (let i = 0; i < K - 1; i++) {
          fills.push(await recordUse(delegationId, grantee.id, "test-sum-include"));
        }

        const doubleCost = await recordUse(
          delegationId,
          grantee.id,
          "test-sum-include",
          { costCents: 2 * COST_CENTS },
        );

        const probe = await recordUse(delegationId, grantee.id, "test-sum-include");

        const rows = await auditRowsFor(delegationId);
        const refusedRow = rows.find(
          (r) => r.invocation_id === doubleCost.invocationId,
        );

        const willFail =
          fills.some((r) => !r.admitted) ||
          doubleCost.refusalReason !== HOURLY_REASON ||
          probe.refusalReason !== HOURLY_REASON ||
          !refusedRow ||
          refusedRow.unit_cost_cents !== 2 * COST_CENTS;
        const diag = await diagIf(willFail);

        fills.forEach((r, i) => {
          expect(
            r.admitted,
            `fill call ${i + 1} (cumulative ${(i + 1) * COST_CENTS}) admitted${diag}`,
          ).toBe(true);
        });
        expect(
          doubleCost.refusalReason,
          `the 2×COST call (would reach ${(K - 1) * COST_CENTS + 2 * COST_CENTS}) is refused${diag}`,
        ).toBe(HOURLY_REASON);
        expect(
          refusedRow,
          `the refused 2×COST call ledgered its row${diag}`,
        ).toBeDefined();
        expect(
          refusedRow!.unit_cost_cents,
          `the refused row carries its FULL ${2 * COST_CENTS}c cost${diag}`,
        ).toBe(2 * COST_CENTS);

        expect(
          probe.refusalReason,
          `the follow-up ${COST_CENTS}c call is REFUSED — the SUM counts the refused ` +
            `${2 * COST_CENTS}c row. If this is null the window EXCLUDES refusal rows and ` +
            `the cap leaks (every call under cap−frozen would pass forever)${diag}`,
        ).toBe(HOURLY_REASON);
      },
      120_000,
    );

    test(
      "T8 — daily branch in isolation via aged-seed (`ts = now() − 2h`)",
      async () => {
        // hourly == daily == CAP_CENTS (the table CHECK forces hourly ≤ daily).
        const { delegationId, grantee } = await grantDelegation(
          CAP_CENTS,
          CAP_CENTS,
        );

        // Pre-seed aged audit rows summing to CAP_CENTS − COST_CENTS (= 400)
        // with ts = now() − 2h: INSIDE the 24h daily window, OUTSIDE the 1h
        // hourly window. This is the ONLY way to load the daily window while
        // leaving the hourly window empty — with all live calls in one hour,
        // hourly (checked first) always trips at-or-before daily.
        // `audit_byok_use.ts` is client-insertable because the WORM triggers are
        // BEFORE UPDATE/DELETE only; workspace_id is NOT NULL (mig 055/059) so
        // the seed carries the grantor workspace.
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
        const call1 = await recordUse(delegationId, grantee.id, "test-daily-boundary");

        // Live call 2: hourly = 100 (call-1 live row) + 100 = 200 ≤ 500 (does
        // NOT trip); daily = 400 aged + 100 live + 100 = 600 > 500 → refused.
        // The reason being DAILY (not hourly) proves it is the daily branch and
        // pins its strict-`>` boundary.
        const call2 = await recordUse(delegationId, grantee.id, "test-daily-boundary");

        const rows = await auditRowsFor(delegationId);
        // Scope the partition assertion to the daily reason: the fixture holds
        // 4 seed + 1 pass + 1 refusal, so an unscoped count means nothing here.
        const dailyRefusals = refusedRows(rows, DAILY_REASON);
        const hourlyRefusals = refusedRows(rows, HOURLY_REASON);

        const willFail =
          !call1.admitted ||
          call2.refusalReason !== DAILY_REASON ||
          dailyRefusals.length !== 1 ||
          hourlyRefusals.length !== 0 ||
          dailyRefusals[0]?.invocation_id !== call2.invocationId ||
          dailyRefusals[0]?.founder_id !== grantee.id;
        const diag = await diagIf(willFail);

        expect(
          call1.admitted,
          `live call 1 at daily == cap (${CAP_CENTS}) is admitted${diag}`,
        ).toBe(true);
        expect(
          call2.error,
          `live call 2 must not RAISE — refusal is a returned value${diag}`,
        ).toBeNull();
        expect(
          call2.refusalReason,
          `live call 2 (daily would reach ${CAP_CENTS + COST_CENTS}) returns the DAILY reason${diag}`,
        ).toBe(DAILY_REASON);
        expect(
          hourlyRefusals.length,
          `hourly branch did NOT fire (hourly at ${2 * COST_CENTS} ≤ ${CAP_CENTS})${diag}`,
        ).toBe(0);
        expect(
          dailyRefusals.length,
          `exactly 1 row with attribution_shift_reason = ${DAILY_REASON}${diag}`,
        ).toBe(1);
        expect(
          dailyRefusals[0].invocation_id,
          `the daily-refusal row is call 2's own invocation${diag}`,
        ).toBe(call2.invocationId);
        expect(
          dailyRefusals[0].founder_id,
          `daily-refusal row attributes to the GRANTEE${diag}`,
        ).toBe(grantee.id);
      },
      120_000,
    );

    test(
      "T7 — `ON CONFLICT` dedupes an identical replayed payload",
      async () => {
        // NOT the anti-double-count proof. `invocationId` is a fresh
        // randomUUID() per call inside persistTurnCost, so the production
        // double-count is unreachable by ON CONFLICT; what this pins is that a
        // REPLAY of an already-minted payload writes no second row.
        //
        // The positive control is what makes it a real gate: `count === 1`
        // after the FIRST refusal fails against the pre-136 state (which wrote
        // no row at all), so this test cannot pass green against the bug it
        // guards.
        const { delegationId, grantee } = await grantDelegation(
          CAP_CENTS,
          DAILY_CEILING,
        );

        for (let i = 0; i < K; i++) {
          await recordUse(delegationId, grantee.id, "test-replay");
        }

        const replayId = randomUUID();
        const first = await recordUse(delegationId, grantee.id, "test-replay", {
          invocationId: replayId,
        });
        const afterFirst = await rowCountForInvocation(replayId);

        // Byte-identical replay: same invocation id, same cost, same role.
        const second = await recordUse(delegationId, grantee.id, "test-replay", {
          invocationId: replayId,
        });
        const afterSecond = await rowCountForInvocation(replayId);

        const willFail =
          first.refusalReason !== HOURLY_REASON ||
          afterFirst !== 1 ||
          second.refusalReason !== HOURLY_REASON ||
          afterSecond !== 1;
        const diag = await diagIf(willFail);

        expect(
          first.refusalReason,
          `the first over-cap call is refused${diag}`,
        ).toBe(HOURLY_REASON);
        expect(
          afterFirst,
          `POSITIVE CONTROL: the refusal wrote exactly 1 row — 0 here is the ` +
            `pre-136 RAISE-rollback state this test exists to catch${diag}`,
        ).toBe(1);
        expect(
          second.refusalReason,
          `the replay is STILL refused (dedupe must not read as an admit)${diag}`,
        ).toBe(HOURLY_REASON);
        expect(
          afterSecond,
          `the replay added no second row (ON CONFLICT (invocation_id) DO NOTHING)${diag}`,
        ).toBe(1);
      },
      120_000,
    );

    test(
      "T5 — concurrency / FOR UPDATE / no-TOCTOU-double-spend (partitioned)",
      async () => {
        // Hourly cap = CAP_CENTS; daily at the ceiling. Fan out N concurrent
        // uses (each a distinct invocation_id). Concurrency is client-side;
        // serialization is DB-side via the row `FOR UPDATE`. The no-double-spend
        // proof requires the N calls to genuinely overlap in the DB — on a
        // cold/contended pooler, transport-layer serialization could mask a
        // dropped lock. This is an accepted limitation inherited from the
        // b020ebecf precedent; the self-diagnosis banner surfaces any breach
        // that does occur.
        const { delegationId, grantee } = await grantDelegation(
          CAP_CENTS,
          DAILY_CEILING,
        );

        const settled = await Promise.allSettled(
          Array.from({ length: N }, () =>
            recordUse(delegationId, grantee.id, "test-concurrency"),
          ),
        );

        // FIVE disjoint classes, partitioned over `settled` and deliberately
        // NOT over the old `results = settled.map(r => … : null)` array (#7055).
        //
        // `readRefusalReasonLive` THROWS on production's `unreadable` arm — on
        // purpose, because production is fail-CLOSED — and `recordUse` calls it
        // un-caught. So a short or empty PostgREST payload (exactly what a
        // degraded pooler under this suite's own ten-way fan-out produces)
        // makes the promise REJECT, and `Promise.allSettled` yields
        // `status:"rejected"`. Mapping that to `null` first loses the outcome
        // either way: `r?.error !== null` files it under ERRORED and then
        // prints `undefined` for both code and message — a partition naming an
        // outcome it never observed — while `r !== null && r.error !== null`
        // drops it out of every class and silently falsifies the sum below.
        //
        // The counts these classes feed are left at EXACT equality on purpose:
        // exact equality is what proves the row `FOR UPDATE` lock holds. The
        // defect this partition fixes is that an outcome could land in no class
        // and surface as a bare `expected 5, received 4`, not that the counts
        // were too strict.
        const rejected = settled.filter(
          (r): r is PromiseRejectedResult => r.status === "rejected",
        );
        const fulfilled = settled
          .filter(
            (r): r is PromiseFulfilledResult<UseResult> =>
              r.status === "fulfilled",
          )
          .map((r) => r.value);
        const errored = fulfilled.filter((r) => r.error !== null);
        const returned = fulfilled.filter((r) => r.error === null);
        const refusedHourly = returned.filter(
          (r) => r.refusalReason === HOURLY_REASON,
        );
        const refusedOther = returned.filter(
          (r) => r.refusalReason !== null && r.refusalReason !== HOURLY_REASON,
        );
        const admittedCalls = returned.filter((r) => r.refusalReason === null);
        // Exhaustiveness is the structural claim; the membership list is only
        // today's and changes the moment a migration adds a refusal reason —
        // which is why this sums the classes instead of naming four counts.
        const classified = [
          rejected.length,
          errored.length,
          refusedHourly.length,
          refusedOther.length,
          admittedCalls.length,
        ].reduce((a, b) => a + b, 0);
        const admitted = admittedCalls.length;
        const refused = refusedHourly.length;

        const rejectedDetail = rejected
          .map(
            (r) =>
              (r.reason as { message?: string } | undefined)?.message ??
              String(r.reason),
          )
          .join(" | ");
        const erroredDetail = errored
          .map(
            (r) =>
              `${r.invocationId}: code=${r.error?.code ?? "<none>"} ` +
              `message=${r.error?.message ?? "<none>"}`,
          )
          .join(" | ");
        const refusedOtherDetail = refusedOther
          .map(
            (r) =>
              `${r.invocationId}: refusal_reason=${r.refusalReason} ` +
              `code=${r.error?.code ?? "<none>"} message=${r.error?.message ?? "<none>"}`,
          )
          .join(" | ");

        const rows = await auditRowsFor(delegationId);
        const passedRows = admittedRows(rows);
        const refusedLedger = refusedRows(rows, HOURLY_REASON);
        // The LEDGER channel carries the identical blind spot:
        // `refusedRows(rows, HOURLY_REASON)` filters by reason, so a row
        // carrying any OTHER in-enum reason (`daily_cap_exceeded`, `expired`,
        // `revoked_post_grace`, `consent_withdrawn`) falls outside both counted
        // classes in precisely the way the client-side filter excluded a
        // foreign refusal. Partition it too, and assert the third class empty.
        const otherReasonRows = rows.filter(
          (r) =>
            r.attribution_shift_reason !== null &&
            r.attribution_shift_reason !== HOURLY_REASON,
        );
        const ledgerClassified =
          passedRows.length + refusedLedger.length + otherReasonRows.length;
        const otherReasonDetail = otherReasonRows
          .map(
            (r) =>
              `${r.invocation_id}: attribution_shift_reason=${r.attribution_shift_reason}`,
          )
          .join(" | ");

        // Atomicity signal: without FOR UPDATE, concurrent callers reading the
        // same pre-INSERT SUM snapshot would each pass the cap check and INSERT
        // an ADMITTED row → the admitted partition exceeds K and admitted spend
        // exceeds the cap (double-spend). With FOR UPDATE serializing the
        // read+INSERT critical section, exactly K are admitted.
        //
        // NOTE the inversion from the pre-136 shape: `rows.length === K` is NO
        // LONGER the double-spend proof, because every refusal now ledgers too.
        // The proof is the ADMITTED partition and its spend.
        const allFulfilled = settled.every((r) => r.status === "fulfilled");
        // Both new partitions are folded into `willFail` BEFORE `diagIf` is
        // awaited — otherwise the new assertions ship without the live-body
        // diagnostic banner, which is most of their value.
        const willFail =
          !allFulfilled ||
          rejected.length !== 0 ||
          errored.length !== 0 ||
          refusedOther.length !== 0 ||
          classified !== N ||
          otherReasonRows.length !== 0 ||
          ledgerClassified !== rows.length ||
          admitted !== K ||
          refused !== N - K ||
          passedRows.length !== K ||
          spendOf(passedRows) !== CAP_CENTS ||
          refusedLedger.length !== N - K;
        const diag = await diagIf(willFail);

        // The pre-existing assertion, retained ahead of the new ones — but its
        // message now carries the rejection detail too. It and `rejected.length
        // === 0` fail on the same condition, and vitest stops at the first, so
        // without this the rejection message would be reported by an assertion
        // that could not name it.
        expect(
          allFulfilled,
          `all ${N} calls settled fulfilled${
            rejectedDetail ? ` — rejected: ${rejectedDetail}` : ""
          }${diag}`,
        ).toBe(true);
        // The three classes that must be EMPTY, asserted before the counts, so
        // a lost outcome is named rather than showing up as an off-by-one.
        expect(
          rejected.length,
          `no call REJECTED — a rejection is an unreadable PostgREST payload ` +
            `(readRefusalReasonLive is fail-closed and throws): ${rejectedDetail}${diag}`,
        ).toBe(0);
        expect(
          errored.length,
          `no call returned a non-null error: ${erroredDetail}${diag}`,
        ).toBe(0);
        expect(
          refusedOther.length,
          `no call returned a refusal reason other than ${HOURLY_REASON}: ` +
            `${refusedOtherDetail}${diag}`,
        ).toBe(0);
        expect(
          classified,
          `every one of the ${N} settled outcomes lands in exactly one class ` +
            `(rejected=${rejected.length} errored=${errored.length} ` +
            `refused-hourly=${refusedHourly.length} refused-other=${refusedOther.length} ` +
            `admitted=${admittedCalls.length})${diag}`,
        ).toBe(N);

        expect(admitted, `exactly K=${K} calls admitted${diag}`).toBe(K);
        expect(
          refused,
          `exactly N−K=${N - K} calls return the hourly reason${diag}`,
        ).toBe(N - K);

        // The LEDGER partition, same shape: the third class must be empty and
        // the three classes must account for every row read back.
        expect(
          otherReasonRows.length,
          `no ledger row carries a reason other than ${HOURLY_REASON}: ` +
            `${otherReasonDetail}${diag}`,
        ).toBe(0);
        expect(
          ledgerClassified,
          `every audit row lands in exactly one ledger class ` +
            `(admitted=${passedRows.length} refused-hourly=${refusedLedger.length} ` +
            `refused-other=${otherReasonRows.length})${diag}`,
        ).toBe(rows.length);

        // THE PARTITION — the load-bearing pair.
        expect(
          passedRows.length,
          `admitted partition (reason IS NULL) === K=${K} — no double-spend${diag}`,
        ).toBe(K);
        expect(
          spendOf(passedRows),
          `admitted spend === cap (${CAP_CENTS})${diag}`,
        ).toBe(CAP_CENTS);
        expect(
          refusedLedger.length,
          `refused partition (reason = ${HOURLY_REASON}) === N−K=${N - K} — ` +
            `every refused turn's real spend is ledgered (#7829)${diag}`,
        ).toBe(N - K);
        // Derived, not load-bearing: one row per call is a fixture property.
        expect(rows.length, `derived total === N=${N}${diag}`).toBe(N);
        // Every admitted row is the grantor's; every refused row the grantee's.
        expect(
          passedRows.every((r) => r.founder_id === grantor.id),
          `all admitted rows attribute to the grantor${diag}`,
        ).toBe(true);
        expect(
          refusedLedger.every((r) => r.founder_id === grantee.id),
          `all refused rows attribute to the grantee${diag}`,
        ).toBe(true);
      },
      120_000,
    );

    test(
      "T10 — null-change control: a sibling delegation's committed traffic does NOT move delegation A's hourly meter",
      async () => {
        // The property under test is migration 137's meter predicate,
        // `WHERE au.delegation_id = p_delegation_id AND au.ts > clock_timestamp()
        // - interval '1 hour'` — an equality on a primary key. An equality does
        // not need two simultaneous writers to be tested, so THIS CONTROL IS
        // SEQUENTIAL BY DESIGN. A concurrent form would add a second fan-out,
        // two more synthetic users and several more overlapping transactions to
        // the very suite being repaired for going red intermittently (#7055) —
        // raising the rate of the thing it exists to help. Sequential is both
        // cheaper and strictly more deterministic.
        //
        // T5's pooler-serialization limitation banner is deliberately NOT
        // copied here: T5 needs genuine overlap for its lock proof and inherits
        // that caveat; this control never overlaps at all, so claiming the
        // limitation would be claiming one it does not have.
        //
        // WHAT IS TRUE OF THE RPC UNDER TEST AND FALSE OF ITS LAYER-1 SIBLING.
        // Migration 137 carries a SECOND meter without this property.
        // `record_byok_use_and_check_cap` — the founder-cap sibling — sums
        // `WHERE founder_id = p_founder_id AND attribution_shift_reason IS NULL
        // AND ts > now() - interval '1 hour'`, with NO delegation filter. Both
        // A's and B's ADMITTED rows carry `founder_id = grantor.id`, so B's
        // traffic DOES pool into A's founder-scoped hourly meter even though it
        // provably cannot touch A's delegation-scoped one. Do not generalise
        // "delegations are isolated" past the predicate that makes it true.
        // Whether that founder-scoped pooling is a defect is out of scope here;
        // naming it is not.
        const M = 3;
        // Genuine headroom: all M of B's calls are admitted, and no arithmetic
        // is left implicit. Satisfies `byok_delegations_hourly_le_daily`
        // (B_CAP_CENTS ≪ DAILY_CEILING).
        const B_CAP_CENTS = M * COST_CENTS;

        // A is T5's fixture exactly: hourly pinned at CAP_CENTS, daily at the
        // ceiling.
        const a = await grantDelegation(CAP_CENTS, DAILY_CEILING);
        // B is a SIBLING: same grantor, same workspace. It is legal only
        // because `grantDelegation()` mints a FRESH grantee per call —
        // `064_byok_delegations.sql` › `byok_delegations_active_triple_uidx` is
        // unique on (grantor_user_id, grantee_user_id, workspace_id) WHERE
        // revoked_at IS NULL and `grant_byok_delegation` has no ON CONFLICT, so
        // a second grant to the same grantee would raise. `grantDelegation()`
        // also runs `addMember(grantor.workspaceId, grantee.id)` first, without
        // which the `byok_delegations_same_workspace` trigger raises
        // `byok_delegations:cross-tenant`.
        const b = await grantDelegation(B_CAP_CENTS, DAILY_CEILING);

        // STEP 1 — the outside writer runs FIRST, alone, to completion.
        const bResults: UseResult[] = [];
        for (let i = 0; i < M; i++) {
          bResults.push(
            await recordUse(b.delegationId, b.grantee.id, "test-null-change-b"),
          );
        }
        // `admitted` means the RPC returned no error and no refusal reason, and
        // migration 137 does the cap check and the audit INSERT inside one
        // transaction — so an admitted call is a COMMITTED row. The count is
        // therefore the positive control on its own; a second read-back of B's
        // ledger would only re-assert the same fact, and would additionally
        // steal the discriminative failure from the negative control when B's
        // delegation id is moved onto A's (Guard 3 mutation row 4).
        const bAdmitted = bResults.filter((r) => r.admitted).length;

        // STEP 2 — THEN drive A's N calls, at the same cost T5 uses. Calls
        // 1..K reach exactly CAP_CENTS and are admitted; K+1..N breach and
        // return the hourly reason.
        const aResults: UseResult[] = [];
        for (let i = 0; i < N; i++) {
          aResults.push(
            await recordUse(a.delegationId, a.grantee.id, "test-null-change-a"),
          );
        }
        const aAdmitted = aResults.filter((r) => r.admitted).length;
        const aRefused = aResults.filter(
          (r) => r.refusalReason === HOURLY_REASON,
        ).length;
        const aRows = await auditRowsFor(a.delegationId);

        // `addMember` inside `grantDelegation` fails LOUD but fails AFTER B's
        // user, org, workspace and membership rows exist, and `afterAll`
        // deletes nothing — so a failed run still grows the #3934 synthetic
        // population. Phase 3.3 wires the diagnostic banner into T5 only, so
        // wire one in here too rather than failing bare.
        const willFail =
          bAdmitted !== M ||
          aAdmitted !== K ||
          aRefused !== N - K ||
          aRows.length !== N;
        const diag = await diagIf(willFail);

        // POSITIVE CONTROL. Without it the negative control is vacuous: a B
        // that refuses for its own reasons never writes, and "A is unchanged"
        // would then pass by B having done nothing.
        expect(
          bAdmitted,
          `POSITIVE CONTROL: all M=${M} of the sibling's calls are admitted ` +
            `(cap ${B_CAP_CENTS} has genuine headroom) — a B that never writes ` +
            `makes the negative control below vacuous${diag}`,
        ).toBe(M);
        // NEGATIVE CONTROL. B's M committed rows sit in the same table, under
        // the same workspace and the same grantor, inside the same rolling
        // hour — and A's counts are exactly what T5 asserts with no sibling
        // present at all.
        expect(
          aAdmitted,
          `NEGATIVE CONTROL: A still admits exactly K=${K} — the sibling's ` +
            `${M} rows do not enter A's delegation-scoped meter${diag}`,
        ).toBe(K);
        expect(
          aRefused,
          `NEGATIVE CONTROL: A still refuses exactly N−K=${N - K}${diag}`,
        ).toBe(N - K);
        expect(
          aRows.length,
          `NEGATIVE CONTROL: A's ledger holds exactly N=${N} rows${diag}`,
        ).toBe(N);
      },
      120_000,
    );

    test(
      "caller identity pin — a non-grantee caller RAISES 42501 and ledgers NOTHING",
      async () => {
        // Added by mig 137. Once a refusal row persists, `founder_id` is a
        // durable BILLING assertion that enters the named user's DSAR export —
        // so the RPC must refuse to book one caller's turn against another's
        // identity. The grantor is the sharpest probe: they own the delegation
        // and the key, and were still never its grantee.
        const { delegationId } = await grantDelegation(CAP_CENTS, DAILY_CEILING);

        const asGrantor = await recordUse(
          delegationId,
          grantor.id,
          "test-caller-pin",
        );
        const rows = await auditRowsFor(delegationId);

        const willFail =
          asGrantor.error === null ||
          !/byok_delegations:caller_not_grantee/.test(
            asGrantor.error?.message ?? "",
          ) ||
          rows.length !== 0;
        const diag = await diagIf(willFail);

        expect(
          asGrantor.error,
          `calling as the grantor RAISES (a validation failure, not an accounted refusal)${diag}`,
        ).not.toBeNull();
        expect(
          asGrantor.error?.message,
          `caller_not_grantee marker${diag}`,
        ).toMatch(/byok_delegations:caller_not_grantee/);
        expect(asGrantor.error?.code, `SQLSTATE 42501${diag}`).toBe("42501");
        expect(
          asGrantor.refusalReason,
          `a raise is NOT a refusal reason${diag}`,
        ).toBeNull();
        // No provider call is attributable to a caller the delegation does not
        // resolve for, so no ledger row is owed.
        expect(
          rows.length,
          `no audit row is written for a rejected caller${diag}`,
        ).toBe(0);
      },
      120_000,
    );

    test("case floor — every scenario in this file is still dispatched", () => {
      // WHY THIS EXISTS. Deleting a `test(...)` block from a vitest file leaves
      // a GREEN run: the deleted scenario simply stops being reported, and
      // nothing in the suite notices. The null-change control above is a
      // control — silently losing it is exactly the failure it is meant to
      // prevent — so this file needs a dispatch floor, and it had none. (The
      // ADR-193 floor cited nearby is on the SHELL suite
      // `tests/scripts/test-tenant-integration-gate-verdict.sh`, a different
      // artifact; it does not cover this file.)
      //
      // It lives INSIDE `describe.skipIf(!INTEGRATION_ENABLED)` on purpose:
      // outside it, this file would report a non-zero test count even without
      // TENANT_INTEGRATION_TEST=1, which is precisely the "a check that passed
      // because its suite was skipped" signal the acceptance command relies on.
      //
      // Counting is anchored on the source's own dispatch lines (`    test(` at
      // the describe body's indent), not on a token that also appears in prose.
      const source = readFileSync(fileURLToPath(import.meta.url), "utf8");
      const dispatched = source.match(/^ {4}test\(/gm)?.length ?? 0;
      expect(
        dispatched,
        "this file dispatches EXPECTED_TEST_CASES scenarios — if you added or " +
          "removed one deliberately, update the constant in the same commit; " +
          "if you did not, a scenario was lost",
      ).toBe(EXPECTED_TEST_CASES);
    });
  },
);
