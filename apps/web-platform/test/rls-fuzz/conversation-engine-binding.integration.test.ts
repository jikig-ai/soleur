import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import type postgres from "postgres";
import { asTenant, connect, seedTwoTenant } from "./harness-fixture";
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
});
