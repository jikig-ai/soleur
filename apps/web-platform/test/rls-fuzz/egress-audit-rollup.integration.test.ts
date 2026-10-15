import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import type postgres from "postgres";
import { asTenant, attackAsAnon, connect, rolledBackRaw, seedTwoTenant, withTransientRetry } from "./harness-fixture";
import type { Ctx } from "./targets";

// Live-database cases for 162_workspace_egress_audit_rollup (#9545, PR1).
// Gated like the rest of the harness: describe.skipIf(!ENABLED) would exit 0 on a
// skipped run, so the CI workflow also asserts a non-zero executed count for this
// file (see rls-authz-fuzz.yml). Every case runs inside a transaction that rolls back.
//
// Synthetic data only (cq-test-fixtures-synthesized-only): hosts are *.example.test.

const ENABLED = process.env.RLS_FUZZ_LOCAL === "1";
const DSN = process.env.RLS_FUZZ_DATABASE_URL ?? "postgres://postgres:postgres@127.0.0.1:54322/postgres";

type Txn = postgres.TransactionSql<{}>;
type Counts = {
  accepted: number;
  skipped_unknown: number;
  skipped_toggle_off: number;
  skipped_invalid: number;
};

let sql: postgres.Sql<{}>;
let ctx: Ctx;

const bucketAt = (minutesAgo: number): string => {
  const ms = Math.floor((Date.now() - minutesAgo * 60_000) / 900_000) * 900_000;
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
};

// One fixed, aligned bucket for every case: the first_seen/last_seen assertions use explicit
// second offsets from it, never the wall clock, so they cannot flake across a bucket boundary.
const BASE = bucketAt(60);
const at = (seconds: number): string =>
  new Date(Date.parse(BASE) + seconds * 1000).toISOString().replace(/\.\d{3}Z$/, "Z");

const row = (ws: string, over: Record<string, unknown> = {}) => ({
  workspace_id: ws,
  bucket_start: BASE,
  requested_host: "a.example.test",
  decision: "allowed",
  source_host: "web-1",
  request_count: 5,
  bytes_out: 100,
  first_seen: at(0),
  last_seen: at(300),
  ...over,
});

const ingest = async (t: Txn, rows: unknown[]): Promise<Counts> => {
  const [r] = await t<{ c: Counts }[]>`
    select public.ingest_egress_audit_rollup(${t.json(rows as never)}::jsonb) as c`;
  return r.c;
};

const asService = <T>(fn: (t: Txn) => Promise<T>): Promise<T> =>
  rolledBackRaw(sql, async (t) => {
    await t`update public.workspaces set web_egress = true where id in (${ctx.wsA}, ${ctx.wsB})`;
    await t`set local role service_role`;
    return fn(t);
  });

const readAll = async (t: Txn, ws: string) => {
  // Read as the table owner: the service role has no SELECT path by design.
  await t`reset role`;
  return t<{ requested_host: string; decision: string; request_count: string; bytes_out: string; first_seen: Date; last_seen: Date }[]>`
    select requested_host, decision, request_count::text, bytes_out::text, first_seen, last_seen
      from public.workspace_egress_audit_rollup where workspace_id = ${ws} order by requested_host, decision`;
};

