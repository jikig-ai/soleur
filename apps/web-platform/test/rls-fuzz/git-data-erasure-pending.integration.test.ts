import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import type postgres from "postgres";
import { attackAsAnon, connect, rolledBackRaw, withTransientRetry } from "./harness-fixture";

// Live-database cases for 164_git_data_erasure_pending (#8211, PR-B1). Gated like the rest of
// the harness (a local disposable Postgres only; assertLocalDsn refuses anything else). The
// ledger has no foreign keys, so most cases need no tenant seed. Cases that must observe
// concurrency commit their own rows (random uuids) and delete them in a finally; every other
// case runs inside a transaction that rolls back, so now() is fixed within a case and the
// bucket boundaries are exact.
//
// Synthetic data only (cq-test-fixtures-synthesized-only): random uuids, *.example.test emails.

const ENABLED = process.env.RLS_FUZZ_LOCAL === "1";
const DSN = process.env.RLS_FUZZ_DATABASE_URL ?? "postgres://postgres:postgres@127.0.0.1:54322/postgres";

type Txn = postgres.TransactionSql<{}>;

let sql: postgres.Sql<{}>;
let sqlB: postgres.Sql<{}>;

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

const as = {
  anon: <T>(fn: (t: Txn) => Promise<T>) => attackAsAnon(sql, fn),
  authenticated: asAuthenticated,
  service_role: asService,
};

const ANY_ID = randomUUID();
const RPC_CALLS = [
  `select public.record_git_data_erasure_pending('${ANY_ID}'::uuid, 'refused')`,
  `select public.record_git_data_erasure_pending('${ANY_ID}'::uuid, 'seeded', now() - interval '1 day')`,
  `select * from public.claim_git_data_erasure_pending(5, interval '1 hour')`,
  `select public.resolve_git_data_erasure_pending('${ANY_ID}'::uuid)`,
  `select public.oldest_git_data_erasure_pending_age()`,
  `select public.git_data_erasure_owner_gone('${ANY_ID}'::uuid)`,
];

const TABLES = ["git_data_erasure_pending", "git_data_erasure_counts"] as const;
const DML: Record<(typeof TABLES)[number], string[]> = {
  git_data_erasure_pending: [
    "select count(*) from public.git_data_erasure_pending",
    `insert into public.git_data_erasure_pending (workspace_id) values ('${ANY_ID}')`,
    "update public.git_data_erasure_pending set attempts = 1",
    "delete from public.git_data_erasure_pending",
  ],
  git_data_erasure_counts: [
    "select count(*) from public.git_data_erasure_counts",
    "insert into public.git_data_erasure_counts (month, bucket, count) values ('2026-01-01', 'lt_1h', 1)",
    "update public.git_data_erasure_counts set count = 1",
    "delete from public.git_data_erasure_counts",
  ],
};

// Seed one pending row at an exact age (the txn's fixed now() makes boundaries exact).
async function seedAged(t: Txn, age: string, id = randomUUID()): Promise<string> {
  await t`select public.record_git_data_erasure_pending(${id}::uuid, 'refused')`;
  await t`reset role`;
  await t`update public.git_data_erasure_pending set requested_at = now() - ${age}::interval where workspace_id = ${id}`;
  await t`set local role service_role`;
  return id;
}

