import { describe, test, expect, beforeAll } from "bun:test";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

const SCRIPT = resolve(
  import.meta.dir,
  "../../skills/ux-audit/scripts/bot-fixture.ts",
);

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const BOT_EMAIL = process.env.UX_AUDIT_BOT_EMAIL;
const BOT_PASSWORD = process.env.UX_AUDIT_BOT_PASSWORD;
const ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

const hasCreds = Boolean(
  SUPABASE_URL && SERVICE_KEY && BOT_EMAIL && BOT_PASSWORD && ANON_KEY,
);

// Blast-radius guard: the `reset` call in beforeAll deletes all conversations
// for BOT_EMAIL against prod Supabase. Refuse to run if the env points at
// anything other than the synthetic bot. A mis-set env var should crash the
// suite loudly, not silently wipe a real user's chat history.
if (hasCreds && BOT_EMAIL !== "ux-audit-bot@jikigai.com") {
  throw new Error(
    `UX_AUDIT_BOT_EMAIL must be "ux-audit-bot@jikigai.com" for these tests ` +
      `(got "${BOT_EMAIL}"). Running against any other email risks data loss.`,
  );
}

// Note: these tests skip when creds are absent (local dev w/o Doppler, or the
// plugin CI test-all.sh which doesn't inject Supabase secrets). Previously
// silent; now emits a one-line console.warn listing missing env vars (#2362.7).
// The CI loud-fail guardrail is tracked separately in #2361 — it needs a
// dedicated ux-audit smoke job that explicitly loads Doppler prd_scheduled,
// rather than throwing at module load in the shared suite.
const describeIfCreds = hasCreds ? describe : describe.skip;

if (!hasCreds) {
  const missing = [
    !SUPABASE_URL && "SUPABASE_URL",
    !SERVICE_KEY && "SUPABASE_SERVICE_ROLE_KEY",
    !BOT_EMAIL && "UX_AUDIT_BOT_EMAIL",
    !BOT_PASSWORD && "UX_AUDIT_BOT_PASSWORD",
    !ANON_KEY && "NEXT_PUBLIC_SUPABASE_ANON_KEY",
  ].filter(Boolean);
  console.warn(
    `[bot-fixture.test] skipping integration suite — missing env: ${missing.join(", ")}`,
  );
}

async function restGet(path: string): Promise<unknown> {
  const res = await fetch(`${SUPABASE_URL}${path}`, {
    headers: {
      apikey: SERVICE_KEY!,
      Authorization: `Bearer ${SERVICE_KEY}`,
    },
  });
  if (!res.ok) throw new Error(`GET ${path} -> ${res.status}`);
  return res.json();
}

async function getBotUserId(): Promise<string> {
  const data = (await restGet(
    `/auth/v1/admin/users?per_page=1000`,
  )) as { users: Array<{ id: string; email: string }> };
  const bot = data.users.find((u) => u.email === BOT_EMAIL);
  if (!bot) throw new Error(`Bot user ${BOT_EMAIL} not found`);
  return bot.id;
}

async function countConversations(userId: string): Promise<number> {
  const rows = (await restGet(
    `/rest/v1/conversations?user_id=eq.${userId}&select=id`,
  )) as Array<{ id: string }>;
  return rows.length;
}

async function countMessages(userId: string): Promise<number> {
  const conversations = (await restGet(
    `/rest/v1/conversations?user_id=eq.${userId}&select=id`,
  )) as Array<{ id: string }>;
  let total = 0;
  for (const c of conversations) {
    const msgs = (await restGet(
      `/rest/v1/messages?conversation_id=eq.${c.id}&select=id`,
    )) as Array<{ id: string }>;
    total += msgs.length;
  }
  return total;
}

async function getUserRow(userId: string) {
  const rows = (await restGet(
    `/rest/v1/users?id=eq.${userId}&select=tc_accepted_version,subscription_status,onboarding_completed_at,stripe_customer_id`,
  )) as Array<Record<string, unknown>>;
  if (rows.length === 0) throw new Error(`User ${userId} not found`);
  return rows[0];
}

function runScript(cmd: "seed" | "reset") {
  return spawnSync("bun", [SCRIPT, cmd], {
    encoding: "utf-8",
    env: process.env,
  });
}

