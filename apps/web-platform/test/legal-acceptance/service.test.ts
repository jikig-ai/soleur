/**
 * #12011 PR-C workstream A: the legal-acceptance service layer (issue, claim, mark, record), the email-code check on a
 * throwaway auth client, the identity derivation (session id exactly as the SQL reads it) and the per-user ceiling.
 * All fixtures are synthesized; no real address, code or text.
 */
import { beforeEach, describe, expect, it, vi } from "vitest";

const h = vi.hoisted(() => ({ report: vi.fn(), warnSink: vi.fn(), errSink: vi.fn() }));
vi.mock("@/server/observability", () => ({
  warnSilentFallback: (...a: unknown[]) => h.warnSink(...a),
  reportSilentFallback: (...a: unknown[]) => h.errSink(...a),
}));
vi.mock("@/server/approval/ops", async (orig) => ({
  ...(await orig<typeof import("@/server/approval/ops")>()),
  reportLegalOp: (...a: unknown[]) => h.report(...a),
}));

import { parseLegalText } from "@/server/legal-acceptance/canonical";
import {
  AttemptCeiling,
  CODE_RE,
  SendFailureMemory,
  SEND_FAILURE_TTL_MS,
  createThrowawayAuthClient,
  readCappedBody,
  resolveIdentity,
  sendReauthCode,
  tokenFacts,
  verifyReauthCode,
  type Identity,
  type ThrowawayAuthClient,
} from "@/server/legal-acceptance/reauth";
import { decideLegal, LegalServiceError, normaliseNote, recordAcceptance, type LegalRpcClient } from "@/server/legal-acceptance/service";

const USER = "00000000-0000-4000-8000-0000000000aa";
const EMAIL = "founder.fixture@example.invalid";
const SESSION = "11111111-1111-4111-8111-111111111111";
const EVENT = "22222222-2222-4222-8222-222222222222";
const ENTRY = parseLegalText("fixture-terms", "---\nversion: fx-1\n---\nSynthesized fixture text.\n");
const ID: Extract<Identity, { ok: true }> = { ok: true, userId: USER, email: EMAIL, sessionId: SESSION };

const jwt = (payload: Record<string, unknown>) =>
  `${Buffer.from('{"alg":"none"}').toString("base64url")}.${Buffer.from(JSON.stringify(payload)).toString("base64url")}.sig`;

/** A fake rpc client: per-function queue of results, plus a shared ordered call log. */
function fakeRpc(log: string[], results: Record<string, Array<{ data?: unknown; error?: { message: string; code?: string } | null }>>) {
  const calls: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const client: LegalRpcClient = {
    async rpc(fn, args = {}) {
      log.push(`rpc:${fn}`);
      calls.push({ fn, args });
      const r = results[fn]?.shift();
      if (!r) throw new Error(`unexpected rpc ${fn}`);
      return { data: r.data ?? null, error: r.error ?? null };
    },
  };
  return { client, calls };
}

function fakeAuth(
  log: string[],
  o: {
    send?: () => { error: unknown } | Promise<{ error: unknown }>;
    verify?: () => { error: unknown } | Promise<{ error: unknown }>;
    signOut?: () => { error: unknown } | Promise<{ error: unknown }>;
  } = {},
) {
  const spies = {
    signInWithOtp: vi.fn(async (_a: unknown) => {
      log.push("auth:send");
      return (o.send ? await o.send() : { error: null }) as { error: null };
    }),
    verifyOtp: vi.fn(async (_a: unknown) => {
      log.push("auth:verify");
      return (o.verify ? await o.verify() : { error: null }) as { error: null };
    }),
    signOut: vi.fn(async (_a: unknown) => {
      log.push("auth:signOut");
      return (o.signOut ? await o.signOut() : { error: null }) as { error: null };
    }),
  };
  const client = { auth: spies } as unknown as ThrowawayAuthClient;
  return { client, spies, factory: vi.fn(() => client) };
}

beforeEach(() => h.report.mockReset());

describe("session id and audience: derived exactly as the SQL reads them", () => {
  it("session_id wins; ses_id is the fallback; an empty string means absent and does NOT fall through (COALESCE then NULLIF)", () => {
    expect(tokenFacts(jwt({ sub: USER, aud: "authenticated", session_id: "s1", ses_id: "s2" })).sessionId).toBe("s1");
    expect(tokenFacts(jwt({ sub: USER, aud: "authenticated", ses_id: "s2" })).sessionId).toBe("s2");
    expect(tokenFacts(jwt({ aud: "authenticated", session_id: null, ses_id: "s2" })).sessionId).toBe("s2");
    expect(tokenFacts(jwt({ aud: "authenticated", session_id: "", ses_id: "s2" })).sessionId).toBeNull();
    expect(tokenFacts(jwt({ aud: "authenticated", ses_id: "" })).sessionId).toBeNull();
    expect(tokenFacts(jwt({ aud: "authenticated" })).sessionId).toBeNull();
    expect(tokenFacts(jwt({ aud: "authenticated", session_id: { a: 1 } })).sessionId).toBeNull();
    expect(tokenFacts("not-a-jwt").sessionId).toBeNull();
  });

  const client = (token: string | null, user: { id: string; email?: string } | null = { id: USER, email: EMAIL }) => ({
    auth: {
      getUser: async () => ({ data: { user }, error: null }),
      getSession: async () => ({ data: { session: token ? { access_token: token } : null }, error: null }),
    },
  });

  it("a verified web token gives the founder id, email and session id", async () => {
    const id = await resolveIdentity(client(jwt({ sub: USER, aud: "authenticated", session_id: SESSION })), USER);
    expect(id).toEqual({ ok: true, userId: USER, email: EMAIL, sessionId: SESSION });
  });

  it("refuses (403) a token whose audience is not exactly 'authenticated': a runtime token never opens an intent", async () => {
    // "soleur-runtime" is the real agent-token audience (lib/supabase/tenant.ts JWT_AUDIENCE)
    for (const aud of ["soleur-runtime", "Authenticated", ["authenticated"], undefined]) {
      const id = await resolveIdentity(client(jwt({ sub: USER, aud, session_id: SESSION })), USER);
      expect(id, JSON.stringify(aud)).toMatchObject({ ok: false, status: 403 });
    }
  });

  it("an absent session id, no session, no user, or a user that is not the wrapper's user is a 401", async () => {
    expect(await resolveIdentity(client(jwt({ sub: USER, aud: "authenticated", session_id: "" })), USER)).toMatchObject({ ok: false, status: 401 });
    expect(await resolveIdentity(client(null), USER)).toMatchObject({ ok: false, status: 401 });
    expect(await resolveIdentity(client(jwt({ sub: USER, aud: "authenticated", session_id: SESSION }), null), USER)).toMatchObject({ ok: false, status: 401 });
    expect(await resolveIdentity(client(jwt({ sub: USER, aud: "authenticated", session_id: SESSION })), "someone-else")).toMatchObject({ ok: false, status: 401 });
    // token sub disagreeing with getUser
    expect(await resolveIdentity(client(jwt({ sub: "other", aud: "authenticated", session_id: SESSION })), USER)).toMatchObject({ ok: false, status: 401 });
  });

  it("a rejecting or stalled auth service is a 401 (the bounded helpers), never a throw and never a hang", async () => {
    vi.stubEnv("SOLEUR_AUTH_GETUSER_TIMEOUT_MS", "25");
    try {
      const token = jwt({ sub: USER, aud: "authenticated", session_id: SESSION });
      const base = client(token);
      const rejectUser = { auth: { ...base.auth, getUser: async () => { throw new Error("down"); } } };
      const stallUser = { auth: { ...base.auth, getUser: () => new Promise<never>(() => {}) } };
      const rejectSession = { auth: { ...base.auth, getSession: async () => { throw new Error("down"); } } };
      const stallSession = { auth: { ...base.auth, getSession: () => new Promise<never>(() => {}) } };
      for (const c of [rejectUser, stallUser, rejectSession, stallSession]) {
        expect(await resolveIdentity(c as unknown as Parameters<typeof resolveIdentity>[0], USER)).toMatchObject({ ok: false, status: 401 });
      }
    } finally {
      vi.unstubAllEnvs();
    }
  });
});

