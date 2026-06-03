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
vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));

import { POST } from "@/app/api/keys/route";

const OPERATOR = "op-1";
const NON_OP = "non-op";

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
    const res = await POST(req({ key: "sk-ant-oat-token", credential_type: "oauth_token" }));
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
});
