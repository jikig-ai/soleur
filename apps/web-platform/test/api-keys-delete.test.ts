import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// #11524 — DELETE /api/keys removes the caller's stored subscription token
// (api_keys.provider = 'anthropic_oauth') through the service-role-only
// delete_oauth_credential RPC (ADR-048 write boundary: the provider is
// hardcoded inside the function, so this path can never reach the user's
// 'anthropic' fallback key). The route has NO operator / kill-switch fence: a
// user can always erase their own stored secret.

const h = vi.hoisted(() => ({
  user: { id: "user-1" } as { id: string } | null,
  rpc: vi.fn(async (..._args: unknown[]) => ({ data: true as unknown, error: null as unknown })),
  from: vi.fn(),
  csrfValid: true,
  loggerError: vi.fn(),
  loggerInfo: vi.fn(),
  loggerWarn: vi.fn(),
  captureException: vi.fn(),
  addBreadcrumb: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: async () => ({ data: { user: h.user } }) },
  })),
  createServiceClient: vi.fn(() => ({
    // Any direct table access from DELETE is a regression (RPC-only boundary).
    from: h.from,
    rpc: h.rpc,
  })),
}));
vi.mock("@/server/byok", () => ({
  encryptKey: vi.fn(() => ({
    encrypted: Buffer.from("enc"),
    iv: Buffer.from("iv"),
    tag: Buffer.from("tag"),
  })),
}));
vi.mock("@/server/token-validators", () => ({
  validateToken: vi.fn(async () => true),
}));
vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: vi.fn(() =>
    h.csrfValid
      ? { valid: true, origin: "https://app.test" }
      : { valid: false, origin: "https://evil.test" },
  ),
  rejectCsrf: vi.fn(() => new Response("csrf", { status: 403 })),
}));
vi.mock("@/server/observability", () => ({
  // Deterministic stand-in: the real HMAC is pepper-dependent.
  hashUserId: vi.fn((id: string) => `hash(${id})`),
}));
vi.mock("@/server/logger", () => ({
  default: { error: h.loggerError, info: h.loggerInfo, warn: h.loggerWarn },
}));
vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: h.addBreadcrumb,
  captureException: h.captureException,
}));

import { DELETE, POST } from "@/app/api/keys/route";

const USER = "user-1";

function req(body: unknown, opts: { raw?: string; noBody?: boolean } = {}) {
  return new Request("https://app.test/api/keys", {
    method: "DELETE",
    headers: { "content-type": "application/json", origin: "https://app.test" },
    body: opts.noBody ? undefined : (opts.raw ?? JSON.stringify(body)),
  });
}

const OAUTH_BODY = { credential_type: "oauth_token" };

let savedAdmins: string | undefined;
let savedEnabled: string | undefined;

beforeEach(() => {
  h.user = { id: USER };
  h.csrfValid = true;
  h.rpc.mockReset();
  h.rpc.mockResolvedValue({ data: true, error: null });
  h.from.mockReset();
  h.loggerError.mockReset();
  h.loggerInfo.mockReset();
  h.loggerWarn.mockReset();
  h.captureException.mockReset();
  h.addBreadcrumb.mockReset();
  savedAdmins = process.env.ADMIN_USER_IDS;
  savedEnabled = process.env.CC_OAUTH_ENABLED;
  // The caller is NOT an operator and the kill-switch is unset: erase must
  // still work (no operator / CC_OAUTH_ENABLED fence on DELETE).
  delete process.env.ADMIN_USER_IDS;
  delete process.env.CC_OAUTH_ENABLED;
});

afterEach(() => {
  if (savedAdmins === undefined) delete process.env.ADMIN_USER_IDS;
  else process.env.ADMIN_USER_IDS = savedAdmins;
  if (savedEnabled === undefined) delete process.env.CC_OAUTH_ENABLED;
  else process.env.CC_OAUTH_ENABLED = savedEnabled;
});

describe("DELETE /api/keys — exact-body gate", () => {
  it.each([
    ["empty object", {}],
    ["api_key credential_type", { credential_type: "api_key" }],
    ["a provider field only", { provider: "anthropic" }],
    ["provider smuggled beside the right type", { credential_type: "oauth_token", provider: "anthropic" }],
    ["unknown credential_type", { credential_type: "bedrock" }],
    ["non-string credential_type", { credential_type: 1 }],
    ["null body", null],
    ["array body", [OAUTH_BODY]],
    ["non-JSON body", "RAW:not json {"],
    ["bodyless DELETE", "NOBODY"],
  ])("rejects %s with 400 unsupported_credential_type and never calls the RPC", async (_label, body) => {
    const res = await DELETE(
      body === "NOBODY"
        ? req(null, { noBody: true })
        : typeof body === "string" && body.startsWith("RAW:")
          ? req(null, { raw: body.slice(4) })
          : req(body),
    );
    expect(res.status).toBe(400);
    expect((await res.json()).code).toBe("unsupported_credential_type");
    expect(h.rpc).not.toHaveBeenCalled();
    expect(h.from).not.toHaveBeenCalled();
  });
});