describe("per-user verify ceiling", () => {
  it("allows 10 per 15 minutes per user across keys, then refuses; the window slides on the injected clock", () => {
    let t = 1_000_000;
    const c = new AttemptCeiling(10, 15 * 60_000, () => t);
    for (let i = 0; i < 10; i++) expect(c.consume(USER)).toBe(true);
    expect(c.consume(USER)).toBe(false);
    expect(c.consume("other-user")).toBe(true); // per user, not global
    t += 15 * 60_000 + 1;
    expect(c.consume(USER)).toBe(true);
  });
  it("a refused attempt is not counted (it does not extend the lockout)", () => {
    let t = 0;
    const c = new AttemptCeiling(2, 1000, () => t);
    expect(c.consume("u")).toBe(true);
    t = 500;
    expect(c.consume("u")).toBe(true);
    t = 900;
    expect(c.consume("u")).toBe(false);
    t = 1001; // the first hit has left the window
    expect(c.consume("u")).toBe(true);
  });
  it("crosses the sweep threshold: idle users' entries are dropped, live ones kept (the map does not grow without bound)", () => {
    let t = 0;
    const store = new Map<string, number[]>();
    for (let i = 0; i < 5_000; i++) store.set(`idle-${i}`, [1]);
    const c = new AttemptCeiling(10, 1000, () => t, store);
    t = 10_000;
    expect(c.consume("live")).toBe(true); // size is now 5001: over the threshold, so the sweep runs
    expect(store.size).toBe(1);
    expect(store.has("live")).toBe(true);
  });
});

