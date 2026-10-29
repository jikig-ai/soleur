import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import postgres from "postgres";

// Behavioural proof of migration 180 against a REAL database (#4672): the consume predicate (incl. the principal
// re-check), the status machine, decide_approval (owner / expiry / closed conversation / two-Owner race / REVOKE),
// the pending caps and notify coalescing, the write-once trigger with its Art. 17 carve-outs, the Art. 17 DELETE of a
// memberless personal workspace's rows, the sweep, RLS and the grant matrix. Every scenario runs in its own
// transaction that is ROLLED BACK, so nothing persists; every row is a real row written through the real RPCs and
// triggers.
//
// Collected by tenant-integration.yml (path matches test/server/*.tenant-isolation.test.ts), which applies this PR's
// migrations to DEV and runs `test/server/` with TENANT_INTEGRATION_TEST=1 inside `doppler run -c dev_scheduled`.
// Gate: APPROVAL_DB_URL (a local supabase stack or DEV, session-mode :5432), OR TENANT_INTEGRATION_TEST=1 plus
// DATABASE_URL_POOLER (:6543 rewritten to :5432: the transaction-mode pooler cannot hold SET LOCAL role/claims across
// statements). It REFUSES the production project ref (hr-dev-prd-distinct-supabase-projects). Synthetic data only
// (cq-test-fixtures-synthesized-only): fresh random UUIDs, example.test addresses.
//
//   doppler run -p soleur -c dev -- bash -c 'APPROVAL_DB_URL="${DATABASE_URL_POOLER/:6543/:5432}" \
//     ./node_modules/.bin/vitest run test/server/approval-request.tenant-isolation.test.ts'

const URL_ENV =
  process.env.APPROVAL_DB_URL ??
  (process.env.TENANT_INTEGRATION_TEST === "1" && process.env.DATABASE_URL_POOLER
    ? process.env.DATABASE_URL_POOLER.replace(":6543", ":5432")
    : undefined);
const PRD_REF = "ifsccnjhymdmidffkzhl";
const ENABLED = Boolean(URL_ENV) && !URL_ENV!.includes(PRD_REF);

const TOOL = "mcp__soleur_platform__email_send";
const CANON = { v: 1, tool: TOOL, fields: { to: "maria@example.test", subject: "s", body: "b", jurisdiction: "unknown" } };
const hex = (c: string) => c.repeat(64);
const H1 = hex("a");
const H2 = hex("b");

type Txn = postgres.TransactionSql<{}>;
interface Ctx {
  userA: string; // wsA owner
  userB: string; // other tenant owner
  userC: string; // wsA plain member
  userD: string; // wsA member (requester that gets erased)
  userE: string; // wsA second owner
  wsA: string;
  wsB: string;
  convA: string;
  convA2: string;
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
  const [userA, userB, userC, userD, userE] = [1, 2, 3, 4, 5].map(() => randomUUID());
  for (const [n, u] of Object.entries({ a: userA, b: userB, c: userC, d: userD, e: userE })) {
    await t`insert into auth.users (id, email) values (${u}, ${`${n}-${u}@example.test`})`;
  }
  const [a] = await t`select workspace_id from workspace_members where user_id = ${userA} limit 1`;
  const [b] = await t`select workspace_id from workspace_members where user_id = ${userB} limit 1`;
  const wsA = a.workspace_id as string;
  const wsB = b.workspace_id as string;
  await t`insert into workspace_members (workspace_id, user_id, role) values
    (${wsA}, ${userC}, 'member'), (${wsA}, ${userD}, 'member'), (${wsA}, ${userE}, 'owner')`;
  const convA = randomUUID();
  const convA2 = randomUUID();
  await t`insert into conversations (id, user_id, workspace_id, status, visibility) values
    (${convA}, ${userA}, ${wsA}, 'active', 'workspace'), (${convA2}, ${userA}, ${wsA}, 'active', 'workspace')`;
  return { userA, userB, userC, userD, userE, wsA, wsB, convA, convA2 };
}

/** Run fn as a database role with request claims; always back to the owner role afterwards. */
async function as<T>(t: Txn, role: "service_role" | "authenticated" | "anon", sub: string | null, fn: () => Promise<T>): Promise<T> {
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
  expect(`${m.code ?? ""} ${m.message ?? ""}`).toMatch(pattern);
}

const create = async (t: Txn, c: Ctx, over: { hash?: string; conv?: string; ttl?: number; ws?: string; user?: string } = {}) =>
  as(t, "service_role", null, async () => {
    const [r] = await t<{ r: any }[]>`select public.create_approval_request(
      ${over.ws ?? c.wsA}::uuid, ${over.conv ?? c.convA}::uuid, ${over.user ?? c.userA}::uuid, ${TOOL}::text,
      ${over.hash ?? H1}::text, ${t.json(CANON as never)}::jsonb, ${over.ttl ?? 86400}::int) as r`;
    return r.r;
  });

const decide = async (t: Txn, who: string, id: string, decision: string) =>
  as(t, "authenticated", who, async () => {
    const [r] = await t<{ r: any }[]>`select public.decide_approval(${id}::uuid, ${decision}::text) as r`;
    return r.r;
  });

const consume = async (t: Txn, id: string, hash: string, conv: string) =>
  as(t, "service_role", null, async () => {
    const [r] = await t<{ r: any }[]>`select public.consume_approval(${id}::uuid, ${hash}::text, ${conv}::uuid) as r`;
    return r.r;
  });

/** Time-forge a row (owner role, trigger disabled for one statement) to make it overdue / old without waiting. */
async function forge(t: Txn, id: string, setClause: string) {
  await t.unsafe("alter table public.approval_request disable trigger approval_request_guard");
  await t.unsafe(`update public.approval_request set ${setClause} where id = '${id}'`);
  await t.unsafe("alter table public.approval_request enable trigger approval_request_guard");
}

