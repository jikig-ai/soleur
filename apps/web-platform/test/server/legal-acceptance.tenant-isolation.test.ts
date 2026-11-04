import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import postgres from "postgres";

// Behavioural proof of migration 184 against a REAL database (#12011 PR-B, ADR-318): every Guard 3 mutation row,
// the single-use email-code challenge, the write-once trigger, the checksum and the erasure carve-out. Every scenario
// runs in its own transaction that is ROLLED BACK, so nothing persists. The static shape test
// (test/legal-acceptance/migration-184-legal-acceptance.test.ts) is the cheap backstop; this file is the proof.
//
// Collected by tenant-integration.yml (path matches test/server/*.tenant-isolation.test.ts), which applies this PR's
// migrations to DEV. Gate: LEGAL_DB_URL (a local stack or DEV, session-mode :5432), OR TENANT_INTEGRATION_TEST=1 plus
// DATABASE_URL_POOLER (:6543 rewritten to :5432). It REFUSES the production project ref. Synthetic data only.
//
//   doppler run -p soleur -c dev -- bash -c 'LEGAL_DB_URL="${DATABASE_URL_POOLER/:6543/:5432}" \
//     ./node_modules/.bin/vitest run test/server/legal-acceptance.tenant-isolation.test.ts'

const URL_ENV =
  process.env.LEGAL_DB_URL ??
  (process.env.TENANT_INTEGRATION_TEST === "1" && process.env.DATABASE_URL_POOLER
    ? process.env.DATABASE_URL_POOLER.replace(":6543", ":5432")
    : undefined);
const PRD_REF = "ifsccnjhymdmidffkzhl";
const ENABLED = Boolean(URL_ENV) && !URL_ENV!.includes(PRD_REF);

const KEY = "terms-update";
const hex = (c: string) => c.repeat(64);
const H1 = hex("a");
const H2 = hex("b");
const VERSION = "2026-11-01";

type Txn = postgres.TransactionSql<{}>;
interface Ctx {
  userA: string;
  userB: string;
  sessionA: string;
}

const ROLLBACK = Symbol("rollback");
let sql: postgres.Sql<{}>;

beforeAll(() => {
  if (!ENABLED) return;
  sql = postgres(URL_ENV!, { ssl: { rejectUnauthorized: false }, max: 1, onnotice: () => {} });
});
afterAll(async () => {
  if (sql) await sql.end();
});

async function scenario(fn: (t: Txn, c: Ctx) => Promise<void>): Promise<void> {
  try {
    await sql.begin(async (t) => {
      const [userA, userB] = [randomUUID(), randomUUID()];
      for (const [n, u] of Object.entries({ a: userA, b: userB })) {
        await t`insert into auth.users (id, email) values (${u}, ${`${n}-${u}@example.test`})`;
      }
      await fn(t, { userA, userB, sessionA: randomUUID() });
      return Promise.reject(ROLLBACK);
    });
  } catch (e) {
    if (e !== ROLLBACK) throw e;
  }
}

type Claims = { sub?: string; session_id?: string; aud?: string; jti?: string };

/** Run fn as a database role with request claims; always back to the owner role afterwards. */
async function as<T>(t: Txn, role: "service_role" | "authenticated" | "anon", claims: Claims | null, fn: () => Promise<T>): Promise<T> {
  await t.unsafe(`set local role ${role}`);
  const body = JSON.stringify(claims ? { role, aud: "authenticated", ...claims } : { role });
  await t`select set_config('request.jwt.claims', ${body}, true)`;
  try {
    return await fn();
  } finally {
    await t.unsafe("reset role").catch(() => undefined);
  }
}

/** Expect fn to throw; the failing statement is isolated in a savepoint so the scenario transaction survives. */
async function failsWith(t: Txn, pattern: RegExp, fn: () => Promise<unknown>): Promise<void> {
  let err: unknown = null;
  try {
    await t.savepoint(async () => {
      await fn();
    });
  } catch (e) {
    err = e;
  }
  expect(err, "expected an error").not.toBeNull();
  const m = err as { message?: string; code?: string };
  expect(`${m.code ?? ""} ${m.message ?? ""}`).toMatch(pattern);
}

