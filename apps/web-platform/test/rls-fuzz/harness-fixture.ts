// Shared harness fixture (#6256, ADR-111, AC2) — the UNION SUPERSET of the three
// integration files' previously-forked `connect`/`seedContext`/`seedRpcCtx` +
// rollback helpers. Item 8 of the #6307 hardening: the three copies had begun to
// diverge, and adding the user-isolation / anon / row-hijack dimensions to three
// separate forks would triple the divergence. Extraction first is the enabling
// refactor; the migration is behavior-preserving (RED→GREEN — the suite is its own
// regression test).
//
// Three load-bearing behaviors a naive merge would silently break (each a total
// false-green), preserved here as documented invariants:
//
//  1. `max: 1` is load-bearing. `set local role` / `set_config('request.jwt.claims')`
//     apply PER CONNECTION; a pool > 1 could run a query on a different connection
//     than the one the role/claims were set on → the attack silently runs as
//     service_role or claim-less. Pinned in connect().
//  2. The txn helpers are NOT interchangeable but COMPOSE around ONE primitive
//     (rolledBackRaw) with ONE rollback sentinel — shrinking the sentinel-mismatch
//     surface. rolledBackRaw does NOT set role (callers set it; the AC5 / RPC self-
//     test paths `alter table … disable rls` or `reset role` mid-txn as superuser,
//     which a pre-set role would break). attackAs/asTenant layer role+claims on top.
//  3. seedRpcCtx flag-poisoning (debug_mode=true, ack=now(), installation_id=424242)
//     is preserved: a leaked getter read returns identically to a denial (null)
//     unless A's flags are poisoned to non-sentinel values.
//  4. Every bare `sql`-handle statement MUST ride withTransientRetry — a new
//     unwrapped statement on the raw handle is an unretried deadlock victim
//     waiting to resurface as a CI flake (#9779). The wrap census is pinned by
//     rls-fuzz-census.test.ts, and transient codes caught in a probe's own
//     catch arm are re-thrown by verdict.ts › rethrowIfTransient() before they
//     can classify as test-error.

import { randomUUID } from "node:crypto";
import postgres from "postgres";
import { sqlStateFromError } from "../../lib/postgres-errors";
import { assertLocalDsn } from "./local-dsn-guard";
import { buildAuthenticatedClaims } from "./claim";
import { TRANSIENT_SQLSTATES } from "./verdict";
import type { Ctx } from "./targets";
import type { RpcCtx } from "./rpc-cases";

type Sql = postgres.Sql<{}>;
type Txn = postgres.TransactionSql<{}>;

// Transient set lives in verdict.ts › TRANSIENT_SQLSTATES (the catch-arm
// classifiers there rethrow the same codes so they can reach this retry).
const TRANSIENT_MAX_ATTEMPTS = 3;

/**
 * Retry `fn` on a transient Postgres lock error (40P01 deadlock_detected,
 * 55P03 lock_not_available) with 80–120 ms jitter — the same bound and cadence
 * as server/concurrency.ts's acquireSlot. Parallel vitest workers share ONE
 * disposable Postgres, so any statement can be elected deadlock victim — the
 * victim is picked nondeterministically, which is why the retry lives here at
 * the `Sql`-handle level rather than at the DDL call site (#9779).
 *
 * NEVER wrap a transaction-scoped `t` handle: a statement issued on an aborted
 * txn re-raises 25P02, which is not transient and would mask the real 40P01
 * from the outer retry. Retry only ever replays a complete unit of work.
 */
export async function withTransientRetry<T>(
  fn: () => Promise<T>,
  opts?: { sleep?: (ms: number) => Promise<void> },
): Promise<T> {
  const sleep =
    opts?.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  for (let attempt = 1; ; attempt++) {
    try {
      return await fn();
    } catch (e) {
      const code = sqlStateFromError(e);
      if (code === undefined || !TRANSIENT_SQLSTATES.has(code) || attempt >= TRANSIENT_MAX_ATTEMPTS) {
        throw e;
      }
      // Keep the flake visible in CI logs — a green run that silently absorbed
      // three deadlocks must not read identically to a run with none.
      console.warn(`[rls-fuzz] transient ${code} — retrying (attempt ${attempt + 1}/${TRANSIENT_MAX_ATTEMPTS})`);
      await sleep(80 + Math.random() * 40); // 80–120 ms jitter, same as concurrency.ts › acquireSlot()
    }
  }
}

/**
 * Connect to the LOCAL disposable Postgres after the fail-closed DSN guard.
 * `max: 1` is load-bearing (per-connection role/claims — see file header). Every
 * caller MUST use this instead of `postgres(...)` directly so the pin cannot drift.
 * The DSN is passed by each caller (the `*.integration.test.ts` files own the
 * `RLS_FUZZ_DATABASE_URL ?? <local default>` literal — allowlisted there); this
 * module deliberately holds no DSN literal so it needs no secret-scan waiver.
 */
export function connect(dsn: string): Sql {
  assertLocalDsn(dsn); // refuse any non-local target before connecting
  return postgres(dsn, { max: 1, prepare: false, onnotice: () => {} });
}