describe("send", () => {
  const issued = { data: { outcome: "issued", reused: false, event_id: EVENT, expires_at: "2099-01-01T00:00:00Z" } };

  it("issues the intent with the registry version and hash, then emails the code; resend is passed through", async () => {
    const log: string[] = [];
    const svc = fakeRpc(log, { issue_legal_reauth: [issued, issued] });
    const auth = fakeAuth(log);
    const deps = { service: svc.client, authClient: auth.factory };
    expect(await sendReauthCode(deps, { id: ID, entry: ENTRY, resend: false })).toEqual({ ok: true, state: "sent" });
    expect(await sendReauthCode(deps, { id: ID, entry: ENTRY, resend: true })).toEqual({ ok: true, state: "sent" });
    expect(svc.calls[0].args).toEqual({
      p_user_id: USER, p_key: "fixture-terms", p_text_hash: ENTRY.textHash, p_version: "fx-1", p_session_id: SESSION, p_resend: false,
    });
    expect(svc.calls[1].args.p_resend).toBe(true);
    expect(auth.spies.signInWithOtp).toHaveBeenCalledWith({ email: EMAIL, options: { shouldCreateUser: false } });
    expect(log.slice(0, 2)).toEqual(["rpc:issue_legal_reauth", "auth:send"]);
  });

  it("an expired or replaced text sends nothing and issues nothing", async () => {
    const log: string[] = [];
    const old = parseLegalText("fixture-terms", "---\nversion: fx-1\nvalid_until: 2020-01-01\n---\nx\n");
    const auth = fakeAuth(log);
    const r = await sendReauthCode({ service: fakeRpc(log, {}).client, authClient: auth.factory }, { id: ID, entry: old, resend: false });
    expect(r).toEqual({ ok: false, reason: "replaced" });
    expect(log).toEqual([]);
  });

  it("already_recorded and rate_limited from the database come back typed and the email is not sent", async () => {
    const log: string[] = [];
    const auth = fakeAuth(log);
    const svc = fakeRpc(log, { issue_legal_reauth: [{ data: { outcome: "already_recorded", choice: "accept" } }, { data: { outcome: "rate_limited" } }] });
    const deps = { service: svc.client, authClient: auth.factory };
    expect(await sendReauthCode(deps, { id: ID, entry: ENTRY, resend: false })).toEqual({ ok: false, reason: "already_recorded" });
    expect(await sendReauthCode(deps, { id: ID, entry: ENTRY, resend: true })).toEqual({ ok: false, reason: "rate_limited" });
    expect(auth.spies.signInWithOtp).not.toHaveBeenCalled();
  });

  const sendWith = async (
    send: () => { error: unknown },
    o: { reused?: boolean; resend?: boolean; id?: Identity & { ok: true }; sendFailures?: SendFailureMemory } = {},
  ) => {
    const log: string[] = [];
    const row = { data: { outcome: "issued", reused: o.reused === true, event_id: EVENT, expires_at: "2099-01-01T00:00:00Z" } };
    const svc = fakeRpc(log, { issue_legal_reauth: [row] });
    const auth = fakeAuth(log, { send });
    const r = await sendReauthCode(
      { service: svc.client, authClient: auth.factory, sendFailures: o.sendFailures ?? new SendFailureMemory() },
      { id: o.id ?? ID, entry: ENTRY, resend: o.resend === true },
    );
    return { r, auth };
  };
  const unknownUser = () => ({ error: { name: "AuthApiError", status: 422, code: "otp_disabled", message: EMAIL } });

  it("the auth service's 422 otp_disabled (unknown address) is returned identically to a successful send, and reported at warn level with its class only", async () => {
    const known = (await sendWith(() => ({ error: null }))).r;
    h.report.mockReset();
    const unknown = (await sendWith(unknownUser)).r;
    expect(unknown).toEqual(known);
    expect(unknown).toEqual({ ok: true, state: "sent" });
    expect(h.report).toHaveBeenCalledTimes(1);
    expect(h.report).toHaveBeenCalledWith(
      "reauthFailed",
      null,
      expect.objectContaining({ level: "warn", extra: { stage: "send_422", errorClass: "AuthApiError:422:otp_disabled" } }),
    );
    expect(JSON.stringify(h.report.mock.calls)).not.toContain(EMAIL);
  });

  it("any other 422 is NOT a sent: unavailable, reported at error level (no level override) with its class", async () => {
    const { r } = await sendWith(() => ({ error: { name: "AuthApiError", status: 422, code: "validation_failed", message: EMAIL } }));
    expect(r).toEqual({ ok: false, reason: "unavailable" });
    expect(h.report).toHaveBeenCalledTimes(1);
    const ctx = h.report.mock.calls[0][2];
    expect(ctx.level).toBeUndefined();
    expect(ctx.extra.errorClass).toBe("AuthApiError:422:validation_failed");
    expect(JSON.stringify(h.report.mock.calls)).not.toContain(EMAIL);
  });

  it("the auth service's 429 is rate_limited and is NOT reported as an error-level reauth_failed", async () => {
    const { r } = await sendWith(() => ({ error: { name: "AuthApiError", status: 429, code: "over_email_send_rate_limit", message: EMAIL } }));
    expect(r).toEqual({ ok: false, reason: "rate_limited" });
    expect(h.report).not.toHaveBeenCalled();
  });

  it("a real send failure (5xx, a throw) is unavailable and reported with a class, never the address", async () => {
    for (const send of [
      () => ({ error: { name: "AuthRetryableFetchError", status: 503, message: `down for ${EMAIL}` } }),
      () => {
        throw new Error(`network ${EMAIL}`);
      },
    ]) {
      h.report.mockReset();
      const { r } = await sendWith(send);
      expect(r).toEqual({ ok: false, reason: "unavailable" });
      expect(h.report).toHaveBeenCalledTimes(1);
      expect(h.report.mock.calls[0][0]).toBe("reauthFailed");
      expect(JSON.stringify(h.report.mock.calls[0])).not.toContain(EMAIL);
      expect(JSON.stringify(h.report.mock.calls[0])).toMatch(/errorClass/);
    }
  });

  it("a reused intent without a resend is 'sent' and sends NO email (the earlier code is still valid); a resend does email", async () => {
    const reusedNoResend = await sendWith(() => ({ error: null }), { reused: true, resend: false });
    expect(reusedNoResend.r).toEqual({ ok: true, state: "sent" });
    expect(reusedNoResend.auth.spies.signInWithOtp).not.toHaveBeenCalled();
    const reusedResend = await sendWith(() => ({ error: null }), { reused: true, resend: true });
    expect(reusedResend.r).toEqual({ ok: true, state: "sent" });
    expect(reusedResend.auth.spies.signInWithOtp).toHaveBeenCalledTimes(1);
    const fresh = await sendWith(() => ({ error: null }), { reused: false, resend: false });
    expect(fresh.auth.spies.signInWithOtp).toHaveBeenCalledTimes(1);
  });

  it("a plain send after a FAILED send mails again (the reused-intent skip never claims a code that was not sent); success clears it", async () => {
    const mem = new SendFailureMemory();
    const failures: Array<() => { error: unknown }> = [
      () => ({ error: { name: "AuthRetryableFetchError", status: 503, message: "down" } }),
      () => ({ error: { name: "AuthApiError", status: 429, code: "over_email_send_rate_limit", message: "slow" } }),
      () => ({ error: { name: "AuthApiError", status: 422, code: "validation_failed", message: "bad" } }),
      () => {
        throw new Error("network");
      },
    ];
    for (const fail of failures) {
      const first = await sendWith(fail, { reused: false, resend: false, sendFailures: mem });
      expect(first.r.ok).toBe(false);
      // The intent is still live, so the database now says reused; the retry is a plain send and MUST email.
      const retry = await sendWith(() => ({ error: null }), { reused: true, resend: false, sendFailures: mem });
      expect(retry.r).toEqual({ ok: true, state: "sent" });
      expect(retry.auth.spies.signInWithOtp).toHaveBeenCalledTimes(1);
      // Cleared by the success: the next plain send on a reused intent skips the mail again.
      const after = await sendWith(() => ({ error: null }), { reused: true, resend: false, sendFailures: mem });
      expect(after.auth.spies.signInWithOtp).not.toHaveBeenCalled();
    }
  });

  it("a failed send with no address is remembered too; a failure for one key or user never forces a mail for another", async () => {
    const mem = new SendFailureMemory();
    await sendWith(() => ({ error: null }), { id: { ...ID, email: null }, sendFailures: mem });
    const same = await sendWith(() => ({ error: null }), { reused: true, resend: false, sendFailures: mem });
    expect(same.auth.spies.signInWithOtp).toHaveBeenCalledTimes(1);
    await sendWith(() => ({ error: { status: 503 } }), { sendFailures: mem });
    const otherUser = await sendWith(() => ({ error: null }), {
      reused: true,
      resend: false,
      sendFailures: mem,
      id: { ...ID, userId: "00000000-0000-4000-8000-0000000000bb" },
    });
    expect(otherUser.auth.spies.signInWithOtp).not.toHaveBeenCalled();
  });

  it("the remembered failure expires with the intent window", () => {
    let t = 1_000;
    const mem = new SendFailureMemory(() => t);
    mem.mark(USER, "fixture-terms");
    expect(mem.has(USER, "fixture-terms")).toBe(true);
    t += SEND_FAILURE_TTL_MS - 1;
    expect(mem.has(USER, "fixture-terms")).toBe(true);
    t += 2;
    expect(mem.has(USER, "fixture-terms")).toBe(false);
  });

  it("an auth client factory that throws (anon key missing) on SEND is unavailable and reported (stage send), not a thrown 500; the retry then mails again", async () => {
    const mem = new SendFailureMemory();
    const log: string[] = [];
    const row = { data: { outcome: "issued", reused: false, event_id: EVENT, expires_at: "2099-01-01T00:00:00Z" } };
    const svc = fakeRpc(log, { issue_legal_reauth: [row, { data: { ...row.data, reused: true } }] });
    const boom = new Error(`anon key is not configured for ${EMAIL}`);
    const factory = vi.fn(() => {
      throw boom;
    });
    const r = await sendReauthCode({ service: svc.client, authClient: factory, sendFailures: mem }, { id: ID, entry: ENTRY, resend: false });
    expect(r).toEqual({ ok: false, reason: "unavailable" });
    expect(factory).toHaveBeenCalledTimes(1);
    expect(h.report).toHaveBeenCalledTimes(1);
    expect(h.report).toHaveBeenCalledWith("reauthFailed", boom, expect.objectContaining({ userId: USER, extra: expect.objectContaining({ stage: "send" }) }));
    const ctx = h.report.mock.calls[0][2];
    expect(ctx.level).toBeUndefined();
    expect(JSON.stringify(ctx)).not.toContain(EMAIL);
    // No code was sent, so the next plain send on the still-live intent must mail (the failure is remembered).
    const auth = fakeAuth(log);
    const retry = await sendReauthCode({ service: svc.client, authClient: auth.factory, sendFailures: mem }, { id: ID, entry: ENTRY, resend: false });
    expect(retry).toEqual({ ok: true, state: "sent" });
    expect(auth.spies.signInWithOtp).toHaveBeenCalledTimes(1);
  });

  it("no address on the session: unavailable, reported (stage send_no_address), nothing is emailed", async () => {
    const { r, auth } = await sendWith(() => ({ error: null }), { id: { ...ID, email: null } });
    expect(r).toEqual({ ok: false, reason: "unavailable" });
    expect(auth.spies.signInWithOtp).not.toHaveBeenCalled();
    expect(h.report).toHaveBeenCalledWith("reauthFailed", null, expect.objectContaining({ extra: expect.objectContaining({ stage: "send_no_address" }) }));
  });
});

