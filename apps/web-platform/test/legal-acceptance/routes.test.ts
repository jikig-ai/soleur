/**
 * #12011 PR-C workstream A: POST /api/legal-acceptance/[key]/{reauth,decide}.
 * Cookie-session routes: CSRF fails closed on an absent Origin, JSON required, flag-gated, unknown key 404, identity from
 * getUser() only, a runtime-audience token never opens an intent, the decision is recorded on the USER client only, and
 * the unknown-address 422 looks exactly like a send.
 */
import { afterAll, beforeEach, describe, expect, it, vi } from "vitest";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

const USER = "00000000-0000-4000-8000-0000000000aa";
const EMAIL = "founder.fixture@example.invalid";
const SESSION = "11111111-1111-4111-8111-111111111111";
const EVENT = "22222222-2222-4222-8222-222222222222";

const h = vi.hoisted(() => ({
  verified: { value: null as string | null },
  flag: { value: true },
  token: { value: "" },
  getUserUser: { value: null as { id: string; email: string } | null },
  userRpc: vi.fn(),
  serviceRpc: vi.fn(),
  throwaway: { send: vi.fn(), verify: vi.fn(), signOut: vi.fn() },
  report: vi.fn(),
  texts: { dir: "" },
  ceiling: { value: null as unknown },
  failures: { value: null as unknown },
  clientFails: { value: false },
  flush: vi.fn(),
  after: vi.fn(),
  // The card kinds declared for the fixture keys (the real map declares only the committed text).
  declared: { value: { "fixture-terms": "terms", "fixture-other": "terms" } as Record<string, "terms" | "acknowledgement"> },
}));

// `after` is spied and then delegated to the real one (which throws outside a request scope, so the helper's fallback runs the task).
vi.mock("next/server", async (orig) => {
  const real = await orig<typeof import("next/server")>();
  return {
    ...real,
    after: (...a: Parameters<typeof real.after>) => {
      h.after(...a);
      return real.after(...a);
    },
  };
});

// Only `flush` is replaced: the decide route flushes the accepted event before it acknowledges the row (#12011 PR-D).
vi.mock("@sentry/nextjs", async (orig) => ({ ...(await orig<typeof import("@sentry/nextjs")>()), flush: (...a: unknown[]) => h.flush(...a) }));
vi.mock("@/server/request-auth", () => ({
  verifiedUserId: async () => h.verified.value,
  // The bounded helpers return the `data` of the underlying call (or null on a stall or a throw), like the real ones.
  boundedAuthGetUser: async (c: { auth: { getUser: () => Promise<{ data: unknown }> } }) => (await c.auth.getUser()).data,
  boundedAuthGetSession: async (c: { auth: { getSession: () => Promise<{ data: unknown }> } }) => (await c.auth.getSession()).data,
}));
vi.mock("@/server/with-user-rate-limit", async () => {
  const { verifiedUserId } = await import("@/server/request-auth");
  return {
    withUserRateLimit: (handler: (req: Request, user: { id: string }) => Promise<Response>) => async (req: Request) => {
      const id = await verifiedUserId(req);
      if (!id) return Response.json({ error: "Unauthorized" }, { status: 401 });
      return handler(req, { id });
    },
  };
});
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => {
    if (h.clientFails.value) throw new TypeError("not a database problem");
    return {
    rpc: (...a: unknown[]) => h.userRpc(...a),
    auth: {
      getUser: async () => ({ data: { user: h.getUserUser.value }, error: null }),
      getSession: async () => ({ data: { session: h.token.value ? { access_token: h.token.value } : null }, error: null }),
    },
    };
  },
}));
vi.mock("@/lib/supabase/service", () => ({
  serverUrl: () => "https://fixture.supabase.invalid",
  createServiceClient: () => ({ rpc: (...a: unknown[]) => h.serviceRpc(...a) }),
}));
vi.mock("@supabase/supabase-js", () => ({
  createClient: () => ({
    auth: {
      signInWithOtp: (...a: unknown[]) => h.throwaway.send(...a),
      verifyOtp: (...a: unknown[]) => h.throwaway.verify(...a),
      signOut: (...a: unknown[]) => h.throwaway.signOut(...a),
    },
  }),
}));
vi.mock("@/server/approval/flag", () => ({ isApprovalQueueEnabled: async () => h.flag.value }));
// The fixture keys are not in the real LEGAL_TEXT_KIND, so the kind lookup the guard uses reads the per-test map instead.
vi.mock("@/lib/legal-acceptance-copy", async (orig) => {
  const real = await orig<typeof import("@/lib/legal-acceptance-copy")>();
  return { ...real, legalKindCopy: (key: string) => real.legalKindCopy(key, h.declared.value) };
});
vi.mock("@/server/approval/ops", async (orig) => ({
  ...(await orig<typeof import("@/server/approval/ops")>()),
  reportLegalOp: (...a: unknown[]) => h.report(...a),
}));
// The per-user verify ceiling is injected per test (a fresh one in beforeEach), not reached into through a private field.
vi.mock("@/server/legal-acceptance/reauth", async (orig) => {
  const real = await orig<typeof import("@/server/legal-acceptance/reauth")>();
  return {
    ...real,
    verifyReauthCode: (deps: Parameters<typeof real.verifyReauthCode>[0], a: Parameters<typeof real.verifyReauthCode>[1]) =>
      real.verifyReauthCode({ ...deps, ceiling: h.ceiling.value as InstanceType<typeof real.AttemptCeiling> }, a),
    sendReauthCode: (deps: Parameters<typeof real.sendReauthCode>[0], a: Parameters<typeof real.sendReauthCode>[1]) =>
      real.sendReauthCode({ ...deps, sendFailures: h.failures.value as InstanceType<typeof real.SendFailureMemory> }, a),
  };
});
// The registry directory is a fixture dir, so these route tests do not depend on whatever the real texts directory holds.
vi.mock("@/server/legal-acceptance/canonical", async (orig) => {
  const real = await orig<typeof import("@/server/legal-acceptance/canonical")>();
  return { ...real, getLegalText: (key: string) => real.getLegalText(key, h.texts.dir) };
});

