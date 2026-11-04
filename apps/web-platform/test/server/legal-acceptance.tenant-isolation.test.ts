import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import postgres from "postgres";

// Behavioural proof of migration 184 against a REAL database (#12011 PR-B, ADR-319): every Guard 3 mutation row,
// the server-issued intent that backs EVERY decision, the single-use email-code challenge behind a Yes, the write-once
// trigger, the checksum and the erasure carve-out. Every scenario runs in its own transaction that is ROLLED BACK, so
// nothing persists. The static shape test (test/legal-acceptance/migration-184-legal-acceptance.test.ts) is the cheap
// backstop; this file is the proof.
//
// Collected by tenant-integration.yml (path matches test/server/*.tenant-isolation.test.ts), which applies this PR's
// migrations to DEV. Gate: LEGAL_DB_URL (a local stack or DEV, session-mode :5432), OR TENANT_INTEGRATION_TEST=1 plus
// DATABASE_URL_POOLER (:6543 rewritten to :5432). It REFUSES the production project ref. Synthetic data only.
// Under TENANT_INTEGRATION_TEST=1 a missing or prd URL is a hard failure, never a silent skip.
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

type Claims = { sub?: string; session_id?: string; ses_id?: string; aud?: string; jti?: string };

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

type O = { key?: string; hash?: string; version?: string };
const issue = (t: Txn, user: string, session: string, over: O & { resend?: boolean } = {}) =>
  as(t, "service_role", null, async () => {
    const [r] = await t<{ r: any }[]>`select public.issue_legal_reauth(${user}::uuid, ${over.key ?? KEY}::text, ${over.hash ?? H1}::text,
      ${over.version ?? VERSION}::text, ${session}::text, ${over.resend ?? false}::boolean) as r`;
    return r.r;
  });
const claim = (t: Txn, user: string, session: string, over: O = {}) =>
  as(t, "service_role", null, async () => {
    const [r] = await t<{ r: any }[]>`select public.claim_legal_reauth_attempt(${user}::uuid, ${over.key ?? KEY}::text, ${over.hash ?? H1}::text, ${session}::text) as r`;
    return r.r;
  });
const markVerified = (t: Txn, user: string, eventId: string, session: string, over: O = {}) =>
  as(t, "service_role", null, async () => {
    const [r] = await t<{ r: any }[]>`select public.mark_legal_reauth_verified(${user}::uuid, ${eventId}::uuid, ${over.key ?? KEY}::text, ${over.hash ?? H1}::text, ${session}::text) as r`;
    return r.r;
  });
/** Intent only (enough for Decline / Request changes). Returns the event id. */
const intent = async (t: Txn, user: string, session: string, over: O = {}) => {
  const r = await issue(t, user, session, over);
  expect(r.outcome).toBe("issued");
  return r.event_id as string;
};
/** Intent plus a confirmed email code (what a Yes needs). Returns the event id. */
const verifiedIntent = async (t: Txn, user: string, session: string, over: O = {}) => {
  const id = await intent(t, user, session, over);
  const cl = await claim(t, user, session, over);
  expect(cl).toMatchObject({ outcome: "allowed", event_id: id });
  expect((await markVerified(t, user, id, session, over)).outcome).toBe("verified");
  return id;
};
const record = (
  t: Txn,
  claims: Claims | null,
  over: { key?: string; hash?: string; choice?: string; edit?: string | null; role?: "authenticated" | "service_role" } = {},
) =>
  as(t, over.role ?? "authenticated", claims, async () => {
    const [r] = await t<{ r: any }[]>`select public.record_legal_acceptance(
      ${over.key ?? KEY}::text, ${over.hash ?? H1}::text, ${over.choice ?? "accept"}::text, ${over.edit ?? null}::text) as r`;
    return r.r;
  });
