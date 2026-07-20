import { describe, test, expect, beforeAll, afterAll } from "vitest";
import { randomUUID } from "node:crypto";
import type postgres from "postgres";
import { classifySelectOutcome, classifyMutationOutcome, isPass, type Verdict } from "./verdict";
import { connect, asTenant } from "./harness-fixture";

// storage.objects attachment isolation (#6256, ADR-111, AC9). message_attachments
// object isolation lives in storage.objects RLS: chat-attachments objects are
// keyed on the first path segment `(storage.foldername(name))[1] = auth.uid()`
// (mig 068). A tenant-A object must not be SELECT/UPDATE/DELETE-able by tenant-B.
// Gated behind RLS_FUZZ_LOCAL=1 against a LOCAL disposable Postgres. Shared
// connect/asTenant helpers live in harness-fixture.ts (Item 8).
const ENABLED = process.env.RLS_FUZZ_LOCAL === "1";
const DSN = process.env.RLS_FUZZ_DATABASE_URL ?? "postgres://postgres:postgres@127.0.0.1:54322/postgres";
const BUCKET = "chat-attachments";

let sql: postgres.Sql<{}>;
let userA = "";
let userB = "";
let objectId = "";

async function countObject(h: postgres.Sql | postgres.TransactionSql): Promise<number> {
  const [r] = await h.unsafe("select count(*)::int as n from storage.objects where id = $1", [objectId]);
  return (r as unknown as { n: number }).n;
}

describe.skipIf(!ENABLED)("RLS/authz-fuzz — storage.objects attachment isolation (local)", () => {
  beforeAll(async () => {
    sql = connect(DSN); // assertLocalDsn + max:1 pinned in the shared fixture
    userA = randomUUID();
    userB = randomUUID();
    await sql`insert into auth.users (id, email) values (${userA}, ${`a-${userA}@example.test`}), (${userB}, ${`b-${userB}@example.test`})`;
    await sql`insert into storage.buckets (id, name) values (${BUCKET}, ${BUCKET}) on conflict do nothing`;
    // Seed a tenant-A object as superuser (bypasses storage RLS). Folder[1] = userA;
    // folder[2] is a random non-workspace segment so the co-member SELECT branch cannot apply.
    const [o] = await sql`insert into storage.objects (bucket_id, name, owner_id)
      values (${BUCKET}, ${`${userA}/${randomUUID()}/attachment.txt`}, ${userA}) returning id`;
    objectId = o.id as string;
  });

  afterAll(async () => {
    if (sql) await sql.end({ timeout: 5 });
  });

  test("AC9 precondition: service_role sees tenant-A's object (count=1)", async () => {
    expect(await countObject(sql)).toBe(1);
  });

  test("AC9 positive control: tenant A CAN see its own attachment object", async () => {
    expect(await asTenant(sql, userA, (t) => countObject(t))).toBe(1);
  });

  test("AC9: tenant B cannot SELECT tenant A's attachment object", async () => {
    const n = await asTenant(sql, userB, (t) => countObject(t));
    expect(isPass(classifySelectOutcome(n)), `B saw ${n} of A's objects`).toBe(true);
  });

  test("AC9: tenant B cannot UPDATE tenant A's attachment object", async () => {
    const verdict = await asTenant(sql, userB, async (t): Promise<Verdict> => {
      try {
        const res = await t.unsafe("update storage.objects set name = name where id = $1", [objectId]);
        return classifyMutationOutcome(null, res.count);
      } catch (err) {
        return classifyMutationOutcome(err as { code?: string }, 0);
      }
    });
    expect(verdict).toEqual({ kind: "denied" });
  });

  test("AC9: tenant B cannot DELETE tenant A's attachment object", async () => {
    const verdict = await asTenant(sql, userB, async (t): Promise<Verdict> => {
      try {
        const res = await t.unsafe("delete from storage.objects where id = $1", [objectId]);
        return classifyMutationOutcome(null, res.count);
      } catch (err) {
        return classifyMutationOutcome(err as { code?: string }, 0);
      }
    });
    expect(verdict).toEqual({ kind: "denied" });
  });

  test("AC9 tail: tenant A's object is intact after the attacks", async () => {
    expect(await countObject(sql)).toBe(1);
  });
});
