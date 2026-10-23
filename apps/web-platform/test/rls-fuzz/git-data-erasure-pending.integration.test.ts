import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import type postgres from "postgres";
import { attackAsAnon, connect, rolledBackRaw, withTransientRetry } from "./harness-fixture";

// Live-database cases for 164_git_data_erasure_pending (#8211, PR-B1). Gated like the rest of
// the harness (a local disposable Postgres only; assertLocalDsn refuses anything else). The
// ledger has no foreign keys, so these cases need no tenant seed. Cases that must observe
// concurrency commit their own rows (random uuids) and delete them in afterAll; every other
// case runs inside a transaction that rolls back.
//
// Synthetic data only (cq-test-fixtures-synthesized-only): random uuids.

const ENABLED = process.env.RLS_FUZZ_LOCAL === "1";
const DSN = process.env.RLS_FUZZ_DATABASE_URL ?? "postgres://postgres:postgres@127.0.0.1:54322/postgres";

type Txn = postgres.TransactionSql<{}>;

let sql: postgres.Sql<{}>;
let sqlB: postgres.Sql<{}>;
const committed: string[] = [];

// Every statement on the raw handle rides withTransientRetry (rls-fuzz-census, #9779).
const q = <T extends object = Record<string, unknown>>(strings: TemplateStringsArray, ...values: unknown[]) =>
  withTransientRetry(() => sql<T[]>(strings, ...(values as never[])));

const asService = <T>(fn: (t: Txn) => Promise<T>): Promise<T> =>
  rolledBackRaw(sql, async (t) => {
    await t`set local role service_role`;
    return fn(t);
  });

const asAuthenticated = <T>(fn: (t: Txn) => Promise<T>): Promise<T> =>
  rolledBackRaw(sql, async (t) => {
    await t`set local role authenticated`;
    await t.unsafe("select set_config('request.jwt.claims', $1, true)", [
      JSON.stringify({ sub: randomUUID(), role: "authenticated" }),
    ]);
    return fn(t);
  });

const RPC_CALLS = [
  `select public.record_git_data_erasure_pending('${randomUUID()}'::uuid, 'refused')`,
  `select * from public.claim_git_data_erasure_pending(5, interval '1 hour')`,
  `select public.resolve_git_data_erasure_pending('${randomUUID()}'::uuid)`,
  `select public.oldest_git_data_erasure_pending_age()`,
];