describe("verify", () => {
  const allowed = { data: { outcome: "allowed", event_id: EVENT, attempts: 1 } };

  it("counts the attempt in the database BEFORE the auth service is asked, verifies on the throwaway client, discards its session, then marks verified with the claimed event id", async () => {
    const log: string[] = [];
    const svc = fakeRpc(log, { claim_legal_reauth_attempt: [allowed], mark_legal_reauth_verified: [{ data: { outcome: "verified" } }] });
    const auth = fakeAuth(log);
    const r = await verifyReauthCode({ service: svc.client, authClient: auth.factory, ceiling: new AttemptCeiling() }, { id: ID, entry: ENTRY, code: "123456" });
    expect(r).toEqual({ ok: true });
    expect(log).toEqual(["rpc:claim_legal_reauth_attempt", "auth:verify", "auth:signOut", "rpc:mark_legal_reauth_verified"]);
    expect(auth.spies.verifyOtp).toHaveBeenCalledWith({ email: EMAIL, token: "123456", type: "email" });
    // local scope: the default (global) would end the founder's own sessions
    expect(auth.spies.signOut).toHaveBeenCalledWith({ scope: "local" });
    expect(svc.calls[1].args).toEqual({ p_user_id: USER, p_event_id: EVENT, p_key: "fixture-terms", p_text_hash: ENTRY.textHash, p_session_id: SESSION });
  });

  it.each([
    ["locked", "locked"],
    ["code_stale", "code_stale"],
    ["expired", "expired"],
    ["replaced", "replaced"],
    ["not_found", "replaced"],
  ])("claim outcome %s maps to %s without asking the auth service", async (outcome, reason) => {
    const log: string[] = [];
    const svc = fakeRpc(log, { claim_legal_reauth_attempt: [{ data: { outcome } }] });
    const auth = fakeAuth(log);
    const r = await verifyReauthCode({ service: svc.client, authClient: auth.factory, ceiling: new AttemptCeiling() }, { id: ID, entry: ENTRY, code: "123456" });
    expect(r).toEqual({ ok: false, reason });
    expect(auth.spies.verifyOtp).not.toHaveBeenCalled();
  });

  it("a wrong code (403 from the auth service) is wrong_code, the session is still discarded, and nothing is marked", async () => {
    const log: string[] = [];
    const svc = fakeRpc(log, { claim_legal_reauth_attempt: [allowed] });
    const auth = fakeAuth(log, { verify: () => ({ error: { name: "AuthApiError", status: 403, code: "otp_expired" } }) });
    const r = await verifyReauthCode({ service: svc.client, authClient: auth.factory, ceiling: new AttemptCeiling() }, { id: ID, entry: ENTRY, code: "654321" });
    expect(r).toEqual({ ok: false, reason: "wrong_code" });
    expect(auth.spies.signOut).toHaveBeenCalledWith({ scope: "local" });
    expect(log).not.toContain("rpc:mark_legal_reauth_verified");
    expect(h.report).not.toHaveBeenCalled();
  });

  it("an auth outage on verify is unavailable (reported with a class), the session is discarded, and nothing is marked", async () => {
    for (const verify of [
      () => ({ error: { name: "AuthRetryableFetchError", status: 502 } }),
      () => {
        throw new Error("boom");
      },
    ]) {
      h.report.mockReset();
      const log: string[] = [];
      const svc = fakeRpc(log, { claim_legal_reauth_attempt: [allowed] });
      const auth = fakeAuth(log, { verify });
      const r = await verifyReauthCode({ service: svc.client, authClient: auth.factory, ceiling: new AttemptCeiling() }, { id: ID, entry: ENTRY, code: "123456" });
      expect(r).toEqual({ ok: false, reason: "unavailable" });
      expect(auth.spies.signOut).toHaveBeenCalledWith({ scope: "local" });
      expect(h.report.mock.calls[0][0]).toBe("reauthFailed");
      expect(log).not.toContain("rpc:mark_legal_reauth_verified");
    }
  });

  it("the OTP code never appears in any reported event (auth outage, a 5xx, a throw that echoes it)", async () => {
    const CODE = "918273";
    for (const verify of [
      () => ({ error: { name: "AuthRetryableFetchError", status: 502, message: `bad gateway for ${CODE}` } }),
      () => {
        throw new Error(`network ${CODE}`);
      },
      () => ({ error: { name: "AuthApiError", status: 400, code: "validation_failed", message: CODE } }),
    ]) {
      h.report.mockReset();
      const log: string[] = [];
      const svc = fakeRpc(log, { claim_legal_reauth_attempt: [allowed] });
      await verifyReauthCode({ service: svc.client, authClient: fakeAuth(log, { verify }).factory, ceiling: new AttemptCeiling() }, { id: ID, entry: ENTRY, code: CODE });
      expect(h.report).toHaveBeenCalled();
      expect(JSON.stringify(h.report.mock.calls)).not.toContain(CODE);
      expect(JSON.stringify(h.report.mock.calls)).not.toContain(EMAIL);
    }
  });

  it("a 400 or 422 from the auth service is wrong_code but is made visible with a warn-level report (class only)", async () => {
    for (const status of [400, 422]) {
      h.report.mockReset();
      const log: string[] = [];
      const svc = fakeRpc(log, { claim_legal_reauth_attempt: [allowed] });
      const auth = fakeAuth(log, { verify: () => ({ error: { name: "AuthApiError", status, code: "validation_failed" } }) });
      const r = await verifyReauthCode({ service: svc.client, authClient: auth.factory, ceiling: new AttemptCeiling() }, { id: ID, entry: ENTRY, code: "123456" });
      expect(r).toEqual({ ok: false, reason: "wrong_code" });
      expect(h.report).toHaveBeenCalledWith(
        "reauthFailed",
        null,
        expect.objectContaining({ level: "warn", extra: { stage: "verify_rejected", errorClass: `AuthApiError:${status}:validation_failed` } }),
      );
    }
  });

  it("a client factory that throws (anon key missing) is unavailable and reported, not a thrown 500", async () => {
    const log: string[] = [];
    const svc = fakeRpc(log, {});
    const factory = vi.fn(() => {
      throw new Error("anon key is not configured");
    });
    const r = await verifyReauthCode({ service: svc.client, authClient: factory, ceiling: new AttemptCeiling() }, { id: ID, entry: ENTRY, code: "123456" });
    expect(r).toEqual({ ok: false, reason: "unavailable" });
    expect(h.report).toHaveBeenCalledWith("reauthFailed", expect.any(Error), expect.objectContaining({ extra: expect.objectContaining({ stage: "verify_client" }) }));
  });

  it("the throwaway client refuses to be built without an anon key (our own guard, no silent empty-key fallback)", () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "");
    try {
      expect(() => createThrowawayAuthClient()).toThrow("auth anon key is not configured");
    } finally {
      vi.unstubAllEnvs();
    }
  });

  it("the client is built BEFORE the attempt is claimed or counted: a missing key burns no attempt", async () => {
    const log: string[] = [];
    const svc = fakeRpc(log, { claim_legal_reauth_attempt: [allowed] });
    const ceiling = new AttemptCeiling(1, 60_000, () => 0);
    const factory = vi.fn(() => {
      throw new Error("auth anon key is not configured");
    });
    const deps = { service: svc.client, authClient: factory, ceiling };
    expect(await verifyReauthCode(deps, { id: ID, entry: ENTRY, code: "123456" })).toEqual({ ok: false, reason: "unavailable" });
    // No database claim, and the per-user ceiling (max 1) was not consumed: the next call is not "locked".
    expect(log).toEqual([]);
    expect(await verifyReauthCode(deps, { id: ID, entry: ENTRY, code: "123456" })).toEqual({ ok: false, reason: "unavailable" });
    expect(h.report).toHaveBeenCalledWith("reauthFailed", expect.any(Error), expect.objectContaining({ extra: expect.objectContaining({ stage: "verify_client" }) }));
  });

  it("the code pattern is the wire module's range: 6 to 8 ASCII digits", () => {
    expect(CODE_RE.test("123456")).toBe(true);
    expect(CODE_RE.test("12345678")).toBe(true);
    expect(CODE_RE.test("12345")).toBe(false);
    expect(CODE_RE.test("123456789")).toBe(false);
    expect(CODE_RE.test("12345a")).toBe(false);
  });

  it("a signOut that rejects or errors never turns a good verify into a throw: the verify still succeeds and the failure is reported", async () => {
    for (const signOut of [
      () => {
        throw new Error("revoke blew up");
      },
      () => ({ error: { name: "AuthApiError", status: 500 } }),
    ]) {
      h.report.mockReset();
      const log: string[] = [];
      const svc = fakeRpc(log, { claim_legal_reauth_attempt: [allowed], mark_legal_reauth_verified: [{ data: { outcome: "verified" } }] });
      const auth = fakeAuth(log, { signOut });
      const r = await verifyReauthCode({ service: svc.client, authClient: auth.factory, ceiling: new AttemptCeiling() }, { id: ID, entry: ENTRY, code: "123456" });
      expect(r).toEqual({ ok: true });
      expect(h.report.mock.calls.some((c) => c[0] === "reauthFailed" && c[2].extra.stage === "discard")).toBe(true);
    }
  });

  it("even a throwing reporter inside the discard failure path cannot turn a good verify into a throw", async () => {
    h.report.mockReset();
    h.report.mockImplementation((_op: string, _e: unknown, ctx: { extra: { stage: string } }) => {
      if (ctx.extra.stage === "discard") throw new Error("reporter down");
    });
    try {
      const log: string[] = [];
      const svc = fakeRpc(log, { claim_legal_reauth_attempt: [allowed], mark_legal_reauth_verified: [{ data: { outcome: "verified" } }] });
      const auth = fakeAuth(log, {
        signOut: () => {
          throw new Error("revoke blew up");
        },
      });
      const r = await verifyReauthCode({ service: svc.client, authClient: auth.factory, ceiling: new AttemptCeiling() }, { id: ID, entry: ENTRY, code: "123456" });
      expect(r).toEqual({ ok: true });
    } finally {
      h.report.mockReset();
    }
  });

  it("the session is discarded even when mark_legal_reauth_verified throws", async () => {
    const log: string[] = [];
    const svc = fakeRpc(log, { claim_legal_reauth_attempt: [allowed], mark_legal_reauth_verified: [{ error: { message: "x", code: "XX000" } }] });
    const auth = fakeAuth(log);
    await expect(
      verifyReauthCode({ service: svc.client, authClient: auth.factory, ceiling: new AttemptCeiling() }, { id: ID, entry: ENTRY, code: "123456" }),
    ).rejects.toBeInstanceOf(LegalServiceError);
    expect(auth.spies.signOut).toHaveBeenCalledWith({ scope: "local" });
  });

  it("no address on the session: unavailable after the claim, reported (stage verify_no_address), the auth service is never asked", async () => {
    const log: string[] = [];
    const svc = fakeRpc(log, { claim_legal_reauth_attempt: [allowed] });
    const auth = fakeAuth(log);
    const r = await verifyReauthCode({ service: svc.client, authClient: auth.factory, ceiling: new AttemptCeiling() }, { id: { ...ID, email: null }, entry: ENTRY, code: "123456" });
    expect(r).toEqual({ ok: false, reason: "unavailable" });
    expect(auth.spies.verifyOtp).not.toHaveBeenCalled();
    expect(h.report).toHaveBeenCalledWith("reauthFailed", null, expect.objectContaining({ extra: expect.objectContaining({ stage: "verify_no_address" }) }));
  });

  it.each([
    ["not_claimed", "unavailable"],
    ["expired", "expired"],
    ["replaced", "replaced"],
    ["not_found", "replaced"],
  ])("mark outcome %s maps to %s", async (outcome, reason) => {
    const log: string[] = [];
    const svc = fakeRpc(log, { claim_legal_reauth_attempt: [allowed], mark_legal_reauth_verified: [{ data: { outcome } }] });
    const r = await verifyReauthCode({ service: svc.client, authClient: fakeAuth(log).factory, ceiling: new AttemptCeiling() }, { id: ID, entry: ENTRY, code: "123456" });
    expect(r).toEqual({ ok: false, reason });
  });

  it("a not_claimed mark is unavailable AND reported (stage mark_not_claimed, no level override)", async () => {
    const log: string[] = [];
    const svc = fakeRpc(log, { claim_legal_reauth_attempt: [allowed], mark_legal_reauth_verified: [{ data: { outcome: "not_claimed" } }] });
    const r = await verifyReauthCode({ service: svc.client, authClient: fakeAuth(log).factory, ceiling: new AttemptCeiling() }, { id: ID, entry: ENTRY, code: "123456" });
    expect(r).toEqual({ ok: false, reason: "unavailable" });
    const hit = h.report.mock.calls.filter((c) => c[0] === "reauthFailed" && c[2].extra.stage === "mark_not_claimed");
    expect(hit).toHaveLength(1);
    expect(hit[0][2].level).toBeUndefined();
  });

  it("the per-user ceiling stops guesses before the database or the auth service is touched, across keys", async () => {
    const log: string[] = [];
    const ceiling = new AttemptCeiling(2, 60_000, () => 0);
    const other = parseLegalText("other-key", "---\nversion: o-1\n---\ny\n");
    const svc = fakeRpc(log, { claim_legal_reauth_attempt: [{ data: { outcome: "locked" } }, { data: { outcome: "locked" } }] });
    const deps = { service: svc.client, authClient: fakeAuth(log).factory, ceiling };
    await verifyReauthCode(deps, { id: ID, entry: ENTRY, code: "123456" });
    await verifyReauthCode(deps, { id: ID, entry: other, code: "123456" });
    log.length = 0;
    expect(await verifyReauthCode(deps, { id: ID, entry: parseLegalText("third-key", "---\nversion: t\n---\nz\n"), code: "123456" })).toEqual({ ok: false, reason: "locked" });
    expect(log).toEqual([]);
  });
});

