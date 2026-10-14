// #9648 Phase B-0 — /api/keys provider field must be an explicit allowlist.
// The old `body.provider === "openai" ? "openai" : "anthropic"` ternary
// silently coerced any unrecognized value to "anthropic" — a typo'd
// `"mistrall"` would POST the user's Mistral key to api.anthropic.com for
// validation. Unrecognized provider ⇒ 400, before validateToken runs.

import { describe, it, expect, beforeEach, vi } from "vitest";

const h = vi.hoisted(() => ({
  user: { id: "user-1" } as { id: string } | null,
  upsert: vi.fn(async () => ({ error: null })),
  rpc: vi.fn(async () => ({ error: null })),
  validateToken: vi.fn(async () => true),
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
  validateToken: h.validateToken,
}));
vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.test" })),
  rejectCsrf: vi.fn(() => new Response("csrf", { status: 403 })),
}));
vi.mock("@/server/logger", () => ({
  default: { error: vi.fn(), info: vi.fn(), warn: vi.fn() },
}));
vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: vi.fn(), captureException: vi.fn() }));

import { POST } from "@/app/api/keys/route";

function req(body: unknown) {
  return new Request("https://app.test/api/keys", {
    method: "POST",
    headers: { "content-type": "application/json", origin: "https://app.test" },
    body: JSON.stringify(body),
  });
}

beforeEach(() => {
  h.user = { id: "user-1" };
  h.upsert.mockClear();
  h.rpc.mockClear();
  h.validateToken.mockClear();
});

describe("/api/keys — provider allowlist (#9648 B-0)", () => {
  it("unrecognized provider value → 400, validateToken never sees the key", async () => {
    const res = await POST(req({ key: "sk-test", provider: "mistrall" }));
    expect(res.status).toBe(400);
    expect(h.validateToken).not.toHaveBeenCalled();
    expect(h.upsert).not.toHaveBeenCalled();
  });

  it.each(["ANTHROPIC", "Anthropic", "openai ", "bedrock", "", 42, null, {}, []])(
    "provider %j → 400 (strict match, no coercion)",
    async (provider) => {
      const res = await POST(req({ key: "sk-test", provider }));
      expect(res.status).toBe(400);
      expect(h.validateToken).not.toHaveBeenCalled();
    },
  );

  it("400 body carries a machine-readable code + allowed list", async () => {
    const res = await POST(req({ key: "sk-test", provider: "mistrall" }));
    expect(await res.json()).toMatchObject({
      code: "unknown_provider",
      allowed: ["anthropic", "openai"],
    });
  });

  it("provider check precedes the oauth branch: bogus provider + oauth_token → 400, RPC untouched", async () => {
    const res = await POST(
      req({ key: "sk-test", provider: "mistrall", credential_type: "oauth_token" }),
    );
    expect(res.status).toBe(400);
    expect(h.rpc).not.toHaveBeenCalled();
  });

  it("oauth_token + a non-anthropic provider → 400 (store_oauth_credential is anthropic-hardcoded)", async () => {
    process.env.ADMIN_USER_IDS = "user-1";
    process.env.CC_OAUTH_ENABLED = "1";
    try {
      const res = await POST(
        req({ key: "sk-ant-oat", provider: "openai", credential_type: "oauth_token" }),
      );
      expect(res.status).toBe(400);
      expect(h.rpc).not.toHaveBeenCalled();
    } finally {
      delete process.env.ADMIN_USER_IDS;
      delete process.env.CC_OAUTH_ENABLED;
    }
  });

  it.each(["oauth", "OAUTH_TOKEN", "jwt"])(
    "credential_type %j → 400 (same no-coercion rule as provider)",
    async (credential_type) => {
      const res = await POST(req({ key: "sk-test", credential_type }));
      expect(res.status).toBe(400);
      expect(h.validateToken).not.toHaveBeenCalled();
    },
  );

  it("whitespace-only key → 400 before any outbound validation call", async () => {
    const res = await POST(req({ key: "   " }));
    expect(res.status).toBe(400);
    expect(h.validateToken).not.toHaveBeenCalled();
  });

  it("provider 'anthropic' → validateToken('anthropic', key)", async () => {
    const res = await POST(req({ key: "sk-ant-test", provider: "anthropic" }));
    expect(res.status).toBe(200);
    expect(h.validateToken).toHaveBeenCalledWith("anthropic", "sk-ant-test");
  });

  it("provider 'openai' → validateToken('openai', key)", async () => {
    const res = await POST(req({ key: "sk-oai-test", provider: "openai" }));
    expect(res.status).toBe(200);
    expect(h.validateToken).toHaveBeenCalledWith("openai", "sk-oai-test");
  });

  it("absent provider keeps the anthropic default (existing callers omit the field)", async () => {
    const res = await POST(req({ key: "sk-ant-test" }));
    expect(res.status).toBe(200);
    expect(h.validateToken).toHaveBeenCalledWith("anthropic", "sk-ant-test");
  });
});