import { POST as reauth } from "@/app/api/legal-acceptance/[key]/reauth/route";
import { POST as decide } from "@/app/api/legal-acceptance/[key]/decide/route";
import { getLegalText } from "@/server/legal-acceptance/canonical";
import { AttemptCeiling, SendFailureMemory } from "@/server/legal-acceptance/reauth";

const jwt = (payload: Record<string, unknown>) =>
  `${Buffer.from('{"alg":"none"}').toString("base64url")}.${Buffer.from(JSON.stringify(payload)).toString("base64url")}.sig`;
const webToken = () => jwt({ sub: USER, aud: "authenticated", session_id: SESSION });

const dir = mkdtempSync(path.join(tmpdir(), "legal-routes-"));
mkdirSync(dir, { recursive: true });
writeFileSync(path.join(dir, "fixture-terms.md"), "---\nversion: fx-1\n---\nSynthesized fixture text.\n");
writeFileSync(path.join(dir, "fixture-other.md"), "---\nversion: fx-2\n---\nA different synthesized fixture text.\n");
h.texts.dir = dir;
afterAll(() => rmSync(dir, { recursive: true, force: true }));
const HASH = getLegalText("fixture-terms").textHash;
const HASH_OTHER = getLegalText("fixture-other").textHash;

function req(action: "reauth" | "decide", body: unknown, o: { key?: string; origin?: string | null; ct?: string | null; raw?: string } = {}) {
  const headers: Record<string, string> = {};
  if (o.ct !== null) headers["content-type"] = o.ct ?? "application/json";
  if (o.origin !== null) headers.origin = o.origin ?? "https://app.soleur.ai";
  return new Request(`https://app.soleur.ai/api/legal-acceptance/${o.key ?? "fixture-terms"}/${action}`, {
    method: "POST",
    headers,
    body: o.raw ?? JSON.stringify(body),
  });
}
const json = async (r: Response) => ({ status: r.status, body: await r.json() });
const issued = { data: { outcome: "issued", reused: false, event_id: EVENT, expires_at: "2099-01-01T00:00:00Z" }, error: null };

