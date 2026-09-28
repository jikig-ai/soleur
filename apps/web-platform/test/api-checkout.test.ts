import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";

// Legacy STRIPE_PRICE_ID path is still exercised by these tests. Set the env
// var before the route imports so priceIdForTier() fallback resolves cleanly.
process.env.STRIPE_PRICE_ID = "price_legacy";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const { mockGetUser, mockFrom, mockCreateSession, mockCaptureException, mockCaptureMessage, mockMarkerInsert, mockClaimSingle, mockMarkerUpdate, mockUpdateSelect } =
  vi.hoisted(() => ({
    mockGetUser: vi.fn(),
    mockFrom: vi.fn(),
    mockCreateSession: vi.fn(),
    mockCaptureException: vi.fn(),
    mockCaptureMessage: vi.fn(),
    mockMarkerInsert: vi.fn(),
    mockClaimSingle: vi.fn(),
    mockMarkerUpdate: vi.fn(),
    mockUpdateSelect: vi.fn(),
  }));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: mockFrom,
  })),
}));

vi.mock("@/lib/supabase/service", () => ({
  // #8918: route claims a pending_checkout_sessions row via service-role.
  // Defaults here make the claim succeed so these tests stay on the
  // own-slot path; the race paths live in api-checkout-idempotency.test.ts.
  getServiceClient: vi.fn(() => ({
    from: () => {
      const deleteEq2 = {
        select: vi.fn().mockResolvedValue({ data: [{ user_id: "user-1" }], error: null }),
        then: (res: (v: unknown) => unknown) => Promise.resolve({ error: null }).then(res),
      };
      return {
        insert: (row: unknown) => {
          mockMarkerInsert(row);
          return { select: () => ({ single: mockClaimSingle }) };
        },
        update: (patch: unknown) => {
          mockMarkerUpdate(patch);
          return { eq: () => ({ eq: () => ({ select: mockUpdateSelect }) }) };
        },
        delete: () => ({ eq: () => ({ eq: () => deleteEq2, is: () => ({ eq: () => ({ select: vi.fn() }) }) }) }),
        select: () => ({
          eq: () => ({ maybeSingle: vi.fn().mockResolvedValue({ data: null, error: null }) }),
        }),
      };
    },
  })),
}));

vi.mock("@/lib/stripe", () => ({
  getStripe: () => ({
    checkout: {
      sessions: {
        create: mockCreateSession,
        retrieve: vi.fn(),
        expire: vi.fn(),
      },
    },
  }),
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: mockCaptureException,
  captureMessage: mockCaptureMessage,
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.ai" })),
  rejectCsrf: vi.fn(
    () => new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
  ),
}));

// ---------------------------------------------------------------------------
// Import route handler AFTER mocks
// ---------------------------------------------------------------------------

import { POST } from "@/app/api/checkout/route";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const USER_ID = "user-uuid-123";
const USER_EMAIL = "test@example.com";
const CUSTOMER_ID = "cus_existing123";

function makeRequest(): Request {
  return new Request("https://app.soleur.ai/api/checkout", {
    method: "POST",
    headers: { origin: "https://app.soleur.ai" },
  });
}

function setupAuthenticatedUser(overrides: Record<string, unknown> = {}) {
  mockGetUser.mockResolvedValue({
    data: { user: { id: USER_ID, email: USER_EMAIL, ...overrides } },
  });
}