describe("decide", () => {
  const rec = (outcome: string, extra: Record<string, unknown> = {}) => ({ data: { outcome, ...extra } });
  const recorded = (choice: string) => rec("recorded", { choice, text_hash: ENTRY.textHash, decided_at: "2026-11-05T10:00:00Z", reauth_at: choice === "accept" ? "2026-11-05T09:58:00Z" : null });
  const mk = (service: Parameters<typeof fakeRpc>[1], user: Parameters<typeof fakeRpc>[1]) => {
    const log: string[] = [];
    const s = fakeRpc(log, service);
    const u = fakeRpc(log, user);
    return { log, s, u, deps: { service: s.client, user: u.client } };
  };
  const base = { userId: USER, sessionId: SESSION, entry: ENTRY, textHash: ENTRY.textHash, note: null };

  it("accept only records, on the USER client; it never opens an intent", async () => {
    const t = mk({}, { record_legal_acceptance: [recorded("accept")] });
    const out = await decideLegal(t.deps, { ...base, choice: "accept" });
    expect(out).toEqual({ kind: "result", result: { outcome: "recorded", choice: "accept", decidedAt: "2026-11-05T10:00:00Z", reauthAt: "2026-11-05T09:58:00Z" } });
    expect(t.s.calls).toEqual([]);
    expect(t.u.calls[0].args).toEqual({ p_key: "fixture-terms", p_text_hash: ENTRY.textHash, p_choice: "accept", p_requested_edit: null });
  });

  it("decline and request_changes open the intent with the SERVICE client first, then record on the USER client", async () => {
    const t = mk(
      { issue_legal_reauth: [{ data: { outcome: "issued", reused: false, event_id: EVENT, expires_at: "x" } }, { data: { outcome: "issued", reused: true, event_id: EVENT, expires_at: "x" } }] },
      { record_legal_acceptance: [recorded("decline"), recorded("request_changes")] },
    );
    await decideLegal(t.deps, { ...base, choice: "decline" });
    await decideLegal(t.deps, { ...base, choice: "request_changes", note: "Please change clause 2" });
    expect(t.log).toEqual(["rpc:issue_legal_reauth", "rpc:record_legal_acceptance", "rpc:issue_legal_reauth", "rpc:record_legal_acceptance"]);
    expect(t.s.calls.every((c) => c.fn === "issue_legal_reauth")).toBe(true);
    expect(t.u.calls.every((c) => c.fn === "record_legal_acceptance")).toBe(true);
    expect(t.u.calls[1].args.p_requested_edit).toBe("Please change clause 2");
  });

  it("a stale hash is replaced, a passed valid_until is expired; nothing is called, nothing is recorded", async () => {
    const t = mk({}, {});
    expect(await decideLegal(t.deps, { ...base, choice: "accept", textHash: "f".repeat(64) })).toEqual({ kind: "result", result: { outcome: "replaced" } });
    const old = parseLegalText("fixture-terms", "---\nversion: fx-1\nvalid_until: 2020-01-01\n---\nx\n");
    expect(await decideLegal(t.deps, { ...base, entry: old, textHash: old.textHash, choice: "accept" })).toEqual({ kind: "result", result: { outcome: "expired" } });
    expect(t.log).toEqual([]);
    expect(h.report.mock.calls.map((c) => c[2].tags.reason)).toEqual(["hash_mismatch", "text_expired"]);
  });

  it.each(["replaced", "expired", "code_expired"])("SQL outcome %s is returned as a 200 result and reported with a reason tag", async (outcome) => {
    const t = mk({}, { record_legal_acceptance: [rec(outcome)] });
    expect(await decideLegal(t.deps, { ...base, choice: "accept" })).toEqual({ kind: "result", result: { outcome } });
    expect(h.report).toHaveBeenCalledWith("decideRejected", null, expect.objectContaining({ tags: { reason: outcome } }));
  });

  it("already_recorded is returned without a rejection report (a second tab is normal); no accepted event either", async () => {
    const t = mk({}, { record_legal_acceptance: [rec("already_recorded", { choice: "accept" })] });
    expect(await decideLegal(t.deps, { ...base, choice: "accept" })).toEqual({ kind: "result", result: { outcome: "already_recorded", choice: "accept" } });
    expect(h.report).not.toHaveBeenCalled();
  });

  it("42501 (no live intent, or email code required) is forbidden, not code_expired, and is reported as denied_42501", async () => {
    const t = mk({}, { record_legal_acceptance: [{ error: { message: "x", code: "42501" } }] });
    expect(await decideLegal(t.deps, { ...base, choice: "accept" })).toEqual({ kind: "forbidden" });
    expect(h.report).toHaveBeenCalledWith("decideRejected", expect.any(LegalServiceError), expect.objectContaining({ tags: { reason: "denied_42501" } }));
  });

  it("any other database error propagates (the route answers 500); a rate-limited intent is 429 and nothing is recorded", async () => {
    const t = mk({}, { record_legal_acceptance: [{ error: { message: "x", code: "XX000" } }] });
    await expect(decideLegal(t.deps, { ...base, choice: "accept" })).rejects.toBeInstanceOf(LegalServiceError);
    const r = mk({ issue_legal_reauth: [{ data: { outcome: "rate_limited" } }] }, {});
    expect(await decideLegal(r.deps, { ...base, choice: "decline" })).toEqual({ kind: "rate_limited" });
    expect(r.u.calls).toEqual([]);
  });

  it("decline when a decision already exists comes back already_recorded and is not recorded again", async () => {
    const t = mk({ issue_legal_reauth: [{ data: { outcome: "already_recorded", choice: "decline" } }] }, {});
    expect(await decideLegal(t.deps, { ...base, choice: "decline" })).toEqual({ kind: "result", result: { outcome: "already_recorded", choice: "decline" } });
    expect(t.u.calls).toEqual([]);
  });

  it("emits op=accepted exactly once per recorded row, with ids and enums only (never the note)", async () => {
    const t = mk({ issue_legal_reauth: [{ data: { outcome: "issued", reused: false, event_id: EVENT, expires_at: "x" } }] }, { record_legal_acceptance: [recorded("request_changes")] });
    await decideLegal(t.deps, { ...base, choice: "request_changes", note: "PRIVATE-NOTE-TEXT" });
    const accepted = h.report.mock.calls.filter((c) => c[0] === "accepted");
    expect(accepted).toHaveLength(1);
    expect(JSON.stringify(h.report.mock.calls)).not.toContain("PRIVATE-NOTE-TEXT");
  });

  it("the note never appears in the decide_rejected event (hash mismatch, a replaced text, a rejection from the database)", async () => {
    const NOTE = "PRIVATE-NOTE-TEXT";
    const t = mk({ issue_legal_reauth: [{ data: { outcome: "issued", reused: false, event_id: EVENT, expires_at: "x" } }] }, { record_legal_acceptance: [rec("replaced")] });
    await decideLegal(t.deps, { ...base, choice: "request_changes", note: NOTE, textHash: "f".repeat(64) });
    await decideLegal(t.deps, { ...base, choice: "request_changes", note: NOTE });
    const rejected = h.report.mock.calls.filter((c) => c[0] === "decideRejected");
    expect(rejected).toHaveLength(2);
    expect(JSON.stringify(h.report.mock.calls)).not.toContain(NOTE);
  });

  it("a recorded reply whose text_hash is not the hash that was sent is a bad_payload, never success", async () => {
    const t = mk({}, { record_legal_acceptance: [rec("recorded", { choice: "accept", text_hash: "e".repeat(64), decided_at: "2026-11-05T10:00:00Z", reauth_at: null })] });
    await expect(decideLegal(t.deps, { ...base, choice: "accept" })).rejects.toMatchObject({ code: "bad_payload" });
    const u = fakeRpc([], { record_legal_acceptance: [rec("recorded", { choice: "accept", decided_at: "2026-11-05T10:00:00Z", reauth_at: null })] });
    await expect(recordAcceptance(u.client, { key: "fixture-terms", textHash: ENTRY.textHash, choice: "accept", note: null })).rejects.toMatchObject({ code: "bad_payload" });
  });

  it("a serialization failure (40001) is retried once; a second one propagates", async () => {
    const ok = mk({}, { record_legal_acceptance: [{ error: { message: "x", code: "40001" } }, recorded("accept")] });
    expect((await decideLegal(ok.deps, { ...base, choice: "accept" })).kind).toBe("result");
    expect(ok.u.calls).toHaveLength(2);
    const bad = mk({}, { record_legal_acceptance: [{ error: { message: "x", code: "40001" } }, { error: { message: "x", code: "40001" } }] });
    await expect(decideLegal(bad.deps, { ...base, choice: "accept" })).rejects.toMatchObject({ code: "40001" });
    expect(bad.u.calls).toHaveLength(2);
  });

  it("an unknown outcome from the database is an error, never success", async () => {
    const t = mk({}, { record_legal_acceptance: [rec("maybe")] });
    await expect(decideLegal(t.deps, { ...base, choice: "accept" })).rejects.toMatchObject({ code: "bad_payload" });
  });
});