beforeEach(() => {
  vi.stubEnv("NODE_ENV", "production");
  vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", USER);
  h.declared.value = { "fixture-terms": "terms", "fixture-other": "terms" };
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "anon-key-fixture");
  h.verified.value = USER;
  h.flag.value = true;
  h.token.value = webToken();
  h.getUserUser.value = { id: USER, email: EMAIL };
  for (const f of [h.userRpc, h.serviceRpc, h.throwaway.send, h.throwaway.verify, h.throwaway.signOut, h.report]) f.mockReset();
  h.throwaway.send.mockResolvedValue({ error: null });
  h.throwaway.verify.mockResolvedValue({ error: null });
  h.throwaway.signOut.mockResolvedValue({ error: null });
  h.serviceRpc.mockResolvedValue(issued);
  h.ceiling.value = new AttemptCeiling();
  h.failures.value = new SendFailureMemory();
  h.clientFails.value = false;
  h.flush.mockReset();
  h.flush.mockResolvedValue(false);
});

describe.each(["reauth", "decide"] as const)("%s: request guards", (action) => {
  const ok = action === "reauth" ? { step: "send" } : { choice: "decline", textHash: HASH };

  it("an absent Origin fails closed (403) even though the shared validateOrigin would let it through; a foreign Origin is 403", async () => {
    const post = action === "reauth" ? reauth : decide;
    expect((await json(await post(req(action, ok, { origin: null })))).status).toBe(403);
    expect((await json(await post(req(action, ok, { origin: "https://evil.example" })))).status).toBe(403);
    expect(h.serviceRpc).not.toHaveBeenCalled();
  });

  it("unauthenticated is 401 (wrapper); a body-supplied identity is ignored", async () => {
    const post = action === "reauth" ? reauth : decide;
    h.verified.value = null;
    expect((await json(await post(req(action, { ...ok, userId: "attacker", email: "x@y.z" })))).status).toBe(401);
  });

  it("flag off and unknown or malformed key are 404 with an error body; nothing is called", async () => {
    const post = action === "reauth" ? reauth : decide;
    h.flag.value = false;
    expect(await json(await post(req(action, ok)))).toEqual({ status: 404, body: { error: "Not found" } });
    h.flag.value = true;
    expect((await json(await post(req(action, ok, { key: "no-such-key" })))).status).toBe(404);
    expect((await json(await post(req(action, ok, { key: "Bad_Key" })))).status).toBe(404);
    expect(h.serviceRpc).not.toHaveBeenCalled();
  });

  it("founder gate: with the flag ON only the configured founder gets through; another user, an unset variable and a malformed variable are the same 404 and nothing is called (AC13)", async () => {
    const post = action === "reauth" ? reauth : decide;
    const notFound = { status: 404, body: { error: "Not found" } };
    const OTHER = "00000000-0000-4000-8000-0000000000bb";
    h.flag.value = true;
    h.verified.value = OTHER;
    h.getUserUser.value = { id: OTHER, email: EMAIL };
    expect(await json(await post(req(action, ok)))).toEqual(notFound);
    h.verified.value = USER;
    h.getUserUser.value = { id: USER, email: EMAIL };
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "");
    expect(await json(await post(req(action, ok)))).toEqual(notFound);
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", "not-a-uuid");
    expect(await json(await post(req(action, ok)))).toEqual(notFound);
    expect(h.serviceRpc).not.toHaveBeenCalled();
    expect(h.userRpc).not.toHaveBeenCalled();
    // the founder, flag on, variable equal: enabled (the request proceeds past the guard)
    vi.stubEnv("LEGAL_ACCEPTANCE_FOUNDER_ID", USER);
    expect((await json(await post(req(action, ok)))).status).not.toBe(404);
    // flag off with the variable equal: disabled
    h.flag.value = false;
    expect(await json(await post(req(action, ok)))).toEqual(notFound);
  });

  it("a registered text with no declared card kind is the same 404 (no default kind), and nothing is called", async () => {
    const post = action === "reauth" ? reauth : decide;
    h.declared.value = {};
    expect(await json(await post(req(action, ok)))).toEqual({ status: 404, body: { error: "Not found" } });
    expect(h.serviceRpc).not.toHaveBeenCalled();
    expect(h.userRpc).not.toHaveBeenCalled();
    h.declared.value = { "fixture-terms": "acknowledgement" };
    expect((await json(await post(req(action, ok)))).status).not.toBe(404);
  });

  it("requires application/json and a JSON object body", async () => {
    const post = action === "reauth" ? reauth : decide;
    expect((await json(await post(req(action, ok, { ct: "text/plain" })))).status).toBe(415);
    expect((await json(await post(req(action, ok, { ct: null })))).status).toBe(415);
    expect((await json(await post(req(action, ok, { raw: "{not json" })))).status).toBe(400);
    expect((await json(await post(req(action, ok, { raw: "[]" })))).status).toBe(400);
  });

  it("a runtime-audience token is 403 and nothing is issued; no session id is 401 and nothing is issued", async () => {
    const post = action === "reauth" ? reauth : decide;
    h.token.value = jwt({ sub: USER, aud: "soleur-runtime", session_id: SESSION });
    expect((await json(await post(req(action, ok)))).status).toBe(403);
    h.token.value = jwt({ sub: USER, aud: "authenticated", session_id: "" });
    expect((await json(await post(req(action, ok)))).status).toBe(401);
    expect(h.serviceRpc).not.toHaveBeenCalled();
    expect(h.userRpc).not.toHaveBeenCalled();
    expect(h.throwaway.send).not.toHaveBeenCalled();
  });
});

