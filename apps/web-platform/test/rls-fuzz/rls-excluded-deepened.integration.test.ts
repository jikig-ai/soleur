import { describe, test, expect, beforeAll, afterAll } from "vitest";
import { randomUUID } from "node:crypto";
import type postgres from "postgres";
import { classifyWriteOutcome, classifySelectOutcome, isPass, type Verdict } from "./verdict";
import { type Ctx } from "./targets";
import { connect, seedTwoTenant, seedEmailTriageItem, asTenant } from "./harness-fixture";

// Deepened EXCLUDED_ISOLATION tables (#6307 Item 1, ADR-111, AC4). These carry
// workspace_id (so AC1b tracks them) but are isolated by a NON-is_workspace_member
// predicate (workspace-OWNER-gating, user_id=auth.uid()), so none can be an AC1 base
// target. Rather than leave them as rationale-only exclusions, drive a FAITHFUL
// bespoke attack: a co-member of wsA (userC) — who passes workspace membership but is
// neither the row's owner nor the workspace owner — must be denied, while the owner
// (userA) succeeds (the positive control that falsifies a green-by-emptiness result).
// Gated behind RLS_FUZZ_LOCAL=1 against a LOCAL disposable Postgres.
const ENABLED = process.env.RLS_FUZZ_LOCAL === "1";
const DSN = process.env.RLS_FUZZ_DATABASE_URL ?? "postgres://postgres:postgres@127.0.0.1:54322/postgres";

let sql: postgres.Sql<{}>;
let ctx: Ctx;
const ids: Record<string, string> = {};
let msgA = "";
let grantA = "";

const countById = (h: postgres.Sql | postgres.TransactionSql, table: string, id: string) =>
  h.unsafe(`select count(*)::int as n from "${table}" where id = $1`, [id]).then((r) => (r[0] as unknown as { n: number }).n);

describe.skipIf(!ENABLED)("RLS/authz-fuzz — deepened excluded tables (co-member attacker, local)", () => {
  beforeAll(async () => {
    sql = connect(DSN); // assertLocalDsn + max:1 pinned in the shared fixture
    ctx = await seedTwoTenant(sql);

    ids.email_triage_items = await seedEmailTriageItem(sql, ctx);

    const [inbox] = await sql`insert into inbox_item (user_id, workspace_id, severity, source, title)
      values (${ctx.userA}, ${ctx.wsA}, 'info', 'system', 'rls-fuzz') returning id`;
    ids.inbox_item = inbox.id as string;

    const [dsar] = await sql`insert into dsar_export_jobs (workspace_id, user_id)
      values (${ctx.wsA}, ${ctx.userA}) returning id`;
    ids.dsar_export_jobs = dsar.id as string;

    // action_sends carries NOT-NULL FKs (message_id → messages, grant_id → scope_grants);
    // constraints fire BEFORE the RLS WITH CHECK, so the forge MUST use A-owned FK rows
    // or it would 23503 (test-error) instead of exercising the user_id=auth.uid() gate.
    const [m] = await sql`insert into messages (workspace_id, template_id, conversation_id, role, content)
      values (${ctx.wsA}, 'work', ${ctx.convA}, 'user', 'x') returning id`;
    msgA = m.id as string;
    const [g] = await sql`insert into scope_grants (founder_id, workspace_id, action_class, tier)
      values (${ctx.userA}, ${ctx.wsA}, ${`general.${randomUUID().slice(0, 8)}`}, 'auto') returning id`;
    grantA = g.id as string;
    const [as] = await sql`insert into action_sends
      (user_id, message_id, action_class, tier_at_send, template_hash, per_send_body_sha256, recipient_id_hash, grant_id)
      values (${ctx.userA}, ${msgA}, 'general', 'auto', ${`h-${randomUUID()}`}, ${`s-${randomUUID()}`}, ${`r-${randomUUID()}`}, ${grantA})
      returning id`;
    ids.action_sends = as.id as string;
  });
  afterAll(async () => {
    if (sql) await sql.end({ timeout: 5 });
  });

  // SELECT-USING isolation, shared shape: service_role precondition, OWNER positive
  // control (userA), CO-MEMBER negative (userC — a wsA member who is neither the
  // row's user nor the workspace owner → must be denied).
  for (const table of ["email_triage_items", "inbox_item", "dsar_export_jobs", "action_sends"]) {
    test(`deepened-excluded SELECT isolation: ${table}`, async () => {
      const id = ids[table];
      expect(await countById(sql, table, id), `${table}: seed precondition`).toBe(1);
      const aSees = await asTenant(sql, ctx.userA, (t) => countById(t, table, id));
      expect(aSees, `${table}: positive control (owner userA self-read)`).toBe(1);
      const cSees = await asTenant(sql, ctx.userC, (t) => countById(t, table, id));
      expect(isPass(classifySelectOutcome(cSees)), `${table}: co-member userC SELECT (saw ${cSees})`).toBe(true);
      expect(await countById(sql, table, id), `${table}: row intact after read attacks`).toBe(1);
    });
  }

  // action_sends is the ONE table here with a real INSERT WITH CHECK (user_id =
  // auth.uid()) — a cross-tenant INSERT-forge (claiming A's user_id, with A-owned FK
  // rows so it clears constraints first) must be RLS-denied (42501), a faithful,
  // non-trigger-masked write test. The other three either REVOKE INSERT from
  // authenticated (grant denial, not RLS) or have no INSERT policy, so their forge is
  // dropped per the WORM/grant discipline (AC5) — SELECT-USING carries their proof.
  test("deepened-excluded INSERT-forge (action_sends real WITH CHECK): co-member denied (42501)", async () => {
    const verdict = await asTenant(sql, ctx.userC, async (t): Promise<Verdict> => {
      try {
        await t`insert into action_sends
          (user_id, message_id, action_class, tier_at_send, template_hash, per_send_body_sha256, recipient_id_hash, grant_id)
          values (${ctx.userA}, ${msgA}, 'general', 'auto', ${`h-${randomUUID()}`}, ${`s-${randomUUID()}`}, ${`r-${randomUUID()}`}, ${grantA})`;
        return classifyWriteOutcome(null); // committed → cross-tenant write went through
      } catch (err) {
        return classifyWriteOutcome(err as { code?: string });
      }
    });
    expect(verdict, "action_sends: co-member INSERT-forge must be RLS-denied (42501)").toEqual({ kind: "denied" });
  });
});
