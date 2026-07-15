import { describe, test, expect, beforeAll, afterAll } from "vitest";
import { randomUUID } from "node:crypto";
import type postgres from "postgres";
import { buildAuthenticatedClaims } from "./claim";
import {
  classifyWriteOutcome,
  classifyMutationOutcome,
  classifySelectOutcome,
  isPass,
  RLS_VIOLATION_SQLSTATE,
  type Verdict,
} from "./verdict";
import { isolationSet, workspaceTenancyTables } from "./catalog";
import { ISOLATION_TARGETS, EXCLUDED_ISOLATION, type Ctx, type Locate } from "./targets";
import { connect, seedTwoTenant, attackAs, rolledBackRaw } from "./harness-fixture";

// Runtime RLS/authz-fuzz harness (#6256, ADR-111). Drives a non-member tenant's
// identity against another tenant's rows across every workspace-isolated RLS
// table (catalog-derived) and asserts RLS denies at the DB layer. Gated: runs
// only with RLS_FUZZ_LOCAL=1 against a LOCAL disposable Postgres (the normal
// suite skips it — no stack in ordinary CI). The shared connect/seed/txn helpers
// live in harness-fixture.ts (Item 8 — one module, no per-file forks).
const ENABLED = process.env.RLS_FUZZ_LOCAL === "1";
const DSN = process.env.RLS_FUZZ_DATABASE_URL ?? "postgres://postgres:postgres@127.0.0.1:54322/postgres";

let sql: postgres.Sql<{}>;
let ctx: Ctx;
const seeded = new Map<string, Locate>();

/** Set role+claims, run fn, roll back. Thin alias over the shared attackAs (bound sql). */
const attackTxn = <T>(claims: string, fn: (t: postgres.TransactionSql<{}>) => Promise<T>): Promise<T> =>
  attackAs(sql, claims, fn);

/** Count rows matching A's seeded canonical row under the given handle/role. */
async function countRows(h: postgres.Sql | postgres.TransactionSql, table: string, loc: Locate): Promise<number> {
  const rows = await h.unsafe(`select count(*)::int as n from "${table}" where ${loc.where}`, loc.params as never[]);
  return (rows[0] as unknown as { n: number }).n;
}

