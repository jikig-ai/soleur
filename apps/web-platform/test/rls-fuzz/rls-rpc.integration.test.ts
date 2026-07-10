import { describe, test, expect, beforeAll, afterAll } from "vitest";
import { randomUUID } from "node:crypto";
import postgres from "postgres";
import { assertLocalDsn } from "./local-dsn-guard";
import { buildAuthenticatedClaims } from "./claim";
import { type Verdict } from "./verdict";
import { securityDefinerAuthenticatedFns } from "./catalog";
import { ATTACK_SQL, EXCLUDED, KNOWN_EXPOSURES, type RpcCtx } from "./rpc-cases";

// SECURITY DEFINER RPC-bypass dimension (#6256, ADR-103, AC8). Drives every
// authenticated-EXECUTE definer fn with tenant-B claims + tenant-A params and
// asserts each denies (throw / empty / false / 0-rows). The catalog is the
// enumerator; rpc-cases.ts is the classification; the coverage gate fails on any
// uncovered fn. Gated behind RLS_FUZZ_LOCAL=1 against a LOCAL disposable Postgres.
const ENABLED = process.env.RLS_FUZZ_LOCAL === "1";
const DSN = process.env.RLS_FUZZ_DATABASE_URL ?? "postgres://postgres:postgres@127.0.0.1:54322/postgres";

let sql: ReturnType<typeof postgres>;
let ctx: RpcCtx;
const bClaims = () => buildAuthenticatedClaims({ sub: ctx.userB });

/** Run fn in a txn that ALWAYS rolls back; returns fn's value. */
async function rolledBack<T>(fn: (t: postgres.TransactionSql) => Promise<T>): Promise<T> {
  let out: T;
  const sentinel = Symbol("rb");
  try {
    await sql.begin(async (t) => {
      out = await fn(t);
      return Promise.reject(sentinel);
    });
  } catch (e) {
    if (e !== sentinel) throw e;
  }
  return out!;
}

/** Execute one RPC under tenant-B claims; classify the outcome as denied|leaked. */
async function driveDenied(sqlText: string): Promise<Verdict> {
  try {
    return await rolledBack(async (t): Promise<Verdict> => {
      await t`set local role authenticated`;
      await t.unsafe("select set_config('request.jwt.claims', $1, true)", [bClaims()]);
      const rows = await t.unsafe(sqlText);
      if (rows.length === 0) return { kind: "denied" };
      const v = Object.values(rows[0] as object)[0];
      if (v === null || v === false || v === 0 || v === "0") return { kind: "denied" };
      return { kind: "leaked" };
    });
  } catch {
    // A throw (membership/ownership guard, or param validation) means the fn did
    // NOT perform the cross-tenant action for tenant-B → denied.
    return { kind: "denied" };
  }
}

async function seedRpcCtx(): Promise<RpcCtx> {
  const userA = randomUUID();
  const userB = randomUUID();
  const userC = randomUUID();
  await sql`insert into auth.users (id, email) values
    (${userA}, ${`a-${userA}@example.test`}), (${userB}, ${`b-${userB}@example.test`}), (${userC}, ${`c-${userC}@example.test`})`;
  const [a] = await sql`select workspace_id, (select organization_id from workspaces where id = workspace_id) as org from workspace_members where user_id = ${userA} limit 1`;
  const [b] = await sql`select workspace_id from workspace_members where user_id = ${userB} limit 1`;
  const wsA = a.workspace_id as string;
  const wsB = b.workspace_id as string;
  const orgA = a.org as string;
  await sql`insert into workspace_members (workspace_id, user_id, role) values (${wsA}, ${userC}, 'member')`;
  const convA = randomUUID();
  const convA2 = randomUUID();
  await sql`insert into conversations (id, user_id, workspace_id, status, visibility) values
    (${convA}, ${userA}, ${wsA}, 'active', 'workspace'), (${convA2}, ${userA}, ${wsA}, 'active', 'workspace')`;
  const [kb] = await sql`insert into kb_files (workspace_id, user_id, file_path, filename, visibility)
    values (${wsA}, ${userA}, ${`/a/${randomUUID()}`}, 'a', 'workspace') returning id`;
  const [msg] = await sql`insert into messages (workspace_id, template_id, conversation_id, role, content)
    values (${wsA}, 'work', ${convA}, 'user', 'x') returning id`;
  const [del] = await sql`insert into byok_delegations (grantor_user_id, grantee_user_id, workspace_id, created_by_user_id, daily_usd_cap_cents, hourly_usd_cap_cents)
    values (${userA}, ${userC}, ${wsA}, ${userA}, 1000, 100) returning id`;
  return { userA, userB, userC, wsA, wsB, orgA, convA, convA2, kbFileA: kb.id, messageA: msg.id, delegationA: del.id };
}