describe("reauth", () => {
  it("send: issues for the verified session, emails via the throwaway client with shouldCreateUser false, answers {ok:true,state:'sent'}", async () => {
    const out = await json(await reauth(req("reauth", { step: "send", resend: true })));
    expect(out).toEqual({ status: 200, body: { ok: true, state: "sent" } });
    expect(h.serviceRpc).toHaveBeenCalledWith("issue_legal_reauth", {
      p_user_id: USER, p_key: "fixture-terms", p_text_hash: HASH, p_version: "fx-1", p_session_id: SESSION, p_resend: true,
    });
    expect(h.throwaway.send).toHaveBeenCalledWith({ email: EMAIL, options: { shouldCreateUser: false } });
    expect(h.userRpc).not.toHaveBeenCalled();
  });

  it("send: the 422 for an unknown address returns the byte-identical response as a successful send", async () => {
    const known = await (await reauth(req("reauth", { step: "send" }))).text();
    h.throwaway.send.mockResolvedValue({ error: { name: "AuthApiError", status: 422, code: "otp_disabled", message: EMAIL } });
    const unknown = await (await reauth(req("reauth", { step: "send" }))).text();
    expect(unknown).toBe(known);
    // reported once at warn level (an abnormal state for a signed-in founder), class only, never the address
    expect(h.report).toHaveBeenCalledTimes(1);
    expect(h.report).toHaveBeenCalledWith("reauthFailed", null, expect.objectContaining({ level: "warn" }));
    expect(JSON.stringify(h.report.mock.calls)).not.toContain(EMAIL);
  });

  it("send: a real failure is {ok:false,reason:'unavailable'} and the address is never reported", async () => {
    h.throwaway.send.mockResolvedValue({ error: { name: "AuthRetryableFetchError", status: 503, message: EMAIL } });
    expect(await json(await reauth(req("reauth", { step: "send" })))).toEqual({ status: 200, body: { ok: false, reason: "unavailable" } });
    expect(h.report).toHaveBeenCalledWith("reauthFailed", null, expect.anything());
    expect(JSON.stringify(h.report.mock.calls)).not.toContain(EMAIL);
  });

  it("send: a database rate limit is typed and sends nothing", async () => {
    h.serviceRpc.mockResolvedValue({ data: { outcome: "rate_limited" }, error: null });
    expect((await json(await reauth(req("reauth", { step: "send" })))).body).toEqual({ ok: false, reason: "rate_limited" });
    expect(h.throwaway.send).not.toHaveBeenCalled();
  });

  it("send: the auth service's 429 is {ok:false,reason:'rate_limited'} and is not an error-level report", async () => {
    h.throwaway.send.mockResolvedValue({ error: { name: "AuthApiError", status: 429, code: "over_email_send_rate_limit", message: EMAIL } });
    expect(await json(await reauth(req("reauth", { step: "send" })))).toEqual({ status: 200, body: { ok: false, reason: "rate_limited" } });
    expect(h.report).not.toHaveBeenCalled();
  });

  it("send: a reused intent without a resend answers sent and emails nothing", async () => {
    h.serviceRpc.mockResolvedValue({ data: { outcome: "issued", reused: true, event_id: EVENT, expires_at: "2099-01-01T00:00:00Z" }, error: null });
    expect(await json(await reauth(req("reauth", { step: "send" })))).toEqual({ status: 200, body: { ok: true, state: "sent" } });
    expect(h.throwaway.send).not.toHaveBeenCalled();
    await reauth(req("reauth", { step: "send", resend: true }));
    expect(h.throwaway.send).toHaveBeenCalledTimes(1);
  });

  it("verify: a session with no address is unavailable and the auth service is not asked", async () => {
    h.getUserUser.value = { id: USER, email: "" };
    h.serviceRpc.mockResolvedValue({ data: { outcome: "allowed", event_id: EVENT, attempts: 1 }, error: null });
    expect((await json(await reauth(req("reauth", { step: "verify", code: "123456" })))).body).toEqual({ ok: false, reason: "unavailable" });
    expect(h.throwaway.verify).not.toHaveBeenCalled();
  });

  it("verify: claims first, verifies on the throwaway client, signs it out locally, marks with the claimed event id", async () => {
    const order: string[] = [];
    h.serviceRpc.mockImplementation(async (fn: string) => {
      order.push(fn);
      return fn === "claim_legal_reauth_attempt"
        ? { data: { outcome: "allowed", event_id: EVENT, attempts: 1 }, error: null }
        : { data: { outcome: "verified" }, error: null };
    });
    h.throwaway.verify.mockImplementation(async () => (order.push("verifyOtp"), { error: null }));
    h.throwaway.signOut.mockImplementation(async () => (order.push("signOut"), { error: null }));
    const out = await json(await reauth(req("reauth", { step: "verify", code: "123456" })));
    expect(out).toEqual({ status: 200, body: { ok: true } });
    expect(order).toEqual(["claim_legal_reauth_attempt", "verifyOtp", "signOut", "mark_legal_reauth_verified"]);
    expect(h.throwaway.verify).toHaveBeenCalledWith({ email: EMAIL, token: "123456", type: "email" });
    expect(h.throwaway.signOut).toHaveBeenCalledWith({ scope: "local" });
    expect(h.serviceRpc).toHaveBeenLastCalledWith("mark_legal_reauth_verified", {
      p_user_id: USER, p_event_id: EVENT, p_key: "fixture-terms", p_text_hash: HASH, p_session_id: SESSION,
    });
  });

  it("verify: accepts 6 to 8 digits only (dev OTP is 8, prod 6)", async () => {
    h.serviceRpc.mockResolvedValue({ data: { outcome: "locked" }, error: null });
    for (const code of ["12345", "123456789", "12a456", " 123456", 123456, null]) {
      expect((await json(await reauth(req("reauth", { step: "verify", code })))).status, String(code)).toBe(400);
    }
    for (const code of ["123456", "1234567", "12345678"]) {
      expect((await json(await reauth(req("reauth", { step: "verify", code })))).status, code).toBe(200);
    }
  });

  it("verify: a locked challenge never reaches the auth service; a wrong code is typed", async () => {
    h.serviceRpc.mockResolvedValue({ data: { outcome: "locked" }, error: null });
    expect((await json(await reauth(req("reauth", { step: "verify", code: "123456" })))).body).toEqual({ ok: false, reason: "locked" });
    expect(h.throwaway.verify).not.toHaveBeenCalled();
    h.serviceRpc.mockResolvedValue({ data: { outcome: "allowed", event_id: EVENT, attempts: 2 }, error: null });
    h.throwaway.verify.mockResolvedValue({ error: { name: "AuthApiError", status: 403, code: "otp_expired" } });
    expect((await json(await reauth(req("reauth", { step: "verify", code: "123456" })))).body).toEqual({ ok: false, reason: "wrong_code" });
  });

  it("verify: the 11th attempt inside 15 minutes is locked by the per-user ceiling, whatever the key", async () => {
    h.serviceRpc.mockResolvedValue({ data: { outcome: "locked" }, error: null });
    for (let i = 0; i < 10; i++) await reauth(req("reauth", { step: "verify", code: "123456" }));
    h.serviceRpc.mockClear();
    expect((await json(await reauth(req("reauth", { step: "verify", code: "123456" })))).body).toEqual({ ok: false, reason: "locked" });
    expect(h.serviceRpc).not.toHaveBeenCalled();
  });

  it("an unknown step or a non-boolean resend is 400; a database failure is a static 500", async () => {
    expect((await json(await reauth(req("reauth", { step: "nope" })))).status).toBe(400);
    expect((await json(await reauth(req("reauth", { step: "send", resend: "yes" })))).status).toBe(400);
    h.serviceRpc.mockResolvedValue({ data: null, error: { message: `db says ${EMAIL}`, code: "XX000" } });
    const out = await json(await reauth(req("reauth", { step: "send" })));
    expect(out).toEqual({ status: 500, body: { error: "Internal error" } });
    expect(h.report).toHaveBeenCalledWith(
      "reauthFailed",
      expect.objectContaining({ name: "LegalServiceError", code: "XX000" }),
      expect.objectContaining({ tags: { reason: "db_error" }, extra: { stage: "route" } }),
    );
    expect(JSON.stringify(h.report.mock.calls)).not.toContain(EMAIL);
  });
});