const issue = (t: Txn, user: string, session: string, over: { key?: string; hash?: string } = {}) =>
  as(t, "service_role", null, async () => {
    const [r] = await t<{ r: any }[]>`select public.issue_legal_reauth(${user}::uuid, ${over.key ?? KEY}::text, ${over.hash ?? H1}::text, ${session}::text) as r`;
    return r.r;
  });
const claim = (t: Txn, user: string, session: string, over: { key?: string; hash?: string } = {}) =>
  as(t, "service_role", null, async () => {
    const [r] = await t<{ r: any }[]>`select public.claim_legal_reauth_attempt(${user}::uuid, ${over.key ?? KEY}::text, ${over.hash ?? H1}::text, ${session}::text) as r`;
    return r.r;
  });
const markVerified = (t: Txn, user: string, session: string, over: { key?: string; hash?: string } = {}) =>
  as(t, "service_role", null, async () => {
    const [r] = await t<{ r: any }[]>`select public.mark_legal_reauth_verified(${user}::uuid, ${over.key ?? KEY}::text, ${over.hash ?? H1}::text, ${session}::text) as r`;
    return r.r;
  });
const verifiedChallenge = async (t: Txn, user: string, session: string, over: { key?: string; hash?: string } = {}) => {
  expect((await issue(t, user, session, over)).outcome).toBe("issued");
  expect((await claim(t, user, session, over)).outcome).toBe("allowed");
  expect((await markVerified(t, user, session, over)).outcome).toBe("verified");
};
const record = (
  t: Txn,
  claims: Claims | null,
  over: { key?: string; hash?: string; choice?: string; edit?: string | null; role?: "authenticated" | "service_role" } = {},
) =>
  as(t, over.role ?? "authenticated", claims, async () => {
    const [r] = await t<{ r: any }[]>`select public.record_legal_acceptance(
      ${over.key ?? KEY}::text, ${over.hash ?? H1}::text, ${VERSION}::text, ${over.choice ?? "accept"}::text, ${over.edit ?? null}::text) as r`;
    return r.r;
  });
const events = async (t: Txn, user: string) => (await t`select * from public.legal_reauth_event where user_id = ${user} order by created_at`) as any[];
const rows = async (t: Txn, user: string) => (await t`select * from public.legal_acceptance where founder_id = ${user}`) as any[];

