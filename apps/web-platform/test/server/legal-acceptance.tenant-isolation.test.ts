import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";
import { afterAll, beforeAll, beforeEach, describe, expect, test } from "vitest";
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
let sql2: postgres.Sql<{}>; // a SECOND connection, for the advisory-lock proof

beforeAll(() => {
  if (!ENABLED) return;
  sql = postgres(URL_ENV!, { ssl: { rejectUnauthorized: false }, max: 1, onnotice: () => {} });
  sql2 = postgres(URL_ENV!, { ssl: { rejectUnauthorized: false }, max: 1, onnotice: () => {} });
});
afterAll(async () => {
  if (sql) await sql.end();
  if (sql2) await sql2.end();
});
beforeEach(() => {
  expect.hasAssertions(); // a test that asserts nothing is a failure, not a pass
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

  test("Guard 3: the guard's own intent predicate binds user, key, text hash, version, session and (for a Yes) the confirmed time", async () => {
    await scenario(async (t, c) => {
      const ev = await intent(t, c.userA, c.sessionA);
      await record(t, web(c), { choice: "decline" }); // the intent is now consumed, and it carries NO confirmed code
      await t`select set_config('app.legal_acceptance_rpc', 'on', true)`;
      const attempt = (over: Partial<{ founder: string; key: string; hash: string; version: string; session: string; event: string; choice: string }>) => {
        const o = { founder: c.userB, key: KEY, hash: H2, version: VERSION, session: c.sessionA, event: ev, choice: "decline", ...over };
        return t`insert into public.legal_acceptance (founder_id, key, text_hash, version, choice, reauth_method, reauth_at, session_id, event_id)
          values (${o.founder}, ${o.key}, ${o.hash}, ${o.version}, ${o.choice}, ${o.choice === "accept" ? "email-code" : null}, ${o.choice === "accept" ? new Date() : null}, ${o.session}, ${o.event})`;
      };
      // Every row below differs from the consumed intent in exactly one attribute (the base row is for another user AND another hash,
      // so first make it match, then break one attribute at a time).
      const match = { founder: c.userA, hash: H1 };
      for (const over of [
        { founder: c.userB, hash: H1 }, // another user
        { founder: c.userA, hash: H2 }, // another text hash
        { ...match, key: "other-key" },
        { ...match, version: "other-version" },
        { ...match, session: "other-session" },
        { ...match, event: randomUUID() },
        { ...match, choice: "accept" }, // a Yes against an intent whose code was never confirmed
      ]) {
        await failsWith(t, /no consumed intent/, () => attempt(over));
      }
      await t`select set_config('app.legal_acceptance_rpc', 'off', true)`;
      expect(await rows(t, c.userB)).toHaveLength(0);
    });
  });

  // Guard 3 row 4: the checksum covers every column. Tamper ONE column at a time with the guard off and require the verify
  // function to fail closed on exactly the row that was changed (UPDATE ... RETURNING names it; a fresh scenario per case).
  type Kind = "yes" | "request_changes";
  const tamperCases: Array<[string, Kind, string, string?]> = [
    ["text_hash", "yes", `text_hash = '${H2}'`],
    ["version", "yes", "version = 'tampered'"],
    ["session_id", "yes", "session_id = 'tampered'"],
    ["event_id", "yes", "event_id = gen_random_uuid()"],
    ["founder_id", "yes", "founder_id = gen_random_uuid()"],
    ["id", "yes", "id = gen_random_uuid()"],
    ["created_at (one microsecond)", "yes", "created_at = created_at + interval '1 microsecond'"],
    ["reauth_at (one microsecond)", "yes", "reauth_at = reauth_at + interval '1 microsecond'"],
    ["requested_edit", "request_changes", "requested_edit = 'something else'"],
    ["choice (alone)", "request_changes", "choice = 'decline'", "alter table public.legal_acceptance drop constraint legal_acceptance_edit_only_with_request"],
  ];
  for (const [col, kind, setClause, pre] of tamperCases) {
    test(`Guard 3 row 4: the checksum covers ${col} (a changed value reads as invalid, never accepted)`, async () => {
      await scenario(async (t, c) => {
        if (kind === "yes") {
          await verifiedIntent(t, c.userA, c.sessionA);
          await record(t, web(c));
        } else {
          await intent(t, c.userA, c.sessionA);
          await record(t, web(c), { choice: "request_changes", edit: "Please shorten clause 4." });
        }
        const before = await verifyFn(t, c.userA);
        expect(before).toMatchObject({ row_ok: true });
        expect(before.status).toBe(kind === "yes" ? "accepted" : "changes_requested");
        await t.unsafe("alter table public.legal_acceptance disable trigger legal_acceptance_guard");
        if (pre) await t.unsafe(pre);
        const upd = await t.unsafe(`update public.legal_acceptance set ${setClause} where founder_id = '${c.userA}' returning founder_id, key, text_hash`);
        expect(upd).toHaveLength(1);
        await t.unsafe("alter table public.legal_acceptance enable trigger legal_acceptance_guard");
        const v = await verifyFn(t, upd[0].founder_id as string, upd[0].text_hash as string, upd[0].key as string);
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
      await failsWith(t, /web session token/, () => record(t, { ...web(c), aud: null as unknown as string })); // an ABSENT audience is not a web session
      await failsWith(t, /authenticated callers only/, () => record(t, { session_id: c.sessionA })); // authenticated role but no subject
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
      const seenWithNoAud = await as(t, "authenticated", { ...web(c), aud: null as unknown as string }, () => t`select founder_id from public.legal_acceptance`);
      expect(seenWithNoAud).toHaveLength(0); // the read is a whitelist of the web audience, not a blocklist of one other audience
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
      expect(Math.abs(lifetime - 30 * 60)).toBeLessThan(5); // 30 minutes, not 31 and not 29
      for (let i = 0; i < 4; i++) expect(await issue(t, c.userA, c.sessionA)).toMatchObject({ outcome: "issued", reused: true, event_id: first.event_id });
      expect(await events(t, c.userA)).toHaveLength(1); // reopening a card inserted nothing and burned no cap
      const r2 = await issue(t, c.userA, c.sessionA, { resend: true });
      const r3 = await issue(t, c.userA, c.sessionA, { resend: true });
      expect(r2.reused).toBe(false);
      expect(r3.event_id).not.toBe(r2.event_id);
      const ev = await events(t, c.userA);
      expect(ev.filter((e: any) => e.superseded_at === null)).toHaveLength(1); // only the newest is live
      expect((await issue(t, c.userA, c.sessionA, { resend: true })).outcome).toBe("rate_limited"); // the 4th insert in the window
      // 8 minutes later the three still count (the window is 15 minutes, not 1)...
      await t`update public.legal_reauth_event set created_at = now() - interval '8 minutes' where user_id = ${c.userA}`;
      expect((await issue(t, c.userA, c.sessionA, { resend: true })).outcome).toBe("rate_limited");
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

  test("the 30-day purge runs even when the call ends in an early return (a founder who already decided)", async () => {
    await scenario(async (t, c) => {
      await intent(t, c.userB, c.sessionA);
      await record(t, web(c, c.userB), { choice: "decline" });
      const oldEv = await intent(t, c.userA, randomUUID());
      await t`update public.legal_reauth_event set created_at = now() - interval '31 days' where id = ${oldEv}`;
      expect((await issue(t, c.userB, c.sessionA)).outcome).toBe("already_recorded"); // early return
      expect((await events(t, c.userA)).map((e: any) => e.id)).not.toContain(oldEv);
    });
  });

  test("a confirmed code that went stale is its own outcome, burns no attempt, and reopening the card opens a NEW intent (the founder can confirm again)", async () => {
    await scenario(async (t, c) => {
      const ev = await verifiedIntent(t, c.userA, c.sessionA);
      await t`update public.legal_reauth_event set verified_at = now() - interval '6 minutes' where id = ${ev}`;
      const attemptsBefore = (await events(t, c.userA))[0].attempts;
      expect((await claim(t, c.userA, c.sessionA)).outcome).toBe("code_stale");
      expect((await events(t, c.userA))[0].attempts).toBe(attemptsBefore); // nothing burned
      expect((await record(t, web(c))).outcome).toBe("code_expired");
      const reopened = await issue(t, c.userA, c.sessionA);
      expect(reopened).toMatchObject({ outcome: "issued", reused: false });
      expect(reopened.event_id).not.toBe(ev);
      expect((await events(t, c.userA)).find((e: any) => e.id === ev).superseded_at).not.toBeNull();
      const cl = await claim(t, c.userA, c.sessionA);
      expect(cl.outcome).toBe("allowed");
      await markVerified(t, c.userA, cl.event_id, c.sessionA);
      expect((await record(t, web(c))).outcome).toBe("recorded");
    });
  });

  test("a reused intent must carry the same version (a relabelled text opens a new intent, so the record never keeps a stale label)", async () => {
    await scenario(async (t, c) => {
      const first = await issue(t, c.userA, c.sessionA, { version: "2026-11-01" });
      const second = await issue(t, c.userA, c.sessionA, { version: "2026-11-02" });
      expect(second).toMatchObject({ outcome: "issued", reused: false });
      expect(second.event_id).not.toBe(first.event_id);
      await record(t, web(c), { choice: "decline" });
      expect((await rows(t, c.userA))[0].version).toBe("2026-11-02");
    });
  });

  test("two tabs are serialised: the decision and the issue hold their advisory locks until the transaction ends (proved from a second connection)", async () => {
    await scenario(async (t, c) => {
      await intent(t, c.userA, c.sessionA);
      // issue_legal_reauth holds the (user,key) lock for the rest of this transaction.
      const [free1] = await sql2`select pg_try_advisory_xact_lock(hashtextextended(${c.userA + ":" + KEY}, 0)) as got`;
      expect(free1.got).toBe(false);
      await record(t, web(c), { choice: "decline" });
      // record_legal_acceptance holds the (user,key,hash) lock too.
      const [free2] = await sql2`select pg_try_advisory_xact_lock(hashtextextended(${c.userA + ":" + KEY + ":" + H1}, 0)) as got`;
      expect(free2.got).toBe(false);
      // A control: a key nobody locked is free, so a false above is the function's lock and not a broken probe.
      const [control] = await sql2`select pg_try_advisory_xact_lock(hashtextextended(${randomUUID()}, 0)) as got`;
      expect(control.got).toBe(true);
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

// ---------------------------------------------------------------------------------------------------------------
// Migration 185 (#12011 PR-D, ADR-319): the acknowledgement table and its two service-role RPCs (Guard 3).
// ---------------------------------------------------------------------------------------------------------------
const ackFn = (t: Txn, user: string, hash = H1, key = KEY) =>
  as(t, "service_role", null, async () => {
    const [r] = await t<{ r: any }[]>`select public.ack_legal_acceptance(${user}::uuid, ${key}::text, ${hash}::text) as r`;
    return r.r;
  });
const ackState = (t: Txn, user: string, hash = H1, key = KEY) =>
  as(t, "service_role", null, async () => {
    const [r] = await t<{ r: any }[]>`select public.legal_acceptance_ack_state(${user}::uuid, ${key}::text, ${hash}::text) as r`;
    return r.r;
  });
const ackRows = async (t: Txn) => (await t`select * from public.legal_acceptance_ack`) as any[];

describe.skipIf(!ENABLED)("migration 185 behaviour (rolled-back real rows)", () => {
  test("no decision row: ack answers not_found and writes nothing; ack_state answers none", async () => {
    await scenario(async (t, c) => {
      expect(await ackState(t, c.userA)).toEqual({ outcome: "none" });
      expect(await ackFn(t, c.userA)).toEqual({ outcome: "not_found" });
      expect(await ackRows(t)).toHaveLength(0);
    });
  });

  test("a decision row starts unacked with a database-computed age; ack marks it once and is idempotent (first time kept)", async () => {
    await scenario(async (t, c) => {
      await verifiedIntent(t, c.userA, c.sessionA);
      await record(t, web(c));
      const before = await ackState(t, c.userA);
      expect(before).toMatchObject({ outcome: "row", acked: false });
      expect(Number.isInteger(before.age_seconds)).toBe(true);
      expect(before.age_seconds).toBeGreaterThanOrEqual(0);

      expect(await ackFn(t, c.userA)).toEqual({ outcome: "acked" });
      const first = (await ackRows(t))[0];
      expect(await ackState(t, c.userA)).toMatchObject({ outcome: "row", acked: true });
      expect(await ackFn(t, c.userA)).toEqual({ outcome: "acked" });
      const after = await ackRows(t);
      expect(after).toHaveLength(1);
      expect(after[0].acked_at).toEqual(first.acked_at); // ON CONFLICT DO NOTHING keeps the first time
    });
  });

  test("age is computed in the database from the decision row's own time", async () => {
    await scenario(async (t, c) => {
      await verifiedIntent(t, c.userA, c.sessionA);
      await record(t, web(c));
      // The write-once trigger forbids touching the row, so age the clock by comparing against a later statement time.
      await t`select pg_sleep(1.2)`;
      const s = await ackState(t, c.userA);
      // Inside one transaction now() is frozen at the transaction start, so the age is 0 here; the integer type and
      // the floor-at-zero are what this asserts. A cross-transaction age is covered by the verify sentinel in CI.
      expect(s.age_seconds).toBe(0);
    });
  });

  test("the ack carries the acceptance id and a time only, and is bound to the founder's own row (another founder's ack does not mark it)", async () => {
    await scenario(async (t, c) => {
      await verifiedIntent(t, c.userA, c.sessionA);
      await record(t, web(c));
      expect(await ackFn(t, c.userB)).toEqual({ outcome: "not_found" });
      expect(await ackState(t, c.userA)).toMatchObject({ acked: false });
      await ackFn(t, c.userA);
      const [acc] = await rows(t, c.userA);
      const acks = await ackRows(t);
      expect(Object.keys(acks[0]).sort()).toEqual(["acceptance_id", "acked_at"]);
      expect(acks[0].acceptance_id).toBe(acc.id);
      // A different text hash of the same founder and key is a different row: still unacked / absent.
      expect(await ackState(t, c.userA, H2)).toEqual({ outcome: "none" });
    });
  });

  test("Guard 3 row 8: neither function opens the write door of legal_acceptance, and the record stays write-once", async () => {
    await scenario(async (t, c) => {
      await verifiedIntent(t, c.userA, c.sessionA);
      await record(t, web(c));
      await ackFn(t, c.userA);
      await ackState(t, c.userA);
      const [g] = await t`select current_setting('app.legal_acceptance_rpc', true) as v`;
      expect(g.v ?? "").not.toBe("on");
      await failsWith(t, /write-once/, () => t`update public.legal_acceptance set choice = 'decline' where founder_id = ${c.userA}`);
    });
  });

  test("Guard 3 row 7: the ack table has no founder id, no foreign key, RLS on, and no api role can touch it", async () => {
    await scenario(async (t, c) => {
      const cols = await t`select column_name from information_schema.columns where table_schema = 'public' and table_name = 'legal_acceptance_ack' order by ordinal_position`;
      expect(cols.map((r: any) => r.column_name)).toEqual(["acceptance_id", "acked_at"]);
      const [fk] = await t`select count(*)::int n from pg_constraint where conrelid = 'public.legal_acceptance_ack'::regclass and contype = 'f'`;
      expect(fk.n).toBe(0);
      const [rls] = await t`select relrowsecurity r from pg_class where oid = 'public.legal_acceptance_ack'::regclass`;
      expect(rls.r).toBe(true);
      for (const role of ["anon", "authenticated", "service_role"] as const) {
        await failsWith(t, /permission denied/, () => as(t, role, role === "authenticated" ? { sub: c.userA } : null, () => t`select * from public.legal_acceptance_ack`));
        await failsWith(t, /permission denied/, () => as(t, role, role === "authenticated" ? { sub: c.userA } : null, () => t`insert into public.legal_acceptance_ack (acceptance_id) values (${randomUUID()})`));
      }
    });
  });

  test("both functions refuse a user identity (42501), raise 22023 on a malformed key or hash, and EXECUTE is service_role only", async () => {
    await scenario(async (t, c) => {
      await verifiedIntent(t, c.userA, c.sessionA);
      await record(t, web(c));
      for (const fn of ["ack_legal_acceptance", "legal_acceptance_ack_state"]) {
        await failsWith(t, /42501|service role only/, () =>
          as(t, "authenticated", { sub: c.userA }, () => t.unsafe(`select public.${fn}($1::uuid, $2::text, $3::text)`, [c.userA, KEY, H1])));
        await failsWith(t, /permission denied/, () => as(t, "anon", null, () => t.unsafe(`select public.${fn}($1::uuid, $2::text, $3::text)`, [c.userA, KEY, H1])));
        for (const [k, h] of [["Bad Key", H1], [KEY, "xyz"], [KEY, H1.toUpperCase()], ["", H1]] as const) {
          await failsWith(t, /22023|invalid input/, () =>
            as(t, "service_role", null, () => t.unsafe(`select public.${fn}($1::uuid, $2::text, $3::text)`, [c.userA, k, h])));
        }
        await failsWith(t, /22023|invalid input/, () =>
          as(t, "service_role", null, () => t.unsafe(`select public.${fn}(null::uuid, $1::text, $2::text)`, [KEY, H1])));
      }
      expect(await ackRows(t)).toHaveLength(0);
    });
  });

  test("AC6: the 185 down file refuses while an acknowledgement exists, and drops nothing", async () => {
    await scenario(async (t, c) => {
      await verifiedIntent(t, c.userA, c.sessionA);
      await record(t, web(c));
      await ackFn(t, c.userA);
      const down = readFileSync(path.join(__dirname, "../../supabase/migrations/185_legal_acceptance_ack.down.sql"), "utf8");
      await failsWith(t, /185 down refused/, () => t.unsafe(down));
      expect(await ackRows(t)).toHaveLength(1);
    });
  });

  test("AC6: the 185 verify sentinel reports bad = 0 on the live catalog", async () => {
    await scenario(async (t) => {
      const verify = readFileSync(path.join(__dirname, "../../supabase/verify/185_legal_acceptance_ack.sql"), "utf8");
      const out = (await t.unsafe(verify)) as any[];
      expect(out.length).toBeGreaterThan(20);
      expect(out.filter((r) => Number(r.bad) !== 0).map((r) => r.check_name)).toEqual([]);
    });
  });
});