describe("decide", () => {
  const recorded = (choice: string) => ({
    data: { outcome: "recorded", choice, text_hash: HASH, decided_at: "2026-11-05T10:00:00Z", reauth_at: choice === "accept" ? "2026-11-05T09:58:00Z" : null },
    error: null,
  });

  it("accept records on the USER client only and returns the typed result; the service client is not used", async () => {
    h.userRpc.mockResolvedValue(recorded("accept"));
    const out = await json(await decide(req("decide", { choice: "accept", textHash: HASH })));
    expect(out).toEqual({ status: 200, body: { outcome: "recorded", choice: "accept", decidedAt: "2026-11-05T10:00:00Z", reauthAt: "2026-11-05T09:58:00Z" } });
    expect(h.userRpc).toHaveBeenCalledWith("record_legal_acceptance", { p_key: "fixture-terms", p_text_hash: HASH, p_choice: "accept", p_requested_edit: null });
    expect(h.serviceRpc).not.toHaveBeenCalled();
  });

  it("PR-D ack: a recorded decision is acknowledged AFTER the response, only once the flush returned true, with the user's id", async () => {
    h.userRpc.mockResolvedValue(recorded("accept"));
    h.flush.mockResolvedValue(true);
    h.serviceRpc.mockResolvedValue({ data: { outcome: "acked" }, error: null });
    const out = await json(await decide(req("decide", { choice: "accept", textHash: HASH })));
    expect(out.body.outcome).toBe("recorded");
    await vi.waitFor(() =>
      expect(h.serviceRpc).toHaveBeenCalledWith("ack_legal_acceptance", { p_founder_id: USER, p_key: "fixture-terms", p_text_hash: HASH }),
    );
    expect(h.flush).toHaveBeenCalledWith(2000);
  });

  it("PR-D ack: the decide route hands the flush-then-ack task to next/server after() (not run inline, not dropped)", async () => {
    h.after.mockReset();
    h.userRpc.mockResolvedValue(recorded("accept"));
    h.flush.mockResolvedValue(true);
    h.serviceRpc.mockResolvedValue({ data: { outcome: "acked" }, error: null });
    expect((await json(await decide(req("decide", { choice: "accept", textHash: HASH })))).body.outcome).toBe("recorded");
    expect(h.after).toHaveBeenCalledTimes(1);
    expect(typeof h.after.mock.calls[0][0]).toBe("function");
    await vi.waitFor(() =>
      expect(h.serviceRpc).toHaveBeenCalledWith("ack_legal_acceptance", { p_founder_id: USER, p_key: "fixture-terms", p_text_hash: HASH }),
    );
    // already_recorded schedules nothing
    h.after.mockReset();
    h.userRpc.mockResolvedValue({ data: { outcome: "already_recorded", choice: "accept" }, error: null });
    await json(await decide(req("decide", { choice: "accept", textHash: HASH })));
    expect(h.after).not.toHaveBeenCalled();
  });

  it("PR-D ack: the ack carries the key and hash of the decision it follows (two keys: a hard-coded key or hash fails)", async () => {
    h.flush.mockResolvedValue(true);
    h.serviceRpc.mockResolvedValue({ data: { outcome: "acked" }, error: null });
    for (const [key, hash] of [["fixture-terms", HASH], ["fixture-other", HASH_OTHER]] as const) {
      h.serviceRpc.mockClear();
      h.userRpc.mockResolvedValue({
        data: { outcome: "recorded", choice: "accept", text_hash: hash, decided_at: "2026-11-05T10:00:00Z", reauth_at: "2026-11-05T09:58:00Z" },
        error: null,
      });
      expect((await json(await decide(req("decide", { choice: "accept", textHash: hash }, { key })))).body.outcome).toBe("recorded");
      expect(h.userRpc).toHaveBeenLastCalledWith("record_legal_acceptance", { p_key: key, p_text_hash: hash, p_choice: "accept", p_requested_edit: null });
      await vi.waitFor(() => expect(h.serviceRpc).toHaveBeenCalledTimes(1));
      expect(h.serviceRpc.mock.calls).toEqual([["ack_legal_acceptance", { p_founder_id: USER, p_key: key, p_text_hash: hash }]]);
    }
  });

  it("PR-D ack: a flush that returns false writes no ack; a flush that never resolves does not delay the response", async () => {
    h.userRpc.mockResolvedValue(recorded("accept"));
    h.flush.mockResolvedValue(false);
    expect((await json(await decide(req("decide", { choice: "accept", textHash: HASH })))).body.outcome).toBe("recorded");
    await vi.waitFor(() => expect(h.flush).toHaveBeenCalledTimes(1));
    h.flush.mockImplementation(() => new Promise<boolean>(() => {}));
    const out = await json(await decide(req("decide", { choice: "accept", textHash: HASH })));
    expect(out.status).toBe(200); // returned although the flush is still pending
    expect(h.serviceRpc).not.toHaveBeenCalledWith("ack_legal_acceptance", expect.anything());
  });

  it("PR-D ack: a flush that throws and an ack that errors leave the response unchanged and are reported as store_failed", async () => {
    h.userRpc.mockResolvedValue(recorded("accept"));
    h.flush.mockRejectedValue(new Error("transport"));
    const out = await json(await decide(req("decide", { choice: "accept", textHash: HASH })));
    expect(out.status).toBe(200);
    await vi.waitFor(() => expect(h.report.mock.calls.some((c) => c[0] === "storeFailed")).toBe(true));
    expect(h.report.mock.calls.some((c) => c[0] === "decideRejected")).toBe(false);
  });

  it("PR-D ack: already_recorded never flushes or acks", async () => {
    h.userRpc.mockResolvedValue({ data: { outcome: "already_recorded", choice: "accept" }, error: null });
    h.flush.mockResolvedValue(true);
    await json(await decide(req("decide", { choice: "accept", textHash: HASH })));
    await new Promise((r) => setTimeout(r, 20));
    expect(h.flush).not.toHaveBeenCalled();
    expect(h.serviceRpc).not.toHaveBeenCalledWith("ack_legal_acceptance", expect.anything());
  });

  it("request_changes opens the intent (service) then records the trimmed note (user)", async () => {
    h.userRpc.mockResolvedValue(recorded("request_changes"));
    const out = await json(await decide(req("decide", { choice: "request_changes", textHash: HASH, note: "  clause 2 please  " })));
    expect(out.body.outcome).toBe("recorded");
    expect(h.serviceRpc).toHaveBeenCalledWith("issue_legal_reauth", expect.objectContaining({ p_user_id: USER, p_session_id: SESSION, p_resend: false }));
    expect(h.userRpc).toHaveBeenCalledWith("record_legal_acceptance", expect.objectContaining({ p_requested_edit: "clause 2 please" }));
  });

  it("malformed bodies are 400: bad choice, bad hash, missing or too-long or stray note", async () => {
    for (const body of [
      { choice: "maybe", textHash: HASH },
      { choice: "accept" },
      { choice: "accept", textHash: "xyz" },
      { choice: "request_changes", textHash: HASH },
      { choice: "request_changes", textHash: HASH, note: "   " },
      { choice: "request_changes", textHash: HASH, note: "a".repeat(1001) },
      { choice: "decline", textHash: HASH, note: "stray" },
    ]) {
      expect((await json(await decide(req("decide", body)))).status, JSON.stringify(body).slice(0, 60)).toBe(400);
    }
    expect(h.userRpc).not.toHaveBeenCalled();
  });

  it("a hash that is not the registry's is {outcome:'replaced'} with HTTP 200 and nothing is recorded", async () => {
    const out = await json(await decide(req("decide", { choice: "accept", textHash: "f".repeat(64) })));
    expect(out).toEqual({ status: 200, body: { outcome: "replaced" } });
    expect(h.userRpc).not.toHaveBeenCalled();
    expect(h.serviceRpc).not.toHaveBeenCalled();
  });

  it("42501 from the database is HTTP 403 {error:'reverify'}, not a 200 code_expired, and is labelled denied_42501", async () => {
    h.userRpc.mockResolvedValue({ data: null, error: { message: "legal acceptance: no live intent", code: "42501" } });
    expect(await json(await decide(req("decide", { choice: "accept", textHash: HASH })))).toEqual({ status: 403, body: { error: "reverify" } });
    expect(h.report).toHaveBeenCalledWith("decideRejected", expect.anything(), expect.objectContaining({ tags: { reason: "denied_42501" } }));
  });

  it.each(["already_recorded", "replaced", "expired", "code_expired"])("SQL outcome %s is a 200 result", async (outcome) => {
    h.userRpc.mockResolvedValue({ data: { outcome, choice: "accept" }, error: null });
    const out = await json(await decide(req("decide", { choice: "accept", textHash: HASH })));
    expect(out.status).toBe(200);
    expect(out.body.outcome).toBe(outcome);
  });

  it("a database error is a static 500 and nothing is reported with the note", async () => {
    h.serviceRpc.mockResolvedValue({ data: null, error: { message: "boom PRIVATE-NOTE", code: "XX000" } });
    const out = await json(await decide(req("decide", { choice: "request_changes", textHash: HASH, note: "PRIVATE-NOTE" })));
    expect(out).toEqual({ status: 500, body: { error: "Internal error" } });
    expect(JSON.stringify(h.report.mock.calls)).not.toContain("PRIVATE-NOTE");
  });

  it("the catch reports the caught error and labels a database failure db_error", async () => {
    h.serviceRpc.mockResolvedValue({ data: null, error: { message: "boom", code: "XX000" } });
    await decide(req("decide", { choice: "decline", textHash: HASH }));
    const call = h.report.mock.calls.find((c) => c[0] === "decideRejected");
    expect(call?.[1]).toMatchObject({ name: "LegalServiceError", code: "XX000" });
    expect(call?.[2]).toMatchObject({ tags: { reason: "db_error" } });
  });

  it("a non-database failure is reported with the error and a non-db_error reason (decide and reauth)", async () => {
    h.clientFails.value = true;
    expect((await json(await decide(req("decide", { choice: "accept", textHash: HASH })))).status).toBe(500);
    const d = h.report.mock.calls.find((c) => c[0] === "decideRejected");
    expect(d?.[1]).toBeInstanceOf(TypeError);
    expect(d?.[2]).toMatchObject({ tags: { reason: "unexpected" } });

    h.report.mockReset();
    expect((await json(await reauth(req("reauth", { step: "send" })))).status).toBe(500);
    const r = h.report.mock.calls.find((c) => c[0] === "reauthFailed");
    expect(r?.[1]).toBeInstanceOf(TypeError);
    expect(r?.[2]).toMatchObject({ tags: { reason: "unexpected" }, extra: { stage: "route" } });
  });

  it("a body over the cap is 413 before it is parsed (content-length and a streamed body without one)", async () => {
    const big = JSON.stringify({ choice: "decline", textHash: HASH, pad: "x".repeat(9000) });
    expect((await json(await decide(req("decide", null, { raw: big })))).status).toBe(413);
    const streamed = new Request("https://app.soleur.ai/api/legal-acceptance/fixture-terms/decide", {
      method: "POST",
      headers: { "content-type": "application/json", origin: "https://app.soleur.ai" },
      body: new ReadableStream({
        start(c) {
          c.enqueue(new TextEncoder().encode(big));
          c.close();
        },
      }),
      // @ts-expect-error duplex is required by undici for a stream body
      duplex: "half",
    });
    expect((await json(await decide(streamed))).status).toBe(413);
    expect(h.serviceRpc).not.toHaveBeenCalled();
  });
});