/** The RPC GUC is transaction-local and an earlier RPC in this scenario transaction set it: turn it off to act as a direct writer. */
const directWriter = (t: Txn) => t`select set_config('app.approval_rpc', 'off', true), set_config('app.approval_scrub', 'off', true)`;

const row = async (t: Txn, id: string) => (await t`select * from public.approval_request where id = ${id}`)[0] as any;
const inbox = async (t: Txn, id: string) =>
  (await t`select severity, source, acted_at, title, source_ref from public.inbox_item where dedup_key = ${id}`)[0] as any;

describe.skipIf(!ENABLED)("migration 180 behaviour (rolled-back real rows)", () => {
  test("create: pending row, content-free inbox item, request count, idempotent on the live (conversation, hash)", async () => {
    await scenario(async (t, c) => {
      const r1 = await create(t, c);
      expect(r1.created).toBe(true);
      expect(r1.request_count).toBe(1);
      expect(r1.approval.status).toBe("pending");
      expect(r1.approval.action_sha256).toBe(H1);
      const ib = await inbox(t, r1.approval.id);
      expect(ib).toMatchObject({ severity: "action_required", source: "approval_required", acted_at: null });
      expect(ib.title).toBe("An action needs your approval");
      expect(JSON.stringify(ib.source_ref)).not.toContain("example.test");
      const r2 = await create(t, c);
      expect(r2.created).toBe(false);
      expect(r2.approval.id).toBe(r1.approval.id);
      expect((await t`select count(*)::int n from public.inbox_item where dedup_key = ${r1.approval.id}`)[0].n).toBe(1);
      const other = await create(t, c, { hash: H2 });
      expect(other.approval.id).not.toBe(r1.approval.id);
    });
  });

  test("create refuses a wrong workspace, a bad hash, an archived conversation, a non-member requester and any user identity", async () => {
    await scenario(async (t, c) => {
      await failsWith(t, /conversation not found/, () => create(t, c, { ws: c.wsB }));
      await failsWith(t, /invalid action hash/, () => create(t, c, { hash: "nope" }));
      await failsWith(t, /requester is not a workspace member/, () => create(t, c, { user: c.userB }));
      await t`update public.conversations set archived_at = now() where id = ${c.convA2}`;
      await failsWith(t, /conversation closed/, () => create(t, c, { conv: c.convA2 }));
      await failsWith(t, /permission denied|service role only/, () =>
        as(t, "authenticated", c.userA, () => t`select public.create_approval_request(${c.wsA}::uuid, ${c.convA}::uuid, ${c.userA}::uuid, ${TOOL}::text, ${H1}::text, '{}'::jsonb, 86400)`),
      );
    });
  });

  test("decide: only a workspace Owner, same error for non-owner and unknown id, never anon or service_role", async () => {
    await scenario(async (t, c) => {
      const { approval } = await create(t, c);
      await failsWith(t, /approval: not authorized/, () => decide(t, c.userC, approval.id, "approve")); // member
      await failsWith(t, /approval: not authorized/, () => decide(t, c.userB, approval.id, "approve")); // other tenant
      await failsWith(t, /approval: not authorized/, () => decide(t, c.userA, randomUUID(), "approve")); // unknown id
      await failsWith(t, /permission denied/, () => as(t, "anon", null, () => t`select public.decide_approval(${approval.id}::uuid, 'approve')`));
      await failsWith(t, /permission denied/, () => as(t, "service_role", null, () => t`select public.decide_approval(${approval.id}::uuid, 'approve')`));
      await failsWith(t, /invalid decision/, () => decide(t, c.userA, approval.id, "approve_all"));
      expect((await row(t, approval.id)).status).toBe("pending");
    });
  });

  test("decide: Owner approves, repeat is unchanged, the opposite is a conflict, the inbox item leaves the action_required count", async () => {
    await scenario(async (t, c) => {
      const { approval } = await create(t, c);
      const d1 = await decide(t, c.userA, approval.id, "approve");
      expect(d1.outcome).toBe("decided");
      expect(d1.approval.status).toBe("approved");
      expect(d1.approval.decided_by).toBe(c.userA);
      expect(d1.approval).not.toHaveProperty("canonical_action");
      expect((await inbox(t, approval.id)).acted_at).not.toBeNull();
      expect((await decide(t, c.userA, approval.id, "approve")).outcome).toBe("unchanged"); // same decider, same decision
      const second = await decide(t, c.userE, approval.id, "approve"); // a DIFFERENT Owner repeating the decision
      expect(second.outcome).toBe("already_decided");
      expect(second.approval.decided_by).toBe(c.userA);
      expect((await row(t, approval.id)).status).toBe("approved");
    });
  });

  test("decide: deny is recorded as rejected and cannot be flipped to approve", async () => {
    await scenario(async (t, c) => {
      const { approval } = await create(t, c);
      expect((await decide(t, c.userA, approval.id, "deny")).approval.status).toBe("rejected");
      expect((await decide(t, c.userE, approval.id, "approve")).outcome).toBe("conflict");
      expect((await decide(t, c.userA, approval.id, "deny")).outcome).toBe("unchanged");
      expect((await decide(t, c.userE, approval.id, "deny")).outcome).toBe("already_decided");
      expect((await row(t, approval.id)).status).toBe("rejected");
    });
  });

  test("decide: an overdue request flips to expired inline and is never recorded as approved (Guard 1 row 2)", async () => {
    await scenario(async (t, c) => {
      const { approval } = await create(t, c);
      await forge(t, approval.id, "created_at = now() - interval '2 hours', expires_at = now() - interval '1 hour'");
      const d = await decide(t, c.userA, approval.id, "approve");
      expect(d.outcome).toBe("expired");
      const r = await row(t, approval.id);
      expect(r.status).toBe("expired");
      expect(r.decided_at).toBeNull();
      expect(r.expired_at).not.toBeNull();
      expect((await inbox(t, approval.id)).severity).toBe("info");
      expect((await decide(t, c.userA, approval.id, "approve")).outcome).toBe("expired");
    });
  });

  test("decide: an archived conversation refuses the decision and records nothing (Guard 1 row 9)", async () => {
    await scenario(async (t, c) => {
      const { approval } = await create(t, c);
      await t`update public.conversations set archived_at = now() where id = ${c.convA}`;
      const d = await decide(t, c.userA, approval.id, "approve");
      expect(d.outcome).toBe("closed");
      const r = await row(t, approval.id);
      expect(r.status).toBe("pending");
      expect(r.decided_at).toBeNull();
    });
  });

  test("decide: an Owner who lost the role is refused at decision time", async () => {
    await scenario(async (t, c) => {
      const { approval } = await create(t, c);
      await t`update public.workspace_members set role = 'member' where workspace_id = ${c.wsA} and user_id = ${c.userE}`;
      await failsWith(t, /approval: not authorized/, () => decide(t, c.userE, approval.id, "approve"));
    });
  });

  test("consume: exactly once for an approved, unexpired, same-hash, same-conversation request (Guard 1 rows 1-3)", async () => {
    await scenario(async (t, c) => {
      const { approval } = await create(t, c);
      expect(await consume(t, approval.id, H1, c.convA)).toEqual({ consumed: false, reason: "not_approved" }); // pending
      await decide(t, c.userA, approval.id, "approve");
      expect(await consume(t, approval.id, H2, c.convA)).toEqual({ consumed: false, reason: "hash_mismatch" });
      expect(await consume(t, approval.id, H1, c.convA2)).toEqual({ consumed: false, reason: "wrong_conversation" });
      expect((await row(t, approval.id)).status).toBe("approved"); // rejected attempts changed nothing
      expect(await consume(t, approval.id, H1, c.convA)).toEqual({ consumed: true, reason: "ok" });
      expect(await consume(t, approval.id, H1, c.convA)).toEqual({ consumed: false, reason: "already_consumed" });
      const r = await row(t, approval.id);
      expect(r.status).toBe("consumed");
      expect(r.consumed_at).not.toBeNull();
    });
  });

  test("consume: an expired approval, a rejected one and an unknown id are refused", async () => {
    await scenario(async (t, c) => {
      const a = (await create(t, c)).approval;
      await decide(t, c.userA, a.id, "approve");
      await forge(t, a.id, "created_at = now() - interval '2 hours', expires_at = now() - interval '1 hour'");
      expect(await consume(t, a.id, H1, c.convA)).toEqual({ consumed: false, reason: "expired" });
      const b = (await create(t, c, { hash: H2 })).approval;
      await decide(t, c.userA, b.id, "deny");
      expect(await consume(t, b.id, H2, c.convA)).toEqual({ consumed: false, reason: "not_approved" });
      expect(await consume(t, randomUUID(), H1, c.convA)).toEqual({ consumed: false, reason: "not_found" });
    });
  });

  test("consume: parallel proposals do not cross-consume (Guard 1 row 10): approving hash A never releases hash B", async () => {
    await scenario(async (t, c) => {
      const a = (await create(t, c, { hash: H1 })).approval;
      const b = (await create(t, c, { hash: H2 })).approval;
      await decide(t, c.userA, a.id, "approve");
      expect((await consume(t, b.id, H2, c.convA)).consumed).toBe(false);
      expect((await consume(t, b.id, H1, c.convA)).consumed).toBe(false);
      expect((await consume(t, a.id, H2, c.convA)).consumed).toBe(false);
      expect((await consume(t, a.id, H1, c.convA)).consumed).toBe(true);
    });
  });

  test("re-proposal: an approved live row is returned as approved (the caller consumes it at once); a consumed one allows a new request", async () => {
    await scenario(async (t, c) => {
      const a = (await create(t, c)).approval;
      await decide(t, c.userA, a.id, "approve");
      const again = await create(t, c);
      expect(again.created).toBe(false);
      expect(again.approval.status).toBe("approved");
      expect(again.approval.id).toBe(a.id);
      expect((await consume(t, a.id, H1, c.convA)).consumed).toBe(true);
      const next = await create(t, c);
      expect(next.created).toBe(true);
      expect(next.approval.id).not.toBe(a.id);
      expect(next.request_count).toBe(2);
    });
  });

  test("create: an overdue live row for the same action is expired first, never wedging the unique index", async () => {
    await scenario(async (t, c) => {
      const a = (await create(t, c)).approval;
      await forge(t, a.id, "created_at = now() - interval '2 hours', expires_at = now() - interval '1 hour'");
      const b = await create(t, c);
      expect(b.created).toBe(true);
      expect(b.approval.id).not.toBe(a.id);
      expect((await row(t, a.id)).status).toBe("expired");
    });
  });

  test("get_approval_status and list_live_approvals (service_role): no action text, live rows only", async () => {
    await scenario(async (t, c) => {
      const a = (await create(t, c)).approval;
      const b = (await create(t, c, { hash: H2 })).approval;
      await decide(t, c.userA, b.id, "deny");
      const st = await as(t, "service_role", null, async () => (await t`select public.get_approval_status(${a.id}::uuid) as r`)[0].r);
      expect(st.status).toBe("pending");
      expect(st).not.toHaveProperty("canonical_action");
      const none = await as(t, "service_role", null, async () => (await t`select public.get_approval_status(${randomUUID()}::uuid) as r`)[0].r);
      expect(none).toBeNull();
      const live = await as(t, "service_role", null, async () => (await t`select public.list_live_approvals(${c.convA}::uuid) as r`)[0].r);
      expect(live).toHaveLength(1);
      expect(live[0].approval.id).toBe(a.id);
      expect(live[0].request_count).toBe(1);
    });
  });

  test("write-once trigger: direct writes, illegal transitions and identity edits are refused even for the table owner", async () => {
    await scenario(async (t, c) => {
      const a = (await create(t, c)).approval;
      await directWriter(t);
      await failsWith(t, /writes go through the approval RPCs/, () => t`update public.approval_request set status = 'approved' where id = ${a.id}`);
      await failsWith(t, /writes go through the approval RPCs/, () =>
        t`insert into public.approval_request (workspace_id, conversation_id, tool_name, action_sha256, expires_at)
          values (${c.wsA}, ${c.convA}, ${TOOL}, ${H2}, now() + interval '1 day')`,
      );
      await decide(t, c.userA, a.id, "approve");
      await consume(t, a.id, H1, c.convA);
      await directWriter(t);
      await failsWith(t, /DELETE rejected/, () => t`delete from public.approval_request where id = ${a.id}`);
      // With the RPC GUC on (a hostile definer path), terminal rows still cannot move and identity is write-once.
      const guc = () => t`select set_config('app.approval_rpc', 'on', true)`;
      await guc();
      await failsWith(t, /illegal status transition/, () => t`update public.approval_request set status = 'approved' where id = ${a.id}`);
      await failsWith(t, /illegal status transition/, () => t`update public.approval_request set status = 'pending', consumed_at = null where id = ${a.id}`);
      await failsWith(t, /write-once column/, () => t`update public.approval_request set action_sha256 = ${H2} where id = ${a.id}`);
      await failsWith(t, /write-once column/, () => t`update public.approval_request set conversation_id = ${c.convA2} where id = ${a.id}`);
      await failsWith(t, /write-once column/, () => t`update public.approval_request set expires_at = expires_at + interval '1 day' where id = ${a.id}`);
      const b = (await create(t, c, { hash: H2 })).approval;
      await guc();
      await failsWith(t, /decision is write-once|a decision is recorded only/, () => t`update public.approval_request set decided_at = now(), decided_by = ${c.userA} where id = ${b.id}`);
    });
  });

  test("Art. 17: deleting the requester and the decider SET NULLs their columns and keeps the row (carve-out, mig 162 shape)", async () => {
    await scenario(async (t, c) => {
      const a = (await create(t, c, { user: c.userD })).approval;
      await decide(t, c.userE, a.id, "approve");
      // Erasure removes membership first (account-delete.ts); the approval row is what must survive the user delete.
      // (replica role only for these two deletes, as the anonymise wrappers do for the WORM member-action log).
      await t.unsafe("set local session_replication_role = replica");
      await t`delete from public.workspace_member_actions where target_user_id in (${c.userD}, ${c.userE}) or actor_user_id in (${c.userD}, ${c.userE})`;
      await t`delete from public.workspace_members where user_id in (${c.userD}, ${c.userE})`;
      await t.unsafe("set local session_replication_role = origin");
      await directWriter(t);
      await t`delete from auth.users where id = ${c.userD}`;
      let r = await row(t, a.id);
      expect(r.requested_by_user_id).toBeNull();
      expect(r.decided_by).toBe(c.userE);
      expect(r.status).toBe("approved");
      expect(r.action_sha256).toBe(H1);
      await t`delete from auth.users where id = ${c.userE}`;
      r = await row(t, a.id);
      expect(r.decided_by).toBeNull();
      expect(r.decided_at).not.toBeNull();
    });
  });

  test("Art. 17 carve-out is bound to a DELETED parent: nulling the column of a live user is refused", async () => {
    await scenario(async (t, c) => {
      const a = (await create(t, c)).approval;
      await directWriter(t);
      await failsWith(t, /writes go through the approval RPCs/, () => t`update public.approval_request set requested_by_user_id = null where id = ${a.id}`);
    });
  });

  test("workspace cascade: deleting the workspace removes its approval rows (DELETE carve-out); a direct DELETE is still refused", async () => {
    await scenario(async (t, c) => {
      const a = (await create(t, c)).approval;
      // Clear the unrelated RESTRICT dependents the way an erasure does (replica role only for these deletes).
      await t.unsafe("set local session_replication_role = replica");
      await t`delete from public.workspace_member_actions where workspace_id = ${c.wsA}`;
      await t`delete from public.workspace_members where workspace_id = ${c.wsA}`;
      await t`delete from public.conversations where workspace_id = ${c.wsA}`;
      await t.unsafe("set local session_replication_role = origin");
      await directWriter(t);
      await failsWith(t, /DELETE rejected/, () => t`delete from public.approval_request where id = ${a.id}`);
      await t`delete from public.workspaces where id = ${c.wsA}`;
      expect((await t`select count(*)::int n from public.approval_request where id = ${a.id}`)[0].n).toBe(0);
    });
  });

  test("sweep: expires due rows (unanswered vs unconsumed), flags unanswered once, scrubs text 30 days after the terminal state, idempotent", async () => {
    await scenario(async (t, c) => {
      const sweep = async () => as(t, "service_role", null, async () => (await t`select public.sweep_approvals() as r`)[0].r);
      const old = (await create(t, c, { hash: H1 })).approval;
      await forge(t, old.id, "created_at = now() - interval '20 minutes'");
      const s1 = await sweep();
      expect(s1.flagged.map((x: any) => x.id)).toEqual([old.id]);
      expect((await row(t, old.id)).unanswered_flagged_at).not.toBeNull();
      expect((await sweep()).flagged).toEqual([]); // once

      const unanswered = (await create(t, c, { hash: H2 })).approval;
      const unconsumed = (await create(t, c, { hash: hex("c") })).approval;
      await decide(t, c.userA, unconsumed.id, "approve");
      for (const id of [unanswered.id, unconsumed.id]) await forge(t, id, "created_at = now() - interval '2 hours', expires_at = now() - interval '1 hour'");
      const s2 = await sweep();
      const byId = Object.fromEntries(s2.expired.map((x: any) => [x.id, x.reason]));
      expect(byId[unanswered.id]).toBe("unanswered");
      expect(byId[unconsumed.id]).toBe("unconsumed");
      expect((await inbox(t, unanswered.id)).severity).toBe("info");
      expect((await sweep()).expired).toEqual([]);

      await forge(t, unanswered.id, "expired_at = now() - interval '31 days'");
      const s3 = await sweep();
      expect(s3.scrubbed).toBe(1);
      const scrubbed = await row(t, unanswered.id);
      expect(scrubbed.canonical_action).toBeNull();
      expect(scrubbed.action_sha256).toBe(H2); // audit fields survive
      expect(scrubbed.status).toBe("expired");
      expect((await row(t, unconsumed.id)).canonical_action).not.toBeNull(); // not yet 30 days
      expect((await sweep()).scrubbed).toBe(0);
    });
  });

  test("anonymise_approval_request (workspace with other members): nulls the user's columns and action text, expires live rows, keeps the audit row", async () => {
    await scenario(async (t, c) => {
      const a = (await create(t, c, { user: c.userD })).approval;
      const n = await as(t, "service_role", null, async () => (await t`select public.anonymise_approval_request(${c.userD}::uuid) as r`)[0].r);
      expect(n).toBe(1);
      const r = await row(t, a.id);
      expect(r.requested_by_user_id).toBeNull();
      expect(r.canonical_action).toBeNull();
      expect(r.status).toBe("expired");
      expect(r.action_sha256).toBe(H1);
      expect(r.workspace_id).toBe(c.wsA); // wsA still has members: the row is kept
      await failsWith(t, /permission denied/, () => as(t, "authenticated", c.userD, () => t`select public.anonymise_approval_request(${c.userD}::uuid)`));
    });
  });

  test("RLS and grants: Owner reads the row; a member and another tenant read nothing; no api role can write; service_role has no table access", async () => {
    await scenario(async (t, c) => {
      const a = (await create(t, c)).approval;
      const seen = async (who: string) => as(t, "authenticated", who, async () => (await t`select count(*)::int n from public.approval_request where id = ${a.id}`)[0].n);
      expect(await seen(c.userA)).toBe(1);
      expect(await seen(c.userE)).toBe(1);
      expect(await seen(c.userC)).toBe(0);
      expect(await seen(c.userB)).toBe(0);
      await failsWith(t, /permission denied/, () => as(t, "authenticated", c.userA, () => t`update public.approval_request set status = 'approved' where id = ${a.id}`));
      await failsWith(t, /permission denied/, () => as(t, "authenticated", c.userA, () => t`delete from public.approval_request where id = ${a.id}`));
      await failsWith(t, /permission denied/, () => as(t, "service_role", null, () => t`select count(*) from public.approval_request`));
      await failsWith(t, /permission denied/, () => as(t, "anon", null, () => t`select count(*) from public.approval_request`));
    });
  });

  // -------------------------------------------------------------------------------------------------------------
  // Review round: revoke, principal re-check, caps / notify, Art. 17 deletion of a memberless personal workspace.
  // -------------------------------------------------------------------------------------------------------------

  const hashN = (n: number) => n.toString(16).padStart(2, "0").repeat(32);
  const newConv = async (t: Txn, c: Ctx, ws = c.wsA) => {
    const id = randomUUID();
    await t`insert into conversations (id, user_id, workspace_id, status, visibility) values (${id}, ${c.userA}, ${ws}, 'active', 'workspace')`;
    return id;
  };

  test("revoke: an Owner's deny on an APPROVED, unconsumed request turns it into rejected, records who and when, and kills consume", async () => {
    await scenario(async (t, c) => {
      const { approval } = await create(t, c);
      await decide(t, c.userA, approval.id, "approve");
      const rv = await decide(t, c.userE, approval.id, "deny"); // a second Owner revokes
      expect(rv.outcome).toBe("revoked");
      expect(rv.approval.status).toBe("rejected");
      const r = await row(t, approval.id);
      expect(r.status).toBe("rejected");
      expect(r.revoked_by).toBe(c.userE);
      expect(r.revoked_at).not.toBeNull();
      expect(r.decided_by).toBe(c.userA); // the approval facts are kept
      expect(r.decided_at).not.toBeNull();
      expect(await consume(t, approval.id, H1, c.convA)).toEqual({ consumed: false, reason: "not_approved" }); // revoke wins
      expect((await decide(t, c.userE, approval.id, "deny")).outcome).toBe("unchanged"); // same revoker
      expect((await decide(t, c.userA, approval.id, "deny")).outcome).toBe("already_decided"); // other Owner, same decision
      expect((await decide(t, c.userA, approval.id, "approve")).outcome).toBe("conflict"); // no un-revoke
      // Denial is not sticky: a re-ask finds no live row and creates a new pending request.
      const again = await create(t, c);
      expect(again.created).toBe(true);
      expect(again.request_count).toBe(2);
    });
  });

  test("revoke vs consume serialise: consume wins -> revoke is a conflict and the row stays consumed", async () => {
    await scenario(async (t, c) => {
      const { approval } = await create(t, c);
      await decide(t, c.userA, approval.id, "approve");
      expect((await consume(t, approval.id, H1, c.convA)).consumed).toBe(true);
      const late = await decide(t, c.userA, approval.id, "deny");
      expect(late.outcome).toBe("conflict");
      expect(late.approval.status).toBe("consumed");
      expect((await decide(t, c.userA, approval.id, "approve")).outcome).toBe("conflict");
      expect((await row(t, approval.id)).revoked_at).toBeNull();
    });
  });

  test("revoke: a non-owner gets the same error as for an unknown id, and nothing changes", async () => {
    await scenario(async (t, c) => {
      const { approval } = await create(t, c);
      await decide(t, c.userA, approval.id, "approve");
      await failsWith(t, /approval: not authorized/, () => decide(t, c.userC, approval.id, "deny")); // member
      await failsWith(t, /approval: not authorized/, () => decide(t, c.userB, approval.id, "deny")); // other tenant
      expect((await row(t, approval.id)).status).toBe("approved");
    });
  });

  test("revoke after expiry is reported as expired (not a conflict) and flips the overdue approved row", async () => {
    await scenario(async (t, c) => {
      const { approval } = await create(t, c);
      await decide(t, c.userA, approval.id, "approve");
      await forge(t, approval.id, "created_at = now() - interval '2 hours', expires_at = now() - interval '1 hour'");
      const d = await decide(t, c.userA, approval.id, "deny");
      expect(d.outcome).toBe("expired");
      const r = await row(t, approval.id);
      expect(r.status).toBe("expired");
      expect(r.revoked_at).toBeNull();
      expect((await decide(t, c.userA, approval.id, "deny")).outcome).toBe("expired"); // and stays expired
      expect((await decide(t, c.userA, approval.id, "approve")).outcome).toBe("expired");
    });
  });

  test("revoke still works in an archived conversation (withdrawing authority is always allowed); a pending decision there is still 'closed'", async () => {
    await scenario(async (t, c) => {
      const a = (await create(t, c)).approval;
      const b = (await create(t, c, { hash: H2 })).approval;
      await decide(t, c.userA, a.id, "approve");
      await t`update public.conversations set archived_at = now() where id = ${c.convA}`;
      expect((await decide(t, c.userA, a.id, "deny")).outcome).toBe("revoked");
      expect((await decide(t, c.userA, b.id, "approve")).outcome).toBe("closed");
      expect((await row(t, b.id)).status).toBe("pending");
    });
  });

  test("revoke columns are write-once and only settable with approved -> rejected (trigger, even with the rpc GUC on)", async () => {
    await scenario(async (t, c) => {
      const a = (await create(t, c)).approval;
      await decide(t, c.userA, a.id, "approve");
      const b = (await create(t, c, { hash: H2 })).approval;
      await directWriter(t);
      await failsWith(t, /writes go through the approval RPCs/, () => t`update public.approval_request set status = 'rejected', revoked_at = now(), revoked_by = ${c.userA} where id = ${a.id}`);
      await t`select set_config('app.approval_rpc', 'on', true)`;
      // A revoke must carry both columns.
      await failsWith(t, /a revoke records revoked_at and revoked_by/, () => t`update public.approval_request set status = 'rejected' where id = ${a.id}`);
      // revoked_* cannot be set on a pending row, or by anything but approved -> rejected.
      await failsWith(t, /revoked_at\/revoked_by are write-once|approval_request_revoked_pairing/, () => t`update public.approval_request set revoked_at = now(), revoked_by = ${c.userA} where id = ${b.id}`);
      // Do the real revoke, then it is final.
      await decide(t, c.userA, a.id, "deny");
      await t`select set_config('app.approval_rpc', 'on', true)`;
      await failsWith(t, /revoked_at\/revoked_by are write-once|illegal status transition/, () => t`update public.approval_request set revoked_at = now() + interval '1 minute' where id = ${a.id}`);
      await failsWith(t, /illegal status transition/, () => t`update public.approval_request set status = 'approved' where id = ${a.id}`);
    });
  });

  test("consume re-checks the principals atomically: a demoted decider is refused (decider_not_owner), the approval is not burned", async () => {
    await scenario(async (t, c) => {
      const { approval } = await create(t, c);
      await decide(t, c.userE, approval.id, "approve"); // userE (second Owner) approves
      await t`update public.workspace_members set role = 'member' where workspace_id = ${c.wsA} and user_id = ${c.userE}`;
      expect(await consume(t, approval.id, H1, c.convA)).toEqual({ consumed: false, reason: "decider_not_owner" });
      expect((await row(t, approval.id)).status).toBe("approved"); // refused, not consumed
      await t`update public.workspace_members set role = 'owner' where workspace_id = ${c.wsA} and user_id = ${c.userE}`;
      expect(await consume(t, approval.id, H1, c.convA)).toEqual({ consumed: true, reason: "ok" }); // restored principal consumes
    });
  });

  test("consume re-checks the principals atomically: a removed requester is refused (requester_not_member)", async () => {
    await scenario(async (t, c) => {
      const { approval } = await create(t, c, { user: c.userD });
      await decide(t, c.userA, approval.id, "approve");
      await t.unsafe("set local session_replication_role = replica");
      await t`delete from public.workspace_member_actions where target_user_id = ${c.userD} or actor_user_id = ${c.userD}`;
      await t`delete from public.workspace_members where workspace_id = ${c.wsA} and user_id = ${c.userD}`;
      await t.unsafe("set local session_replication_role = origin");
      expect(await consume(t, approval.id, H1, c.convA)).toEqual({ consumed: false, reason: "requester_not_member" });
      expect((await row(t, approval.id)).status).toBe("approved");
    });
  });

  test("consume fails closed for an erased decider or requester (NULL user column is never consumable)", async () => {
    await scenario(async (t, c) => {
      const a = (await create(t, c, { user: c.userD })).approval;
      await decide(t, c.userE, a.id, "approve");
      // Erase the DECIDER the way the saga does (membership first, then the user row; Art. 17 SET NULL carve-out).
      await t.unsafe("set local session_replication_role = replica");
      await t`delete from public.workspace_member_actions where target_user_id = ${c.userE} or actor_user_id = ${c.userE}`;
      await t`delete from public.workspace_members where user_id = ${c.userE}`;
      await t.unsafe("set local session_replication_role = origin");
      await directWriter(t);
      await t`delete from auth.users where id = ${c.userE}`;
      expect((await row(t, a.id)).decided_by).toBeNull();
      expect(await consume(t, a.id, H1, c.convA)).toEqual({ consumed: false, reason: "decider_not_owner" });
      expect((await row(t, a.id)).status).toBe("approved");
    });
  });

  test("caps: the 6th pending request of a conversation is AP429; an idempotent re-ask of an existing request at the cap is NOT blocked", async () => {
    await scenario(async (t, c) => {
      for (let n = 1; n <= 5; n++) await create(t, c, { hash: hashN(n) });
      await failsWith(t, /AP429|too many pending requests/, () => create(t, c, { hash: hashN(6) }));
      const again = await create(t, c, { hash: hashN(3) }); // exists: idempotent, exempt
      expect(again.created).toBe(false);
      // Another conversation of the same workspace is unaffected.
      expect((await create(t, c, { conv: c.convA2, hash: hashN(6) })).created).toBe(true);
      // Answering one frees a slot (an approved row no longer counts as pending).
      const first = (await create(t, c, { hash: hashN(1) })).approval;
      await decide(t, c.userA, first.id, "approve");
      expect((await create(t, c, { hash: hashN(7) })).created).toBe(true);
    });
  });

  test("caps: the 21st pending request of a workspace is AP430 (SQLSTATE), even across conversations", async () => {
    await scenario(async (t, c) => {
      const convs = [c.convA, c.convA2, await newConv(t, c), await newConv(t, c)];
      let n = 0;
      for (const conv of convs) for (let k = 0; k < 5; k++) await create(t, c, { conv, hash: hashN(++n) });
      const extra = await newConv(t, c);
      let err: { code?: string; message?: string } | null = null;
      try {
        await t.savepoint(async () => {
          await create(t, c, { conv: extra, hash: hashN(99) });
        });
      } catch (e) {
        err = e as { code?: string; message?: string };
      }
      expect(err?.code).toBe("AP430");
      expect(await create(t, c, { conv: convs[0], hash: hashN(1) })).toMatchObject({ created: false }); // re-ask exempt
    });
  });

  test("caps: the conversation cap error carries SQLSTATE AP429", async () => {
    await scenario(async (t, c) => {
      for (let n = 1; n <= 5; n++) await create(t, c, { hash: hashN(n) });
      let err: { code?: string } | null = null;
      try {
        await t.savepoint(async () => {
          await create(t, c, { hash: hashN(6) });
        });
      } catch (e) {
        err = e as { code?: string };
      }
      expect(err?.code).toBe("AP429");
    });
  });

  test("create returns expires_at and coalesces notification: only the first new request in 10 minutes has notify=true", async () => {
    await scenario(async (t, c) => {
      const r1 = await create(t, c, { hash: hashN(1) });
      expect(r1.notify).toBe(true);
      expect(new Date(r1.expires_at).getTime()).toBe(new Date(r1.approval.expires_at).getTime());
      const r2 = await create(t, c, { hash: hashN(2) });
      expect(r2.created).toBe(true);
      expect(r2.notify).toBe(false); // another pending request of the workspace was created in the last 10 minutes
      const reask = await create(t, c, { hash: hashN(1) });
      expect(reask.created).toBe(false);
      expect(reask.notify).toBe(false);
      // Once the earlier requests are older than 10 minutes, the next new request notifies again.
      await forge(t, r1.approval.id, "created_at = now() - interval '11 minutes'");
      await forge(t, r2.approval.id, "created_at = now() - interval '11 minutes'");
      expect((await create(t, c, { hash: hashN(3) })).notify).toBe(true);
    });
  });

  test("get_approval_status is a scalar projection: no action text, no user ids, includes revoked_at", async () => {
    await scenario(async (t, c) => {
      const a = (await create(t, c)).approval;
      await decide(t, c.userA, a.id, "approve");
      await decide(t, c.userA, a.id, "deny");
      const st = await as(t, "service_role", null, async () => (await t`select public.get_approval_status(${a.id}::uuid) as r`)[0].r);
      expect(st.status).toBe("rejected");
      expect(st.revoked_at).not.toBeNull();
      for (const k of ["canonical_action", "requested_by_user_id", "decided_by", "revoked_by"]) expect(st).not.toHaveProperty(k);
    });
  });

  // ---- Art. 17: solo (personal) workspace ------------------------------------------------------------------------

  /** A fresh user whose personal workspace id equals the user id (the CLO's solo case), with a conversation. */
  async function soloUser(t: Txn) {
    const u = randomUUID();
    await t`insert into auth.users (id, email) values (${u}, ${`solo-${u}@example.test`})`;
    const [m] = await t`select workspace_id from workspace_members where user_id = ${u} limit 1`;
    const ws = m.workspace_id as string;
    const conv = randomUUID();
    await t`insert into conversations (id, user_id, workspace_id, status, visibility) values (${conv}, ${u}, ${ws}, 'active', 'workspace')`;
    return { u, ws, conv };
  }

  const createFor = async (t: Txn, ws: string, conv: string, user: string, hash: string) =>
    as(t, "service_role", null, async () => {
      const [r] = await t<{ r: any }[]>`select public.create_approval_request(${ws}::uuid, ${conv}::uuid, ${user}::uuid, ${TOOL}::text, ${hash}::text, ${t.json(CANON as never)}::jsonb, 86400::int) as r`;
      return r.r;
    });

  const decideFor = async (t: Txn, who: string, id: string, decision: string) => decide(t, who, id, decision);

  /** The saga's membership removal (step 5.7) as the existing Art. 17 tests do it (replica role for the WORM log only). */
  async function removeMemberships(t: Txn, userId: string) {
    await t.unsafe("set local session_replication_role = replica");
    await t`delete from public.workspace_member_actions where target_user_id = ${userId} or actor_user_id = ${userId}`;
    await t`delete from public.workspace_members where user_id = ${userId}`;
    await t.unsafe("set local session_replication_role = origin");
  }

  const anonymise = async (t: Txn, userId: string) =>
    as(t, "service_role", null, async () => (await t`select public.anonymise_approval_request(${userId}::uuid) as r`)[0].r as number);

  test("Art. 17 (solo): erasing a personal workspace's only user leaves ZERO approval rows (all five states) and zero approval inbox rows for workspace_id = user id", async () => {
    await scenario(async (t) => {
      const { u, ws, conv } = await soloUser(t);
      expect(ws).toBe(u); // the premise: workspaces.id = users.id for a personal workspace
      const pending = (await createFor(t, ws, conv, u, hashN(1))).approval;
      const approved = (await createFor(t, ws, conv, u, hashN(2))).approval;
      const rejected = (await createFor(t, ws, conv, u, hashN(3))).approval;
      const expired = (await createFor(t, ws, conv, u, hashN(4))).approval;
      const consumed = (await createFor(t, ws, conv, u, hashN(5))).approval;
      await decideFor(t, u, approved.id, "approve");
      await decideFor(t, u, rejected.id, "deny");
      await decideFor(t, u, consumed.id, "approve");
      expect((await as(t, "service_role", null, async () => (await t`select public.consume_approval(${consumed.id}::uuid, ${hashN(5)}::text, ${conv}::uuid) as r`)[0].r)).consumed).toBe(true);
      await forge(t, expired.id, "created_at = now() - interval '2 hours', expires_at = now() - interval '1 hour', status = 'expired', expired_at = now()");
      const states = (await t`select status from public.approval_request where workspace_id = ${u} order by status`).map((r) => r.status);
      expect(states.sort()).toEqual(["approved", "consumed", "expired", "pending", "rejected"]);
      expect((await t`select count(*)::int n from public.inbox_item where workspace_id = ${u} and source = 'approval_required'`)[0].n).toBe(5);

      // The saga: step 5.7 removes the membership, step 5.16 anonymise_approval_request runs.
      await removeMemberships(t, u);
      const n = await anonymise(t, u);
      expect(n).toBeGreaterThanOrEqual(5);
      // The CLO falsifier.
      expect((await t`select count(*)::int n from public.approval_request where workspace_id = ${u}`)[0].n).toBe(0);
      expect((await t`select count(*)::int n from public.inbox_item where workspace_id = ${u} and source = 'approval_required'`)[0].n).toBe(0);
      // Idempotent on a second run.
      expect(await anonymise(t, u)).toBe(0);
      expect(pending.workspace_id).toBe(u);
    });
  });

  test("Art. 17 (shared workspace): a user erased from a workspace that keeps another member leaves the rows, with the user columns NULL", async () => {
    await scenario(async (t, c) => {
      const a = (await create(t, c, { user: c.userD })).approval;
      await decide(t, c.userE, a.id, "approve");
      const b = (await create(t, c, { user: c.userA, hash: H2 })).approval;
      await decide(t, c.userE, b.id, "approve");
      await decide(t, c.userE, b.id, "deny"); // revoke by userE
      await removeMemberships(t, c.userD);
      await removeMemberships(t, c.userE);
      expect(await anonymise(t, c.userD)).toBeGreaterThanOrEqual(1);
      expect(await anonymise(t, c.userE)).toBeGreaterThanOrEqual(1);
      const ra = await row(t, a.id);
      expect(ra).toMatchObject({ requested_by_user_id: null, decided_by: null, canonical_action: null, workspace_id: c.wsA });
      const rb = await row(t, b.id);
      expect(rb.revoked_by).toBeNull();
      expect(rb.decided_by).toBeNull();
      expect(rb.revoked_at).not.toBeNull();
      expect(rb.requested_by_user_id).toBe(c.userA); // not an erased user's column
      expect((await t`select count(*)::int n from public.approval_request where workspace_id = ${c.wsA}`)[0].n).toBe(2); // wsA still has userA
      expect((await t`select count(*)::int n from public.inbox_item where workspace_id = ${c.wsA} and source = 'approval_required'`)[0].n).toBe(2);
    });
  });

  test("Art. 17 DELETE carve-out: without the GUC it is rejected; with the GUC while a member exists it is rejected; only GUC + memberless succeeds", async () => {
    await scenario(async (t) => {
      const { u, ws, conv } = await soloUser(t);
      const a = (await createFor(t, ws, conv, u, hashN(1))).approval;
      await directWriter(t);
      // No GUC, member present.
      await failsWith(t, /DELETE rejected/, () => t`delete from public.approval_request where id = ${a.id}`);
      // GUC on, member still present: still rejected.
      await t`select set_config('app.approval_erase', 'on', true)`;
      await failsWith(t, /DELETE rejected/, () => t`delete from public.approval_request where id = ${a.id}`);
      // Remove the membership but turn the GUC off: still rejected.
      await removeMemberships(t, u);
      await directWriter(t);
      await t`select set_config('app.approval_erase', 'off', true)`;
      await failsWith(t, /DELETE rejected/, () => t`delete from public.approval_request where id = ${a.id}`);
      // GUC on and memberless: admitted.
      await t`select set_config('app.approval_erase', 'on', true)`;
      await t`delete from public.approval_request where id = ${a.id}`;
      expect((await t`select count(*)::int n from public.approval_request where id = ${a.id}`)[0].n).toBe(0);
    });
  });

  test("the erasure GUC is reset after anonymise: a later direct DELETE in the same transaction is rejected", async () => {
    await scenario(async (t, c) => {
      const { u, ws, conv } = await soloUser(t);
      await createFor(t, ws, conv, u, hashN(1));
      await removeMemberships(t, u);
      await anonymise(t, u);
      expect((await t`select current_setting('app.approval_erase', true) as g`)[0].g).not.toBe("on");
      // A team workspace's row can still not be deleted afterwards.
      const a = (await create(t, c)).approval;
      await directWriter(t);
      await failsWith(t, /DELETE rejected/, () => t`delete from public.approval_request where id = ${a.id}`);
    });
  });
});