describeIfCreds("bot-fixture (DB-only v1)", () => {
  let botId: string;

  beforeAll(async () => {
    botId = await getBotUserId();
    const reset = runScript("reset");
    if (reset.status !== 0) {
      throw new Error(`reset failed: ${reset.stderr}`);
    }
  });

  test("seed unlocks middleware guards (tc + subscription)", async () => {
    const r = runScript("seed");
    expect(r.status).toBe(0);
    const row = await getUserRow(botId);
    expect(row.tc_accepted_version).toBe("1.0.0");
    expect(row.subscription_status).toBe("active");
  });

  test("seed inserts exactly 2 conversations with >=3 messages each", async () => {
    runScript("seed");
    const count = await countConversations(botId);
    expect(count).toBe(2);

    const conversations = (await restGet(
      `/rest/v1/conversations?user_id=eq.${botId}&select=id`,
    )) as Array<{ id: string }>;

    for (const c of conversations) {
      const msgs = (await restGet(
        `/rest/v1/messages?conversation_id=eq.${c.id}&select=id`,
      )) as Array<{ id: string }>;
      expect(msgs.length).toBeGreaterThanOrEqual(3);
    }
  });

  test("seed is idempotent (running twice yields same row counts)", async () => {
    runScript("seed");
    const countAfterFirst = await countConversations(botId);
    const messagesAfterFirst = await countMessages(botId);
    runScript("seed");
    const countAfterSecond = await countConversations(botId);
    const messagesAfterSecond = await countMessages(botId);
    expect(countAfterSecond).toBe(countAfterFirst);
    expect(countAfterSecond).toBe(2);
    // Message count must stay stable (3 + 4 = 7) across re-seeds. Without the
    // DELETE-before-insert guard inside seed(), upsert merge-duplicates would
    // double the count to 14 on the second run.
    expect(messagesAfterSecond).toBe(messagesAfterFirst);
    expect(messagesAfterSecond).toBe(7);
  });

  test("bot can sign in after seed", async () => {
    runScript("seed");
    const res = await fetch(
      `${SUPABASE_URL}/auth/v1/token?grant_type=password`,
      {
        method: "POST",
        headers: {
          apikey: ANON_KEY!,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ email: BOT_EMAIL, password: BOT_PASSWORD }),
      },
    );
    expect(res.ok).toBe(true);
    const body = (await res.json()) as { access_token?: string };
    expect(body.access_token).toBeTruthy();
  });

  test("reset clears seeded conversations but leaves auth user", async () => {
    runScript("seed");
    expect(await countConversations(botId)).toBe(2);
    const r = runScript("reset");
    expect(r.status).toBe(0);
    expect(await countConversations(botId)).toBe(0);
    // Auth user must survive reset — only DB state should be cleared.
    // getBotUserId() throws if the bot email is absent, locking the invariant
    // against any future regression that cascades to /auth/v1/admin/users.
    expect(await getBotUserId()).toBe(botId);
    const row = await getUserRow(botId);
    expect(row.subscription_status).toBe("none");
    expect(row.tc_accepted_version).toBeNull();
  });

  // Contract test for migration 035: locks in PostgREST's ability to infer
  // ON CONFLICT against (user_id, session_id). A future migration that
  // narrows the index back to a partial form (e.g., WHERE archived_at IS
  // NULL) will fail here with 42P10 before the scheduled cron does.
  // POST with a bogus user_id so PostgREST fails at the FK (23503), not at
  // the inference step. 23503 means inference passed; 42P10 means it didn't.
  test("PostgREST infers ON CONFLICT against (user_id, session_id) without 42P10", async () => {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/conversations?on_conflict=user_id,session_id`,
      {
        method: "POST",
        headers: {
          apikey: SERVICE_KEY!,
          Authorization: `Bearer ${SERVICE_KEY}`,
          "Content-Type": "application/json",
          Prefer: "resolution=merge-duplicates",
        },
        body: JSON.stringify({
          user_id: "00000000-0000-0000-0000-000000000000",
          session_id: "contract-test-probe",
          domain_leader: "cmo",
          status: "completed",
        }),
      },
    );
    if (res.ok) {
      // Shouldn't happen (FK is bogus), but if Postgres ever accepts the row
      // we delete it — the contract assertion is "no 42P10", not "no insert".
      const rows = (await res.json()) as Array<{ id: string }>;
      if (rows[0]?.id) {
        await fetch(
          `${SUPABASE_URL}/rest/v1/conversations?id=eq.${rows[0].id}`,
          {
            method: "DELETE",
            headers: {
              apikey: SERVICE_KEY!,
              Authorization: `Bearer ${SERVICE_KEY}`,
            },
          },
        );
      }
      return;
    }
    const body = (await res.json()) as { code?: string };
    expect(body.code).not.toBe("42P10");
  });
});
