import { describe, test, expect, beforeAll, afterAll } from "vitest";
import { randomUUID } from "node:crypto";
import postgres from "postgres";
import { assertLocalDsn } from "./local-dsn-guard";
import { buildAuthenticatedClaims } from "./claim";
import { classifyWriteOutcome, classifySelectOutcome, isPass, type Verdict } from "./verdict";

// Runtime RLS/authz-fuzz harness (#6256, ADR-103). Drives a non-member tenant's
// identity at another tenant's rows at the DB layer and asserts RLS denies.
// Gated: runs only with RLS_FUZZ_LOCAL=1 against a LOCAL disposable Postgres
// (the normal suite skips it — no stack in ordinary CI).
const ENABLED = process.env.RLS_FUZZ_LOCAL === "1";
const DSN = process.env.RLS_FUZZ_DATABASE_URL ?? "postgres://postgres:postgres@127.0.0.1:54322/postgres";

// Synthetic user identities (cq-test-fixtures-synthesized-only). Fresh per run so
// no teardown is needed against the onboarding FK web on a disposable DB — the
// isolation OUTCOME is deterministic regardless of the specific UUID. Each
// auth.users insert fires handle_new_user() which auto-creates that user's
// personal org + workspace + membership → two users = two isolated tenants via
// the REAL onboarding path. Workspace ids are discovered post-seed.
const F = {
  userA: randomUUID(),
  userB: randomUUID(),
};

let sql: ReturnType<typeof postgres>;
let wsA = "";
let wsB = "";

describe.skipIf(!ENABLED)("RLS/authz-fuzz — cross-tenant isolation (local)", () => {
  beforeAll(async () => {
    assertLocalDsn(DSN); // AC7 — refuse any non-local target before connecting
    sql = postgres(DSN, { max: 1, prepare: false, onnotice: () => {} });
    // Seed two synthetic tenants as the superuser connection (bypasses RLS) via
    // the real onboarding path — one auth.users insert per tenant fires the
    // personal-workspace bootstrap. Fresh UUIDs → no teardown against the FK web.
    await sql`insert into auth.users (id, email) values (${F.userA}, ${`a-${F.userA}@example.test`}), (${F.userB}, ${`b-${F.userB}@example.test`})`;
    // Discover each user's auto-created personal workspace.
    const [a] = await sql`select workspace_id from workspace_members where user_id = ${F.userA} limit 1`;
    const [b] = await sql`select workspace_id from workspace_members where user_id = ${F.userB} limit 1`;
    wsA = a.workspace_id;
    wsB = b.workspace_id;
    if (!wsA || !wsB || wsA === wsB) throw new Error(`fixture seed failed: wsA=${wsA} wsB=${wsB}`);
  });

  afterAll(async () => {
    if (sql) await sql.end({ timeout: 5 });
  });

  /** Run a fn inside a txn scoped to `authenticated` + the given sub's claims; rolls back. */
  async function asTenant<T>(sub: string, fn: (t: postgres.TransactionSql) => Promise<T>): Promise<T> {
    // SET LOCAL role + set_config are transaction-scoped and reset when the txn
    // ends, so the pooled connection returns clean regardless of commit/rollback.
    const result = await sql.begin(async (t) => {
      await t`set local role authenticated`;
      await t.unsafe(`select set_config('request.jwt.claims', '${buildAuthenticatedClaims({ sub })}', true)`);
      return fn(t);
    });
    return result as T;
  }

  test("precondition: service_role sees tenant-A's workspace row (count=1)", async () => {
    const [{ n }] = await sql`select count(*)::int as n from workspaces where id = ${wsA}`;
    expect(n).toBe(1); // proves the row exists + query shape is valid (guards vacuous green)
  });

  test("cross-tenant SELECT denied: tenant B cannot see tenant A's workspace", async () => {
    const n = await asTenant(F.userB, async (t) => {
      const rows = await t`select id from workspaces where id = ${wsA}`;
      return rows.length;
    });
    expect(isPass(classifySelectOutcome(n))).toBe(true); // 0 rows → denied
  });

  test("positive control: tenant A CAN see its own workspace", async () => {
    const n = await asTenant(F.userA, async (t) => {
      const rows = await t`select id from workspaces where id = ${wsA}`;
      return rows.length;
    });
    expect(n).toBe(1); // A is a member → visible
  });

  // A failing statement aborts the whole txn, so postgres.js re-raises at the
  // begin() boundary — catch there, not inside, to classify the SQLSTATE.
  async function attemptWrite(sub: string, write: (t: postgres.TransactionSql) => Promise<void>): Promise<Verdict> {
    try {
      await sql.begin(async (t) => {
        await t`set local role authenticated`;
        await t.unsafe(`select set_config('request.jwt.claims', '${buildAuthenticatedClaims({ sub })}', true)`);
        await write(t);
      });
      return classifyWriteOutcome(null); // committed → the cross-tenant write went through (leak)
    } catch (err) {
      return classifyWriteOutcome(err as { code?: string });
    }
  }

  test("cross-tenant write denied with SQLSTATE 42501: tenant B cannot add a member to tenant A's workspace", async () => {
    const outcome = await attemptWrite(F.userB, async (t) => {
      await t`insert into workspace_members (workspace_id, user_id, role) values (${wsA}, ${F.userB}, 'owner')`;
    });
    // MUST be an RLS denial (42501), NOT a constraint error mis-scored as denied
    expect(outcome).toEqual({ kind: "denied" });
  });
});
