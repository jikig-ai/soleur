import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";

// Server-side idempotency for POST /api/checkout (#8918).
//
// The marker table `pending_checkout_sessions` (service-role only, migration
// 144) is the serialization point: claim via INSERT, 23505 routes the loser
// into the marker-hit path (retrieve → reuse / reclaim / 409). These tests
// drive every marker-hit branch via a mocked createServiceClient.

process.env.STRIPE_PRICE_ID_SOLO = "price_solo";
process.env.STRIPE_PRICE_ID_STARTUP = "price_startup";
process.env.STRIPE_PRICE_ID_SCALE = "price_scale";
process.env.STRIPE_PRICE_ID_ENTERPRISE = "price_enterprise";

const {
  mockGetUser,
  mockFrom,
  mockCreateSession,
  mockRetrieveSession,
  mockExpireSession,
  mockMarkerInsert,
  mockMarkerMaybeSingle,
  mockMarkerUpdateEq,
  mockMarkerDeleteEq,
  mockCaptureException,
  mockCaptureMessage,
  mockLogger,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
  mockCreateSession: vi.fn(),
  mockRetrieveSession: vi.fn(),
  mockExpireSession: vi.fn(),
  mockMarkerInsert: vi.fn(),
  mockMarkerMaybeSingle: vi.fn(),
  mockMarkerUpdateEq: vi.fn(),
  mockMarkerDeleteEq: vi.fn(),
  mockCaptureException: vi.fn(),
  mockCaptureMessage: vi.fn(),
  mockLogger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: mockFrom,
  })),
  // Service-role client — used ONLY for pending_checkout_sessions.
  createServiceClient: vi.fn(() => ({
    from: (table: string) => {
      if (table !== "pending_checkout_sessions") {
        throw new Error(`unexpected service table: ${table}`);
      }
      return {
        insert: mockMarkerInsert,
        select: () => ({
          eq: () => ({ maybeSingle: mockMarkerMaybeSingle }),
        }),
        update: () => ({ eq: mockMarkerUpdateEq }),
        delete: () => ({ eq: mockMarkerDeleteEq }),
      };
    },
  })),
}));

vi.mock("@/lib/stripe", () => ({
  getStripe: () => ({
    checkout: {
      sessions: {
        create: mockCreateSession,
        retrieve: mockRetrieveSession,
        expire: mockExpireSession,
      },
    },
  }),
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: mockCaptureException,
  captureMessage: mockCaptureMessage,
}));

vi.mock("@/server/logger", () => ({
  default: mockLogger,
  createChildLogger: () => mockLogger,
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.ai" })),
  rejectCsrf: vi.fn(
    () => new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
  ),
}));

import { POST } from "@/app/api/checkout/route";

const USER_ID = "user-uuid-123";
const USER_EMAIL = "test@example.com";
const SESSION_ID = "cs_test_marker_owned";

