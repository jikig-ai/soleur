import { describe, test, expect, beforeAll, afterAll } from "vitest";
import type postgres from "postgres";
import {
  classifyWriteOutcome,
  classifyMutationOutcome,
  classifySelectOutcome,
  isPass,
  type Verdict,
} from "./verdict";
import { userIsolationTables, isolationSet, workspaceTenancyTables } from "./catalog";
import { USER_ISOLATION_TARGETS, USER_EXCLUDED, type Ctx, type Locate } from "./targets";
import { connect, seedTwoTenant, asTenant } from "./harness-fixture";

// USER-ISOLATION dimension (#6307 Item 5, ADR-111, AC3). The base matrix models
// WORKSPACE isolation (attacker = a non-member of wsA). This models WITHIN-workspace
// USER isolation: a CO-MEMBER of wsA (userC) reading/writing another member's
// (userA's) `user_id = auth.uid()`-keyed rows. userC — NOT the base matrix's userB —
// is the load-bearing attacker: a workspace-only policy denies userB even when the
// user_id clause is missing, so the real co-member leak stays invisible. The catalog
// enumerates the set (disjoint from AC1/AC1b by SQL construction). Gated behind
// RLS_FUZZ_LOCAL=1 against a LOCAL disposable Postgres.
const ENABLED = process.env.RLS_FUZZ_LOCAL === "1";
const DSN = process.env.RLS_FUZZ_DATABASE_URL ?? "postgres://postgres:postgres@127.0.0.1:54322/postgres";

let sql: postgres.Sql<{}>;
let ctx: Ctx;
const seeded = new Map<string, Locate>();

async function countRows(h: postgres.Sql | postgres.TransactionSql, table: string, loc: Locate): Promise<number> {
  const rows = await h.unsafe(`select count(*)::int as n from "${table}" where ${loc.where}`, loc.params as never[]);
  return (rows[0] as unknown as { n: number }).n;
}

describe.skipIf(!ENABLED)("RLS/authz-fuzz — user-isolation dimension (co-member attacker, local)", () => {
  beforeAll(async () => {
    sql = connect(DSN); // assertLocalDsn + max:1 pinned in the shared fixture
    ctx = await seedTwoTenant(sql);
    for (const t of USER_ISOLATION_TARGETS) seeded.set(t.table, await t.seed(sql, ctx));
  });
  afterAll(async () => {
    if (sql) await sql.end({ timeout: 5 });
  });

  // AC3 coverage gate: the live user-isolation set ⊆ targets ∪ excluded (self-
  // tracking — a new user-keyed table with no case reds here), rationales non-trivial,
  // AND the partition is provably DISJOINT from the workspace dimensions (AC1/AC1b).
  test("AC3: userIsolationTables ⊆ targets ∪ excluded, disjoint from AC1/AC1b by construction", async () => {
    const surface = await userIsolationTables(sql);
    const targets = new Set(USER_ISOLATION_TARGETS.map((t) => t.table));
    const excluded = new Set(Object.keys(USER_EXCLUDED));
    const escaped = surface.filter((t) => !targets.has(t) && !excluded.has(t));
    expect(escaped, `user-keyed tables neither targeted nor excluded: ${escaped.join(", ")}`).toEqual([]);
    for (const [t, reason] of Object.entries(USER_EXCLUDED)) {
      expect(reason.length, `${t}: excluded without rationale`).toBeGreaterThan(20);
    }
    // Disjointness proof: the user-isolation set shares nothing with the workspace
    // dimensions — so AC1/AC1b/AC3 are mutually exhaustive, not overlapping-blind.
    const userSet = new Set(surface);
    const workspace = new Set([...(await isolationSet(sql)), ...(await workspaceTenancyTables(sql))]);
    const overlap = [...userSet].filter((t) => workspace.has(t));
    expect(overlap, `AC1/AC3 not disjoint — tables in both dimensions: ${overlap.join(", ")}`).toEqual([]);
  });

  // Per target: precondition, owner positive control, CO-MEMBER negative (the new
  // path — no existing test drives a co-member attacker), write-side.
  for (const target of USER_ISOLATION_TARGETS) {
    test(`user-isolation: ${target.table}`, async () => {
      const loc = seeded.get(target.table)!;

      // precondition: service_role sees A's one seeded row (guards vacuous green).
      expect(await countRows(sql, target.table, loc), `${target.table}: seed precondition`).toBe(1);

      // AC3 positive control: the OWNER (userA) CAN see its own row.
      const aSees = await asTenant(sql, ctx.userA, (t) => countRows(t, target.table, loc));
      expect(aSees, `${target.table}: positive control (owner A self-read)`).toBe(1);

      // AC3 co-member negative: userC (a wsA co-member) sees 0 of A's row → denied.
      const cSees = await asTenant(sql, ctx.userC, (t) => countRows(t, target.table, loc));
      expect(isPass(classifySelectOutcome(cSees)), `${target.table}: co-member C SELECT (saw ${cSees})`).toBe(true);

      // write-side — INSERT-forge as co-member C (where a real WITH CHECK applies): 42501.
      if (target.forge) {
        const insV = await asTenant(sql, ctx.userC, async (t): Promise<Verdict> => {
          try {
            await target.forge!(t, ctx);
            return classifyWriteOutcome(null);
          } catch (err) {
            return classifyWriteOutcome(err as { code?: string });
          }
        });
        expect(insV, `${target.table}: co-member INSERT-forge must be RLS-denied (42501)`).toEqual({ kind: "denied" });
      }

      // write-side — UPDATE A's row as C: USING filters it → 0 rows (denied).
      const updV = await asTenant(sql, ctx.userC, async (t): Promise<Verdict> => {
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
      expect(updV, `${target.table}: co-member UPDATE must not touch A's row`).toEqual({ kind: "denied" });

      // write-side — DELETE A's row as C: USING filters it → 0 rows (denied).
      const delV = await asTenant(sql, ctx.userC, async (t): Promise<Verdict> => {
        try {
          const res = await t.unsafe(`delete from "${target.table}" where ${loc.where}`, loc.params as never[]);
          return classifyMutationOutcome(null, res.count);
        } catch (err) {
          return classifyMutationOutcome(err as { code?: string }, 0);
        }
      });
      expect(delV, `${target.table}: co-member DELETE must not remove A's row`).toEqual({ kind: "denied" });

      // tail: A's row is still present after every attack.
      expect(await countRows(sql, target.table, loc), `${target.table}: A row intact after attacks`).toBe(1);
    });
  }
});
