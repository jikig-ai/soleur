import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

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
  logCalls: [] as unknown[],
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
vi.mock("@/server/logger", () => ({
  default: { error: h.loggerError, info: h.loggerInfo, warn: h.loggerWarn },
}));
vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: h.addBreadcrumb,
  captureException: h.captureException,
}));

import { DELETE } from "@/app/api/keys/route";

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
  ])("rejects %s with 400 unsupported_credential_type and never calls the RPC", async (_label, body) => {
    const res = await DELETE(req(body));
    expect(res.status).toBe(400);
    expect((await res.json()).code).toBe("unsupported_credential_type");
    expect(h.rpc).not.toHaveBeenCalled();
    expect(h.from).not.toHaveBeenCalled();
  });

  it("rejects a non-JSON body with 400", async () => {
    const res = await DELETE(req(null, { raw: "not json {" }));
    expect(res.status).toBe(400);
    expect(h.rpc).not.toHaveBeenCalled();
  });

  it("rejects a bodyless DELETE with 400", async () => {
    const res = await DELETE(req(null, { noBody: true }));
    expect(res.status).toBe(400);
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
    const res = await DELETE(req({ ...OAUTH_BODY }));
    expect(res.status).toBe(200);
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

  it("a non-operator with CC_OAUTH_ENABLED unset is NOT forbidden (users can always erase their own secret)", async () => {
    expect(process.env.ADMIN_USER_IDS).toBeUndefined();
    expect(process.env.CC_OAUTH_ENABLED).toBeUndefined();
    const res = await DELETE(req(OAUTH_BODY));
    expect(res.status).not.toBe(403);
    expect(res.status).toBe(200);
    expect(h.rpc).toHaveBeenCalledTimes(1);
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
  });

  it("success emits the audit line (op oauth-credential-removed) and a breadcrumb", async () => {
    await DELETE(req(OAUTH_BODY));
    expect(h.loggerInfo).toHaveBeenCalledWith(
      expect.objectContaining({
        feature: "api-keys",
        op: "oauth-credential-removed",
        userId: USER,
        deleted: true,
      }),
      expect.any(String),
    );
    expect(h.addBreadcrumb).toHaveBeenCalledWith(
      expect.objectContaining({ message: expect.stringContaining("oauth-credential-removed") }),
    );
    // Breadcrumb carries no user id.
    expect(JSON.stringify(h.addBreadcrumb.mock.calls)).not.toContain(USER);
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
