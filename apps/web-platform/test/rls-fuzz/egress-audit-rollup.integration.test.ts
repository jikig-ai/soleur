import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import type postgres from "postgres";
import { asTenant, attackAs, attackAsAnon, connect, rolledBackRaw, seedTwoTenant, withTransientRetry } from "./harness-fixture";
import { buildAuthenticatedClaims } from "./claim";
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
      // The requester erase refuses while web access is on; switch it off so every call can run.
      await t`reset role`;
      await t`update public.workspaces set web_egress = false where id = ${ctx.wsA}`;
      await t`set local role service_role`;
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
    expect(out.c).toMatchObject({ accepted: 0, skipped_unknown: 0, skipped_orphan: 1 });
    expect(out.rows).toHaveLength(0);
  });

  test("the requester erase refuses while web access is on, and works once it is off", async () => {
    const out = await asService(async (t) => {
      await ingest(t, [row(ctx.wsA)]);
      await t`reset role`;
      await t`delete from public.workspace_members where workspace_id = ${ctx.wsA} and user_id = ${ctx.userC}`;
      await t`set local role service_role`;
      let refused: unknown;
      try {
        await t.savepoint(async (sp) => {
          await sp`select public.erase_egress_audit_rollup_for_requester(${ctx.wsA}::uuid, ${ctx.userA}::uuid)`;
        });
      } catch (err) {
        refused = err;
      }
      await t`reset role`;
      await t`update public.workspaces set web_egress = false where id = ${ctx.wsA}`;
      await t`set local role service_role`;
      const [r] = await t<{ n: string }[]>`select public.erase_egress_audit_rollup_for_requester(${ctx.wsA}::uuid, ${ctx.userA}::uuid)::text as n`;
      return { refused, n: r.n };
    });
    expect(String((out.refused as Error | undefined)?.message)).toContain("web access is still on");
    expect(out.n).toBe("1");
  });

  test("a replay that changes nothing does not rewrite the tuple", async () => {
    const xmin = await asService(async (t) => {
      await ingest(t, [row(ctx.wsA)]);
      await t`reset role`;
      const [a] = await t<{ x: string }[]>`select ctid::text as x from public.workspace_egress_audit_rollup where workspace_id = ${ctx.wsA}`;
      await t`set local role service_role`;
      await ingest(t, [row(ctx.wsA)]);
      await t`reset role`;
      const [b] = await t<{ x: string }[]>`select ctid::text as x from public.workspace_egress_audit_rollup where workspace_id = ${ctx.wsA}`;
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
      await t`reset role`;
      await t`update public.workspaces set web_egress = false where id = ${ctx.wsA}`;
      await t`set local role service_role`;
      const team = await n(ctx.wsA, ctx.userA);
      const wrongRequester = await n(ctx.wsA, randomUUID());
      const nulls = [await n(null, ctx.userA), await n(ctx.wsA, null)];
      await t`reset role`;
      await t`update public.workspaces set web_egress = false where id = ${ctx.wsA}`;
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

  // ---- #9545 PR2: get_egress_audit_summary (member read RPC, migration 177) ----
  // Every case seeds through ingest_egress_audit_rollup (so the GREATEST-merge semantics the counts
  // depend on are exercised, never a raw INSERT) except the window-edge case, which needs buckets the
  // ingest would reject. Hosts are *.example.test.

  type Summary = {
    window: { start: string; end: string };
    truncated: boolean;
    summary: { request_count_min: number | null; blocked_request_count_min: number | null; last_request_at: string | null };
    rows: { host: string; decision: string; request_count: number; last_seen: string }[];
    overflow: { decision: string; request_count: number; last_seen: string }[];
  };

  const IN_BODY_DENIAL = "egress audit: workspace membership required";
  const claimsFor = (sub: string): string => buildAuthenticatedClaims({ sub });

  const rowAt = (ws: string, minutesAgo: number, over: Record<string, unknown> = {}) => {
    const b = bucketAt(minutesAgo);
    const s = (sec: number): string => new Date(Date.parse(b) + sec * 1000).toISOString().replace(/\.\d{3}Z$/, "Z");
    return row(ws, { bucket_start: b, first_seen: s(0), last_seen: s(300), ...over });
  };

  const summarize = async (t: Txn, ws: string, limit: number | null = 200, decision: string | null = null): Promise<Summary> => {
    const [r] = await t<{ s: Summary }[]>`
      select public.get_egress_audit_summary(${ws}::uuid, ${limit}::int, ${decision}::text) as s`;
    return r.s;
  };

  // Seed as service_role through the ingest, then run `fn` as the given member, all in one rolled-back txn.
  const seededAs = <T>(sub: string, seed: (t: Txn) => Promise<void>, fn: (t: Txn) => Promise<T>): Promise<T> =>
    attackAs(sql, claimsFor(sub), async (t) => {
      await t`reset role`;
      await t`update public.workspaces set web_egress = true where id in (${ctx.wsA}, ${ctx.wsB})`;
      await t`set local role service_role`;
      await seed(t);
      await t`reset role`;
      await t`set local role authenticated`;
      return fn(t);
    });

  const seedWsA = async (t: Txn): Promise<void> => {
    await ingest(t, [
      rowAt(ctx.wsA, 60, { requested_host: "a.example.test", decision: "allowed", source_host: "web-1", request_count: 5 }),
      rowAt(ctx.wsA, 60, { requested_host: "a.example.test", decision: "allowed", source_host: "web-2", request_count: 7 }),
      rowAt(ctx.wsA, 90, { requested_host: "a.example.test", decision: "allowed", source_host: "web-1", request_count: 3 }),
      rowAt(ctx.wsA, 30, { requested_host: "b.example.test", decision: "denied", request_count: 4 }),
      rowAt(ctx.wsA, 45, { requested_host: "c.example.test", decision: "other", request_count: 2 }),
    ]);
  };

  // A fresh authenticated user who is NOT a member of wsA; `setup` runs as the table owner.
  const asFreshUser = <T>(setup: (t: Txn, uid: string) => Promise<void>, fn: (t: Txn, uid: string) => Promise<T>): Promise<T> =>
    rolledBackRaw(sql, async (t) => {
      const uid = randomUUID();
      await t`insert into auth.users (id, email) values (${uid}, ${`d-${uid}@example.test`})`;
      await t`update public.workspaces set web_egress = true where id = ${ctx.wsA}`;
      await t`set local role service_role`;
      await seedWsA(t);
      await t`reset role`;
      await setup(t, uid);
      await t`set local role authenticated`;
      await t.unsafe("select set_config('request.jwt.claims', $1, true)", [claimsFor(uid)]);
      return fn(t, uid);
    });

  test("a member reads the 30-day summary: grouped, summed across buckets and sources, newest first; a co-member reads the same", async () => {
    for (const who of [ctx.userA, ctx.userC]) {
      const out = await seededAs(who, seedWsA, (t) => summarize(t, ctx.wsA));
      expect(out.rows.map((r) => [r.host, r.decision, r.request_count])).toEqual([
        ["b.example.test", "denied", 4],
        ["c.example.test", "other", 2],
        ["a.example.test", "allowed", 15],
      ]);
      expect(out.summary.request_count_min).toBe(21);
      expect(out.summary.blocked_request_count_min).toBe(4);
      expect(out.summary.last_request_at).not.toBeNull();
      expect(out.overflow).toEqual([]);
      expect(out.truncated).toBe(false);
    }
  });

  test("a member of another workspace, a no-membership user, a pending invitee and a NULL workspace id all get the in-body 42501", async () => {
    await expect(seededAs(ctx.userB, seedWsA, (t) => summarize(t, ctx.wsA))).rejects.toMatchObject({
      code: "42501",
      message: IN_BODY_DENIAL,
    });
    await expect(asFreshUser(async () => {}, (t) => summarize(t, ctx.wsA))).rejects.toMatchObject({
      code: "42501",
      message: IN_BODY_DENIAL,
    });
    await expect(
      asFreshUser(
        async (t, uid) => {
          await t`insert into public.workspace_invitations (workspace_id, invitee_user_id, token_hash, role, expires_at)
                  values (${ctx.wsA}, ${uid}, ${`h-${randomUUID()}`}, 'member', now() + interval '7 days')`;
        },
        (t) => summarize(t, ctx.wsA),
      ),
    ).rejects.toMatchObject({ code: "42501", message: IN_BODY_DENIAL });
    await expect(
      seededAs(ctx.userA, seedWsA, async (t) => {
        await t`select public.get_egress_audit_summary(null::uuid, 200, null)`;
      }),
    ).rejects.toMatchObject({ code: "42501", message: IN_BODY_DENIAL });
  });

  test("a removed member is denied (a member passes, then the member row is deleted)", async () => {
    let before: Summary | undefined;
    await expect(
      asFreshUser(
        async (t, uid) => {
          await t`insert into public.workspace_members (workspace_id, user_id, role) values (${ctx.wsA}, ${uid}, 'member')`;
        },
        async (t, uid) => {
          before = await summarize(t, ctx.wsA);
          await t`reset role`;
          await t`delete from public.workspace_members where workspace_id = ${ctx.wsA} and user_id = ${uid}`;
          await t`set local role authenticated`;
          await summarize(t, ctx.wsA);
        },
      ),
    ).rejects.toMatchObject({ code: "42501", message: IN_BODY_DENIAL });
    expect(before?.rows.length).toBeGreaterThan(0);
  });

  test("anon and service_role fail on the GRANT (engine text), not on the in-body check; the grantee set is only authenticated", async () => {
    const stmt = `select public.get_egress_audit_summary('${ctx.wsA}'::uuid, 200, null)`;
    await expect(attackAsAnon(sql, (t) => t.unsafe(stmt))).rejects.toMatchObject({
      code: "42501",
      message: expect.stringContaining("permission denied for function"),
    });
    await expect(
      rolledBackRaw(sql, async (t) => {
        await t`set local role service_role`;
        await t.unsafe(stmt);
      }),
    ).rejects.toMatchObject({ code: "42501", message: expect.stringContaining("permission denied for function") });
    const [g] = await withTransientRetry(() => sql<{ anon: boolean; svc: boolean; auth: boolean; public_grants: number }[]>`
      select has_function_privilege('anon', 'public.get_egress_audit_summary(uuid, integer, text)', 'EXECUTE') as anon,
             has_function_privilege('service_role', 'public.get_egress_audit_summary(uuid, integer, text)', 'EXECUTE') as svc,
             has_function_privilege('authenticated', 'public.get_egress_audit_summary(uuid, integer, text)', 'EXECUTE') as auth,
             (select count(*)::int from pg_proc p, aclexplode(p.proacl) a
               where p.oid = 'public.get_egress_audit_summary(uuid, integer, text)'::regprocedure
                 and a.grantee = 0 and a.privilege_type = 'EXECUTE') as public_grants`);
    expect(g).toEqual({ anon: false, svc: false, auth: true, public_grants: 0 });
  });

  test("order oracle: a non-member with an invalid decision gets the authz denial; a member gets 22023", async () => {
    await expect(seededAs(ctx.userB, seedWsA, (t) => summarize(t, ctx.wsA, 200, "x"))).rejects.toMatchObject({
      code: "42501",
      message: IN_BODY_DENIAL,
    });
    await expect(seededAs(ctx.userA, seedWsA, (t) => summarize(t, ctx.wsA, 200, "x"))).rejects.toMatchObject({
      code: "22023",
    });
  });

  test("tenant boundary: with workspace B's newer data present, a member of A sees none of it in any branch", async () => {
    const seedBoth = async (t: Txn) => {
      await seedWsA(t);
      await ingest(t, [
        rowAt(ctx.wsB, 5, { requested_host: "b-only.example.test", decision: "denied", request_count: 1000 }),
        rowAt(ctx.wsB, 6, { requested_host: "b-only-2.example.test", decision: "allowed", request_count: 500 }),
        rowAt(ctx.wsB, 7, { requested_host: "(other)", decision: "denied", request_count: 77 }),
        // Same bucket as A's newest row (30 minutes ago) but a later last_seen: a hint probe that lost its
        // workspace predicate would return this one even though the newest bucket is chosen per workspace.
        rowAt(ctx.wsB, 30, { requested_host: "b-same-bucket.example.test", decision: "allowed", request_count: 3, last_seen: new Date(Date.parse(bucketAt(30)) + 800_000).toISOString().replace(/\.\d{3}Z$/, "Z") }),
      ]);
    };
    const out = await seededAs(ctx.userA, seedBoth, async (t) => ({
      all: await summarize(t, ctx.wsA),
      probe: await summarize(t, ctx.wsA, 0),
      denied: await summarize(t, ctx.wsA, 200, "denied"),
      mine: await summarize(t, ctx.wsA, 1),
    }));
    for (const view of [out.all, out.denied, out.mine]) {
      expect(JSON.stringify(view)).not.toContain("b-only");
    }
    expect(out.all.summary.request_count_min).toBe(21);
    expect(out.all.overflow).toEqual([]);
    expect(out.denied.overflow).toEqual([]);
    expect(out.denied.rows.map((r) => r.host)).toEqual(["b.example.test"]);
    // B has newer rows (5 minutes ago) and a later row inside A's newest bucket; a dropped tenant filter shows in either.
    const aNewest = Date.parse(out.all.rows[0].last_seen);
    expect(Date.parse(out.probe.summary.last_request_at as string)).toBe(aNewest);
    expect(out.probe.rows).toEqual([]);
    expect(out.probe.overflow).toEqual([]);
  });

  test("overflow is a separate typed field summed across buckets and sources, counted in the summary, and never a host row", async () => {
    const out = await seededAs(
      ctx.userA,
      async (t) => {
        await seedWsA(t);
        await ingest(t, [
          rowAt(ctx.wsA, 40, { requested_host: "(other)", decision: "allowed", source_host: "web-1", request_count: 40 }),
          rowAt(ctx.wsA, 41, { requested_host: "(other)", decision: "allowed", source_host: "web-2", request_count: 5 }),
          rowAt(ctx.wsA, 42, { requested_host: "(other)", decision: "denied", request_count: 9 }),
        ]);
      },
      async (t) => ({ all: await summarize(t, ctx.wsA), denied: await summarize(t, ctx.wsA, 200, "denied") }),
    );
    expect(out.all.rows.some((r) => r.host === "(other)")).toBe(false);
    expect(out.all.overflow.map((o) => [o.decision, o.request_count])).toEqual([
      ["allowed", 45],
      ["denied", 9],
    ]);
    // 15 + 4 + 2 (hosts) + 45 + 9 (overflow); blocked = denied only, overflow included.
    expect(out.all.summary.request_count_min).toBe(75);
    expect(out.all.summary.blocked_request_count_min).toBe(13);
    expect(out.denied.overflow.map((o) => o.decision)).toEqual(["denied"]);
    expect(out.denied.rows.map((r) => r.decision)).toEqual(["denied"]);
    expect(out.denied.summary.request_count_min).toBe(75);
  });

  test("truncated is true only when the groups exceed p_limit; NULL behaves as 200; out-of-range limits clamp", async () => {
    const out = await seededAs(ctx.userA, seedWsA, async (t) => ({
      two: await summarize(t, ctx.wsA, 2),
      three: await summarize(t, ctx.wsA, 3),
      nul: await summarize(t, ctx.wsA, null),
      huge: await summarize(t, ctx.wsA, 9999),
      negative: await summarize(t, ctx.wsA, -5),
    }));
    expect(out.two.rows).toHaveLength(2);
    expect(out.two.truncated).toBe(true);
    expect(out.three.rows).toHaveLength(3);
    expect(out.three.truncated).toBe(false);
    expect(out.nul.rows).toHaveLength(3);
    expect(out.huge.rows).toHaveLength(3);
    expect(out.negative.rows).toEqual([]);
    expect(out.negative.truncated).toBe(false);
  });

  test("p_limit = 0 returns only last_request_at: counts null, arrays empty, truncated false", async () => {
    const [probe, full] = await seededAs(ctx.userA, seedWsA, async (t) => [await summarize(t, ctx.wsA, 0), await summarize(t, ctx.wsA, 200)]);
    expect(probe.summary.request_count_min).toBeNull();
    expect(probe.summary.blocked_request_count_min).toBeNull();
    expect(probe.rows).toEqual([]);
    expect(probe.overflow).toEqual([]);
    expect(probe.truncated).toBe(false);
    expect(Date.parse(probe.summary.last_request_at as string)).toBe(Date.parse(full.summary.last_request_at as string));
  });

  test("an empty window yields empty arrays (never NULL), zero totals and a null last request", async () => {
    const out = await seededAs(ctx.userB, async () => {}, async (t) => ({
      full: await summarize(t, ctx.wsB),
      probe: await summarize(t, ctx.wsB, 0),
    }));
    expect(out.full.rows).toEqual([]);
    expect(out.full.overflow).toEqual([]);
    expect(out.full.summary).toEqual({ request_count_min: 0, blocked_request_count_min: 0, last_request_at: null });
    expect(out.probe.summary.last_request_at).toBeNull();
  });

  test("window edges: 29 days in, 31 days and a purge-lagged row out, and a bucket from the near future is excluded", async () => {
    const out = await seededAs(
      ctx.userA,
      async (t) => {
        await t`reset role`;
        const ins = (minutesAgo: number, host: string, count: number, lastOffsetSec: number) => {
          const b = bucketAt(minutesAgo);
          const last = new Date(Date.parse(b) + lastOffsetSec * 1000).toISOString();
          return t`insert into public.workspace_egress_audit_rollup
                     (workspace_id, bucket_start, requested_host, decision, source_host, request_count, bytes_out, first_seen, last_seen)
                   values (${ctx.wsA}, ${b}, ${host}, 'allowed', 'web-1', ${count}, 0, ${b}, ${last})`;
        };
        await ins(29 * 1440, "in-29d.example.test", 3, 10);
        await ins(31 * 1440, "out-31d.example.test", 100, 10);
        await ins(30 * 1440 + 120, "out-lagged.example.test", 100, 10);
        // Passes the bucket_start bound but its last_seen is just before now - 30 days: only the last_seen bound excludes it.
        await ins(30 * 1440, "out-purge-lag.example.test", 100, 1);
        await ins(-15, "future.example.test", 100, 60);
        await t`set local role service_role`;
      },
      async (t) => ({ view: await summarize(t, ctx.wsA), probe: await summarize(t, ctx.wsA, 0) }),
    );
    expect(out.view.rows.map((r) => r.host)).toEqual(["in-29d.example.test"]);
    expect(out.view.summary.request_count_min).toBe(3);
    expect(Date.parse(out.view.summary.last_request_at as string)).toBeLessThanOrEqual(Date.now() + 1000);
    expect(Date.parse(out.probe.summary.last_request_at as string)).toBeLessThanOrEqual(Date.now() + 1000);
  });

  test("history stays readable after web access is switched off (ruling D)", async () => {
    const out = await seededAs(ctx.userA, seedWsA, async (t) => {
      await t`reset role`;
      await t`update public.workspaces set web_egress = false where id = ${ctx.wsA}`;
      await t`set local role authenticated`;
      return summarize(t, ctx.wsA);
    });
    expect(out.rows).toHaveLength(3);
    expect(out.summary.request_count_min).toBe(21);
  });

  test("a member who joined after the rows were written still reads them (pre-join history is visible by design)", async () => {
    const out = await asFreshUser(
      async (t, uid) => {
        await t`insert into public.workspace_members (workspace_id, user_id, role) values (${ctx.wsA}, ${uid}, 'member')`;
      },
      (t) => summarize(t, ctx.wsA),
    );
    expect(out.rows).toHaveLength(3);
  });

  test("the rollup table has no policy and authenticated cannot select it directly", async () => {
    const [r] = await withTransientRetry(() => sql<{ policies: number; can_select: boolean }[]>`
      select (select count(*)::int from pg_policies where schemaname = 'public' and tablename = 'workspace_egress_audit_rollup') as policies,
             has_table_privilege('authenticated', 'public.workspace_egress_audit_rollup', 'SELECT') as can_select`);
    expect(r).toEqual({ policies: 0, can_select: false });
  });

});
