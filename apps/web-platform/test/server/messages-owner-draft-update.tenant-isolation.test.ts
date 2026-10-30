import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import postgres from "postgres";

// Behavioural proof of migration 181 against a REAL database (#11569): the author-only, draft-only, column-narrowed
// UPDATE path on public.messages that Discard, Edit and the send-route archive depend on. Every scenario runs in its
// own transaction that is ROLLED BACK, so nothing persists.
//
// Every denial is preceded by a positive control in the same scenario (a deny cannot pass for the wrong reason), uses
// type-valid payloads, and is followed by a re-read of the row as the table owner. The two denial layers are told apart
// by MESSAGE, not code (both raise 42501): the column privilege says "permission denied for table messages", the
// WITH CHECK says "new row violates row-level security policy".
//
// Collected by tenant-integration.yml (path matches test/server/*.tenant-isolation.test.ts). Gate: APPROVAL_DB_URL
// (a local stack or DEV, session-mode :5432), OR TENANT_INTEGRATION_TEST=1 plus DATABASE_URL_POOLER (:6543 rewritten to
// :5432: the transaction-mode pooler cannot hold SET LOCAL role/claims across statements). It REFUSES the production
// project ref (hr-dev-prd-distinct-supabase-projects). Synthetic data only (cq-test-fixtures-synthesized-only).
//
//   doppler run -p soleur -c dev -- bash -c 'APPROVAL_DB_URL="${DATABASE_URL_POOLER/:6543/:5432}" \
//     ./node_modules/.bin/vitest run test/server/messages-owner-draft-update.tenant-isolation.test.ts'

const URL_ENV =
  process.env.APPROVAL_DB_URL ??
  (process.env.TENANT_INTEGRATION_TEST === "1" && process.env.DATABASE_URL_POOLER
    ? process.env.DATABASE_URL_POOLER.replace(":6543", ":5432")
    : undefined);
const PRD_REF = "ifsccnjhymdmidffkzhl";
const ENABLED = Boolean(URL_ENV) && !URL_ENV!.includes(PRD_REF);

const COLUMN_DENIED = /permission denied for table messages/;
const WITH_CHECK_DENIED = /new row violates row-level security policy/;

type Txn = postgres.TransactionSql<{}>;
interface Ctx {
  userA: string; // wsA owner and the draft author
  userB: string; // other tenant owner (wsB)
  userC: string; // wsA plain member, not the author
  wsA: string;
  wsB: string;
  convA: string;
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
      const c = await seed(t);
      await fn(t, c);
      return Promise.reject(ROLLBACK);
    });
  } catch (e) {
    if (e !== ROLLBACK) throw e;
  }
}

async function seed(t: Txn): Promise<Ctx> {
  const [userA, userB, userC] = [1, 2, 3].map(() => randomUUID());
  for (const [n, u] of Object.entries({ a: userA, b: userB, c: userC })) {
    await t`insert into auth.users (id, email) values (${u}, ${`${n}-${u}@example.test`})`;
  }
  const [a] = await t`select workspace_id from workspace_members where user_id = ${userA} limit 1`;
  const [b] = await t`select workspace_id from workspace_members where user_id = ${userB} limit 1`;
  const wsA = a.workspace_id as string;
  const wsB = b.workspace_id as string;
  await t`insert into workspace_members (workspace_id, user_id, role) values (${wsA}, ${userC}, 'member')`;
  const convA = randomUUID();
  await t`insert into conversations (id, user_id, workspace_id, status, visibility)
    values (${convA}, ${userA}, ${wsA}, 'active', 'workspace')`;
  return { userA, userB, userC, wsA, wsB, convA };
}