describe("DELETE /api/keys — RPC call and response", () => {
  it("calls delete_oauth_credential with ONLY the verified p_user_id and returns 200 { deleted: true }", async () => {
    const res = await DELETE(req(OAUTH_BODY));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ deleted: true });
    expect(h.rpc).toHaveBeenCalledTimes(1);
    expect(h.rpc).toHaveBeenCalledWith("delete_oauth_credential", { p_user_id: USER });
    // Never a direct table delete (the anthropic fallback key must be unreachable).
    expect(h.from).not.toHaveBeenCalled();
  });

  it("an absent row is idempotent: RPC false -> 200 { deleted: false }", async () => {
    h.rpc.mockResolvedValue({ data: false, error: null });
    const res = await DELETE(req(OAUTH_BODY));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ deleted: false });
  });

  it("the user id comes from the verified session, never from the request body", async () => {
    h.user = { id: "someone-else" };
    // A body carrying a user_id field fails the exact-body gate, so a
    // body-supplied id can never reach the RPC either way.
    const smuggled = await DELETE(req({ ...OAUTH_BODY, user_id: "victim" }));
    expect(smuggled.status).toBe(400);
    expect(h.rpc).not.toHaveBeenCalled();
    const res = await DELETE(req({ ...OAUTH_BODY }));
    expect(res.status).toBe(200);
    expect(h.rpc).toHaveBeenCalledTimes(1);
    expect(h.rpc).toHaveBeenCalledWith("delete_oauth_credential", { p_user_id: "someone-else" });
  });
});

describe("DELETE /api/keys — authn / CSRF / no operator fence", () => {
  it("unauthenticated -> 401, no RPC", async () => {
    h.user = null;
    const res = await DELETE(req(OAUTH_BODY));
    expect(res.status).toBe(401);
    expect(h.rpc).not.toHaveBeenCalled();
  });

  it("failed origin check -> rejectCsrf response, no RPC", async () => {
    h.csrfValid = false;
    const res = await DELETE(req(OAUTH_BODY));
    expect(res.status).toBe(403);
    expect(await res.text()).toBe("csrf");
    expect(h.rpc).not.toHaveBeenCalled();
  });
});