describe.skipIf(!ENABLED)("RLS/authz-fuzz — SECURITY DEFINER RPC bypass (local, catalog-driven)", () => {
  beforeAll(async () => {
    assertLocalDsn(DSN);
    sql = postgres(DSN, { max: 1, prepare: false, onnotice: () => {} });
    ctx = await seedRpcCtx();
  });
  afterAll(async () => {
    if (sql) await sql.end({ timeout: 5 });
  });

  // AC8 coverage gate: every catalog fn must be classified exactly once.
  test("AC8: every authenticated-EXECUTE SECURITY DEFINER fn is classified (no uncovered fn)", async () => {
    const catalog = new Set((await securityDefinerAuthenticatedFns(sql)).map((f) => f.proname));
    const classified = new Set([...Object.keys(ATTACK_SQL), ...Object.keys(EXCLUDED), ...Object.keys(KNOWN_EXPOSURES)]);
    const uncovered = [...catalog].filter((f) => !classified.has(f));
    const stale = [...classified].filter((f) => !catalog.has(f));
    // fail on a definer fn granted to authenticated that no case covers…
    expect(uncovered, `uncovered definer fns: ${uncovered.join(", ")}`).toEqual([]);
    // …and on a classification that no longer matches the catalog.
    expect(stale, `stale RPC-case entries: ${stale.join(", ")}`).toEqual([]);
    // a fn must not be double-classified
    const dupes = [...Object.keys(ATTACK_SQL)].filter((f) => EXCLUDED[f] || KNOWN_EXPOSURES[f]);
    expect(dupes, `double-classified: ${dupes.join(", ")}`).toEqual([]);
  });

  // AC8 attack cases — each must DENY tenant-B.
  for (const name of Object.keys(ATTACK_SQL)) {
    test(`RPC denial: ${name}`, async () => {
      const verdict = await driveDenied(ATTACK_SQL[name](ctx));
      expect(verdict, `${name}: definer fn must deny tenant-B + tenant-A params`).toEqual({ kind: "denied" });
    });
  }

  // EXCLUDED — documented as covered (no cross-tenant param surface). Asserting the
  // rationale is non-empty keeps the registry honest (no silent blanks).
  test("EXCLUDED fns each carry a rationale", () => {
    for (const [name, reason] of Object.entries(EXCLUDED)) {
      expect(reason.length, `${name}: excluded without rationale`).toBeGreaterThan(10);
    }
  });

  // KNOWN_EXPOSURES — these LEAK today (harness found them, tracked by the issue).
  // Each denial assertion runs under test.fails: green while the exposure stands,
  // and RED the moment the grant is fixed (assertion starts passing) → un-baseline.
  test.fails(`KNOWN-EXPOSURE ${KNOWN_EXPOSURES.find_stuck_active_conversations.issue}: find_stuck_active_conversations leaks cross-tenant rows`, async () => {
    const rows = await rolledBack(async (t) => {
      await t`set local role authenticated`;
      await t.unsafe("select set_config('request.jwt.claims', $1, true)", [bClaims()]);
      const [r] = await t.unsafe("select count(*)::int as n from find_stuck_active_conversations(0)");
      return (r as unknown as { n: number }).n;
    });
    expect(rows, "denial would be 0 cross-tenant rows").toBe(0);
  });

  test.fails(`KNOWN-EXPOSURE ${KNOWN_EXPOSURES.acquire_conversation_slot.issue}: acquire_conversation_slot writes A's slot`, async () => {
    const status = await rolledBack(async (t) => {
      await t`set local role authenticated`;
      await t.unsafe("select set_config('request.jwt.claims', $1, true)", [bClaims()]);
      const [r] = await t.unsafe(`select status from acquire_conversation_slot('${ctx.userA}','${ctx.convA2}',5,'${ctx.wsA}')`);
      return (r as unknown as { status: string }).status;
    });
    expect(status, "denial would refuse the cross-tenant acquire").not.toBe("ok");
  });

  test.fails(`KNOWN-EXPOSURE ${KNOWN_EXPOSURES.release_conversation_slot.issue}: release_conversation_slot deletes A's slot`, async () => {
    const stillPresent = await rolledBack(async (t) => {
      await t.unsafe(`insert into user_concurrency_slots (user_id,workspace_id,conversation_id) values ('${ctx.userA}','${ctx.wsA}','${ctx.convA}') on conflict do nothing`);
      await t`set local role authenticated`;
      await t.unsafe("select set_config('request.jwt.claims', $1, true)", [bClaims()]);
      await t.unsafe(`select release_conversation_slot('${ctx.userA}','${ctx.convA}')`);
      await t`reset role`; // observe within-txn as superuser
      const [r] = await t.unsafe(`select count(*)::int as n from user_concurrency_slots where user_id='${ctx.userA}' and conversation_id='${ctx.convA}'`);
      return (r as unknown as { n: number }).n;
    });
    expect(stillPresent, "denial would leave A's slot intact").toBeGreaterThan(0);
  });

  test.fails(`KNOWN-EXPOSURE ${KNOWN_EXPOSURES.touch_conversation_slot.issue}: touch_conversation_slot updates A's slot`, async () => {
    const touched = await rolledBack(async (t) => {
      await t.unsafe(`insert into user_concurrency_slots (user_id,workspace_id,conversation_id) values ('${ctx.userA}','${ctx.wsA}','${ctx.convA}') on conflict do nothing`);
      await t`set local role authenticated`;
      await t.unsafe("select set_config('request.jwt.claims', $1, true)", [bClaims()]);
      const [r] = await t.unsafe(`select touch_conversation_slot('${ctx.userA}','${ctx.convA}') as n`);
      return (r as unknown as { n: number }).n;
    });
    expect(touched, "denial would touch 0 of A's slots").toBe(0);
  });
});