const web = (c: Ctx, user = c.userA, session = c.sessionA): Claims => ({ sub: user, session_id: session });
const verifyFn = (t: Txn, user: string, hash = H1, key = KEY) =>
  as(t, "service_role", null, async () => {
    const [r] = await t<{ r: any }[]>`select public.verify_legal_acceptance(${user}::uuid, ${key}::text, ${hash}::text) as r`;
    return r.r;
  });
const events = async (t: Txn, user: string) => (await t`select * from public.legal_reauth_event where user_id = ${user} order by created_at`) as any[];
const rows = async (t: Txn, user: string) => (await t`select * from public.legal_acceptance where founder_id = ${user}`) as any[];

// A silently skipped suite is a green gate with no proof: under the CI flag the database MUST be reachable.
test.runIf(process.env.TENANT_INTEGRATION_TEST === "1" && !ENABLED)("CI configuration: the DB-backed legal-acceptance suite must not be skipped", () => {
  throw new Error("TENANT_INTEGRATION_TEST=1 but no usable non-production database URL (DATABASE_URL_POOLER missing, or it names the production project)");
});

describe.skipIf(!ENABLED)("migration 184 behaviour (rolled-back real rows)", () => {
  test("happy path: a confirmed code is consumed by a Yes; the row carries the intent's version, its event id and a database-computed checksum", async () => {
    await scenario(async (t, c) => {
      const ev = await verifiedIntent(t, c.userA, c.sessionA);
      const r = await record(t, web(c));
      expect(r).toMatchObject({ outcome: "recorded", choice: "accept", text_hash: H1 });
      const [row] = await rows(t, c.userA);
      expect(row.row_hash).toMatch(/^[0-9a-f]{64}$/);
      expect(row).toMatchObject({ method: "web-session", reauth_method: "email-code", surface: "web", session_id: c.sessionA, version: VERSION, event_id: ev });
      expect((await events(t, c.userA))[0].consumed_at).not.toBeNull();
      const [g] = await t`select current_setting('app.legal_acceptance_rpc', true) as v`;
      expect(g.v ?? "").not.toBe("on"); // the write door is shut again after the insert
      // Mutation 5: a second Yes on another text cannot reuse the consumed intent.
      await failsWith(t, /no live intent/, () => record(t, web(c), { hash: H2 }));
    });
  });

  test("Guard 3: UPDATE, DELETE and TRUNCATE are refused for every role, including the table owner", async () => {
    await scenario(async (t, c) => {
      await verifiedIntent(t, c.userA, c.sessionA);
      await record(t, web(c));
      await failsWith(t, /write-once/, () => t`update public.legal_acceptance set choice = 'decline' where founder_id = ${c.userA}`);
      await failsWith(t, /write-once/, () => t`update public.legal_acceptance set row_hash = ${hex("0")} where founder_id = ${c.userA}`);
      await failsWith(t, /write-once/, () => t`delete from public.legal_acceptance where founder_id = ${c.userA}`);
      await failsWith(t, /write-once/, () => t.unsafe("truncate public.legal_acceptance"));
      await failsWith(t, /permission denied|write-once/, () => as(t, "authenticated", { sub: c.userA }, () => t`delete from public.legal_acceptance`));
      await failsWith(t, /permission denied/, () => as(t, "service_role", null, () => t`update public.legal_acceptance set choice = 'decline'`));
      expect(await rows(t, c.userA)).toHaveLength(1);
    });
  });

  test("Guard 3: a direct INSERT is refused, and so is one with the write door open but no consumed intent", async () => {
    await scenario(async (t, c) => {
      await failsWith(t, /direct insert refused/, () =>
        t`insert into public.legal_acceptance (founder_id, key, text_hash, version, choice, session_id, event_id)
          values (${c.userA}, ${KEY}, ${H1}, ${VERSION}, 'decline', ${c.sessionA}, ${randomUUID()})`);
      await failsWith(t, /permission denied/, () =>
        as(t, "authenticated", { sub: c.userA }, () =>
          t`insert into public.legal_acceptance (founder_id, key, text_hash, version, choice, session_id, event_id)
            values (${c.userA}, ${KEY}, ${H1}, ${VERSION}, 'decline', ${c.sessionA}, ${randomUUID()})`));
      // The setting is not the only gate: even an owner session that opens the door needs a consumed intent for the same event.
      await t`select set_config('app.legal_acceptance_rpc', 'on', true)`;
      await failsWith(t, /no consumed intent/, () =>
        t`insert into public.legal_acceptance (founder_id, key, text_hash, version, choice, session_id, event_id)
          values (${c.userA}, ${KEY}, ${H1}, ${VERSION}, 'decline', ${c.sessionA}, ${randomUUID()})`);
      const ev = await intent(t, c.userA, c.sessionA); // an intent that was issued but NOT consumed
      await failsWith(t, /no consumed intent/, () =>
        t`insert into public.legal_acceptance (founder_id, key, text_hash, version, choice, session_id, event_id)
          values (${c.userA}, ${KEY}, ${H1}, ${VERSION}, 'decline', ${c.sessionA}, ${ev})`);
      await t`select set_config('app.legal_acceptance_rpc', 'off', true)`;
      expect(await rows(t, c.userA)).toHaveLength(0);
    });
  });

  // Guard 3 row 4: the checksum covers every column. Tamper one column at a time with the guard off and require the
  // verify function to fail closed. Using a fresh scenario per column keeps each case independent.
  for (const [col, expr] of [
    ["text_hash", `'${H2}'`],
    ["version", "'tampered'"],
    ["session_id", "'tampered'"],
    ["event_id", "gen_random_uuid()"],
    ["founder_id", "gen_random_uuid()"],
    ["id", "gen_random_uuid()"],
    ["created_at", "created_at + interval '1 second'"],
    ["choice", "'decline'"],
  ] as const) {
    test(`Guard 3 row 4: the checksum covers ${col} (a changed value reads as invalid, never accepted)`, async () => {
      await scenario(async (t, c) => {
        await verifiedIntent(t, c.userA, c.sessionA);
        await record(t, web(c));
        expect(await verifyFn(t, c.userA)).toMatchObject({ status: "accepted", row_ok: true });
        await t.unsafe("alter table public.legal_acceptance disable trigger legal_acceptance_guard");
        if (col === "choice") {
          // keep the CHECK constraints satisfied: a decline row carries no reauth columns
          await t.unsafe(`update public.legal_acceptance set choice = 'decline', reauth_method = null, reauth_at = null where founder_id = '${c.userA}'`);
        } else {
          await t.unsafe(`update public.legal_acceptance set ${col} = ${expr} where founder_id = '${c.userA}'`);
        }
        await t.unsafe("alter table public.legal_acceptance enable trigger legal_acceptance_guard");
        const [after] = await t`select founder_id, key, text_hash from public.legal_acceptance where founder_id = ${c.userA} or event_id is not null limit 1`;
        const v = await verifyFn(t, after.founder_id, after.text_hash);
        expect(v).toMatchObject({ status: "invalid", row_ok: false });
      });
    });
  }

  test("Guard 3 row 2: the read function cannot open the write door, refuses a user identity, and a missing decision reads none", async () => {
    await scenario(async (t, c) => {
      await failsWith(t, /service role only|permission denied/, () =>
        as(t, "authenticated", { sub: c.userA }, () => t`select public.verify_legal_acceptance(${c.userA}::uuid, ${KEY}::text, ${H1}::text)`));
      expect(await verifyFn(t, c.userA)).toMatchObject({ status: "none" });
      const [g] = await t`select current_setting('app.legal_acceptance_rpc', true) as v`;
      expect(g.v ?? "").not.toBe("on");
      await failsWith(t, /direct insert refused/, () =>
        t`insert into public.legal_acceptance (founder_id, key, text_hash, version, choice, session_id, event_id)
          values (${c.userA}, ${KEY}, ${H1}, ${VERSION}, 'decline', ${c.sessionA}, ${randomUUID()})`);
    });
  });

  test("Guard 3 row 3: the approval erasure scrub leaves the record, and no foreign key leaves it", async () => {
    await scenario(async (t, c) => {
      await verifiedIntent(t, c.userA, c.sessionA);
      await record(t, web(c));
      await as(t, "service_role", null, () => t`select public.anonymise_approval_request(${c.userA}::uuid)`);
      expect(await rows(t, c.userA)).toHaveLength(1);
      const [fk] = await t`select count(*)::int n from pg_constraint where conrelid = 'public.legal_acceptance'::regclass and contype = 'f'`;
      expect(fk.n).toBe(0); // no cascade from an account (or anything else) can reach the record
    });
  });

  test("EVERY decision needs a server-issued intent: a decision with none is refused and nothing is written", async () => {
    await scenario(async (t, c) => {
      for (const choice of ["accept", "decline"]) {
        await failsWith(t, /no live intent/, () => record(t, web(c), { choice }));
      }
      await failsWith(t, /no live intent/, () => record(t, web(c), { choice: "request_changes", edit: "shorter please" }));
      expect(await rows(t, c.userA)).toHaveLength(0);
      // An invented hash is not a pair the server ever issued: the live intent is bound to H1, so H2 is 'replaced' and nothing is consumed.
      const ev = await intent(t, c.userA, c.sessionA);
      expect((await record(t, web(c), { choice: "decline", hash: H2 })).outcome).toBe("replaced");
      expect((await events(t, c.userA)).find((e) => e.id === ev).consumed_at).toBeNull();
      expect(await rows(t, c.userA)).toHaveLength(0);
    });
  });

  test("Decline and Request changes need no code, consume their intent, and are recorded once (a second tab reads already_recorded)", async () => {
    await scenario(async (t, c) => {
      const ev = await intent(t, c.userA, c.sessionA);
      const d = await record(t, web(c), { choice: "decline" });
      expect(d.outcome).toBe("recorded");
      expect((await events(t, c.userA)).find((e) => e.id === ev).consumed_at).not.toBeNull();
      const [row] = await rows(t, c.userA);
      expect(row).toMatchObject({ choice: "decline", reauth_method: null, reauth_at: null, event_id: ev });
      expect((await record(t, web(c), { choice: "accept" })).outcome).toBe("already_recorded"); // same text, second tab
      await intent(t, c.userA, c.sessionA, { hash: H2 });
      await failsWith(t, /invalid input/, () => record(t, web(c), { choice: "request_changes", hash: H2 }));
      await failsWith(t, /invalid input/, () => record(t, web(c), { choice: "request_changes", hash: H2, edit: "   " }));
      await failsWith(t, /invalid input/, () => record(t, web(c), { choice: "request_changes", hash: H2, edit: "\t\n\r " }));
      await failsWith(t, /invalid input/, () => record(t, web(c), { choice: "decline", hash: H2, edit: "text with a decline" }));
      await failsWith(t, /invalid input/, () => record(t, web(c), { choice: "request_changes", hash: H2, edit: "x".repeat(1001) }));
      const rc = await record(t, web(c), { choice: "request_changes", hash: H2, edit: "Please shorten clause 4." });
      expect(rc.outcome).toBe("recorded");
      const [r2] = await t`select requested_edit from public.legal_acceptance where founder_id = ${c.userA} and text_hash = ${H2}`;
      expect(r2.requested_edit).toBe("Please shorten clause 4.");
    });
  });

  test("a Yes needs a confirmed code: none refuses, and a code confirmed more than 5 minutes ago is code_expired and consumes nothing", async () => {
    await scenario(async (t, c) => {
      const ev = await intent(t, c.userA, c.sessionA);
      await failsWith(t, /email code required/, () => record(t, web(c))); // intent issued, code never confirmed
      expect((await events(t, c.userA))[0].consumed_at).toBeNull();
      await claim(t, c.userA, c.sessionA);
      await markVerified(t, c.userA, ev, c.sessionA);
      await t`update public.legal_reauth_event set verified_at = now() - interval '6 minutes' where id = ${ev}`;
      expect((await record(t, web(c))).outcome).toBe("code_expired");
      expect((await events(t, c.userA))[0].consumed_at).toBeNull();
      await t`update public.legal_reauth_event set verified_at = now() - interval '4 minutes' where id = ${ev}`;
      expect((await record(t, web(c))).outcome).toBe("recorded"); // inside the 5-minute freshness window
    });
  });

  test("Guard 3 row 6: an intent bound to another user, key, session or text cannot back a decision", async () => {
    await scenario(async (t, c) => {
      await verifiedIntent(t, c.userA, c.sessionA);
      await failsWith(t, /no live intent/, () => record(t, web(c, c.userB, c.sessionA)));          // another user
      await failsWith(t, /no live intent/, () => record(t, web(c, c.userA, randomUUID())));       // another session
      await failsWith(t, /no live intent/, () => record(t, web(c), { key: "other-key" }));        // another key
      expect((await record(t, web(c), { hash: H2 })).outcome).toBe("replaced");                    // another text
      expect((await events(t, c.userA))[0].consumed_at).toBeNull();
      expect(await rows(t, c.userA)).toHaveLength(0);
    });
  });

  test("Guard 3 row 7: the actor is the verified web session; runtime and any non-web audience, a denied token, anon and service role are refused", async () => {
    await scenario(async (t, c) => {
      await verifiedIntent(t, c.userA, c.sessionA);
      await failsWith(t, /authenticated callers only|permission denied/, () => record(t, null, { role: "service_role" }));
      await failsWith(t, /permission denied/, () => as(t, "anon", null, () => t`select public.record_legal_acceptance(${KEY}::text, ${H1}::text, 'decline'::text, null::text)`));
      await failsWith(t, /web session token/, () => record(t, { ...web(c), aud: "soleur-runtime" }));
      await failsWith(t, /web session token/, () => record(t, { ...web(c), aud: "some-other-audience" }));
      await failsWith(t, /web session required/, () => record(t, { sub: c.userA })); // no session claim
      const jti = randomUUID();
      await t`insert into public.denied_jti (jti, founder_id, reason) values (${jti}, ${c.userA}, 'test')`;
      await failsWith(t, /token denied/, () => record(t, { ...web(c), jti }));
      expect(await rows(t, c.userA)).toHaveLength(0);
      expect((await events(t, c.userA))[0].consumed_at).toBeNull();
      // The session id may arrive as ses_id (the DSAR re-auth precedent reads both names).
      expect((await record(t, { sub: c.userA, ses_id: c.sessionA })).outcome).toBe("recorded");
    });
  });

  test("the founder reads only their own rows, and not through a runtime-audience token", async () => {
    await scenario(async (t, c) => {
      await verifiedIntent(t, c.userA, c.sessionA);
      await record(t, web(c));
      const seenByB = await as(t, "authenticated", { sub: c.userB }, () => t`select founder_id from public.legal_acceptance`);
      expect(seenByB.filter((r: any) => r.founder_id === c.userA)).toHaveLength(0);
      const seenByA = await as(t, "authenticated", web(c), () => t`select founder_id from public.legal_acceptance`);
      expect(seenByA.map((r: any) => r.founder_id)).toContain(c.userA);
      const seenByRuntime = await as(t, "authenticated", { ...web(c), aud: "soleur-runtime" }, () => t`select founder_id from public.legal_acceptance`);
      expect(seenByRuntime).toHaveLength(0);
    });
  });

  test("Must-PASS: a new text version of the same key is a new row, with its own version from its own intent", async () => {
    await scenario(async (t, c) => {
      await intent(t, c.userA, c.sessionA);
      await record(t, web(c), { choice: "decline" });
      await verifiedIntent(t, c.userA, c.sessionA, { hash: H2, version: "2026-12-01" });
      const r = await record(t, web(c), { hash: H2 });
      expect(r.outcome).toBe("recorded");
      const all = await rows(t, c.userA);
      expect(all).toHaveLength(2);
      expect(all.find((x: any) => x.text_hash === H2).version).toBe("2026-12-01");
    });
  });

  test("intent lifecycle: lives 30 minutes, reopening is free and returns the same intent, a resend voids the old one, 3 new intents per 15 minutes", async () => {
    await scenario(async (t, c) => {
      const first = await issue(t, c.userA, c.sessionA);
      expect(first).toMatchObject({ outcome: "issued", reused: false });
      const [ev0] = await events(t, c.userA);
      const lifetime = (new Date(ev0.expires_at).getTime() - new Date(ev0.created_at).getTime()) / 1000;
      expect(lifetime).toBeGreaterThan(29 * 60);
      expect(lifetime).toBeLessThan(31 * 60);
      for (let i = 0; i < 4; i++) expect(await issue(t, c.userA, c.sessionA)).toMatchObject({ outcome: "issued", reused: true, event_id: first.event_id });
      expect(await events(t, c.userA)).toHaveLength(1); // reopening a card inserted nothing and burned no cap
      const r2 = await issue(t, c.userA, c.sessionA, { resend: true });
      const r3 = await issue(t, c.userA, c.sessionA, { resend: true });
      expect(r2.reused).toBe(false);
      expect(r3.event_id).not.toBe(r2.event_id);
      const ev = await events(t, c.userA);
      expect(ev.filter((e: any) => e.superseded_at === null)).toHaveLength(1); // only the newest is live
      expect((await issue(t, c.userA, c.sessionA, { resend: true })).outcome).toBe("rate_limited"); // the 4th insert in the window
      // Back-date everything past the 15-minute window: a new intent is allowed again.
      await t`update public.legal_reauth_event set created_at = now() - interval '16 minutes' where user_id = ${c.userA}`;
      expect((await issue(t, c.userA, c.sessionA, { resend: true })).outcome).toBe("issued");
    });
  });

  test("code attempts: five are allowed, the sixth is locked, and a locked intent never becomes verified", async () => {
    await scenario(async (t, c) => {
      const ev = await intent(t, c.userA, c.sessionA);
      for (let i = 0; i < 5; i++) expect((await claim(t, c.userA, c.sessionA)).outcome).toBe("allowed");
      expect((await claim(t, c.userA, c.sessionA)).outcome).toBe("locked");
      await failsWith(t, /email code required/, () => record(t, web(c)));
      expect((await events(t, c.userA)).find((e) => e.id === ev).verified_at).toBeNull();
    });
  });

  test("expiry: an intent past its 30 minutes is not consumed (record says expired) and claim says expired", async () => {
    await scenario(async (t, c) => {
      const ev = await verifiedIntent(t, c.userA, c.sessionA);
      await t`update public.legal_reauth_event set expires_at = now() - interval '1 second' where id = ${ev}`;
      expect((await claim(t, c.userA, c.sessionA)).outcome).toBe("expired");
      expect((await record(t, web(c))).outcome).toBe("expired");
      expect((await events(t, c.userA))[0].consumed_at).toBeNull();
      // A fresh intent after the lapse works.
      await verifiedIntent(t, c.userA, c.sessionA, { hash: H2 });
      expect((await record(t, web(c), { hash: H2 })).outcome).toBe("recorded");
    });
  });

  test("mark_verified is bound to the event id claim returned: a resend between claim and mark cannot move the confirmation", async () => {
    await scenario(async (t, c) => {
      const e1 = await intent(t, c.userA, c.sessionA);
      expect(await claim(t, c.userA, c.sessionA)).toMatchObject({ outcome: "allowed", event_id: e1 });
      const e2 = (await issue(t, c.userA, c.sessionA, { resend: true })).event_id;
      expect((await markVerified(t, c.userA, e1, c.sessionA)).outcome).toBe("replaced"); // E1 was voided by the resend
      expect((await markVerified(t, c.userA, e2, c.sessionA)).outcome).toBe("not_claimed"); // E2 was never claimed
      expect((await events(t, c.userA)).every((e) => e.verified_at === null)).toBe(true);
      // Another user's or another session's event id is not found.
      expect((await markVerified(t, c.userB, e2, c.sessionA)).outcome).toBe("not_found");
      expect((await markVerified(t, c.userA, e2, randomUUID())).outcome).toBe("not_found");
    });
  });

  test("claim and mark refuse a NULL argument instead of skipping the 'replaced' branch", async () => {
    await scenario(async (t, c) => {
      const ev = await intent(t, c.userA, c.sessionA);
      await failsWith(t, /invalid input/, () =>
        as(t, "service_role", null, () => t`select public.claim_legal_reauth_attempt(${c.userA}::uuid, ${KEY}::text, null::text, ${c.sessionA}::text)`));
      await failsWith(t, /invalid input/, () =>
        as(t, "service_role", null, () => t`select public.mark_legal_reauth_verified(${c.userA}::uuid, ${ev}::uuid, ${KEY}::text, null::text, ${c.sessionA}::text)`));
    });
  });

  test("issue refuses when a decision exists, validates its inputs, and purges rows older than 30 days without touching live ones", async () => {
    await scenario(async (t, c) => {
      await intent(t, c.userB, randomUUID());
      await record(t, web(c, c.userB, (await events(t, c.userB))[0].session_id), { choice: "decline" });
      expect((await issue(t, c.userB, randomUUID())).outcome).toBe("already_recorded");
      await failsWith(t, /invalid input/, () => issue(t, c.userA, c.sessionA, { version: "" }));
      await failsWith(t, /invalid input/, () => issue(t, c.userA, c.sessionA, { hash: "nothex" }));
      // Purge: an old challenge of one founder disappears when anyone requests a challenge; a live one of another stays.
      const oldEv = await intent(t, c.userA, c.sessionA);
      await t`update public.legal_reauth_event set created_at = now() - interval '31 days' where id = ${oldEv}`;
      const liveSession = randomUUID();
      const liveEv = await intent(t, c.userA, liveSession, { key: "another-key" });
      await t`update public.legal_reauth_event set created_at = now() - interval '29 days' where id = ${liveEv}`;
      await issue(t, c.userB, randomUUID(), { key: "yet-another-key" });
      const left = (await events(t, c.userA)).map((e: any) => e.id);
      expect(left).not.toContain(oldEv);
      expect(left).toContain(liveEv);
    });
  });

  test("the service RPCs refuse a user identity and the event table is closed to every api role", async () => {
    await scenario(async (t, c) => {
      await failsWith(t, /service role only|permission denied/, () =>
        as(t, "authenticated", { sub: c.userA }, () => t`select public.issue_legal_reauth(${c.userA}::uuid, ${KEY}::text, ${H1}::text, ${VERSION}::text, 'x'::text, false)`));
      for (const role of ["anon", "authenticated", "service_role"] as const) {
        await failsWith(t, /permission denied/, () => as(t, role, role === "authenticated" ? { sub: c.userA } : null, () => t`select * from public.legal_reauth_event`));
      }
    });
  });

  test("AC4: the down file refuses while a decision row exists, and drops nothing", async () => {
    await scenario(async (t, c) => {
      await intent(t, c.userA, c.sessionA);
      await record(t, web(c), { choice: "decline" });
      const down = readFileSync(path.join(__dirname, "../../supabase/migrations/184_legal_acceptance.down.sql"), "utf8");
      await failsWith(t, /184 down refused/, () => t.unsafe(down));
      const [n] = await t`select count(*)::int n from public.legal_acceptance where founder_id = ${c.userA}`;
      expect(n.n).toBe(1);
    });
  });
});
