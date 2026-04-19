import { describe, test, expect, vi, beforeEach } from "vitest";

process.env.STRIPE_PRICE_ID_SOLO = "price_solo";
process.env.STRIPE_PRICE_ID_STARTUP = "price_startup";
process.env.STRIPE_PRICE_ID_SCALE = "price_scale";
process.env.STRIPE_PRICE_ID_ENTERPRISE = "price_enterprise";

const { mockGetUser, mockFrom, mockCreateSession } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
  mockCreateSession: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: mockFrom,
  })),
}));

vi.mock("@/lib/stripe", () => ({
  getStripe: () => ({
    checkout: { sessions: { create: mockCreateSession } },
  }),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.ai" })),
  rejectCsrf: vi.fn(() => new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 })),
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

import { POST } from "@/app/api/checkout/route";

function setupUser(overrides: Record<string, unknown> = {}) {
  mockGetUser.mockResolvedValue({
    data: { user: { id: "user-1", email: "t@e.com", ...overrides } },
  });
  const single = vi.fn().mockResolvedValue({
    data: { stripe_customer_id: null, subscription_status: null },
    error: null,
  });
  const eq = vi.fn().mockReturnValue({ single });
  const select = vi.fn().mockReturnValue({ eq });
  mockFrom.mockReturnValue({ select });
}

function makeRequest(body: unknown): Request {
  return new Request("https://app.soleur.ai/api/checkout", {
    method: "POST",
    headers: { origin: "https://app.soleur.ai", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/checkout — targetTier", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockCreateSession.mockResolvedValue({
      client_secret: "cs_test_clientsecret",
      url: null,
    });
  });

  test("targetTier='startup' resolves to STRIPE_PRICE_ID_STARTUP", async () => {
    setupUser();
    const res = await POST(makeRequest({ targetTier: "startup" }));
    expect(res.status).toBe(200);
    expect(mockCreateSession).toHaveBeenCalledWith(
      expect.objectContaining({
        line_items: [{ price: "price_startup", quantity: 1 }],
        ui_mode: "embedded",
      }),
    );
    const [[args]] = mockCreateSession.mock.calls;
    expect(args.return_url).toContain("upgrade=complete");
    expect(args.return_url).toContain("{CHECKOUT_SESSION_ID}");
    const body = await res.json();
    expect(body.clientSecret).toBe("cs_test_clientsecret");
  });

  test("unknown targetTier returns 400", async () => {
    setupUser();
    const res = await POST(makeRequest({ targetTier: "bogus" }));
    expect(res.status).toBe(400);
    expect(mockCreateSession).not.toHaveBeenCalled();
  });

  test("targetTier='free' is rejected as invalid (no paid price)", async () => {
    setupUser();
    const res = await POST(makeRequest({ targetTier: "free" }));
    expect(res.status).toBe(400);
    expect(mockCreateSession).not.toHaveBeenCalled();
  });

  test("metadata includes supabase_user_id and target_tier", async () => {
    setupUser();
    await POST(makeRequest({ targetTier: "scale" }));
    expect(mockCreateSession).toHaveBeenCalledWith(
      expect.objectContaining({
        metadata: { supabase_user_id: "user-1", target_tier: "scale" },
      }),
    );
  });
});
