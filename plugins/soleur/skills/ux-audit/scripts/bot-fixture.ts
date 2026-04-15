#!/usr/bin/env bun
/**
 * bot-fixture.ts — seed/reset the ux-audit bot's DB state.
 *
 * Scope: DB-only v1. KB file seeding deferred to #2351 (files live in GitHub
 * workspace, not Supabase Storage).
 *
 * Usage: bun plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts <seed|reset>
 *
 * Env (from Doppler prd + prd_scheduled):
 *   SUPABASE_URL                    prd
 *   SUPABASE_SERVICE_ROLE_KEY       prd
 *   UX_AUDIT_BOT_EMAIL              prd_scheduled
 */

const TC_VERSION = "1.0.0";

const FIXTURE_CONVERSATIONS = [
  {
    session_id: "ux-audit-fixture-conv-1",
    domain_leader: "cmo",
    messages: [
      { role: "user", content: "What's the highest-leverage thing I can do this week to grow?" },
      { role: "assistant", content: "Given your current stage, I'd focus on outbound to the 12 closest-fit prospects from last month's signups. Want me to draft the sequence?" },
      { role: "user", content: "Yes, draft it." },
    ],
  },
  {
    session_id: "ux-audit-fixture-conv-2",
    domain_leader: "cto",
    messages: [
      { role: "user", content: "Is our CI pipeline a bottleneck?" },
      { role: "assistant", content: "Looking at the last 50 runs, median is 6m 40s. The Eleventy build step is the longest single job. Want me to profile it?" },
      { role: "user", content: "Please do, and share the top 3 wins." },
      { role: "assistant", content: "Top wins: (1) cache node_modules between jobs, (2) parallelize lint + typecheck, (3) skip docs build on non-docs PRs." },
    ],
  },
] as const;

function env(key: string): string {
  const v = process.env[key];
  if (!v) throw new Error(`Missing env: ${key}`);
  return v;
}

async function sbFetch(
  path: string,
  init: RequestInit = {},
): Promise<Response> {
  const SUPABASE_URL = env("SUPABASE_URL");
  const SERVICE_KEY = env("SUPABASE_SERVICE_ROLE_KEY");
  return fetch(`${SUPABASE_URL}${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
      ...init.headers,
    },
  });
}

async function getBotUserId(): Promise<string> {
  const email = env("UX_AUDIT_BOT_EMAIL");
  const res = await sbFetch(`/auth/v1/admin/users?per_page=1000`);
  if (!res.ok) throw new Error(`admin users GET ${res.status}`);
  const data = (await res.json()) as {
    users: Array<{ id: string; email: string }>;
  };
  const bot = data.users.find((u) => u.email === email);
  if (!bot) throw new Error(`bot user ${email} not found — run 1.1 first`);
  return bot.id;
}

async function updateUserRow(
  userId: string,
  patch: Record<string, unknown>,
): Promise<void> {
  const res = await sbFetch(`/rest/v1/users?id=eq.${userId}`, {
    method: "PATCH",
    body: JSON.stringify(patch),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`PATCH users failed: ${res.status} ${body}`);
  }
}

async function findConversationId(
  userId: string,
  sessionId: string,
): Promise<string | null> {
  const res = await sbFetch(
    `/rest/v1/conversations?user_id=eq.${userId}&session_id=eq.${sessionId}&select=id`,
  );
  if (!res.ok) throw new Error(`conversations GET ${res.status}`);
  const rows = (await res.json()) as Array<{ id: string }>;
  return rows[0]?.id ?? null;
}

async function insertConversation(
  userId: string,
  sessionId: string,
  domainLeader: string,
): Promise<string> {
  const res = await sbFetch(`/rest/v1/conversations`, {
    method: "POST",
    headers: { Prefer: "return=representation" },
    body: JSON.stringify({
      user_id: userId,
      session_id: sessionId,
      domain_leader: domainLeader,
      status: "completed",
    }),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`POST conversations failed: ${res.status} ${body}`);
  }
  const rows = (await res.json()) as Array<{ id: string }>;
  if (!rows[0]) {
    throw new Error(`POST conversations returned empty array — representation missing`);
  }
  return rows[0].id;
}

async function insertMessages(
  conversationId: string,
  messages: ReadonlyArray<{ role: string; content: string }>,
): Promise<void> {
  const res = await sbFetch(`/rest/v1/messages`, {
    method: "POST",
    body: JSON.stringify(
      messages.map((m) => ({
        conversation_id: conversationId,
        role: m.role,
        content: m.content,
      })),
    ),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`POST messages failed: ${res.status} ${body}`);
  }
}

async function seed(): Promise<void> {
  const botId = await getBotUserId();
  console.log(`[seed] bot user id: ${botId}`);

  await updateUserRow(botId, {
    tc_accepted_version: TC_VERSION,
    tc_accepted_at: new Date().toISOString(),
    onboarding_completed_at: new Date().toISOString(),
    subscription_status: "active",
    stripe_customer_id: "cus_ux_audit_fixture",
    stripe_subscription_id: "sub_ux_audit_fixture",
    current_period_end: new Date(Date.now() + 365 * 24 * 3600 * 1000).toISOString(),
    cancel_at_period_end: false,
  });
  console.log("[seed] users row patched (tc + subscription + onboarding)");

  for (const c of FIXTURE_CONVERSATIONS) {
    const existing = await findConversationId(botId, c.session_id);
    if (existing) {
      console.log(`[seed] conversation ${c.session_id} exists (${existing}) — skip`);
      continue;
    }
    const cid = await insertConversation(botId, c.session_id, c.domain_leader);
    await insertMessages(cid, c.messages);
    console.log(`[seed] conversation ${c.session_id} created (${cid}) with ${c.messages.length} messages`);
  }

  console.log("[seed] done");
}

async function reset(): Promise<void> {
  const botId = await getBotUserId();
  console.log(`[reset] bot user id: ${botId}`);

  const convRes = await sbFetch(
    `/rest/v1/conversations?user_id=eq.${botId}&select=id`,
  );
  if (!convRes.ok) throw new Error(`conversations GET ${convRes.status}`);
  const conversations = (await convRes.json()) as Array<{ id: string }>;

  for (const c of conversations) {
    await sbFetch(`/rest/v1/messages?conversation_id=eq.${c.id}`, { method: "DELETE" });
  }
  if (conversations.length > 0) {
    await sbFetch(`/rest/v1/conversations?user_id=eq.${botId}`, { method: "DELETE" });
  }
  console.log(`[reset] deleted ${conversations.length} conversations + messages`);

  await updateUserRow(botId, {
    tc_accepted_version: null,
    tc_accepted_at: null,
    onboarding_completed_at: null,
    subscription_status: "none",
    stripe_customer_id: null,
    stripe_subscription_id: null,
    current_period_end: null,
    cancel_at_period_end: false,
  });
  console.log("[reset] users row cleared");
  console.log("[reset] done");
}

const cmd = process.argv[2];
if (cmd === "seed") {
  await seed();
} else if (cmd === "reset") {
  await reset();
} else {
  console.error(`Usage: bun ${import.meta.path} <seed|reset>`);
  process.exit(2);
}