function setupUserQuery(data: Record<string, unknown> | null) {
  const mockSingle = vi.fn().mockResolvedValue({ data, error: null });
  const mockEq = vi.fn().mockReturnValue({ single: mockSingle });
  const mockSelect = vi.fn().mockReturnValue({ eq: mockEq });
  mockFrom.mockReturnValue({ select: mockSelect });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("POST /api/checkout", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockCreateSession.mockResolvedValue({ id: "cs_test_1", url: "https://checkout.stripe.com/session", client_secret: "cs_secret", status: "open" });
    mockClaimSingle.mockResolvedValue({
      data: { created_at: new Date().toISOString() },
      error: null,
    });
    mockUpdateSelect.mockResolvedValue({
      data: [{ user_id: "user-uuid-123" }],
      error: null,
    });
    // Default for existing tests — degraded-path test unsets below via vi.stubEnv(..., "")
    vi.stubEnv("NEXT_PUBLIC_APP_URL", "https://test.example");
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  test("reuses existing stripe_customer_id when available", async () => {
    setupAuthenticatedUser();
    setupUserQuery({
      stripe_customer_id: CUSTOMER_ID,
      subscription_status: null,
    });

    const res = await POST(makeRequest());
    const body = await res.json();

    expect(res.status).toBe(200);
    expect(body.url).toBe("https://checkout.stripe.com/session");
    expect(mockCreateSession).toHaveBeenCalledWith(
      expect.objectContaining({ customer: CUSTOMER_ID }),
      expect.objectContaining({ idempotencyKey: expect.any(String) }),
    );
    // Should NOT have customer_email when customer is set
    expect(mockCreateSession).toHaveBeenCalledWith(
      expect.not.objectContaining({ customer_email: expect.any(String) }),
      expect.objectContaining({ idempotencyKey: expect.any(String) }),
    );
  });

  test("uses customer_email when no stripe_customer_id exists", async () => {
    setupAuthenticatedUser();
    setupUserQuery({ stripe_customer_id: null, subscription_status: null });

    const res = await POST(makeRequest());
    const body = await res.json();

    expect(res.status).toBe(200);
    expect(body.url).toBe("https://checkout.stripe.com/session");
    expect(mockCreateSession).toHaveBeenCalledWith(
      expect.objectContaining({ customer_email: USER_EMAIL }),
      expect.objectContaining({ idempotencyKey: expect.any(String) }),
    );
  });

  test("blocks checkout when subscription is active", async () => {
    setupAuthenticatedUser();
    setupUserQuery({
      stripe_customer_id: CUSTOMER_ID,
      subscription_status: "active",
    });

    const res = await POST(makeRequest());

    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error).toBeDefined();
    expect(mockCreateSession).not.toHaveBeenCalled();
  });

  test("returns 401 when user is not authenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });

    const res = await POST(makeRequest());

    expect(res.status).toBe(401);
    expect(mockCreateSession).not.toHaveBeenCalled();
  });

  test("degraded: NEXT_PUBLIC_APP_URL unset fires Sentry and uses literal fallback", async () => {
    vi.stubEnv("NEXT_PUBLIC_APP_URL", undefined);
    setupAuthenticatedUser();
    setupUserQuery({ stripe_customer_id: CUSTOMER_ID, subscription_status: null });

    const res = await POST(makeRequest());
    expect(res.status).toBe(200);

    expect(mockCaptureMessage).toHaveBeenCalledWith(
      expect.stringContaining("NEXT_PUBLIC_APP_URL unset"),
      expect.objectContaining({
        level: "error",
        tags: expect.objectContaining({ feature: "checkout", op: "create-session" }),
      }),
    );
    expect(mockCreateSession).toHaveBeenCalledWith(
      expect.objectContaining({
        return_url: expect.stringMatching(/^https:\/\/app\.soleur\.ai\//),
      }),
      expect.objectContaining({ idempotencyKey: expect.any(String) }),
    );
  });

  test("happy: NEXT_PUBLIC_APP_URL set routes URL to Stripe and Sentry stays silent", async () => {
    vi.stubEnv("NEXT_PUBLIC_APP_URL", "https://test.example");
    setupAuthenticatedUser();
    setupUserQuery({ stripe_customer_id: CUSTOMER_ID, subscription_status: null });

    const res = await POST(makeRequest());
    expect(res.status).toBe(200);

    expect(mockCaptureException).not.toHaveBeenCalled();
    expect(mockCaptureMessage).not.toHaveBeenCalled();
    expect(mockCreateSession).toHaveBeenCalledWith(
      expect.objectContaining({
        return_url: expect.stringMatching(/^https:\/\/test\.example\//),
      }),
      expect.objectContaining({ idempotencyKey: expect.any(String) }),
    );
  });
});