describe("note rules", () => {
  it("request_changes requires non-empty trimmed text, at most 1000 characters; the others must not carry one", () => {
    expect(normaliseNote("request_changes", "  fix it  ")).toEqual({ ok: true, note: "fix it" });
    expect(normaliseNote("request_changes", "   ")).toEqual({ ok: false });
    expect(normaliseNote("request_changes", undefined)).toEqual({ ok: false });
    expect(normaliseNote("request_changes", "a".repeat(1000))).toMatchObject({ ok: true });
    expect(normaliseNote("request_changes", "a".repeat(1001))).toEqual({ ok: false });
    expect(normaliseNote("accept", undefined)).toEqual({ ok: true, note: null });
    expect(normaliseNote("decline", "x")).toEqual({ ok: false });
    expect(normaliseNote("accept", 5)).toEqual({ ok: false });
  });
  it("the cap counts characters (code points), exactly like the database CHECK: 600 emoji are accepted, 1001 are refused", () => {
    const emoji = "\u{1F600}";
    expect(emoji.length).toBe(2);
    expect(normaliseNote("request_changes", emoji.repeat(600))).toMatchObject({ ok: true });
    expect(normaliseNote("request_changes", emoji.repeat(1000))).toMatchObject({ ok: true });
    expect(normaliseNote("request_changes", emoji.repeat(1001))).toEqual({ ok: false });
    // BMP-only text: the unit count and the character count agree.
    expect(normaliseNote("request_changes", "b".repeat(1000))).toMatchObject({ ok: true });
    expect(normaliseNote("request_changes", "b".repeat(1001))).toEqual({ ok: false });
  });
  it("rejects a NUL (Postgres text cannot hold it) and a lone surrogate (not valid UTF-8); a valid surrogate pair is fine", () => {
    expect(normaliseNote("request_changes", "a\u0000b")).toEqual({ ok: false });
    expect(normaliseNote("request_changes", "bad \uD800 half")).toEqual({ ok: false });
    expect(normaliseNote("request_changes", "bad \uDC00 half")).toEqual({ ok: false });
    expect(normaliseNote("request_changes", "ok \uD83D\uDE00 pair")).toMatchObject({ ok: true });
  });
});

