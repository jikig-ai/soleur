import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const {
  mockGetUser,
  mockFrom,
  mockCreatePortalSession,
  mockValidateOrigin,
  mockCaptureException,
  mockCaptureMessage,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
  mockCreatePortalSession: vi.fn(),
  mockValidateOrigin: vi.fn(() => ({
    valid: true,
    origin: "https://app.soleur.ai",
  })),
  mockCaptureException: vi.fn(),
  mockCaptureMessage: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: mockFrom,
  })),
}));

vi.mock("@/lib/stripe", () => ({
  getStripe: () => ({
    billingPortal: { sessions: { create: mockCreatePortalSession } },
  }),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: mockValidateOrigin,
  rejectCsrf: vi.fn(
    () => new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
  ),
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: mockCaptureException,
  captureMessage: mockCaptureMessage,
}));

// ---------------------------------------------------------------------------
// Import route handler AFTER mocks
// ---------------------------------------------------------------------------

import { POST } from "@/app/api/billing/portal/route";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const USER_ID = "user-uuid-123";
const CUSTOMER_ID = "cus_test123";
const PORTAL_URL = "https://billing.stripe.com/p/session/test_abc";

function makeRequest(): Request {
  return new Request("https://app.soleur.ai/api/billing/portal", {
    method: "POST",
    headers: { origin: "https://app.soleur.ai" },
  });
}

function setupAuthenticatedUser() {
  mockGetUser.mockResolvedValue({
    data: { user: { id: USER_ID } },
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

describe("POST /api/billing/portal", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockValidateOrigin.mockReturnValue({
      valid: true,
      origin: "https://app.soleur.ai",
    });
    mockCreatePortalSession.mockResolvedValue({ url: PORTAL_URL });
    process.env.NEXT_PUBLIC_APP_URL = "https://test.example";
  });

  test("returns portal URL for authenticated user with stripe_customer_id", async () => {
    setupAuthenticatedUser();
    setupUserQuery({ stripe_customer_id: CUSTOMER_ID });

    const res = await POST(makeRequest());
    const body = await res.json();

    expect(res.status).toBe(200);
    expect(body.url).toBe(PORTAL_URL);
    expect(mockCreatePortalSession).toHaveBeenCalledWith(
      expect.objectContaining({
        customer: CUSTOMER_ID,
        return_url: expect.stringContaining("/dashboard/settings"),
      }),
    );
  });

  test("returns 401 when user is not authenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });

    const res = await POST(makeRequest());

    expect(res.status).toBe(401);
    expect(mockCreatePortalSession).not.toHaveBeenCalled();
  });

  test("returns 400 when user has no stripe_customer_id", async () => {
    setupAuthenticatedUser();
    setupUserQuery({ stripe_customer_id: null });

    const res = await POST(makeRequest());

    expect(res.status).toBe(400);
    expect(mockCreatePortalSession).not.toHaveBeenCalled();
  });

  test("calls validateOrigin for CSRF protection", async () => {
    mockValidateOrigin.mockReturnValue({ valid: false, origin: "https://evil.com" });

    const res = await POST(makeRequest());

    expect(res.status).toBe(403);
    expect(mockGetUser).not.toHaveBeenCalled();
  });

  test("degraded: NEXT_PUBLIC_APP_URL unset fires Sentry and uses literal fallback", async () => {
    delete process.env.NEXT_PUBLIC_APP_URL;
    setupAuthenticatedUser();
    setupUserQuery({ stripe_customer_id: CUSTOMER_ID });

    const res = await POST(makeRequest());
    expect(res.status).toBe(200);

    expect(mockCaptureMessage).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({
        level: "error",
        tags: expect.objectContaining({ feature: "billing", op: "portal-session" }),
      }),
    );
    expect(mockCreatePortalSession).toHaveBeenCalledWith(
      expect.objectContaining({
        return_url: "https://app.soleur.ai/dashboard/settings",
      }),
    );
  });

  test("happy: NEXT_PUBLIC_APP_URL set routes URL to Stripe and Sentry stays silent", async () => {
    process.env.NEXT_PUBLIC_APP_URL = "https://test.example";
    setupAuthenticatedUser();
    setupUserQuery({ stripe_customer_id: CUSTOMER_ID });

    const res = await POST(makeRequest());
    expect(res.status).toBe(200);

    expect(mockCaptureException).not.toHaveBeenCalled();
    expect(mockCaptureMessage).not.toHaveBeenCalled();
    expect(mockCreatePortalSession).toHaveBeenCalledWith(
      expect.objectContaining({
        return_url: "https://test.example/dashboard/settings",
      }),
    );
  });
});