describe.skipIf(!ENABLED)("RLS/authz-fuzz — cross-tenant isolation (local, catalog-driven)", () => {
  beforeAll(async () => {
    sql = connect(DSN); // assertLocalDsn + max:1 pinned in the shared fixture
    ctx = await seedTwoTenant(sql);
    for (const t of ISOLATION_TARGETS) {
      seeded.set(t.table, await t.seed(sql, ctx));
    }
  });

  afterAll(async () => {
    if (sql) await sql.end({ timeout: 5 });
  });

  // AC1 — the registry must exactly mirror the live isolation set. A new isolated
  // table with no attack case, or a stale registry entry, fails HERE.
  test("AC1: registry mirrors the live pg_policies isolation set (no source grep)", async () => {
    const catalog = new Set(await isolationSet(sql));
    const registry = new Set(ISOLATION_TARGETS.map((t) => t.table));
    const uncovered = [...catalog].filter((t) => !registry.has(t));
    const stale = [...registry].filter((t) => !catalog.has(t));
    expect(uncovered, `catalog-isolated tables with no attack case: ${uncovered.join(", ")}`).toEqual([]);
    expect(stale, `registry tables not in the live isolation set: ${stale.join(", ")}`).toEqual([]);
  });

  // AC1b — the broader workspace-tenancy surface (workspace_id/message_id-carrying
  // RLS tables) is a SUPERSET of the is_workspace_member predicate set. Every such
  // table must be a base target OR an explicit exclusion-with-rationale; a table
  // isolated by a different predicate (is_workspace_owner, EXISTS-join) can no
  // longer silently escape the harness (the F3 gap).
  test("AC1b: every workspace-tenancy RLS table is targeted or excluded-with-rationale", async () => {
    const surface = await workspaceTenancyTables(sql);
    const targets = new Set(ISOLATION_TARGETS.map((t) => t.table));
    const excluded = new Set(Object.keys(EXCLUDED_ISOLATION));
    const escaped = surface.filter((t) => !targets.has(t) && !excluded.has(t));
    expect(escaped, `workspace-tenancy tables neither targeted nor excluded: ${escaped.join(", ")}`).toEqual([]);
    for (const [t, reason] of Object.entries(EXCLUDED_ISOLATION)) {
      expect(reason.length, `${t}: excluded without rationale`).toBeGreaterThan(20);
    }
  });

  // AC2/AC3 — per isolated table: precondition, cross-tenant denial, positive control, write-side.
  for (const target of ISOLATION_TARGETS) {
    test(`isolation: ${target.table}`, async () => {
      const loc = seeded.get(target.table)!;
      const bClaims = buildAuthenticatedClaims({ sub: ctx.userB });
      const aClaims = buildAuthenticatedClaims({ sub: ctx.userA });

      // AC2 precondition: service_role sees exactly A's one seeded row (guards vacuous green).
      expect(await countRows(sql, target.table, loc), `${target.table}: seed precondition`).toBe(1);

      if (target.selectAuthBlocked) {
        // The SELECT policy is grant-blocked for all authenticated (auth.users ref):
        // A and B both hit 42501, so the SELECT dimension proves nothing about tenancy.
        // Assert B is denied (permission error is a denial) and lean on the write-side.
        const bBlocked = await attackTxn(bClaims, async (t): Promise<Verdict> => {
          try {
            return classifySelectOutcome(await countRows(t, target.table, loc));
          } catch (err) {
            const code = (err as { code?: string }).code;
            return code === RLS_VIOLATION_SQLSTATE ? { kind: "denied" } : { kind: "test-error", sqlstate: code ?? "unknown" };
          }
        });
        expect(bBlocked, `${target.table}: B SELECT must be denied (grant-blocked or filtered)`).toEqual({ kind: "denied" });
      } else {
        // AC3 positive control: tenant A CAN see its own row (falsifies a green-by-emptiness matrix).
        const aSees = await attackTxn(aClaims, (t) => countRows(t, target.table, loc));
        expect(aSees, `${target.table}: positive control (A self-read)`).toBe(1);

        // AC2 cross-tenant SELECT: tenant B sees 0 of A's row → denied.
        const bSees = await attackTxn(bClaims, (t) => countRows(t, target.table, loc));
        expect(isPass(classifySelectOutcome(bSees)), `${target.table}: B SELECT verdict (saw ${bSees})`).toBe(true);
      }

      // AC2 write-side — INSERT-forge (where the table has no pre-RLS trigger): expect 42501.
      if (target.forge) {
        const insVerdict = await attackTxn(bClaims, async (t): Promise<Verdict> => {
          try {
            await target.forge!(t, ctx);
            return classifyWriteOutcome(null); // committed → cross-tenant write went through
          } catch (err) {
            return classifyWriteOutcome(err as { code?: string });
          }
        });
        expect(insVerdict, `${target.table}: INSERT-forge must be an RLS denial (42501)`).toEqual({ kind: "denied" });
      }

      // AC2 write-side — UPDATE A's row: USING filters it → 0 rows affected (denied).
      const updVerdict = await attackTxn(bClaims, async (t): Promise<Verdict> => {
        try {
          const res = await t.unsafe(
            `update "${target.table}" set "${target.updateCol}" = "${target.updateCol}" where ${loc.where}`,
            loc.params as never[],
          );
          return classifyMutationOutcome(null, res.count);
        } catch (err) {
          return classifyMutationOutcome(err as { code?: string }, 0);
        }
      });
      expect(updVerdict, `${target.table}: cross-tenant UPDATE must not touch A's row`).toEqual({ kind: "denied" });

      // AC2 write-side — DELETE A's row: USING filters it → 0 rows affected (denied).
      const delVerdict = await attackTxn(bClaims, async (t): Promise<Verdict> => {
        try {
          const res = await t.unsafe(`delete from "${target.table}" where ${loc.where}`, loc.params as never[]);
          return classifyMutationOutcome(null, res.count);
        } catch (err) {
          return classifyMutationOutcome(err as { code?: string }, 0);
        }
      });
      expect(delVerdict, `${target.table}: cross-tenant DELETE must not remove A's row`).toEqual({ kind: "denied" });

      // AC2 tail: A's row is still present + unchanged after every write attempt.
      expect(await countRows(sql, target.table, loc), `${target.table}: A row intact after attacks`).toBe(1);
    });
  }

  // AC3 — inert negative control: adding a forged org claim changes ZERO RLS
  // decisions (documents that `sub` is the only lever; no policy reads the org claim).
  test("AC3: claim org-swap is inert (sub is the only attacker dimension)", async () => {
    const loc = seeded.get("workspaces")!;
    // B with A's org id in the claim still sees nothing.
    const bWithOrgA = buildAuthenticatedClaims({ sub: ctx.userB, organizationId: ctx.orgA });
    const bSees = await attackTxn(bWithOrgA, (t) => countRows(t, "workspaces", loc));
    expect(bSees, "org-swap must not grant B visibility").toBe(0);
    // A with a bogus org id still sees its own row (org claim is not consulted).
    const aWithBogusOrg = buildAuthenticatedClaims({ sub: ctx.userA, organizationId: randomUUID() });
    const aSees = await attackTxn(aWithBogusOrg, (t) => countRows(t, "workspaces", loc));
    expect(aSees, "bogus org must not revoke A's own visibility").toBe(1);
  });

  // AC4 — jti two-sided on ONE seeded row (A's own workspace, in both the isolation
  // and jti-deny sets). An ALLOWED jti permits; a DENIED jti blocks — SAME row, so a
  // stuck-true/stuck-false jti extractor is falsified (runtime proof of verify/068).
  test("AC4: jti two-sided — allowed jti permits, denied jti blocks (same row)", async () => {
    const loc = seeded.get("workspaces")!;
    const allowedJti = randomUUID();
    const deniedJti = randomUUID();

    const permitted = await attackTxn(buildAuthenticatedClaims({ sub: ctx.userA, jti: allowedJti }), (t) =>
      countRows(t, "workspaces", loc),
    );
    expect(permitted, "allowed jti: A must see its own workspace").toBe(1);

    // Revoke deniedJti (SECURITY DEFINER is_jti_denied reads denied_jti regardless of RLS).
    await sql`insert into denied_jti (jti, founder_id) values (${deniedJti}, ${ctx.userA})`;
    const blocked = await attackTxn(buildAuthenticatedClaims({ sub: ctx.userA, jti: deniedJti }), (t) =>
      countRows(t, "workspaces", loc),
    );
    expect(blocked, "denied jti: the RESTRICTIVE jti policy must block the SAME row").toBe(0);
  });

  // AC5 — mutation self-test: with RLS disabled on one table (rolled back), the
  // harness's own SELECT verdict flips to leaked (RED). Proves the harness can
  // detect a real isolation break, not just report green on an already-safe DB.
  test("AC5: mutation self-test — disabling RLS makes the harness report RED", async () => {
    const table = "workspace_activity";
    const loc = seeded.get(table)!;
    const bSeesWithRlsOff = await rolledBackRaw(sql, async (t) => {
      await t.unsafe(`alter table "${table}" disable row level security`); // superuser, before the role swap
      await t`set local role authenticated`;
      await t.unsafe("select set_config('request.jwt.claims', $1, true)", [
        buildAuthenticatedClaims({ sub: ctx.userB }),
      ]);
      return countRows(t, table, loc); // roll back → RLS re-enabled
    });
    expect(bSeesWithRlsOff, "with RLS off, B must see A's row").toBeGreaterThan(0);
    expect(isPass(classifySelectOutcome(bSeesWithRlsOff)), "harness verdict must be RED (not a pass)").toBe(false);
  });

  // AC10 — routine_runs / routine_run_progress are intentionally OPS-GLOBAL (SELECT
  // policy `auth.uid() IS NOT NULL` → any authenticated user reads all rows). The
  // harness only expresses DENIAL assertions, so an intentional-global table has no
  // falsifiable guard — "ops-global, no PII" as prose is unfalsifiable, and a future
  // migration adding a workspace_id/user_id (or any PII) column would leak with a
  // green suite. This ENFORCES the invariant: the live column set must stay within a
  // non-PII allowlist AND carry no tenant-identifying column, so either such a change
  // reds this test (forcing a per-tenant policy) or the allowlist is deliberately
  // widened under review.
  test("AC10: routine_runs/routine_run_progress stay ops-global (no tenant-identifying column)", async () => {
    const OPS_GLOBAL: Record<string, Set<string>> = {
      routine_runs: new Set([
        "id", "routine_id", "run_id", "status", "trigger_source", "actor_class", "actor_id",
        "delegating_principal", "started_at", "ended_at", "duration_ms", "error_summary", "created_at",
      ]),
      routine_run_progress: new Set(["id", "routine_id", "run_id", "attempt", "started_at", "last_heartbeat_at"]),
    };
    const TENANT_COLS = ["workspace_id", "user_id", "founder_id"];
    for (const [table, allow] of Object.entries(OPS_GLOBAL)) {
      const rows = await sql<{ column_name: string }[]>`
        select column_name from information_schema.columns
        where table_schema = 'public' and table_name = ${table}`;
      const live = rows.map((r) => r.column_name);
      const tenant = live.filter((c) => TENANT_COLS.includes(c));
      expect(tenant, `${table}: grew a tenant-identifying column — global-read is now a per-tenant leak`).toEqual([]);
      const unlisted = live.filter((c) => !allow.has(c));
      expect(
        unlisted,
        `${table}: new column(s) outside the non-PII allowlist — review global-read safety before widening: ${unlisted.join(", ")}`,
      ).toEqual([]);
    }
    // Reconcile with AC1b: no workspace_id means these must NOT surface in the
    // workspace-tenancy set (else a silent exclusion there would defeat AC1b).
    const wsTenancy = new Set(await workspaceTenancyTables(sql));
    for (const table of Object.keys(OPS_GLOBAL)) {
      expect(wsTenancy.has(table), `${table}: unexpectedly in workspaceTenancyTables — reconcile with AC1b`).toBe(false);
    }
  });
});
