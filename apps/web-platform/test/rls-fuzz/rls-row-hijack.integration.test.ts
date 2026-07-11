import { describe, test, expect, beforeAll, afterAll } from "vitest";
import { randomUUID } from "node:crypto";
import type postgres from "postgres";
import { classifyMutationOutcome, type Verdict } from "./verdict";
import { rowHijackTables } from "./catalog";
import { type Ctx, type Locate } from "./targets";
import { connect, seedTwoTenant, asTenant } from "./harness-fixture";

// Row-hijack WITH-CHECK variant (#6307 Item 3 / F4, ADR-111, AC6). The base matrix's
// UPDATE attack does a no-op self-assign (SET col = col); this probes the WITH CHECK
// directly by having the ROW OWNER reassign the tenancy key (SET workspace_id = wsB).
// Running it as a NON-owner (userB) would be vacuous — USING filters A's row → 0 rows
// → WITH CHECK never evaluates → always "denied", proving nothing. Only the owner
// passes USING and can exercise WITH CHECK. A policy whose WITH CHECK re-checks
// membership on the NEW workspace_id denies (42501); one that only re-checks
// user_id = auth.uid() lets the owner re-home the row into a workspace it is not a
// member of → leaked. Gated behind RLS_FUZZ_LOCAL=1 against a LOCAL disposable Postgres.
const ENABLED = process.env.RLS_FUZZ_LOCAL === "1";
const DSN = process.env.RLS_FUZZ_DATABASE_URL ?? "postgres://postgres:postgres@127.0.0.1:54322/postgres";

let sql: postgres.Sql<{}>;
let ctx: Ctx;

interface HijackTarget {
  table: string;
  /** A non-tenancy column for the positive control (owner CAN update its own row). */
  posCol: string;
  seed(base: postgres.Sql<{}>, c: Ctx): Promise<Locate>;
}

const idLoc = (id: string): Locate => ({ where: "id = $1", params: [id] });

// Catalog-derived at runtime (AC6 asserts the registry matches rowHijackTables);
// dispositions verified against the live UPDATE/ALL policy WITH CHECK clauses.
const HIJACK_TARGETS: HijackTarget[] = [
  {
    table: "conversations",
    posCol: "status",
    seed: async (b, c) => {
      const [{ id }] = await b`insert into conversations (id, user_id, workspace_id, status, visibility)
        values (${randomUUID()}, ${c.userA}, ${c.wsA}, 'active', 'workspace') returning id`;
      return idLoc(id);
    },
  },
  {
    table: "kb_files",
    posCol: "filename",
    seed: async (b, c) => {
      const [{ id }] = await b`insert into kb_files (workspace_id, user_id, file_path, filename, visibility)
        values (${c.wsA}, ${c.userA}, ${`/a/${randomUUID()}`}, 'a', 'workspace') returning id`;
      return idLoc(id);
    },
  },
  {
    table: "kb_share_links",
    posCol: "document_path",
    seed: async (b, c) => {
      const [{ id }] = await b`insert into kb_share_links (user_id, workspace_id, token, document_path, content_sha256)
        values (${c.userA}, ${c.wsA}, ${`tok-${randomUUID()}`}, ${`/a/${randomUUID()}`}, ${"a".repeat(64)}) returning id`;
      return idLoc(id);
    },
  },
  {
    table: "push_subscriptions",
    posCol: "endpoint",
    seed: async (b, c) => {
      const [{ id }] = await b`insert into push_subscriptions (user_id, workspace_id, endpoint, p256dh, auth)
        values (${c.userA}, ${c.wsA}, ${`https://push.test/${randomUUID()}`}, 'p', 'au') returning id`;
      return idLoc(id);
    },
  },
];

// The two exposures the hijack SURFACES (harness found them; #6307 Phase 5). Both
// have an UPDATE WITH CHECK of `user_id = auth.uid()` ONLY — no is_workspace_member
// re-check on the NEW workspace_id — so the owner can re-home the row into a
// workspace it does not belong to. Baselined as test.fails (KNOWN_EXPOSURES contract:
// green while tracked, RED once the WITH CHECK is fixed → forces un-baseline).
// Tracked by #6334 (filed from this run).
const HIJACK_EXPOSURES = new Set(["conversations", "kb_files"]);