function makeRequest(body?: unknown): Request {
  return new Request("https://app.soleur.ai/api/checkout", {
    method: "POST",
    headers: {
      origin: "https://app.soleur.ai",
      "content-type": "application/json",
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}

function setupAuthenticatedUser() {
  mockGetUser.mockResolvedValue({
    data: { user: { id: USER_ID, email: USER_EMAIL } },
  });
  const single = vi.fn().mockResolvedValue({
    data: { stripe_customer_id: "cus_123", subscription_status: null },
    error: null,
  });
  const eq = vi.fn().mockReturnValue({ single });
  const select = vi.fn().mockReturnValue({ eq });
  mockFrom.mockReturnValue({ select });
}

function markerRow(overrides: Record<string, unknown> = {}) {
  return {
    session_id: SESSION_ID,
    target_tier: "startup",
    created_at: new Date().toISOString(),
    ...overrides,
  };
}

describe("POST /api/checkout — pending-claim idempotency (#8918)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubEnv("NEXT_PUBLIC_APP_URL", "https://test.example");
    setupAuthenticatedUser();
    // Default: claim succeeds (own the slot); Stripe create returns a session.
    mockMarkerInsert.mockResolvedValue({ error: null });
    mockMarkerUpdateEq.mockResolvedValue({ error: null });
    mockMarkerDeleteEq.mockResolvedValue({ error: null });
    mockCreateSession.mockResolvedValue({
      id: SESSION_ID,
      client_secret: "cs_new_secret",
      url: null,
      status: "open",
    });
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  test("own-slot path: claims marker, creates session with a fresh idempotencyKey, records session_id", async () => {
    const res = await POST(makeRequest({ targetTier: "startup" }));

    expect(res.status).toBe(200);
    expect(mockMarkerInsert).toHaveBeenCalledWith(
      expect.objectContaining({ user_id: USER_ID, target_tier: "startup" }),
    );
    expect(mockCreateSession).toHaveBeenCalledWith(
      expect.objectContaining({ ui_mode: "embedded" }),
      expect.objectContaining({ idempotencyKey: expect.any(String) }),
    );
    expect(mockMarkerUpdateEq).toHaveBeenCalledWith("user_id", USER_ID);
    const body = await res.json();
    expect(body.clientSecret).toBe("cs_new_secret");
  });

  test("marker-hit + open session + same tier: reuses the existing session, create NOT called", async () => {
    mockMarkerInsert.mockResolvedValue({ error: { code: "23505" } });
    mockMarkerMaybeSingle.mockResolvedValue({ data: markerRow(), error: null });
    mockRetrieveSession.mockResolvedValue({
      id: SESSION_ID,
      status: "open",
      client_secret: "cs_existing_secret",
      url: null,
    });

    const res = await POST(makeRequest({ targetTier: "startup" }));
    const body = await res.json();

    expect(res.status).toBe(200);
    expect(body.clientSecret).toBe("cs_existing_secret");
    expect(mockRetrieveSession).toHaveBeenCalledWith(SESSION_ID);
    expect(mockCreateSession).not.toHaveBeenCalled();
  });

  test("marker-hit + complete session: deletes marker, re-claims, creates a NEW session", async () => {
    mockMarkerInsert
      .mockResolvedValueOnce({ error: { code: "23505" } })
      .mockResolvedValueOnce({ error: null });
    mockMarkerMaybeSingle.mockResolvedValue({ data: markerRow(), error: null });
    mockRetrieveSession.mockResolvedValue({
      id: SESSION_ID,
      status: "complete",
      client_secret: null,
      url: null,
    });

    const res = await POST(makeRequest({ targetTier: "startup" }));
    const body = await res.json();

    expect(res.status).toBe(200);
    expect(body.clientSecret).toBe("cs_new_secret");
    expect(mockMarkerDeleteEq).toHaveBeenCalledWith("user_id", USER_ID);
    expect(mockMarkerInsert).toHaveBeenCalledTimes(2);
    expect(mockCreateSession).toHaveBeenCalledTimes(1);
  });

  test("marker-hit + expired session: deletes marker, re-claims, creates a NEW session", async () => {
    mockMarkerInsert
      .mockResolvedValueOnce({ error: { code: "23505" } })
      .mockResolvedValueOnce({ error: null });
    mockMarkerMaybeSingle.mockResolvedValue({ data: markerRow(), error: null });
    mockRetrieveSession.mockResolvedValue({
      id: SESSION_ID,
      status: "expired",
      client_secret: null,
      url: null,
    });

    const res = await POST(makeRequest({ targetTier: "startup" }));

    expect(res.status).toBe(200);
    expect(mockMarkerDeleteEq).toHaveBeenCalledWith("user_id", USER_ID);
    expect(mockCreateSession).toHaveBeenCalledTimes(1);
  });

  test("null-session marker younger than 60s: 409 checkout_in_progress, no Stripe call", async () => {
    mockMarkerInsert.mockResolvedValue({ error: { code: "23505" } });
    mockMarkerMaybeSingle.mockResolvedValue({
      data: markerRow({ session_id: null }),
      error: null,
    });

    const res = await POST(makeRequest({ targetTier: "startup" }));
    const body = await res.json();

    expect(res.status).toBe(409);
    expect(body.code).toBe("checkout_in_progress");
    expect(typeof body.error).toBe("string");
    expect(mockCreateSession).not.toHaveBeenCalled();
    expect(mockRetrieveSession).not.toHaveBeenCalled();
    expect(mockMarkerDeleteEq).not.toHaveBeenCalled();
  });

  test("null-session marker older than 60s: reclaims and creates a new session", async () => {
    mockMarkerInsert
      .mockResolvedValueOnce({ error: { code: "23505" } })
      .mockResolvedValueOnce({ error: null });
    mockMarkerMaybeSingle.mockResolvedValue({
      data: markerRow({
        session_id: null,
        created_at: new Date(Date.now() - 120_000).toISOString(),
      }),
      error: null,
    });

    const res = await POST(makeRequest({ targetTier: "startup" }));

    expect(res.status).toBe(200);
    expect(mockMarkerDeleteEq).toHaveBeenCalledWith("user_id", USER_ID);
    expect(mockCreateSession).toHaveBeenCalledTimes(1);
  });

  test("Stripe create throws after claim won: marker DELETEd before the 5xx", async () => {
    mockCreateSession.mockRejectedValue(new Error("stripe down"));

    const res = await POST(makeRequest({ targetTier: "startup" }));

    expect(res.status).toBe(500);
    expect(mockMarkerDeleteEq).toHaveBeenCalledWith("user_id", USER_ID);
    expect(mockCaptureException).toHaveBeenCalled();
  });

  test("retrieve throws on marker-hit: 500 + Sentry, marker NOT deleted", async () => {
    mockMarkerInsert.mockResolvedValue({ error: { code: "23505" } });
    mockMarkerMaybeSingle.mockResolvedValue({ data: markerRow(), error: null });
    mockRetrieveSession.mockRejectedValue(new Error("stripe 503"));

    const res = await POST(makeRequest({ targetTier: "startup" }));

    expect(res.status).toBe(500);
    expect(mockCaptureException).toHaveBeenCalled();
    expect(mockMarkerDeleteEq).not.toHaveBeenCalled();
  });

  test("marker-hit + open session + DIFFERENT tier: expires the stale session, reclaims, creates new", async () => {
    mockMarkerInsert
      .mockResolvedValueOnce({ error: { code: "23505" } })
      .mockResolvedValueOnce({ error: null });
    mockMarkerMaybeSingle.mockResolvedValue({
      data: markerRow({ target_tier: "scale" }),
      error: null,
    });
    mockRetrieveSession.mockResolvedValue({
      id: SESSION_ID,
      status: "open",
      client_secret: "cs_wrong_tier",
      url: null,
    });
    mockExpireSession.mockResolvedValue({ id: SESSION_ID, status: "expired" });

    const res = await POST(makeRequest({ targetTier: "startup" }));
    const body = await res.json();

    expect(res.status).toBe(200);
    expect(mockExpireSession).toHaveBeenCalledWith(SESSION_ID);
    expect(mockMarkerDeleteEq).toHaveBeenCalledWith("user_id", USER_ID);
    expect(mockCreateSession).toHaveBeenCalledTimes(1);
    expect(body.clientSecret).toBe("cs_new_secret");
  });

  test("non-23505 claim error: 500 + Sentry", async () => {
    mockMarkerInsert.mockResolvedValue({
      error: { code: "40001", message: "serialization_failure" },
    });

    const res = await POST(makeRequest({ targetTier: "startup" }));

    expect(res.status).toBe(500);
    expect(mockCaptureException).toHaveBeenCalled();
    expect(mockCreateSession).not.toHaveBeenCalled();
  });

  test("already-subscribed guard still short-circuits BEFORE any marker write", async () => {
    const single = vi.fn().mockResolvedValue({
      data: { stripe_customer_id: "cus_123", subscription_status: "active" },
      error: null,
    });
    const eq = vi.fn().mockReturnValue({ single });
    mockFrom.mockReturnValue({ select: vi.fn().mockReturnValue({ eq }) });

    const res = await POST(makeRequest());

    expect(res.status).toBe(400);
    expect(mockMarkerInsert).not.toHaveBeenCalled();
  });
});
