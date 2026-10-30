import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// feat-operator-cc-oauth Phase 4.2 — server-side operator gate on the
// oauth_token write path (AC5 + AC8). The gate is enforced at the ROUTE
// (the authoritative authz fence), NOT via UI hiding — these tests POST
// directly, bypassing any client toggle.

const h = vi.hoisted(() => ({
  user: { id: "non-op" } as { id: string } | null,
  upsert: vi.fn(async () => ({ error: null })),
  rpc: vi.fn(async () => ({ error: null })),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: async () => ({ data: { user: h.user } }) },
  })),
  createServiceClient: vi.fn(() => ({
    from: () => ({ upsert: h.upsert }),
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
  validateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.test" })),
  rejectCsrf: vi.fn(() => new Response("csrf", { status: 403 })),
}));
vi.mock("@/server/logger", () => ({
  default: { error: vi.fn(), info: vi.fn(), warn: vi.fn() },
}));
vi.mock("@sentry/nextjs", () => ({
  // verifiedUserId breadcrumbs on the absent-header fallback path.
  addBreadcrumb: vi.fn(), captureException: vi.fn() }));

import { POST } from "@/app/api/keys/route";

const OPERATOR = "op-1";
const NON_OP = "non-op";
// Synthesized fake, shaped like a real subscription token (never a real credential).
const VALID_OAUTH = "sk-ant-oat01-FAKEfake_0123456789-abcdef";

function req(body: unknown) {
  return new Request("https://app.test/api/keys", {
    method: "POST",
    headers: { "content-type": "application/json", origin: "https://app.test" },
    body: JSON.stringify(body),
  });
}

let savedAdmins: string | undefined;
let savedEnabled: string | undefined;

beforeEach(() => {
  h.upsert.mockClear();
  h.rpc.mockClear();
  savedAdmins = process.env.ADMIN_USER_IDS;
  savedEnabled = process.env.CC_OAUTH_ENABLED;
  process.env.ADMIN_USER_IDS = OPERATOR;
  process.env.CC_OAUTH_ENABLED = "1";
});

afterEach(() => {
  if (savedAdmins === undefined) delete process.env.ADMIN_USER_IDS;
  else process.env.ADMIN_USER_IDS = savedAdmins;
  if (savedEnabled === undefined) delete process.env.CC_OAUTH_ENABLED;
  else process.env.CC_OAUTH_ENABLED = savedEnabled;
});

describe("/api/keys — oauth_token operator gate", () => {
  it("AC5: non-operator oauth_token write → 403, no DB write", async () => {
    h.user = { id: NON_OP };
    const res = await POST(req({ key: "sk-ant-oat-token", credential_type: "oauth_token" }));
    expect(res.status).toBe(403);
    expect(h.rpc).not.toHaveBeenCalled();
    expect(h.upsert).not.toHaveBeenCalled();
  });

  it("operator oauth_token write → store_oauth_credential RPC (not the api_key upsert)", async () => {
    h.user = { id: OPERATOR };
    const res = await POST(req({ key: VALID_OAUTH, credential_type: "oauth_token" }));
    expect(res.status).toBe(200);
    expect(h.rpc).toHaveBeenCalledWith(
      "store_oauth_credential",
      expect.objectContaining({ p_user_id: OPERATOR }),
    );
    expect(h.upsert).not.toHaveBeenCalled();
  });

  it("AC8: kill-switch off ⇒ oauth_token write 403s even for the operator", async () => {
    h.user = { id: OPERATOR };
    delete process.env.CC_OAUTH_ENABLED;
    const res = await POST(req({ key: "sk-ant-oat-token", credential_type: "oauth_token" }));
    expect(res.status).toBe(403);
    expect(h.rpc).not.toHaveBeenCalled();
  });

  it("api_key path unchanged: upsert runs, RPC does not (non-operator allowed)", async () => {
    h.user = { id: NON_OP };
    const res = await POST(req({ key: "sk-ant-api03-regular-key" }));
    expect(res.status).toBe(200);
    expect(h.upsert).toHaveBeenCalledTimes(1);
    expect(h.rpc).not.toHaveBeenCalled();
  });

  it("stores an OpenAI API key through the same authenticated settings path", async () => {
    h.user = { id: NON_OP };
    const res = await POST(req({ key: "sk-openai-test", provider: "openai" }));
    expect(res.status).toBe(200);
    expect(h.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ user_id: NON_OP, provider: "openai" }),
      expect.anything(),
    );
    expect(h.rpc).not.toHaveBeenCalled();
  });
});