/** The SINGLE rollback sentinel shared by every txn helper (attacks never persist). */
const ROLLBACK = Symbol("rls-fuzz-rollback");

/**
 * PRIMITIVE: run fn inside a transaction that ALWAYS rolls back; returns fn's value.
 * Does NOT set role — callers that need to observe as superuser first (disable RLS,
 * `reset role` mid-txn to re-read a poisoned row) rely on this. attackAs/asTenant
 * layer role+claims on top.
 *
 * `fn` may be invoked up to TRANSIENT_MAX_ATTEMPTS times (each in a fresh txn)
 * when a transient lock error propagates out of it — keep it replay-safe:
 * DB statements + idempotent local-variable writes only, no external side
 * effects that must run exactly once.
 */
export async function rolledBackRaw<T>(sql: Sql, fn: (t: Txn) => Promise<T>): Promise<T> {
  let out: T;
  try {
    await withTransientRetry(() =>
      sql.begin(async (t) => {
        out = await fn(t as Txn);
        return Promise.reject(ROLLBACK); // discard everything the attack touched
      }),
    );
  } catch (e) {
    if (e !== ROLLBACK) throw e;
  }
  return out!;
}

/**
 * Set the transaction's role `authenticated` + forged `request.jwt.claims` as the
 * first statements, run fn, then ALWAYS roll back. The claim-forging attacker entry
 * point (the previous `attackTxn`).
 */
export async function attackAs<T>(sql: Sql, claims: string, fn: (t: Txn) => Promise<T>): Promise<T> {
  return rolledBackRaw(sql, async (t) => {
    await t`set local role authenticated`;
    await t.unsafe("select set_config('request.jwt.claims', $1, true)", [claims]);
    return fn(t);
  });
}

/**
 * Set the transaction's role `anon` + an anon `request.jwt.claims` (no `sub`,
 * `auth.uid()` = NULL), run fn, roll back. The role axis is a first-class attacker
 * dimension distinct from `sub` (ADR-111 amendment) — under anon every
 * `auth.uid() = founder` premise in a definer fn evaporates.
 */
export async function attackAsAnon<T>(sql: Sql, fn: (t: Txn) => Promise<T>): Promise<T> {
  return rolledBackRaw(sql, async (t) => {
    await t`set local role anon`;
    await t.unsafe("select set_config('request.jwt.claims', $1, true)", ['{"role":"anon"}']);
    return fn(t);
  });
}

/** attackAs with authenticated claims for the given `sub` (the previous per-tenant helper). */
export function asTenant<T>(sql: Sql, sub: string, fn: (t: Txn) => Promise<T>): Promise<T> {
  return attackAs(sql, buildAuthenticatedClaims({ sub }), fn);
}

/**
 * The shared two-tenant bootstrap (synthetic, cq-test-fixtures-synthesized-only):
 * three users A/B/C, each auth.users insert firing handle_new_user() → personal org
 * + workspace + membership; userC joins wsA as a co-member (the byok_delegations
 * grantee trigger requires a real member — and the user-isolation dimension's
 * co-member attacker); two A-owned conversations (parents for messages /
 * user_concurrency_slots seeds); and an A-owned engine run shared by event and RPC
 * attacks. Runs a self-check before returning — a silent seed
 * failure is a beforeAll false-green (treat any vitest `skipped > 0` as a crash trap).
 */
export async function seedTwoTenant(sql: Sql): Promise<Ctx> {
  // ONE committed txn under the transient-retry wrapper: a mid-seed deadlock
  // rolls the whole seed back, so the retry replays on a clean state and a
  // multi-statement seed can never leave a half-provisioned fixture.
  return withTransientRetry(() => sql.begin((t) => seedTwoTenantTx(t as Txn)));
}

async function seedTwoTenantTx(t: Txn): Promise<Ctx> {
  const userA = randomUUID();
  const userB = randomUUID();
  const userC = randomUUID();
  await t`insert into auth.users (id, email) values
    (${userA}, ${`a-${userA}@example.test`}),
    (${userB}, ${`b-${userB}@example.test`}),
    (${userC}, ${`c-${userC}@example.test`})`;
  const [a] = await t`select workspace_id, (select organization_id from workspaces where id = workspace_id) as org from workspace_members where user_id = ${userA} limit 1`;
  const [b] = await t`select workspace_id from workspace_members where user_id = ${userB} limit 1`;
  const wsA = a.workspace_id as string;
  const wsB = b.workspace_id as string;
  const orgA = a.org as string;
  // userC joins wsA as a co-member (co-member attacker + byok_delegations grantee).
  await t`insert into workspace_members (workspace_id, user_id, role) values (${wsA}, ${userC}, 'member')`;
  const convA = randomUUID();
  const convA2 = randomUUID();
  await t`insert into conversations (id, user_id, workspace_id, status, visibility) values
    (${convA}, ${userA}, ${wsA}, 'active', 'workspace'),
    (${convA2}, ${userA}, ${wsA}, 'active', 'workspace')`;
  const [engineRun] = await t<{ id: string }[]>`
    insert into agent_engine_runs (
      workspace_id, execution_kind, conversation_id, engine_id, auth_mode,
      adapter_version, status, created_by
    ) values (
      ${wsA}, 'conversation', ${convA}, 'claude-code', 'managed',
      'rls-fuzz-fixture', 'queued', ${userA}
    ) returning id`;
  const ctx: Ctx = { userA, userB, userC, wsA, wsB, orgA, convA, convA2, engineRunA: engineRun.id };
  await assertTwoTenant(t, ctx);
  return ctx;
}