describe("DELETE /api/keys — failure and audit", () => {
  it("RPC error -> 500 { error: 'Failed to remove token' } + Sentry.captureException, no direct table delete", async () => {
    const rpcError = { message: "function delete_oauth_credential does not exist", code: "42883" };
    h.rpc.mockResolvedValue({ data: null, error: rpcError });
    const res = await DELETE(req(OAUTH_BODY));
    expect(res.status).toBe(500);
    expect(await res.json()).toEqual({ error: "Failed to remove token" });
    expect(h.captureException).toHaveBeenCalledTimes(1);
    expect(h.captureException).toHaveBeenCalledWith(
      rpcError,
      expect.objectContaining({
        tags: { feature: "api-keys", op: "delete-oauth" },
      }),
    );
    expect(h.loggerError).toHaveBeenCalled();
    expect(h.from).not.toHaveBeenCalled();
    // The Sentry extra carries the hashed id, never the raw one.
    const opts = h.captureException.mock.calls[0][1] as { extra: Record<string, unknown> };
    expect(opts.extra.userIdHash).toBe(`hash(${USER})`);
    expect(JSON.stringify(opts.extra)).not.toContain(`"${USER}"`);
    expect(opts.extra).not.toHaveProperty("userId");
  });

  it("a real erasure (deleted: true) emits the audit line at WARN (Vector ships pino >= 40 only); the pino warn mirror is the breadcrumb carrier", async () => {
    await DELETE(req(OAUTH_BODY));
    // infra/vector.toml app_container_warn_filter drops info (30): a real
    // erasure must be warn or it never reaches Better Stack.
    expect(h.loggerInfo).not.toHaveBeenCalled();
    expect(h.loggerWarn).toHaveBeenCalledTimes(1);
    expect(h.loggerWarn).toHaveBeenCalledWith(
      expect.objectContaining({
        feature: "api-keys",
        op: "oauth-credential-removed",
        userId: USER,
        deleted: true,
      }),
      expect.any(String),
    );
    // server/logger.ts mirrorToSentry already turns this warn into a
    // breadcrumb carrying { deleted }; an explicit second one is a duplicate.
    expect(h.addBreadcrumb).not.toHaveBeenCalledWith(
      expect.objectContaining({ category: "api-keys" }),
    );
  });

  it("an idempotent no-op (deleted: false) is logged at INFO, not WARN, and adds no breadcrumb", async () => {
    h.rpc.mockResolvedValue({ data: false, error: null });
    await DELETE(req(OAUTH_BODY));
    expect(h.loggerWarn).not.toHaveBeenCalled();
    expect(h.loggerInfo).toHaveBeenCalledTimes(1);
    expect(h.loggerInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        feature: "api-keys",
        op: "oauth-credential-removed",
        deleted: false,
      }),
      expect.any(String),
    );
    expect(h.addBreadcrumb).not.toHaveBeenCalledWith(
      expect.objectContaining({ category: "api-keys" }),
    );
  });

  it("no token-shaped string, request body or body field name reaches any logger / Sentry argument", async () => {
    const smuggled = "sk-ant-oat01-FAKEcanary_DELETE_0001";
    // A body carrying a token-shaped value is rejected (exact-body gate) ...
    const rejected = await DELETE(req({ ...OAUTH_BODY, key: smuggled }));
    expect(rejected.status).toBe(400);
    expect(await rejected.text()).not.toContain(smuggled);
    // ... and a failing RPC on a valid request logs only the error object.
    h.rpc.mockResolvedValue({ data: null, error: { message: "boom", code: "XX000" } });
    await DELETE(req(OAUTH_BODY));
    await DELETE(req({ ...OAUTH_BODY, key: smuggled }));
    h.rpc.mockResolvedValue({ data: true, error: null });
    await DELETE(req(OAUTH_BODY));

    const sinks = JSON.stringify([
      h.loggerError.mock.calls,
      h.loggerInfo.mock.calls,
      h.loggerWarn.mock.calls,
      h.captureException.mock.calls,
      h.addBreadcrumb.mock.calls,
    ]);
    expect(sinks).not.toContain("FAKEcanary");
    expect(sinks).not.toContain("sk-ant");
    expect(sinks).not.toContain("credential_type");
  });
});

describe("POST /api/keys — kill-switch predicate has a single source", () => {
  // Strip comments so prose mentioning the env var cannot satisfy or trip the
  // assertions; anchor on the call/read form, not the bare token.
  const src = readFileSync(
    path.join(__dirname, "../app/api/keys/route.ts"),
    "utf8",
  )
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/\/\/[^\n]*/g, "");

  it("never reads process.env.CC_OAUTH_ENABLED directly", () => {
    expect(src).not.toMatch(/process\.env\.CC_OAUTH_ENABLED/);
    expect(src).not.toMatch(/process\.env\[\s*["']CC_OAUTH_ENABLED["']\s*\]/);
  });

  it("calls isCcOauthEnabled() from the shared module", () => {
    expect(src).toMatch(/import\s*\{\s*isCcOauthEnabled\s*\}\s*from\s*["']@\/server\/cc-oauth-flag["']/);
    expect(src).toMatch(/!isCcOauthEnabled\(\)/);
  });
});

describe("POST /api/keys (oauth_token) — RPC-error Sentry extra is pseudonymised", () => {
  it("store_oauth_credential error -> 500, extra carries userIdHash and never the raw userId", async () => {
    process.env.ADMIN_USER_IDS = USER;
    process.env.CC_OAUTH_ENABLED = "1";
    const rpcError = { message: "store failed", code: "XX000" };
    h.rpc.mockResolvedValue({ data: null, error: rpcError });
    const res = await POST(
      new Request("https://app.test/api/keys", {
        method: "POST",
        headers: { "content-type": "application/json", origin: "https://app.test" },
        body: JSON.stringify({
          key: "sk-ant-oat01-FAKEfake_0123456789-abcdef",
          credential_type: "oauth_token",
        }),
      }),
    );
    expect(res.status).toBe(500);
    expect(h.captureException).toHaveBeenCalledTimes(1);
    const opts = h.captureException.mock.calls[0][1] as {
      tags: Record<string, string>;
      extra: Record<string, unknown>;
    };
    expect(opts.tags).toEqual({ feature: "api-keys", op: "store-oauth" });
    expect(opts.extra.userIdHash).toBe(`hash(${USER})`);
    expect(opts.extra).not.toHaveProperty("userId");
    expect(JSON.stringify(opts.extra)).not.toContain(`"${USER}"`);
  });
});