describe("Sentry feature tag (the alert rules match feature=legal-acceptance plus the op)", () => {
  it("the five legal ops are reported under feature legal-acceptance with their op literals and unique messages; the gate's ops keep approval-queue", async () => {
    const real = await vi.importActual<typeof import("@/server/approval/ops")>("@/server/approval/ops");
    for (const [key, op, sink] of [
      ["accepted", "accepted", h.warnSink],
      ["decideRejected", "decide_rejected", h.warnSink],
      ["reauthFailed", "reauth_failed", h.errSink],
      ["rowWithoutEvent", "row_without_event", h.errSink],
      ["pageReadFailed", "page_read_failed", h.errSink],
    ] as const) {
      sink.mockReset();
      real.reportLegalOp(key, null, { userId: USER, tags: { reason: "x" } });
      expect(sink.mock.calls[0][1], op).toMatchObject({ feature: "legal-acceptance", op, tags: { reason: "x" } });
    }
    const defs = Object.values(real.LEGAL_OPS);
    const gate = Object.values(real.APPROVAL_OPS);
    expect(new Set([...defs, ...gate].map((d) => d.message)).size).toBe(defs.length + gate.length);
    expect(new Set([...defs, ...gate].map((d) => d.op)).size).toBe(defs.length + gate.length);
    h.warnSink.mockReset();
    real.reportApprovalOp("waitTimeout", null, {});
    expect(h.warnSink.mock.calls[0][1]).toMatchObject({ feature: "approval-queue" });
  });

  it("the thrown value contributes only code, fn and class: never its message", async () => {
    const real = await vi.importActual<typeof import("@/server/approval/ops")>("@/server/approval/ops");
    h.errSink.mockReset();
    real.reportLegalOp("reauthFailed", Object.assign(new Error(`leak ${EMAIL}`), { code: "42501", fn: "x" }), {});
    expect(JSON.stringify(h.errSink.mock.calls)).not.toContain(EMAIL);
    expect(h.errSink.mock.calls[0][1].extra).toMatchObject({ code: "42501", fn: "x", errName: "Error" });
  });

  it("a level override lowers (or keeps) the severity of one report; the op's own level is the default", async () => {
    const real = await vi.importActual<typeof import("@/server/approval/ops")>("@/server/approval/ops");
    h.errSink.mockReset();
    h.warnSink.mockReset();
    real.reportLegalOp("reauthFailed", null, { level: "warn", extra: { stage: "x" } });
    expect(h.warnSink).toHaveBeenCalledTimes(1);
    expect(h.errSink).not.toHaveBeenCalled();
    real.reportLegalOp("reauthFailed", null, {});
    expect(h.errSink).toHaveBeenCalledTimes(1);
  });
});