describe("/api/keys — oauth_token shape gate (#11086)", () => {
  const post = (key: string) => POST(req({ key, credential_type: "oauth_token" }));

  it.each([
    ["an API key", "sk-ant-api03-FAKEcanary0001"],
    ["an admin key", "sk-ant-admin01-FAKEcanary0002"],
    ["a token with an embedded space", "sk-ant-oat01-FAKEcanary BBBB0003"],
    ["a dash-less oat prefix", "sk-ant-oatFAKEcanary0004"],
    ["a foreign-vendor key", "sk-proj-FAKEcanary0005"],
    ["arbitrary text", "not-a-token-FAKEcanary0006"],
    ["a prefix-wrapped copy (no space)", "NAME=sk-ant-oat01-FAKEcanary0007"],
    ["a one-digit version", "sk-ant-oat1-FAKEcanary0008"],
    ["no version digits", "sk-ant-oat-FAKEcanary0009"],
    ["an upper-cased token", "SK-ANT-OAT01-FAKECANARY0010"],
  ])("rejects %s with 400 + oauth_token_shape_invalid before any RPC", async (_label, value) => {
    h.user = { id: OPERATOR };
    const res = await post(value);
    expect(res.status).toBe(400);
    const raw = await res.text();
    expect(JSON.parse(raw).code).toBe("oauth_token_shape_invalid");
    expect(h.rpc).not.toHaveBeenCalled();
    expect(h.upsert).not.toHaveBeenCalled();
    // The response must never echo any part of the submitted value.
    expect(raw).not.toContain("FAKEcanary");
    expect(raw).not.toContain(value);
  });

  it("an API-key-shaped value gets the API-key-specific copy; others get the neutral copy", async () => {
    h.user = { id: OPERATOR };
    const api = await (await post("sk-ant-api03-FAKEcanary0001")).json();
    expect(api.error).toMatch(/looks like an API key, not a subscription token/i);
    const admin = await (await post("sk-ant-admin01-FAKEcanary0002")).json();
    expect(admin.error).toMatch(/looks like an API key, not a subscription token/i);
    const other = await (await post("not-a-token-FAKEcanary0006")).json();
    expect(other.error).not.toMatch(/looks like an API key/i);
    expect(other.error).toMatch(/sk-ant-oat/);
    expect(other.error).toMatch(/no spaces/i);
    for (const e of [api.error, admin.error, other.error]) expect(e).not.toContain("`");
  });

  it("surrounding whitespace is trimmed before the shape check (still stores)", async () => {
    h.user = { id: OPERATOR };
    const res = await post(`  ${VALID_OAUTH}\n`);
    expect(res.status).toBe(200);
    expect(h.rpc).toHaveBeenCalledTimes(1);
  });

  it("a valid-shaped synthesized token still stores via the RPC", async () => {
    h.user = { id: OPERATOR };
    const res = await post(VALID_OAUTH);
    expect(res.status).toBe(200);
    expect(h.rpc).toHaveBeenCalledWith(
      "store_oauth_credential",
      expect.objectContaining({ p_user_id: OPERATOR }),
    );
  });

  it("the shape gate runs AFTER the operator gate (non-operator still gets 403, not a shape oracle)", async () => {
    h.user = { id: NON_OP };
    const res = await post("sk-ant-api03-FAKEcanary0001");
    expect(res.status).toBe(403);
  });
});