describe.skipIf(!ENABLED)("workspace_egress_audit_rollup (local, live database)", () => {
  beforeAll(async () => {
    sql = connect(DSN);
    ctx = await seedTwoTenant(sql);
  });
  afterAll(async () => {
    if (sql) await sql.end({ timeout: 5 });
  });

  test("service-role write succeeds (positive control) and a stored row exists", async () => {
    const out = await asService(async (t) => {
      const c = await ingest(t, [row(ctx.wsA)]);
      return { c, rows: await readAll(t, ctx.wsA) };
    });
    expect(out.c.accepted).toBe(1);
    expect(out.rows).toHaveLength(1);
  });

  test("members of the writing workspace and of another workspace cannot read the table", async () => {
    const seeded = async (t: Txn) => {
      await t`update public.workspaces set web_egress = true where id = ${ctx.wsA}`;
      await t`set local role service_role`;
      await ingest(t, [row(ctx.wsA)]);
      await t`reset role`;
    };
    for (const who of [ctx.userA, ctx.userB, ctx.userC]) {
      await expect(
        asTenant(sql, who, async (t) => {
          // seed as owner first, then re-enter the tenant role
          await t`reset role`;
          await seeded(t);
          await t`set local role authenticated`;
          await t`select count(*) from public.workspace_egress_audit_rollup`;
        }),
      ).rejects.toMatchObject({ code: "42501" });
    }
    // positive control: the same table is non-empty to its owner
    const n = await rolledBackRaw(sql, async (t) => {
      await seeded(t);
      const [r] = await t<{ n: number }[]>`select count(*)::int as n from public.workspace_egress_audit_rollup`;
      return r.n;
    });
    expect(n).toBe(1);
  });

  test("anon and authenticated cannot execute any of the four functions", async () => {
    const calls = [
      "select public.ingest_egress_audit_rollup('[]'::jsonb)",
      "select public.purge_egress_audit_rollup(interval '30 days')",
      `select public.erase_egress_audit_rollup('${ctx.wsA}'::uuid)`,
      `select public.erase_egress_audit_rollup_for_requester('${ctx.wsA}'::uuid, '${ctx.userA}'::uuid)`,
    ];
    for (const stmt of calls) {
      await expect(asTenant(sql, ctx.userA, (t) => t.unsafe(stmt))).rejects.toMatchObject({ code: "42501" });
      await expect(attackAsAnon(sql, (t) => t.unsafe(stmt))).rejects.toMatchObject({ code: "42501" });
    }
    // positive control: service_role can execute the same statements
    await asService(async (t) => {
      for (const stmt of calls) await t.unsafe(stmt);
    });
  });

  test("RLS is enabled and the table has no policy in PR1", async () => {
    const [r] = await withTransientRetry(() => sql<{ rls: boolean; policies: number }[]>`
      select c.relrowsecurity as rls,
             (select count(*)::int from pg_policy p where p.polrelid = c.oid) as policies
        from pg_class c where c.oid = 'public.workspace_egress_audit_rollup'::regclass`);
    expect(r.rls).toBe(true);
    expect(r.policies).toBe(0);
  });

  test("two partial emissions of one bucket keep the larger value per column, first_seen the earlier", async () => {
    const rows = await asService(async (t) => {
      await ingest(t, [row(ctx.wsA, { request_count: 5, bytes_out: 100, first_seen: at(60), last_seen: at(300) })]);
      await ingest(t, [row(ctx.wsA, { request_count: 3, bytes_out: 200, first_seen: at(10), last_seen: at(200) })]);
      return readAll(t, ctx.wsA);
    });
    expect(rows).toHaveLength(1);
    expect(rows[0].request_count).toBe("5");
    expect(rows[0].bytes_out).toBe("200");
    expect(rows[0].first_seen.toISOString()).toBe(new Date(at(10)).toISOString());
    expect(rows[0].last_seen.toISOString()).toBe(new Date(at(300)).toISOString());
  });

  test("an identical replay leaves the row unchanged (idempotent)", async () => {
    const rows = await asService(async (t) => {
      await ingest(t, [row(ctx.wsA)]);
      await ingest(t, [row(ctx.wsA)]);
      return readAll(t, ctx.wsA);
    });
    expect(rows).toHaveLength(1);
    expect(rows[0].request_count).toBe("5");
  });

  test("a workspace with web access off is skipped and counted; on again, it is stored", async () => {
    const out = await rolledBackRaw(sql, async (t) => {
      await t`update public.workspaces set web_egress = false where id = ${ctx.wsA}`;
      await t`set local role service_role`;
      const off = await ingest(t, [row(ctx.wsA)]);
      await t`reset role`;
      const afterOff = await readAll(t, ctx.wsA);
      await t`update public.workspaces set web_egress = true where id = ${ctx.wsA}`;
      await t`set local role service_role`;
      const on = await ingest(t, [row(ctx.wsA)]);
      return { off, on, afterOff, afterOn: await readAll(t, ctx.wsA) };
    });
    expect(out.off).toMatchObject({ accepted: 0, skipped_toggle_off: 1 });
    expect(out.afterOff).toHaveLength(0);
    expect(out.on.accepted).toBe(1);
    expect(out.afterOn).toHaveLength(1);
  });

  test("unknown workspace and malformed rows are skipped and counted without losing the rest of the batch", async () => {
    const out = await asService(async (t) => {
      const c = await ingest(t, [
        row(ctx.wsA, { requested_host: "ok.example.test" }),
        row(randomUUID(), { requested_host: "ghost.example.test" }),
        row(ctx.wsA, { requested_host: "neg.example.test", request_count: -1 }),
        row(ctx.wsA, { requested_host: "badts.example.test", bucket_start: "not-a-timestamp" }),
        row(ctx.wsA, { requested_host: "old.example.test", bucket_start: bucketAt(60 * 24 * 40) }),
        { workspace_id: "not-a-uuid", requested_host: "x.example.test" },
        "not-an-object",
        // CHECK violations (content errors the function must absorb, not raise):
        row(ctx.wsA, { requested_host: "misaligned.example.test", bucket_start: at(1), first_seen: at(1), last_seen: at(2) }),
        row(ctx.wsA, { requested_host: "inverted.example.test", first_seen: at(300), last_seen: at(10) }),
        row(ctx.wsA, { requested_host: "before-bucket.example.test", first_seen: at(-5), last_seen: at(10) }),
        row(ctx.wsA, { requested_host: "after-bucket.example.test", last_seen: at(900) }),
        row(ctx.wsA, { requested_host: "has space.example.test" }),
        row(ctx.wsA, { requested_host: "enum.example.test", decision: "weird" }),
      ]);
      return { c, rows: await readAll(t, ctx.wsA) };
    });
    expect(out.c.accepted).toBe(1);
    expect(out.c.skipped_unknown).toBe(1);
    expect(out.c.skipped_invalid).toBe(11);
    expect(out.rows.map((r) => r.requested_host)).toEqual(["ok.example.test"]);
  });

  test("a non-array payload never raises and reports zero accepted", async () => {
    const c = await asService(async (t) => {
      const [r] = await t<{ c: Counts }[]>`select public.ingest_egress_audit_rollup('{"a":1}'::jsonb) as c`;
      return r.c;
    });
    expect(c.accepted).toBe(0);
  });

  test("an orphaned workspace (no member row) is skipped, so erased history is not re-created", async () => {
    const out = await asService(async (t) => {
      await t`reset role`;
      await t`delete from public.workspace_members where workspace_id = ${ctx.wsA}`;
      await t`set local role service_role`;
      const c = await ingest(t, [row(ctx.wsA)]);
      return { c, rows: await readAll(t, ctx.wsA) };
    });
    expect(out.c).toMatchObject({ accepted: 0, skipped_unknown: 1 });
    expect(out.rows).toHaveLength(0);
  });

  test("a replay that changes nothing does not rewrite the tuple", async () => {
    const xmin = await asService(async (t) => {
      await ingest(t, [row(ctx.wsA)]);
      await t`reset role`;
      const [a] = await t<{ x: string }[]>`select xmin::text as x from public.workspace_egress_audit_rollup where workspace_id = ${ctx.wsA}`;
      await t`set local role service_role`;
      await ingest(t, [row(ctx.wsA)]);
      await t`reset role`;
      const [b] = await t<{ x: string }[]>`select xmin::text as x from public.workspace_egress_audit_rollup where workspace_id = ${ctx.wsA}`;
      return { a: a.x, b: b.x };
    });
    expect(xmin.b).toBe(xmin.a);
  });

  test("distinct hosts beyond the per-bucket cap fold into one (other) row", async () => {
    const out = await asService(async (t) => {
      const rows = Array.from({ length: 520 }, (_, i) => row(ctx.wsA, { requested_host: `h${i}.example.test` }));
      for (let i = 0; i < rows.length; i += 200) await ingest(t, rows.slice(i, i + 200));
      const all = await readAll(t, ctx.wsA);
      return all;
    });
    expect(out.filter((r) => r.requested_host === "(other)")).toHaveLength(1);
    expect(out.length).toBeLessThanOrEqual(501);
  });

  test("one workspace's rows never appear under another (workspace key is the only attribution)", async () => {
    const out = await asService(async (t) => {
      await ingest(t, [row(ctx.wsA, { requested_host: "a-only.example.test" }), row(ctx.wsB, { requested_host: "b-only.example.test" })]);
      return { a: await readAll(t, ctx.wsA), b: await readAll(t, ctx.wsB) };
    });
    expect(out.a.map((r) => r.requested_host)).toEqual(["a-only.example.test"]);
    expect(out.b.map((r) => r.requested_host)).toEqual(["b-only.example.test"]);
  });

  test("rows are removed when the workspace row is deleted (cascade)", async () => {
    const left = await rolledBackRaw(sql, async (t) => {
      const ws = randomUUID();
      await t`insert into public.workspaces (id, organization_id, web_egress) values (${ws}, ${ctx.orgA}, true)`;
      // Inserted directly: a freshly created workspace has no member, so the ingest RPC would
      // (correctly) skip it as an orphan.
      await t`insert into public.workspace_egress_audit_rollup
        (workspace_id, bucket_start, requested_host, decision, source_host, request_count, bytes_out, first_seen, last_seen)
        values (${ws}, ${BASE}::timestamptz, 'a.example.test', 'allowed', 'web-1', 1, 1, ${at(0)}::timestamptz, ${at(60)}::timestamptz)`;
      const before = await readAll(t, ws);
      await t`delete from public.workspaces where id = ${ws}`;
      const after = await readAll(t, ws);
      return { before: before.length, after: after.length };
    });
    expect(left.before).toBe(1);
    expect(left.after).toBe(0);
  });

  test("the sweep deletes a 31-day row and keeps a 29-day row; a retention under one day is refused", async () => {
    const out = await rolledBackRaw(sql, async (t) => {
      await t`insert into public.workspace_egress_audit_rollup
        (workspace_id, bucket_start, requested_host, decision, source_host, request_count, bytes_out, first_seen, last_seen)
        values
        (${ctx.wsA}, date_trunc('hour', now() - interval '31 days'), 'old.example.test', 'allowed', 'web-1', 1, 1,
         date_trunc('hour', now() - interval '31 days'), date_trunc('hour', now() - interval '31 days') + interval '5 minutes'),
        (${ctx.wsA}, date_trunc('hour', now() - interval '29 days'), 'new.example.test', 'allowed', 'web-1', 1, 1,
         date_trunc('hour', now() - interval '29 days'), date_trunc('hour', now() - interval '29 days') + interval '5 minutes')`;
      await t`set local role service_role`;
      const [d] = await t<{ n: string }[]>`select public.purge_egress_audit_rollup(interval '30 days')::text as n`;
      const rows = await readAll(t, ctx.wsA);
      return { deleted: d.n, hosts: rows.map((r) => r.requested_host) };
    });
    expect(out.deleted).toBe("1");
    expect(out.hosts).toEqual(["new.example.test"]);
    await expect(
      rolledBackRaw(sql, async (t) => {
        await t`set local role service_role`;
        await t`select public.purge_egress_audit_rollup(interval '0 seconds')`;
      }),
    ).rejects.toMatchObject({ code: "P0001", message: expect.stringContaining("retention must be at least 1 day") });
  });

  test("the retention job is scheduled daily in pg_cron", async () => {
    const [r] = await withTransientRetry(() => sql<{ n: number; cmd: string }[]>`
      select count(*)::int as n, max(command) as cmd from cron.job where command like '%purge_egress_audit_rollup%'`);
    expect(r.n).toBe(1);
    expect(r.cmd).toMatch(/30 days/);
  });

  test("erase removes an orphaned workspace's rows, is idempotent, and leaves other workspaces", async () => {
    const out = await asService(async (t) => {
      await ingest(t, [row(ctx.wsA), row(ctx.wsB)]);
      await t`reset role`;
      // The saga deletes the departing member's row before step 5.15.
      await t`delete from public.workspace_members where workspace_id = ${ctx.wsA}`;
      await t`set local role service_role`;
      const [first] = await t<{ n: string }[]>`select public.erase_egress_audit_rollup(${ctx.wsA}::uuid)::text as n`;
      const [second] = await t<{ n: string }[]>`select public.erase_egress_audit_rollup(${ctx.wsA}::uuid)::text as n`;
      const [nul] = await t<{ n: string }[]>`select public.erase_egress_audit_rollup(null)::text as n`;
      return { first: first.n, second: second.n, nul: nul.n, a: await readAll(t, ctx.wsA), b: await readAll(t, ctx.wsB) };
    });
    expect(out.first).toBe("1");
    expect(out.second).toBe("0");
    expect(out.nul).toBe("0");
    expect(out.a).toHaveLength(0);
    expect(out.b).toHaveLength(1);
  });

  test("erase does nothing while the workspace still has a member (no over-erasure of a team workspace)", async () => {
    const out = await asService(async (t) => {
      await ingest(t, [row(ctx.wsA)]);
      const [n] = await t<{ n: string }[]>`select public.erase_egress_audit_rollup(${ctx.wsA}::uuid)::text as n`;
      return { n: n.n, rows: await readAll(t, ctx.wsA) };
    });
    expect(out.n).toBe("0");
    expect(out.rows).toHaveLength(1);
  });

  test("requester erase deletes for a sole member, and does nothing for a team workspace, another requester or nulls", async () => {
    const out = await asService(async (t) => {
      await ingest(t, [row(ctx.wsA)]);
      const n = async (ws: string | null, req: string | null) => {
        const [r] = await t<{ n: string }[]>`select public.erase_egress_audit_rollup_for_requester(${ws}::uuid, ${req}::uuid)::text as n`;
        return r.n;
      };
      await t`reset role`;
      const [{ c }] = await t<{ c: number }[]>`select count(*)::int as c from public.workspace_members where workspace_id = ${ctx.wsA}`;
      await t`set local role service_role`;
      // The fixture's wsA is a team workspace (userA owner, userC member): nothing is erased.
      const team = await n(ctx.wsA, ctx.userA);
      const wrongRequester = await n(ctx.wsA, randomUUID());
      const nulls = [await n(null, ctx.userA), await n(ctx.wsA, null)];
      await t`reset role`;
      await t`delete from public.workspace_members where workspace_id = ${ctx.wsA} and user_id = ${ctx.userC}`;
      await t`set local role service_role`;
      const otherSole = await n(ctx.wsA, ctx.userC);
      const sole = await n(ctx.wsA, ctx.userA);
      return { c, team, wrongRequester, nulls, otherSole, sole, left: await readAll(t, ctx.wsA) };
    });
    expect(out.c).toBeGreaterThan(1);
    expect(out.team).toBe("0");
    expect(out.wrongRequester).toBe("0");
    expect(out.nulls).toEqual(["0", "0"]);
    expect(out.otherSole).toBe("0");
    expect(out.sole).toBe("1");
    expect(out.left).toHaveLength(0);
  });

  test("an in-flight ingest holds a lock that blocks the member-row delete, so erasure cannot interleave", async () => {
    // Transaction A ingests (takes FOR SHARE on the member rows) and stays open; transaction B, on a
    // second connection (the saga's member delete), must not get past the lock. Both roll back.
    const other = connect(DSN);
    let blocked: unknown;
    try {
      const A = sql.begin(async (a) => {
        await a`update public.workspaces set web_egress = true where id = ${ctx.wsA}`;
        await a`set local role service_role`;
        await ingest(a, [row(ctx.wsA)]);
        await a`reset role`;
        try {
          await other.begin(async (b) => {
            await b`set local lock_timeout = '400ms'`;
            await b`delete from public.workspace_members where workspace_id = ${ctx.wsA}`;
            throw new Error("rollback-b");
          });
        } catch (err) {
          blocked = err;
        }
        throw new Error("rollback-a");
      });
      await expect(A).rejects.toThrow("rollback-a");
    } finally {
      await other.end({ timeout: 5 });
    }
    expect(blocked).toMatchObject({ code: "55P03" });
  });
});