describe.skipIf(!ENABLED)("migration 184 behaviour (rolled-back real rows)", () => {
  test("happy path: a verified code is consumed by a Yes; the row carries a database-computed checksum", async () => {
    await scenario(async (t, c) => {
      await verifiedChallenge(t, c.userA, c.sessionA);
      const r = await record(t, { sub: c.userA, session_id: c.sessionA });
      expect(r).toMatchObject({ outcome: "recorded", choice: "accept", text_hash: H1 });
      const [row] = await rows(t, c.userA);
      expect(row.row_hash).toMatch(/^[0-9a-f]{64}$/);
      expect(row).toMatchObject({ method: "web-session", reauth_method: "email-code", surface: "web", session_id: c.sessionA });
      expect((await events(t, c.userA))[0].consumed_at).not.toBeNull();
      // Mutation 5: a second Yes on another text cannot reuse the consumed code.
      await failsWith(t, /email code required/, () => record(t, { sub: c.userA, session_id: c.sessionA }, { hash: H2 }));
    });
  });

  test("Guard 3: UPDATE, DELETE and TRUNCATE are refused for every role, including the table owner", async () => {
    await scenario(async (t, c) => {
      await verifiedChallenge(t, c.userA, c.sessionA);
      await record(t, { sub: c.userA, session_id: c.sessionA });
      await failsWith(t, /write-once/, () => t`update public.legal_acceptance set choice = 'decline' where founder_id = ${c.userA}`);
      await failsWith(t, /write-once/, () => t`update public.legal_acceptance set row_hash = ${hex("0")} where founder_id = ${c.userA}`);
      await failsWith(t, /write-once/, () => t`delete from public.legal_acceptance where founder_id = ${c.userA}`);
      await failsWith(t, /write-once/, () => t.unsafe("truncate public.legal_acceptance"));
      await failsWith(t, /permission denied|write-once/, () => as(t, "authenticated", { sub: c.userA }, () => t`delete from public.legal_acceptance`));
      await failsWith(t, /permission denied/, () => as(t, "service_role", null, () => t`update public.legal_acceptance set choice = 'decline'`));
      expect(await rows(t, c.userA)).toHaveLength(1);
    });
  });

  test("Guard 3: a direct INSERT is refused, and a supplied row_hash is overwritten by the database", async () => {
    await scenario(async (t, c) => {
      await failsWith(t, /direct insert refused/, () =>
        t`insert into public.legal_acceptance (founder_id, key, text_hash, version, choice) values (${c.userA}, ${KEY}, ${H1}, ${VERSION}, 'decline')`);
      await failsWith(t, /permission denied/, () =>
        as(t, "authenticated", { sub: c.userA }, () =>
          t`insert into public.legal_acceptance (founder_id, key, text_hash, version, choice) values (${c.userA}, ${KEY}, ${H1}, ${VERSION}, 'decline')`));
      await record(t, { sub: c.userA }, { choice: "decline" });
      const [row] = await rows(t, c.userA);
      expect(row.row_hash).toMatch(/^[0-9a-f]{64}$/);
    });
  });

  test("Guard 3 row 4: the checksum covers text_hash, and the verify function recomputes it", async () => {
    await scenario(async (t, c) => {
      await record(t, { sub: c.userA }, { choice: "decline" });
      await record(t, { sub: c.userA }, { choice: "decline", hash: H2 });
      const [a, b] = await t`select row_hash, text_hash from public.legal_acceptance where founder_id = ${c.userA} order by text_hash`;
      expect(a.row_hash).not.toBe(b.row_hash);
      const [v] = await as(t, "service_role", null, () => t<{ r: any }[]>`select public.verify_legal_acceptance(${c.userA}::uuid, ${KEY}::text, ${H1}::text) as r`);
      expect(v.r).toMatchObject({ status: "declined", text_hash: H1, row_ok: true });
      // Tamper as the owner with the guard disabled: the stored hash no longer matches the row.
      await t.unsafe("alter table public.legal_acceptance disable trigger legal_acceptance_guard");
      await t`update public.legal_acceptance set version = 'tampered' where founder_id = ${c.userA} and text_hash = ${H1}`;
      await t.unsafe("alter table public.legal_acceptance enable trigger legal_acceptance_guard");
      const [v2] = await as(t, "service_role", null, () => t<{ r: any }[]>`select public.verify_legal_acceptance(${c.userA}::uuid, ${KEY}::text, ${H1}::text) as r`);
      expect(v2.r).toMatchObject({ row_ok: false });
      const [none] = await as(t, "service_role", null, () => t<{ r: any }[]>`select public.verify_legal_acceptance(${c.userA}::uuid, 'other-key'::text, ${H1}::text) as r`);
      expect(none.r).toMatchObject({ status: "none" });
    });
  });

  test("Guard 3 row 2: the read function cannot open the write door", async () => {
    await scenario(async (t, c) => {
      await failsWith(t, /service role only|permission denied/, () =>
        as(t, "authenticated", { sub: c.userA }, () => t`select public.verify_legal_acceptance(${c.userA}::uuid, ${KEY}::text, ${H1}::text)`));
      await as(t, "service_role", null, () => t`select public.verify_legal_acceptance(${c.userA}::uuid, ${KEY}::text, ${H1}::text)`);
      const [g] = await t`select current_setting('app.legal_acceptance_rpc', true) as v`;
      expect(g.v ?? "").not.toBe("on");
      await failsWith(t, /direct insert refused/, () =>
        t`insert into public.legal_acceptance (founder_id, key, text_hash, version, choice) values (${c.userA}, ${KEY}, ${H1}, ${VERSION}, 'decline')`);
    });
  });

  test("Guard 3 row 3: the approval erasure scrub leaves the record, and so does deleting the account", async () => {
    await scenario(async (t, c) => {
      await verifiedChallenge(t, c.userA, c.sessionA);
      await record(t, { sub: c.userA, session_id: c.sessionA });
      await as(t, "service_role", null, () => t`select public.anonymise_approval_request(${c.userA}::uuid)`);
      expect(await rows(t, c.userA)).toHaveLength(1);
      // No foreign key leaves the record, so no cascade from the account can reach it.
      const [fk] = await t`select count(*)::int n from pg_constraint where conrelid = 'public.legal_acceptance'::regclass and contype = 'f'`;
      expect(fk.n).toBe(0);
    });
  });

  test("Guard 3 row 5: a Yes without a verified challenge is refused and nothing is consumed", async () => {
    await scenario(async (t, c) => {
      await failsWith(t, /email code required/, () => record(t, { sub: c.userA, session_id: c.sessionA })); // no event at all
      expect((await issue(t, c.userA, c.sessionA)).outcome).toBe("issued");
      await failsWith(t, /email code required/, () => record(t, { sub: c.userA, session_id: c.sessionA })); // issued, never verified
      await failsWith(t, /email code required/, () => record(t, { sub: c.userA }));                          // no session claim
      expect((await events(t, c.userA))[0].consumed_at).toBeNull();
      expect(await rows(t, c.userA)).toHaveLength(0);
    });
  });

  test("Guard 3 row 6: a challenge bound to another user, key, session or text cannot back a Yes", async () => {
    await scenario(async (t, c) => {
      await verifiedChallenge(t, c.userA, c.sessionA);
      await failsWith(t, /email code required/, () => record(t, { sub: c.userB, session_id: c.sessionA }));     // another user
      await failsWith(t, /email code required/, () => record(t, { sub: c.userA, session_id: randomUUID() }));   // another session
      await failsWith(t, /email code required/, () => record(t, { sub: c.userA, session_id: c.sessionA }, { key: "other-key" })); // another key
      const replaced = await record(t, { sub: c.userA, session_id: c.sessionA }, { hash: H2 });                 // another text
      expect(replaced.outcome).toBe("replaced");
      expect((await events(t, c.userA))[0].consumed_at).toBeNull();
      expect(await rows(t, c.userA)).toHaveLength(0);
    });
  });

  test("Guard 3 row 7: the actor comes from the verified session; runtime audience, denied token, anon and service role are refused", async () => {
    await scenario(async (t, c) => {
      await verifiedChallenge(t, c.userA, c.sessionA);
      await failsWith(t, /authenticated callers only|permission denied/, () => record(t, null, { role: "service_role" }));
      await failsWith(t, /permission denied/, () => as(t, "anon", null, () => t`select public.record_legal_acceptance(${KEY}::text, ${H1}::text, ${VERSION}::text, 'decline'::text, null::text)`));
      await failsWith(t, /runtime token/, () => record(t, { sub: c.userA, session_id: c.sessionA, aud: "soleur-runtime" }));
      const jti = randomUUID();
      await t`insert into public.denied_jti (jti, founder_id, reason) values (${jti}, ${c.userA}, 'test')`;
      await failsWith(t, /token denied/, () => record(t, { sub: c.userA, session_id: c.sessionA, jti }));
      expect(await rows(t, c.userA)).toHaveLength(0);
      expect((await events(t, c.userA))[0].consumed_at).toBeNull();
    });
  });

  test("the founder cannot record on behalf of another founder; the row is theirs", async () => {
    await scenario(async (t, c) => {
      await verifiedChallenge(t, c.userA, c.sessionA);
      await record(t, { sub: c.userA, session_id: c.sessionA });
      expect(await rows(t, c.userA)).toHaveLength(1);
      expect(await rows(t, c.userB)).toHaveLength(0);
      const seenByB = await as(t, "authenticated", { sub: c.userB }, () => t`select * from public.legal_acceptance`);
      expect(seenByB.filter((r: any) => r.founder_id === c.userA)).toHaveLength(0);
      const seenByA = await as(t, "authenticated", { sub: c.userA }, () => t`select founder_id from public.legal_acceptance`);
      expect(seenByA.map((r: any) => r.founder_id)).toContain(c.userA);
    });
  });

  test("Decline and Request changes need no code; Request changes needs text within the cap; each is recorded once", async () => {
    await scenario(async (t, c) => {
      const d = await record(t, { sub: c.userA }, { choice: "decline" });
      expect(d.outcome).toBe("recorded");
      expect((await record(t, { sub: c.userA }, { choice: "accept" })).outcome).toBe("already_recorded"); // same text, second tab
      await failsWith(t, /invalid input/, () => record(t, { sub: c.userA }, { choice: "request_changes", hash: H2 }));
      await failsWith(t, /invalid input/, () => record(t, { sub: c.userA }, { choice: "request_changes", hash: H2, edit: "   " }));
      await failsWith(t, /invalid input/, () => record(t, { sub: c.userA }, { choice: "decline", hash: H2, edit: "text with a decline" }));
      await failsWith(t, /invalid input/, () => record(t, { sub: c.userA }, { choice: "request_changes", hash: H2, edit: "x".repeat(1001) }));
      const rc = await record(t, { sub: c.userA }, { choice: "request_changes", hash: H2, edit: "Please shorten clause 4." });
      expect(rc.outcome).toBe("recorded");
      const [row] = await t`select requested_edit from public.legal_acceptance where founder_id = ${c.userA} and text_hash = ${H2}`;
      expect(row.requested_edit).toBe("Please shorten clause 4.");
    });
  });

  test("Must-PASS: a new text version of the same key is a new row", async () => {
    await scenario(async (t, c) => {
      await record(t, { sub: c.userA }, { choice: "decline" });
      await verifiedChallenge(t, c.userA, c.sessionA, { hash: H2 });
      const r = await record(t, { sub: c.userA, session_id: c.sessionA }, { hash: H2 });
      expect(r.outcome).toBe("recorded");
      expect(await rows(t, c.userA)).toHaveLength(2);
    });
  });

  test("challenge lifecycle: a resend voids the old code, five attempts lock it, an expired code is not consumed", async () => {
    await scenario(async (t, c) => {
      await issue(t, c.userA, c.sessionA);
      await issue(t, c.userA, c.sessionA); // resend
      const ev = await events(t, c.userA);
      expect(ev[0].superseded_at).not.toBeNull();
      expect(ev[1].superseded_at).toBeNull();
      for (let i = 0; i < 5; i++) expect((await claim(t, c.userA, c.sessionA)).outcome).toBe("allowed");
      expect((await claim(t, c.userA, c.sessionA)).outcome).toBe("locked");
      // A locked challenge that was never verified cannot back a Yes.
      await failsWith(t, /email code required/, () => record(t, { sub: c.userA, session_id: c.sessionA }));
      // Expiry: a verified challenge past its time is refused and not consumed.
      await verifiedChallenge(t, c.userB, randomUUID());
      const [evB] = await events(t, c.userB);
      await t`update public.legal_reauth_event set expires_at = now() - interval '1 second' where id = ${evB.id}`;
      expect((await claim(t, c.userB, evB.session_id)).outcome).toBe("expired");
      expect((await record(t, { sub: c.userB, session_id: evB.session_id })).outcome).toBe("expired");
      expect((await events(t, c.userB))[0].consumed_at).toBeNull();
    });
  });

  test("mark_verified needs a claimed attempt; issue refuses when a decision exists and caps challenges at 3 per 15 minutes", async () => {
    await scenario(async (t, c) => {
      await issue(t, c.userA, c.sessionA);
      expect((await markVerified(t, c.userA, c.sessionA)).outcome).toBe("not_claimed");
      for (let i = 0; i < 2; i++) expect((await issue(t, c.userA, c.sessionA)).outcome).toBe("issued"); // 3 in total with the first
      expect((await issue(t, c.userA, c.sessionA)).outcome).toBe("rate_limited");
      await record(t, { sub: c.userB }, { choice: "decline" });
      expect((await issue(t, c.userB, randomUUID())).outcome).toBe("already_recorded");
    });
  });

  test("AC4: the down file refuses while a decision row exists, and drops nothing", async () => {
    await scenario(async (t, c) => {
      await record(t, { sub: c.userA }, { choice: "decline" });
      const down = readFileSync(path.join(__dirname, "../../supabase/migrations/184_legal_acceptance.down.sql"), "utf8");
      await failsWith(t, /184 down refused/, () => t.unsafe(down));
      const [n] = await t`select count(*)::int n from public.legal_acceptance where founder_id = ${c.userA}`;
      expect(n.n).toBe(1);
    });
  });

  test("the service RPCs refuse a user identity and the event table is closed to every api role", async () => {
    await scenario(async (t, c) => {
      await failsWith(t, /service role only|permission denied/, () =>
        as(t, "authenticated", { sub: c.userA }, () => t`select public.issue_legal_reauth(${c.userA}::uuid, ${KEY}::text, ${H1}::text, 'x'::text)`));
      for (const role of ["anon", "authenticated", "service_role"] as const) {
        await failsWith(t, /permission denied/, () => as(t, role, role === "authenticated" ? { sub: c.userA } : null, () => t`select * from public.legal_reauth_event`));
      }
    });
  });
});