/** Run fn as a database role with request claims; always back to the owner role afterwards. */
async function as<T>(t: Txn, role: "authenticated" | "anon", sub: string | null, fn: () => Promise<T>): Promise<T> {
  await t.unsafe(`set local role ${role}`);
  const claims = JSON.stringify(sub ? { sub, role } : { role });
  await t`select set_config('request.jwt.claims', ${claims}, true)`;
  try {
    return await fn();
  } finally {
    // After a failed statement the transaction is aborted and RESET fails; the enclosing savepoint rollback restores the role.
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
  expect(m.code).toBe("42501");
  expect(`${m.code ?? ""} ${m.message ?? ""}`).toMatch(pattern);
}

/** A draft card row (conversation_id null, source/owning_domain/draft_preview set), inserted as the table owner. */
async function draft(
  t: Txn,
  over: { ws: string; user: string; status?: string; tier?: string | null; body?: string },
): Promise<string> {
  const [r] = await t`insert into public.messages
    (workspace_id, template_id, user_id, status, source, owning_domain, draft_preview, tier)
    values (${over.ws}, 'work', ${over.user}, ${over.status ?? "draft"}, 'rls-test', 'engineering',
            ${over.body ?? "draft body"}, ${over.tier === undefined ? "external_low_stakes" : over.tier})
    returning id`;
  return r.id as string;
}

/** A plain chat row (conversation_id, role, content set), status complete, inserted as the table owner. */
async function chat(t: Txn, c: Ctx): Promise<string> {
  const [r] = await t`insert into public.messages (workspace_id, template_id, user_id, conversation_id, role, content)
    values (${c.wsA}, 'work', ${c.userA}, ${c.convA}, 'user', 'chat body') returning id`;
  return r.id as string;
}

const row = async (t: Txn, id: string) => (await t`select * from public.messages where id = ${id}`)[0] as any;

/** UPDATE ... RETURNING id as `sub`; the row count is the observable (RLS-hidden rows are zero rows, not errors). */
const updateAs = (t: Txn, sub: string, id: string, setSql: string, role: "authenticated" | "anon" = "authenticated") =>
  as(t, role, sub, async () => t.unsafe(`update public.messages set ${setSql} where id = '${id}' returning id`));

describe.skipIf(!ENABLED)("migration 181 behaviour (rolled-back real rows)", () => {
  test("author discards a draft and edits another draft's body: one row each", async () => {
    await scenario(async (t, c) => {
      const d1 = await draft(t, { ws: c.wsA, user: c.userA });
      const d2 = await draft(t, { ws: c.wsA, user: c.userA });
      expect(await updateAs(t, c.userA, d1, "status = 'archived'")).toHaveLength(1);
      expect((await row(t, d1)).status).toBe("archived");
      expect(await updateAs(t, c.userA, d2, "draft_preview = 'edited body'")).toHaveLength(1);
      expect((await row(t, d2)).draft_preview).toBe("edited body");
      expect((await row(t, d2)).status).toBe("draft");
    });
  });

  test("a second author in the same workspace updates their own draft (the policy is not pinned to one fixture user)", async () => {
    await scenario(async (t, c) => {
      const dC = await draft(t, { ws: c.wsA, user: c.userC });
      expect(await updateAs(t, c.userC, dC, "status = 'archived'")).toHaveLength(1);
      expect((await row(t, dC)).status).toBe("archived");
    });
  });

  test("a workspace member who is not the author updates zero rows and the row is unchanged", async () => {
    await scenario(async (t, c) => {
      const own = await draft(t, { ws: c.wsA, user: c.userA });
      const other = await draft(t, { ws: c.wsA, user: c.userA });
      expect(await updateAs(t, c.userA, own, "status = 'archived'")).toHaveLength(1); // positive control
      expect(await updateAs(t, c.userC, other, "status = 'archived'")).toHaveLength(0);
      expect(await updateAs(t, c.userC, other, "draft_preview = 'hijacked'")).toHaveLength(0);
      const r = await row(t, other);
      expect(r.status).toBe("draft");
      expect(r.draft_preview).toBe("draft body");
    });
  });

  test("a member of another workspace updates zero rows and the row is unchanged", async () => {
    await scenario(async (t, c) => {
      const own = await draft(t, { ws: c.wsA, user: c.userA });
      const target = await draft(t, { ws: c.wsA, user: c.userA });
      expect(await updateAs(t, c.userA, own, "draft_preview = 'mine'")).toHaveLength(1); // positive control
      expect(await updateAs(t, c.userB, target, "status = 'archived'")).toHaveLength(0);
      expect(await updateAs(t, c.userB, target, "draft_preview = 'hijacked'")).toHaveLength(0);
      const r = await row(t, target);
      expect(r.status).toBe("draft");
      expect(r.draft_preview).toBe("draft body");
    });
  });

  test("an already archived draft updates zero rows (USING status = draft)", async () => {
    await scenario(async (t, c) => {
      const live = await draft(t, { ws: c.wsA, user: c.userA });
      const archived = await draft(t, { ws: c.wsA, user: c.userA, status: "archived" });
      expect(await updateAs(t, c.userA, live, "draft_preview = 'ok'")).toHaveLength(1); // positive control
      expect(await updateAs(t, c.userA, archived, "draft_preview = 'edited'")).toHaveLength(0);
      expect(await updateAs(t, c.userA, archived, "status = 'draft'")).toHaveLength(0);
      const r = await row(t, archived);
      expect(r.status).toBe("archived");
      expect(r.draft_preview).toBe("draft body");
    });
  });

  test("the author cannot flip a draft to complete (WITH CHECK), and the row is unchanged", async () => {
    await scenario(async (t, c) => {
      // tier null: an external tier would trip messages_external_tier_status_check, which could mask the RLS layer.
      const d = await draft(t, { ws: c.wsA, user: c.userA, tier: null });
      expect(await updateAs(t, c.userA, d, "status = 'archived'")).toHaveLength(1); // positive control
      const d2 = await draft(t, { ws: c.wsA, user: c.userA, tier: null });
      await failsWith(t, WITH_CHECK_DENIED, () => updateAs(t, c.userA, d2, "status = 'complete'"));
      await failsWith(t, WITH_CHECK_DENIED, () => updateAs(t, c.userA, d2, "status = 'aborted'"));
      expect((await row(t, d2)).status).toBe("draft");
    });
  });

  test("the author cannot rewrite any column outside status and draft_preview (column privilege), row unchanged", async () => {
    await scenario(async (t, c) => {
      const d = await draft(t, { ws: c.wsA, user: c.userA });
      expect(await updateAs(t, c.userA, d, "draft_preview = 'control'")).toHaveLength(1); // positive control
      const before = await row(t, d);
      const attacks: Array<[string, string]> = [
        ["content", "content = 'rewritten'"],
        ["role", "role = 'assistant'"],
        ["user_id", `user_id = '${c.userC}'`],
        ["workspace_id", `workspace_id = '${c.wsB}'`],
        ["trust_tier", "trust_tier = 'auto'"],
        ["action_class", "action_class = 'general.rewritten'"],
        ["template_id", "template_id = 'rewritten'"],
      ];
      for (const [col, setSql] of attacks) {
        await failsWith(t, COLUMN_DENIED, () => updateAs(t, c.userA, d, setSql));
        const after = await row(t, d);
        expect(after[col], `${col} must be unchanged`).toEqual(before[col]);
      }
    });
  });

  test("a complete chat row owned by the caller: status update is zero rows, content update is denied", async () => {
    await scenario(async (t, c) => {
      const d = await draft(t, { ws: c.wsA, user: c.userA });
      expect(await updateAs(t, c.userA, d, "status = 'archived'")).toHaveLength(1); // positive control
      const m = await chat(t, c);
      expect(await updateAs(t, c.userA, m, "status = 'archived'")).toHaveLength(0);
      await failsWith(t, COLUMN_DENIED, () => updateAs(t, c.userA, m, "content = 'rewritten'"));
      const r = await row(t, m);
      expect(r.status).toBe("complete");
      expect(r.content).toBe("chat body");
    });
  });

  test("anon cannot UPDATE (table-level grant revoked)", async () => {
    await scenario(async (t, c) => {
      const d = await draft(t, { ws: c.wsA, user: c.userA });
      expect(await updateAs(t, c.userA, d, "draft_preview = 'control'")).toHaveLength(1); // positive control
      await failsWith(t, COLUMN_DENIED, () => updateAs(t, "", d, "status = 'archived'", "anon"));
      expect((await row(t, d)).status).toBe("draft");
    });
  });

  test("catalog: no table-level UPDATE; authenticated holds UPDATE on exactly status and draft_preview", async () => {
    await scenario(async (t) => {
      const [p] = await t`select
        has_table_privilege('authenticated', 'public.messages', 'UPDATE') as auth_table,
        has_table_privilege('anon', 'public.messages', 'UPDATE') as anon_table`;
      expect(p.auth_table).toBe(false);
      expect(p.anon_table).toBe(false);
      const cols = await t`select a.attname,
          has_column_privilege('authenticated', a.attrelid, a.attname, 'UPDATE') as auth_upd,
          has_column_privilege('anon', a.attrelid, a.attname, 'UPDATE') as anon_upd
        from pg_attribute a
        where a.attrelid = 'public.messages'::regclass and a.attnum > 0 and not a.attisdropped`;
      const granted = cols.filter((x) => x.auth_upd).map((x) => x.attname).sort();
      expect(granted).toEqual(["draft_preview", "status"]);
      expect(cols.filter((x) => x.anon_upd)).toEqual([]);
    });
  });
});