/** Fixture self-check: wsA≠wsB, orgA present, userC is a wsA member. */
async function assertTwoTenant(t: Txn, c: Ctx): Promise<void> {
  if (!c.wsA || !c.wsB || c.wsA === c.wsB || !c.orgA) {
    throw new Error(`fixture seed failed: wsA=${c.wsA} wsB=${c.wsB} orgA=${c.orgA}`);
  }
  const [m] = await t<{ n: number }[]>`
    select count(*)::int as n from workspace_members where workspace_id = ${c.wsA} and user_id = ${c.userC}`;
  if (m.n !== 1) throw new Error(`fixture seed failed: userC is not a wsA member (n=${m.n})`);
}

/**
 * Seed an A-owned resend-ingest email_triage_item (workspace-owner-gated, mig 111).
 * Shared by the Phase 4 base-table exclusion seed AND the Phase 7
 * set_email_triage_status RPC attack — built ONCE here (the exact divergence Item 8
 * exists to prevent). Returns the new row id. `claim_key` is UNIQUE NOT NULL.
 */
export async function seedEmailTriageItem(h: Sql | Txn, c: Ctx): Promise<string> {
  const [row] = await h<{ id: string }[]>`
    insert into email_triage_items (workspace_id, claim_key, resend_email_id, subject, received_at, received_at_source)
    values (${c.wsA}, ${`claim-${randomUUID()}`}, ${`re-${randomUUID()}`}, 'rls-fuzz triage', now(), 'payload')
    returning id`;
  return row.id;
}

/**
 * The RPC-dimension seed: the shared two-tenant bootstrap PLUS the A-owned resource
 * ids the RPC attacks address (kb_file / message / byok_delegation / beta contact /
 * inbox item) AND A's poisoned workspace flags. The poison (debug_mode=true,
 * ack=now(), installation_id=424242) is load-bearing: a leaked getter reads
 * identically to a denial (null/false) unless A's flags are non-sentinel. Self-checks
 * the poison landed before returning.
 */
export async function seedRpcCtx(sql: Sql): Promise<RpcCtx> {
  // Same committed-txn + retry contract as seedTwoTenant.
  return withTransientRetry(() => sql.begin((t) => seedRpcCtxTx(t as Txn)));
}

async function seedRpcCtxTx(t: Txn): Promise<RpcCtx> {
  const base = await seedTwoTenantTx(t);
  const [kb] = await t`insert into kb_files (workspace_id, user_id, file_path, filename, visibility)
    values (${base.wsA}, ${base.userA}, ${`/a/${randomUUID()}`}, 'a', 'workspace') returning id`;
  const [msg] = await t`insert into messages (workspace_id, template_id, conversation_id, role, content)
    values (${base.wsA}, 'work', ${base.convA}, 'user', 'x') returning id`;
  const [del] = await t`insert into byok_delegations (grantor_user_id, grantee_user_id, workspace_id, created_by_user_id, daily_usd_cap_cents, hourly_usd_cap_cents)
    values (${base.userA}, ${base.userC}, ${base.wsA}, ${base.userA}, 1000, 100) returning id`;
  // Poison A's workspace flags to NON-sentinel values (see docstring).
  await t`update workspaces set debug_mode = true, autonomous_disclosure_ack_at = now(), github_installation_id = 424242 where id = ${base.wsA}`;
  const [contact] = await t`insert into beta_contacts (user_id) values (${base.userA}) returning id`;
  const [inbox] = await t`insert into inbox_item (user_id, workspace_id, severity, source, title)
    values (${base.userA}, ${base.wsA}, 'info', 'system', 'rls-fuzz') returning id`;
  const emailTriageA = await seedEmailTriageItem(t, base);
  const [grant] = await t`insert into scope_grants (founder_id, workspace_id, action_class, tier)
    values (${base.userA}, ${base.wsA}, ${`general.${randomUUID().slice(0, 8)}`}, 'auto') returning id`;
  const [poison] = await t<{ debug_mode: boolean }[]>`select debug_mode from workspaces where id = ${base.wsA}`;
  if (poison?.debug_mode !== true) throw new Error("fixture seed failed: workspace flag poison did not land");
  return {
    ...base,
    kbFileA: kb.id as string,
    messageA: msg.id as string,
    delegationA: del.id as string,
    contactA: contact.id as string,
    inboxA: inbox.id as string,
    emailTriageA,
    scopeGrantA: grant.id as string,
  };
}
