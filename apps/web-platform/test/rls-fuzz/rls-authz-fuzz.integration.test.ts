import { describe, test, expect, beforeAll, afterAll } from "vitest";
import { randomUUID } from "node:crypto";
import postgres from "postgres";
import { assertLocalDsn } from "./local-dsn-guard";
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

// Runtime RLS/authz-fuzz harness (#6256, ADR-103). Drives a non-member tenant's
// identity against another tenant's rows across every workspace-isolated RLS
// table (catalog-derived) and asserts RLS denies at the DB layer. Gated: runs
// only with RLS_FUZZ_LOCAL=1 against a LOCAL disposable Postgres (the normal
// suite skips it — no stack in ordinary CI).
const ENABLED = process.env.RLS_FUZZ_LOCAL === "1";
const DSN = process.env.RLS_FUZZ_DATABASE_URL ?? "postgres://postgres:postgres@127.0.0.1:54322/postgres";

let sql: ReturnType<typeof postgres>;
let ctx: Ctx;
const seeded = new Map<string, Locate>();

const ROLLBACK = Symbol("rls-fuzz-rollback");

/** Set the transaction's role + forged claims, run fn, then ALWAYS roll back (attacks never persist). */
async function attackTxn<T>(claims: string, fn: (t: postgres.TransactionSql) => Promise<T>): Promise<T> {
  let out: T;
  try {
    await sql.begin(async (t) => {
      await t`set local role authenticated`;
      await t.unsafe("select set_config('request.jwt.claims', $1, true)", [claims]);
      out = await fn(t);
      return Promise.reject(ROLLBACK); // discard everything the attack touched
    });
  } catch (e) {
    if (e !== ROLLBACK) throw e;
  }
  return out!;
}

/** Count rows matching A's seeded canonical row under the given handle/role. */
async function countRows(h: postgres.Sql | postgres.TransactionSql, table: string, loc: Locate): Promise<number> {
  const rows = await h.unsafe(`select count(*)::int as n from "${table}" where ${loc.where}`, loc.params as never[]);
  return (rows[0] as unknown as { n: number }).n;
}

async function seedContext(): Promise<Ctx> {
  const userA = randomUUID();
  const userB = randomUUID();
  const userC = randomUUID();
  // Each auth.users insert fires handle_new_user() → personal org + workspace + membership.
  await sql`insert into auth.users (id, email) values
    (${userA}, ${`a-${userA}@example.test`}),
    (${userB}, ${`b-${userB}@example.test`}),
    (${userC}, ${`c-${userC}@example.test`})`;
  const [a] = await sql`select workspace_id, (select organization_id from workspaces where id = workspace_id) as org from workspace_members where user_id = ${userA} limit 1`;
  const [b] = await sql`select workspace_id from workspace_members where user_id = ${userB} limit 1`;
  const wsA = a.workspace_id as string;
  const wsB = b.workspace_id as string;
  const orgA = a.org as string;
  if (!wsA || !wsB || wsA === wsB || !orgA) throw new Error(`fixture seed failed: wsA=${wsA} wsB=${wsB} orgA=${orgA}`);
  // userC joins wsA as a co-member (byok_delegations grantee must be a real member).
  await sql`insert into workspace_members (workspace_id, user_id, role) values (${wsA}, ${userC}, 'member')`;
  // Two A-owned conversations (parents for messages / user_concurrency_slots seed + forge).
  const convA = randomUUID();
  const convA2 = randomUUID();
  await sql`insert into conversations (id, user_id, workspace_id, status, visibility) values
    (${convA}, ${userA}, ${wsA}, 'active', 'workspace'),
    (${convA2}, ${userA}, ${wsA}, 'active', 'workspace')`;
  return { userA, userB, userC, wsA, wsB, orgA, convA, convA2 };
}

describe.skipIf(!ENABLED)("RLS/authz-fuzz — cross-tenant isolation (local, catalog-driven)", () => {
  beforeAll(async () => {
    assertLocalDsn(DSN); // AC7 — refuse any non-local target before connecting
    sql = postgres(DSN, { max: 1, prepare: false, onnotice: () => {} });
    ctx = await seedContext();
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
    let bSeesWithRlsOff = -1;
    try {
      await sql.begin(async (t) => {
        await t.unsafe(`alter table "${table}" disable row level security`); // superuser, before the role swap
        await t`set local role authenticated`;
        await t.unsafe("select set_config('request.jwt.claims', $1, true)", [
          buildAuthenticatedClaims({ sub: ctx.userB }),
        ]);
        bSeesWithRlsOff = await countRows(t, table, loc);
        return Promise.reject(ROLLBACK); // roll back → RLS re-enabled
      });
    } catch (e) {
      if (e !== ROLLBACK) throw e;
    }
    expect(bSeesWithRlsOff, "with RLS off, B must see A's row").toBeGreaterThan(0);
    expect(isPass(classifySelectOutcome(bSeesWithRlsOff)), "harness verdict must be RED (not a pass)").toBe(false);
  });
});