describe.skipIf(!ENABLED)("git_data_erasure_pending (local, live database)", () => {
  beforeAll(async () => {
    sql = connect(DSN);
    sqlB = connect(DSN);
    await q`delete from public.git_data_erasure_pending`;
    await q`delete from public.git_data_erasure_counts`;
  });
  afterAll(async () => {
    if (sql) {
      if (committed.length) await q`delete from public.git_data_erasure_pending where workspace_id = any(${committed}::uuid[])`;
      await sql.end({ timeout: 5 });
    }
    if (sqlB) await sqlB.end({ timeout: 5 });
  });

  test("anon and authenticated cannot execute any of the four RPCs; service_role can (positive control)", async () => {
    for (const stmt of RPC_CALLS) {
      await expect(asAuthenticated((t) => t.unsafe(stmt))).rejects.toMatchObject({ code: "42501" });
      await expect(attackAsAnon(sql, (t) => t.unsafe(stmt))).rejects.toMatchObject({ code: "42501" });
      await expect(asService((t) => t.unsafe(stmt))).resolves.toBeDefined();
    }
  });

  test("anon, authenticated and service_role have no direct table access (RLS on, no policy, grants revoked)", async () => {
    for (const table of ["git_data_erasure_pending", "git_data_erasure_counts"]) {
      for (const run of [asAuthenticated, (fn: (t: Txn) => Promise<unknown>) => attackAsAnon(sql, fn), asService]) {
        await expect(run((t) => t.unsafe(`select count(*) from public.${table}`))).rejects.toMatchObject({ code: "42501" });
      }
    }
    const [r] = await q<{ pending: boolean; counts: boolean; policies: number }>`
      select (select relrowsecurity from pg_class where oid = 'public.git_data_erasure_pending'::regclass) as pending,
             (select relrowsecurity from pg_class where oid = 'public.git_data_erasure_counts'::regclass) as counts,
             (select count(*)::int from pg_policy
               where polrelid in ('public.git_data_erasure_pending'::regclass, 'public.git_data_erasure_counts'::regclass)) as policies`;
    expect(r).toEqual({ pending: true, counts: true, policies: 0 });
  });

  test("neither table has a foreign key, and neither carries an identity column beyond workspace_id", async () => {
    const fks = await q`select conname from pg_constraint
      where contype = 'f' and conrelid in ('public.git_data_erasure_pending'::regclass, 'public.git_data_erasure_counts'::regclass)`;
    expect(fks).toHaveLength(0);
    const pendingCols = await q<{ column_name: string }>`select column_name from information_schema.columns
      where table_schema = 'public' and table_name = 'git_data_erasure_pending' order by column_name`;
    expect(pendingCols.map((c) => c.column_name)).toEqual([
      "attempts", "last_attempt_at", "last_outcome", "requested_at", "workspace_id",
    ]);
    const countCols = await q<{ column_name: string }>`select column_name from information_schema.columns
      where table_schema = 'public' and table_name = 'git_data_erasure_counts' order by column_name`;
    expect(countCols.map((c) => c.column_name)).toEqual(["bucket", "count", "month"]);
  });

  test("every function is SECURITY DEFINER with search_path pinned to public, pg_temp", async () => {
    const rows = await q<{ proname: string; prosecdef: boolean; proconfig: string[] }>`
      select proname, prosecdef, proconfig from pg_proc
       where pronamespace = 'public'::regnamespace and proname in (
         'record_git_data_erasure_pending', 'claim_git_data_erasure_pending',
         'resolve_git_data_erasure_pending', 'oldest_git_data_erasure_pending_age')`;
    expect(rows).toHaveLength(4);
    for (const r of rows) {
      expect(r.prosecdef, r.proname).toBe(true);
      expect(r.proconfig, r.proname).toContain("search_path=public, pg_temp");
    }
  });

  test("record is an idempotent upsert that keeps the ORIGINAL requested_at and updates last_outcome", async () => {
    const id = randomUUID();
    const out = await asService(async (t) => {
      await t`select public.record_git_data_erasure_pending(${id}::uuid, 'refused')`;
      await t`reset role`;
      await t`update public.git_data_erasure_pending set requested_at = now() - interval '3 days', attempts = 2 where workspace_id = ${id}`;
      await t`set local role service_role`;
      await t`select public.record_git_data_erasure_pending(${id}::uuid, 'unreachable')`;
      await t`select public.record_git_data_erasure_pending(${id}::uuid, 'unreachable')`;
      await t`reset role`;
      return t<{ n: number; outcome: string; age_s: number; attempts: number }[]>`
        select count(*) over ()::int as n, last_outcome as outcome,
               extract(epoch from now() - requested_at)::int as age_s, attempts
          from public.git_data_erasure_pending where workspace_id = ${id}`;
    });
    expect(out).toHaveLength(1);
    expect(out[0].n).toBe(1);
    expect(out[0].outcome).toBe("unreachable");
    expect(out[0].age_s).toBeGreaterThanOrEqual(3 * 86400);
    expect(out[0].attempts).toBe(2);
  });

  test("record rejects an outcome outside the closed enum and a null id", async () => {
    await expect(
      asService((t) => t`select public.record_git_data_erasure_pending(${randomUUID()}::uuid, 'Command failed: ssh x')`),
    ).rejects.toMatchObject({ code: "23514" });
    await expect(
      asService((t) => t`select public.record_git_data_erasure_pending(null::uuid, 'refused')`),
    ).rejects.toThrow(/workspace id is required/);
    for (const word of ["refused", "unreachable", "unauthorized", "unconfigured", "host_key_mismatch", "thrown", "seeded"]) {
      await asService((t) => t`select public.record_git_data_erasure_pending(${randomUUID()}::uuid, ${word})`);
    }
  });

  test("claim returns at most p_limit due rows oldest first, stamps attempts and last_attempt_at, honours the backoff", async () => {
    const ids = [randomUUID(), randomUUID(), randomUUID()];
    const out = await asService(async (t) => {
      for (const [i, id] of ids.entries()) {
        await t`select public.record_git_data_erasure_pending(${id}::uuid, 'refused')`;
        await t`reset role`;
        await t`update public.git_data_erasure_pending set requested_at = timestamptz '2000-01-01' + ${i} * interval '1 day' where workspace_id = ${id}`;
        await t`set local role service_role`;
      }
      const first = await t<{ workspace_id: string; attempts: number }[]>`select * from public.claim_git_data_erasure_pending(2, interval '1 hour')`;
      const second = await t<{ workspace_id: string; attempts: number }[]>`select * from public.claim_git_data_erasure_pending(5, interval '1 hour')`;
      const third = await t<{ workspace_id: string }[]>`select * from public.claim_git_data_erasure_pending(5, interval '1 hour')`;
      await t`reset role`;
      await t`update public.git_data_erasure_pending set last_attempt_at = now() - interval '2 hours' where workspace_id = any(${ids}::uuid[])`;
      await t`set local role service_role`;
      const fourth = await t<{ workspace_id: string; attempts: number }[]>`select * from public.claim_git_data_erasure_pending(5, interval '1 hour')`;
      return { first, second, third, fourth };
    });
    expect(out.first.map((r) => r.workspace_id)).toEqual([ids[0], ids[1]]);
    expect(out.first.every((r) => r.attempts === 1)).toBe(true);
    expect(out.second.map((r) => r.workspace_id)).toEqual([ids[2]]);
    expect(out.third).toHaveLength(0);
    expect(out.fourth.map((r) => r.workspace_id)).toEqual(ids);
    expect(out.fourth.every((r) => r.attempts === 2)).toBe(true);
  });

  test("claim refuses a limit outside 1..100 and an interval shorter than a minute", async () => {
    await expect(asService((t) => t`select * from public.claim_git_data_erasure_pending(0, interval '1 hour')`)).rejects.toThrow(/limit/);
    await expect(asService((t) => t`select * from public.claim_git_data_erasure_pending(101, interval '1 hour')`)).rejects.toThrow(/limit/);
    await expect(asService((t) => t`select * from public.claim_git_data_erasure_pending(5, interval '0 seconds')`)).rejects.toThrow(/interval/);
    await expect(asService((t) => t`select * from public.claim_git_data_erasure_pending(5, null)`)).rejects.toThrow(/interval/);
  });

  test("two concurrent claims (SKIP LOCKED) never hand the same row to both", async () => {
    const ids: string[] = Array.from({ length: 6 }, () => randomUUID());
    committed.push(...ids);
    for (const id of ids) {
      await q`select public.record_git_data_erasure_pending(${id}::uuid, 'refused')`;
    }
    await q`update public.git_data_erasure_pending set requested_at = timestamptz '1999-01-01' where workspace_id = any(${ids}::uuid[])`;

    try {
      let release!: () => void;
      const gate = new Promise<void>((r) => (release = r));
      let aHolds!: () => void;
      const aClaimed = new Promise<void>((r) => (aHolds = r));
      const A = sql.begin(async (t) => {
        const rows = await t<{ workspace_id: string }[]>`select * from public.claim_git_data_erasure_pending(3, interval '1 hour')`;
        aHolds();
        await gate; // A's row locks are still held here (uncommitted)
        return rows.map((r) => r.workspace_id);
      });
      await aClaimed;
      const bRows = await sqlB.begin(async (t) => {
        const rows = await t<{ workspace_id: string }[]>`select * from public.claim_git_data_erasure_pending(3, interval '1 hour')`;
        return rows.map((r) => r.workspace_id);
      });
      release();
      const aRows = await A;
      expect(aRows).toHaveLength(3);
      expect(bRows).toHaveLength(3);
      expect(new Set([...aRows, ...bRows]).size).toBe(6);
      // and a third run after both committed finds nothing due inside the backoff window
      const c = await q<{ workspace_id: string }>`select * from public.claim_git_data_erasure_pending(100, interval '1 hour')`;
      expect(c.filter((r) => ids.includes(r.workspace_id))).toHaveLength(0);
    } finally {
      await q`delete from public.git_data_erasure_pending where workspace_id = any(${ids}::uuid[])`;
    }
  });

  test("resolve deletes the row, buckets the elapsed time, bumps the counter in one statement and leaves no tombstone", async () => {
    const cases: [string, string][] = [
      ["30 minutes", "lt_1h"], ["5 hours", "lt_24h"], ["3 days", "lt_7d"], ["10 days", "lt_20d"], ["25 days", "ge_20d"],
    ];
    const out = await asService(async (t) => {
      const buckets: string[] = [];
      for (const [age] of [...cases, ["5 minutes"], ["10 minutes"]]) {
        const id = randomUUID();
        await t`select public.record_git_data_erasure_pending(${id}::uuid, 'refused')`;
        await t`reset role`;
        await t`update public.git_data_erasure_pending set requested_at = now() - ${age}::interval where workspace_id = ${id}`;
        await t`set local role service_role`;
        const [r] = await t<{ b: string }[]>`select public.resolve_git_data_erasure_pending(${id}::uuid) as b`;
        buckets.push(r.b);
        const [again] = await t<{ b: string | null }[]>`select public.resolve_git_data_erasure_pending(${id}::uuid) as b`;
        expect(again.b).toBeNull();
      }
      await t`reset role`;
      const counts = await t<{ bucket: string; count: string }[]>`select bucket, count::text from public.git_data_erasure_counts order by bucket`;
      const [left] = await t<{ n: number }[]>`select count(*)::int as n from public.git_data_erasure_pending`;
      return { buckets, counts, left: left.n };
    });
    expect(out.buckets).toEqual([...cases.map(([, b]) => b), "lt_1h", "lt_1h"]);
    expect(out.counts.map((c) => [c.bucket, c.count])).toEqual([
      ["ge_20d", "1"], ["lt_1h", "3"], ["lt_20d", "1"], ["lt_24h", "1"], ["lt_7d", "1"],
    ]);
    expect(out.left).toBe(0);
  });

  test("resolving an id with no row changes no counter", async () => {
    const n = await asService(async (t) => {
      await t`select public.resolve_git_data_erasure_pending(${randomUUID()}::uuid)`;
      await t`reset role`;
      const [r] = await t<{ n: number }[]>`select count(*)::int as n from public.git_data_erasure_counts`;
      return r.n;
    });
    expect(n).toBe(0);
  });

  test("oldest age is NULL when empty and reports the oldest request in seconds", async () => {
    const out = await asService(async (t) => {
      const [empty] = await t<{ a: string | null }[]>`select public.oldest_git_data_erasure_pending_age()::text as a`;
      const [x, y] = [randomUUID(), randomUUID()];
      for (const id of [x, y]) await t`select public.record_git_data_erasure_pending(${id}::uuid, 'refused')`;
      await t`reset role`;
      await t`update public.git_data_erasure_pending set requested_at = now() - interval '2 days' where workspace_id = ${x}`;
      await t`update public.git_data_erasure_pending set requested_at = now() - interval '1 hour' where workspace_id = ${y}`;
      await t`set local role service_role`;
      const [full] = await t<{ a: string }[]>`select public.oldest_git_data_erasure_pending_age()::text as a`;
      return { empty: empty.a, full: Number(full.a) };
    });
    expect(out.full).toBeGreaterThanOrEqual(2 * 86400);
    expect(out.full).toBeLessThan(2 * 86400 + 600);
    expect(out.empty).toBeNull();
  });
});