describe("readCappedBody", () => {
  it("a declared Content-Length over the cap is refused WITHOUT reading the stream", async () => {
    const read = vi.fn();
    const req = {
      headers: new Headers({ "content-length": "9000" }),
      body: { getReader: () => ({ read, cancel: vi.fn() }) },
    } as unknown as Request;
    expect(await readCappedBody(req, 8 * 1024)).toBeNull();
    expect(read).not.toHaveBeenCalled();
  });

  it("an undeclared (chunked) body is cancelled the moment the cap is crossed", async () => {
    const cancel = vi.fn(async () => undefined);
    const chunks = [new Uint8Array(60), new Uint8Array(60), new Uint8Array(60)];
    const read = vi.fn(async () => (chunks.length ? { done: false, value: chunks.shift() as Uint8Array } : { done: true, value: undefined }));
    const req = { headers: new Headers(), body: { getReader: () => ({ read, cancel }) } } as unknown as Request;
    expect(await readCappedBody(req, 100)).toBeNull();
    expect(cancel).toHaveBeenCalledTimes(1);
    // It stopped reading at the overflow: the third chunk was never pulled.
    expect(read).toHaveBeenCalledTimes(2);
  });

  it("a body within the cap is returned whole", async () => {
    const req = new Request("http://localhost/x", { method: "POST", body: '{"a":1}' });
    expect(await readCappedBody(req, 100)).toBe('{"a":1}');
  });
});