describe.skipIf(!ENABLED)("git_data_erasure_pending (local, live database)", () => {
  beforeAll(async () => {
    sql = connect(DSN);
    sqlB = connect(DSN);
    await q`delete from public.git_data_erasure_pending`;
    await q`delete from public.git_data_erasure_counts`;
  });
  afterAll(async () => {
    if (sql) await sql.end({ timeout: 5 });
    if (sqlB) await sqlB.end({ timeout: 5 });
  });

  test("anon and authenticated cannot execute any of the six RPC forms; service_role can (positive control)", async () => {
    for (const stmt of RPC_CALLS) {
      await expect(as.authenticated((t) => t.unsafe(stmt)), stmt).rejects.toMatchObject({ code: "42501" });
      await expect(as.anon((t) => t.unsafe(stmt)), stmt).rejects.toMatchObject({ code: "42501" });
      await expect(as.service_role((t) => t.unsafe(stmt)), stmt).resolves.toBeDefined();
    }
  });

  test("no role has any direct SELECT/INSERT/UPDATE/DELETE on either table (RLS on, no policy, grants revoked)", async () => {
    for (const role of ["anon", "authenticated", "service_role"] as const) {
      for (const table of TABLES) {
        for (const stmt of DML[table]) {
          await expect(as[role]((t) => t.unsafe(stmt)), `${role}: ${stmt}`).rejects.toMatchObject({ code: "42501" });
        }
      }
    }
    const [r] = await q<{ pending: boolean; counts: boolean; policies: number }>`
      select (select relrowsecurity from pg_class where oid = 'public.git_data_erasure_pending'::regclass) as pending,
             (select relrowsecurity from pg_class where oid = 'public.git_data_erasure_counts'::regclass) as counts,
             (select count(*)::int from pg_policy
               where polrelid in ('public.git_data_erasure_pending'::regclass, 'public.git_data_erasure_counts'::regclass)) as policies`;
    expect(r).toEqual({ pending: true, counts: true, policies: 0 });
  });

  test("neither table has a foreign key, and each holds exactly the minimised column set", async () => {
    const fks = await q`select conname from pg_constraint
      where contype = 'f' and conrelid in ('public.git_data_erasure_pending'::regclass, 'public.git_data_erasure_counts'::regclass)`;
    expect(fks).toHaveLength(0);
    const cols = async (t: string) =>
      (await q<{ column_name: string }>`select column_name from information_schema.columns
        where table_schema = 'public' and table_name = ${t} order by column_name`).map((c) => c.column_name);
    expect(await cols("git_data_erasure_pending")).toEqual(["attempts", "last_attempt_at", "last_outcome", "requested_at", "workspace_id"]);
    expect(await cols("git_data_erasure_counts")).toEqual(["bucket", "count", "month"]);
  });

  test("every function is SECURITY DEFINER with search_path pinned to public, pg_temp", async () => {
    const rows = await q<{ proname: string; prosecdef: boolean; proconfig: string[] }>`
      select proname, prosecdef, proconfig from pg_proc
       where pronamespace = 'public'::regnamespace and proname in (
         'record_git_data_erasure_pending', 'claim_git_data_erasure_pending',
         'resolve_git_data_erasure_pending', 'oldest_git_data_erasure_pending_age',
         'git_data_erasure_owner_gone')`;
    expect(rows).toHaveLength(5);
    for (const r of rows) {
      expect(r.prosecdef, r.proname).toBe(true);
      expect(r.proconfig, r.proname).toContain("search_path=public, pg_temp");
    }
  });

  describe("record", () => {
    test("is an idempotent upsert that keeps the ORIGINAL requested_at and updates last_outcome", async () => {
      const id = randomUUID();
      const out = await asService(async (t) => {
        await t`select public.record_git_data_erasure_pending(${id}::uuid, 'refused')`;
        await t`reset role`;
        await t`update public.git_data_erasure_pending set requested_at = now() - interval '3 days', attempts = 2 where workspace_id = ${id}`;
        await t`set local role service_role`;
        await t`select public.record_git_data_erasure_pending(${id}::uuid, 'unreachable')`;
        await t`select public.record_git_data_erasure_pending(${id}::uuid, 'threw')`;
        await t`reset role`;
        return t<{ n: number; outcome: string; age_s: number; attempts: number }[]>`
          select count(*) over ()::int as n, last_outcome as outcome,
                 extract(epoch from now() - requested_at)::int as age_s, attempts
            from public.git_data_erasure_pending where workspace_id = ${id}`;
      });
      expect(out).toHaveLength(1);
      expect(out[0]).toMatchObject({ n: 1, outcome: "threw", attempts: 2 });
      expect(out[0].age_s).toBe(3 * 86400);
    });

    test("p_requested_at back-dates a new row (seed path); an earlier value moves the clock earlier, a later one never resets it", async () => {
      const id = randomUUID();
      const ages = await asService(async (t) => {
        const age = async () => {
          await t`reset role`;
          const [r] = await t<{ s: number }[]>`select extract(epoch from now() - requested_at)::int as s from public.git_data_erasure_pending where workspace_id = ${id}`;
          await t`set local role service_role`;
          return r.s;
        };
        await t`select public.record_git_data_erasure_pending(${id}::uuid, 'seeded', now() - interval '10 days')`;
        const first = await age();
        await t`select public.record_git_data_erasure_pending(${id}::uuid, 'refused', now() - interval '1 day')`; // later: ignored
        const second = await age();
        await t`select public.record_git_data_erasure_pending(${id}::uuid, 'refused', now() - interval '12 days')`; // earlier: wins
        const third = await age();
        await t`select public.record_git_data_erasure_pending(${id}::uuid, 'refused')`; // default now(): never resets
        const fourth = await age();
        return [first, second, third, fourth];
      });
      expect(ages).toEqual([10 * 86400, 10 * 86400, 12 * 86400, 12 * 86400]);
    });

    test("rejects a future requested_at, a NULL outcome, a NULL id and an outcome outside the closed enum", async () => {
      await expect(
        asService((t) => t`select public.record_git_data_erasure_pending(${randomUUID()}::uuid, 'seeded', now() + interval '1 minute')`),
      ).rejects.toThrow(/must not be in the future/);
      await expect(asService((t) => t`select public.record_git_data_erasure_pending(${randomUUID()}::uuid, null)`)).rejects.toThrow(/outcome is required/);
      await expect(asService((t) => t`select public.record_git_data_erasure_pending(null::uuid, 'refused')`)).rejects.toThrow(/workspace id is required/);
      await expect(
        asService((t) => t`select public.record_git_data_erasure_pending(${randomUUID()}::uuid, 'Command failed: ssh x')`),
      ).rejects.toMatchObject({ code: "23514" });
      await expect(
        asService((t) => t`select public.record_git_data_erasure_pending(${randomUUID()}::uuid, 'thrown')`),
      ).rejects.toMatchObject({ code: "23514" });
    });

    test("a NULL outcome never overwrites a known last_outcome", async () => {
      const id = randomUUID();
      const outcome = await asService(async (t) => {
        await t`select public.record_git_data_erasure_pending(${id}::uuid, 'refused')`;
        await t.savepoint(async (sp) => {
          await sp`select public.record_git_data_erasure_pending(${id}::uuid, null)`;
        }).catch(() => undefined);
        await t`reset role`;
        const [r] = await t<{ o: string }[]>`select last_outcome as o from public.git_data_erasure_pending where workspace_id = ${id}`;
        return r.o;
      });
      expect(outcome).toBe("refused");
    });

    test("accepts every word of the closed enum", async () => {
      for (const word of ["refused", "unreachable", "unauthorized", "unconfigured", "host_key_mismatch", "threw", "seeded"]) {
        await asService((t) => t`select public.record_git_data_erasure_pending(${randomUUID()}::uuid, ${word})`);
      }
    });
  });

  describe("claim", () => {
    test("returns at most p_limit due rows OLDEST first (newest inserted first), stamps attempts, honours the backoff", async () => {
      const ids = [randomUUID(), randomUUID(), randomUUID()]; // ids[0] is the oldest request
      const out = await asService(async (t) => {
        // insert the NEWEST row first so insertion order cannot satisfy the ordering assertion
        for (const [i, id] of [...ids.entries()].reverse()) {
          await t`select public.record_git_data_erasure_pending(${id}::uuid, 'refused')`;
          await t`reset role`;
          await t`update public.git_data_erasure_pending set requested_at = timestamptz '2000-01-01' + ${i} * interval '1 day' where workspace_id = ${id}`;
          await t`set local role service_role`;
        }
        const first = await t<{ workspace_id: string; attempts: number }[]>`select * from public.claim_git_data_erasure_pending(2, interval '1 hour')`;
        const second = await t<{ workspace_id: string }[]>`select * from public.claim_git_data_erasure_pending(5, interval '1 hour')`;
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

    test("p_limit edges: NULL, 0, -1 and 101 raise; 1 and 100 are accepted", async () => {
      for (const bad of ["null", "0", "-1", "101"]) {
        await expect(asService((t) => t.unsafe(`select * from public.claim_git_data_erasure_pending(${bad}, interval '1 hour')`)), bad).rejects.toThrow(/limit/);
      }
      for (const ok of ["1", "100"]) {
        await expect(asService((t) => t.unsafe(`select * from public.claim_git_data_erasure_pending(${ok}, interval '1 hour')`)), ok).resolves.toBeDefined();
      }
    });

    test("p_min_interval edges: NULL and 59 seconds raise; exactly 1 minute is accepted", async () => {
      for (const bad of ["null", "interval '59 seconds'", "interval '0 seconds'", "interval '-1 hour'"]) {
        await expect(asService((t) => t.unsafe(`select * from public.claim_git_data_erasure_pending(5, ${bad})`)), bad).rejects.toThrow(/interval/);
      }
      await expect(asService((t) => t`select * from public.claim_git_data_erasure_pending(5, interval '1 minute')`)).resolves.toBeDefined();
    });

    test("two concurrent claims (SKIP LOCKED) never hand the same row to both", async () => {
      const ids: string[] = Array.from({ length: 6 }, () => randomUUID());
      try {
        for (const id of ids) await q`select public.record_git_data_erasure_pending(${id}::uuid, 'refused')`;
        await q`update public.git_data_erasure_pending set requested_at = timestamptz '1999-01-01' where workspace_id = any(${ids}::uuid[])`;

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
        let bRows: string[];
        try {
          bRows = await sqlB.begin(async (t) => {
            await t`set local lock_timeout = '3s'`; // without SKIP LOCKED this blocks on A's locks and fails fast
            const rows = await t<{ workspace_id: string }[]>`select * from public.claim_git_data_erasure_pending(3, interval '1 hour')`;
            return rows.map((r) => r.workspace_id);
          });
        } finally {
          release(); // never leave A parked on the gate, even when B fails
        }
        const aRows = await A;
        expect(aRows).toHaveLength(3);
        expect(bRows).toHaveLength(3);
        expect(new Set([...aRows, ...bRows]).size).toBe(6);
        const c = await q<{ workspace_id: string }>`select * from public.claim_git_data_erasure_pending(100, interval '1 hour')`;
        expect(c.filter((r) => ids.includes(r.workspace_id))).toHaveLength(0);
      } finally {
        await q`delete from public.git_data_erasure_pending where workspace_id = any(${ids}::uuid[])`;
      }
    });
  });

  describe("resolve", () => {
    // [age, expected bucket]. now() is fixed inside the rolled-back txn, so "exactly 1 hour" is exact.
    const BOUNDARIES: [string, string][] = [
      ["59 minutes 59 seconds", "lt_1h"], ["1 hour", "lt_24h"],
      ["23 hours 59 minutes 59 seconds", "lt_24h"], ["24 hours", "lt_7d"],
      ["6 days 23 hours 59 minutes 59 seconds", "lt_7d"], ["7 days", "lt_20d"],
      ["19 days 23 hours 59 minutes 59 seconds", "lt_20d"], ["20 days", "ge_20d"],
      ["45 days", "ge_20d"], ["-5 minutes", "lt_1h"], // a future requested_at (cannot be recorded, but can exist)
    ];

    test("buckets the elapsed time exactly at and just under every boundary", async () => {
      const got = await asService(async (t) => {
        const out: string[] = [];
        for (const [age] of BOUNDARIES) {
          const id = await seedAged(t, age);
          const [r] = await t<{ b: string }[]>`select public.resolve_git_data_erasure_pending(${id}::uuid) as b`;
          out.push(r.b);
        }
        return out;
      });
      expect(got).toEqual(BOUNDARIES.map(([, b]) => b));
    });

    test("deletes the row, bumps the counter in one statement, repeats are no-ops, and leaves no tombstone", async () => {
      const out = await asService(async (t) => {
        const ids = [await seedAged(t, "30 minutes"), await seedAged(t, "5 minutes"), await seedAged(t, "5 hours")];
        const buckets: (string | null)[] = [];
        for (const id of ids) {
          const [r] = await t<{ b: string | null }[]>`select public.resolve_git_data_erasure_pending(${id}::uuid) as b`;
          buckets.push(r.b);
        }
        const [again] = await t<{ b: string | null }[]>`select public.resolve_git_data_erasure_pending(${ids[0]}::uuid) as b`;
        await t`reset role`;
        const counts = await t<{ bucket: string; count: string }[]>`select bucket, count::text from public.git_data_erasure_counts order by bucket`;
        const [left] = await t<{ n: number }[]>`select count(*)::int as n from public.git_data_erasure_pending`;
        return { buckets, again: again.b, counts, left: left.n };
      });
      expect(out.buckets).toEqual(["lt_1h", "lt_1h", "lt_24h"]);
      expect(out.again).toBeNull();
      expect(out.counts.map((c) => [c.bucket, c.count])).toEqual([["lt_1h", "2"], ["lt_24h", "1"]]);
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

    test("the counter month is the UTC month whatever the session TimeZone", async () => {
      // Non-vacuous only within 14 hours of a UTC month edge (the harness cannot fake now());
      // the shape test pins the exact AT TIME ZONE 'UTC' expression for every other day.
      for (const tz of ["Pacific/Kiritimati", "Etc/GMT+12", "America/Los_Angeles", "Asia/Kolkata"]) {
        const out = await asService(async (t) => {
          await t.unsafe(`set local timezone to '${tz}'`);
          const id = await seedAged(t, "10 minutes");
          await t`select public.resolve_git_data_erasure_pending(${id}::uuid)`;
          await t`reset role`;
          const [m] = await t<{ month: string; utc_month: string }[]>`
            select month::text, date_trunc('month', now() at time zone 'UTC')::date::text as utc_month
              from public.git_data_erasure_counts`;
          return m;
        });
        expect(out.month, tz).toBe(out.utc_month);
      }
    });
  });

  describe("oldest age", () => {
    test("is NULL when empty, reports the oldest request in seconds, and is never negative for a future requested_at", async () => {
      const out = await asService(async (t) => {
        const [empty] = await t<{ a: string | null }[]>`select public.oldest_git_data_erasure_pending_age()::text as a`;
        await seedAged(t, "2 days");
        await seedAged(t, "1 hour");
        const [full] = await t<{ a: string }[]>`select public.oldest_git_data_erasure_pending_age()::text as a`;
        await t`reset role`;
        await t`delete from public.git_data_erasure_pending`;
        await t`set local role service_role`;
        await seedAged(t, "-10 minutes"); // a future requested_at
        const [future] = await t<{ a: string }[]>`select public.oldest_git_data_erasure_pending_age()::text as a`;
        return { empty: empty.a, full: Number(full.a), future: Number(future.a) };
      });
      expect(out.empty).toBeNull();
      expect(out.full).toBe(2 * 86400);
      expect(out.future).toBe(0);
    });
  });

  describe("git_data_erasure_owner_gone", () => {
    const newUser = async (t: Txn): Promise<string> => {
      const id = randomUUID();
      await t`insert into auth.users (id, email) values (${id}, ${`${id}@example.test`})`;
      return id;
    };

    // The Art. 17 saga's own steps (account-delete 3.91, 3.92, 3.93, then step 6), run as the table owner.
    const eraseAccount = async (t: Txn, id: string) => {
      await t`select public.anonymise_workspace_members(${id}::uuid)`;
      await t`select public.anonymise_organization_membership(${id}::uuid)`;
      await t`select public.anonymise_workspace_member_actions(${id}::uuid)`;
      await t`delete from auth.users where id = ${id}`;
    };

    test("an id that exists nowhere is gone; NULL raises (a caller must treat an error as not gone)", async () => {
      const [r] = await asService((t) => t<{ g: boolean }[]>`select public.git_data_erasure_owner_gone(${randomUUID()}::uuid) as g`);
      expect(r.g).toBe(true);
      await expect(asService((t) => t`select public.git_data_erasure_owner_gone(null::uuid)`)).rejects.toThrow(/workspace id is required/);
    });

    test("a live account (auth user, public user, own membership) is NOT gone", async () => {
      const g = await asService(async (t) => {
        await t`reset role`;
        const id = await newUser(t);
        await t`set local role service_role`;
        const [r] = await t<{ g: boolean }[]>`select public.git_data_erasure_owner_gone(${id}::uuid) as g`;
        return r.g;
      });
      expect(g).toBe(false);
    });

    test("another member still in the workspace keeps it NOT gone even when the owner's account is deleted", async () => {
      const g = await asService(async (t) => {
        await t`reset role`;
        const owner = await newUser(t);
        const other = await newUser(t);
        await t`insert into public.workspace_members (workspace_id, user_id, role) values (${owner}, ${other}, 'member')`;
        await eraseAccount(t, owner);
        await t`set local role service_role`;
        const [r] = await t<{ g: boolean }[]>`select public.git_data_erasure_owner_gone(${owner}::uuid) as g`;
        return r.g;
      });
      expect(g).toBe(false);
    });

    test("after the saga (memberships and auth user deleted) the id is gone even though the orphan workspace row survives (mig 065)", async () => {
      const out = await asService(async (t) => {
        await t`reset role`;
        const id = await newUser(t);
        await eraseAccount(t, id);
        const [ws] = await t<{ n: number }[]>`select count(*)::int as n from public.workspaces where id = ${id}`;
        await t`set local role service_role`;
        const [r] = await t<{ g: boolean }[]>`select public.git_data_erasure_owner_gone(${id}::uuid) as g`;
        return { gone: r.g, orphanWorkspaceRows: ws.n };
      });
      expect(out.orphanWorkspaceRows).toBe(1);
      expect(out.gone).toBe(true);
    });
  });
});
