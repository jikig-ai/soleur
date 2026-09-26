import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import type postgres from "postgres";
import { asTenant, connect, rolledBackRaw, seedTwoTenant } from "./harness-fixture";
import type { Ctx } from "./targets";

const ENABLED = process.env.RLS_FUZZ_LOCAL === "1";
const DSN = process.env.RLS_FUZZ_DATABASE_URL ?? "postgres://postgres:postgres@127.0.0.1:54322/postgres";

let sql: postgres.Sql<{}>;
let ctx: Ctx;

describe.skipIf(!ENABLED)("conversation engine binding authority (local)", () => {
  beforeAll(async () => {
    sql = connect(DSN);
    ctx = await seedTwoTenant(sql);
  });
  afterAll(async () => {
    if (sql) await sql.end({ timeout: 5 });
  });

  test("migration repairs a pending row with a run while leaving an unbound row pending", async () => {
    const migration = readFileSync(
      path.join(__dirname, "../../supabase/migrations/142_repair_conversation_engine_binding_backfill.sql"),
      "utf8",
    ).replace(/^BEGIN;\s*$/m, "").replace(/^COMMIT;\s*$/m, "");
    const states = await rolledBackRaw(sql, async (t) => {
      const before = await t<{ id: string; engine_binding_state: string }[]>`
        select id, engine_binding_state from public.conversations
        where id in (${ctx.convA}, ${ctx.convA2})`;
      expect(before).toHaveLength(2);
      expect(before.every((row) => row.engine_binding_state === "pending")).toBe(true);
      await t`drop trigger conversations_engine_binding_state_insert on public.conversations`;
      await t.unsafe(migration);
      return await t<{ id: string; engine_binding_state: string }[]>`
        select id, engine_binding_state from public.conversations
        where id in (${ctx.convA}, ${ctx.convA2})`;
    });
    expect(new Map(states.map((row) => [row.id, row.engine_binding_state]))).toEqual(new Map([
      [ctx.convA, "bound"],
      [ctx.convA2, "pending"],
    ]));
  });

  test("an owner can insert pending and bind it through the RPC", async () => {
    const state = await asTenant(sql, ctx.userA, async (t) => {
      const id = randomUUID();
      await t`insert into public.conversations (id, user_id, workspace_id, status, visibility)
        values (${id}, ${ctx.userA}, ${ctx.wsA}, 'active', 'private')`;
      await t`select public.bind_agent_engine_run(${ctx.wsA}, 'conversation', ${id}, null, null, ${ctx.userA})`;
      const [row] = await t<{ engine_binding_state: string }[]>`
        select engine_binding_state from public.conversations where id = ${id}`;
      return row.engine_binding_state;
    });
    expect(state).toBe("bound");
  });

  for (const forgedState of ["legacy", "bound"]) {
    test(`an owner cannot insert a ${forgedState} marker`, async () => {
      await expect(asTenant(sql, ctx.userA, async (t) => {
        await t`insert into public.conversations
          (id, user_id, workspace_id, status, visibility, engine_binding_state)
          values (${randomUUID()}, ${ctx.userA}, ${ctx.wsA}, 'active', 'private', ${forgedState})`;
      })).rejects.toMatchObject({
        code: "42501",
        message: "conversation engine binding state is immutable",
      });
    });
  }

  test("a custom GUC cannot authorize a direct marker change", async () => {
    await expect(asTenant(sql, ctx.userA, async (t) => {
      await t`select set_config('soleur.engine_binding_rpc', '1', true)`;
      await t`update public.conversations set engine_binding_state = 'legacy'
        where id = ${ctx.convA2}`;
    })).rejects.toMatchObject({
      code: "42501",
      message: "conversation engine binding state is immutable",
    });
  });

  test("a workspace co-member cannot bind another owner's private conversation", async () => {
    await expect(asTenant(sql, ctx.userC, async (t) => {
      await t`select public.bind_agent_engine_run(${ctx.wsA}, 'conversation', ${ctx.convA}, null, null, ${ctx.userC})`;
    })).rejects.toMatchObject({ code: "42501" });
  });
});