const seeded = new Map<string, Locate>();

/** Owner-A reassigns the tenancy key to wsB (rolled back). count≥1 = leaked, 42501/0-rows = denied. */
async function hijack(table: string, loc: Locate): Promise<Verdict> {
  return asTenant(sql, ctx.userA, async (t): Promise<Verdict> => {
    try {
      const res = await t.unsafe(
        `update "${table}" set workspace_id = $${loc.params.length + 1} where ${loc.where} returning id`,
        [...loc.params, ctx.wsB] as never[],
      );
      return classifyMutationOutcome(null, res.count); // a returned row now carries wsB → leaked
    } catch (err) {
      return classifyMutationOutcome(err as { code?: string }, 0); // WITH CHECK 42501 → denied
    }
  });
}

describe.skipIf(!ENABLED)("RLS/authz-fuzz — row-hijack WITH-CHECK (owner attacker, local)", () => {
  beforeAll(async () => {
    sql = connect(DSN); // assertLocalDsn + max:1 pinned in the shared fixture
    ctx = await seedTwoTenant(sql);
    for (const h of HIJACK_TARGETS) seeded.set(h.table, await h.seed(sql, ctx));
  });
  afterAll(async () => {
    if (sql) await sql.end({ timeout: 5 });
  });

  // AC6 gate: the registry is the catalog UPDATE/ALL-policy set, not a hand-list.
  test("AC6: hijack registry == catalog rowHijackTables set", async () => {
    const catalog = new Set(await rowHijackTables(sql));
    const registry = new Set(HIJACK_TARGETS.map((h) => h.table));
    const uncovered = [...catalog].filter((t) => !registry.has(t));
    const stale = [...registry].filter((t) => !catalog.has(t));
    expect(uncovered, `UPDATE-policy tables with no hijack case: ${uncovered.join(", ")}`).toEqual([]);
    expect(stale, `hijack registry entries not in the catalog set: ${stale.join(", ")}`).toEqual([]);
  });

  // Fixture invariant the oracle depends on: userA is NOT a member of wsB (else a
  // "denied" could be membership-legitimate rather than the WITH CHECK doing its job).
  test("fixture invariant: userA is not a member of wsB", async () => {
    const [{ m }] = await sql<{ m: boolean }[]>`select is_workspace_member(${ctx.wsB}, ${ctx.userA}) as m`;
    expect(m, "userA must be a non-member of wsB for the hijack oracle to be sound").toBe(false);
  });

  for (const h of HIJACK_TARGETS) {
    const loc = () => seeded.get(h.table)!;

    // Positive control (every target): the owner CAN update a NON-tenancy column on
    // its own row — so a hijack "denied" is the WITH CHECK working, not a missing
    // UPDATE policy / non-existent row.
    test(`row-hijack positive control: owner updates ${h.table}.${h.posCol}`, async () => {
      const affected = await asTenant(sql, ctx.userA, async (t) => {
        const res = await t.unsafe(
          `update "${h.table}" set "${h.posCol}" = "${h.posCol}" where ${loc().where}`,
          loc().params as never[],
        );
        return res.count;
      });
      expect(affected, `${h.table}: owner must be able to update its own non-tenancy column`).toBe(1);
    });

    if (HIJACK_EXPOSURES.has(h.table)) {
      // KNOWN exposure — the UPDATE WITH CHECK is user_id=auth.uid() only. This
      // assertion (expect denied) FAILS today because the hijack leaks, so test.fails
      // is green; when the WITH CHECK adds is_workspace_member(NEW.workspace_id, …) it
      // will pass → test.fails reds → forces un-baseline. Tracked by #6334.
      test.fails(`row-hijack EXPOSURE (baselined, #6334): ${h.table} owner can re-home to wsB`, async () => {
        expect(await hijack(h.table, loc())).toEqual({ kind: "denied" });
      });
    } else {
      test(`row-hijack: ${h.table} WITH CHECK denies owner re-home to wsB`, async () => {
        expect(await hijack(h.table, loc()), `${h.table}: SET workspace_id=wsB must be denied`).toEqual({
          kind: "denied",
        });
      });
    }
  }
});
