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
  mockClaimSingle,
  mockMarkerMaybeSingle,
  mockMarkerUpdate,
  mockUpdateSelect,
  mockMarkerDelete,
  mockDeleteEq1,
  mockDeleteSelect,
  mockCaptureException,
  mockCaptureMessage,
  mockLogger,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
  mockCreateSession: vi.fn(),
  mockRetrieveSession: vi.fn(),
  mockExpireSession: vi.fn(),
  // Marker-table chain terminals. The route's per-site chain shapes:
  //   insert(row).select("created_at").single()
  //   select(cols).eq("user_id",u).maybeSingle()
  //   update(patch).eq("user_id",u).eq("created_at",t).select("user_id")
  //   delete().eq("user_id",u).eq("session_id",v).select("user_id")   (reclaim)
  //   delete().eq("user_id",u).is("session_id",null).eq("created_at",t).select("user_id")  (stale-null)
  //   delete().eq("user_id",u).eq("created_at",t)                     (release — awaited bare)
  mockMarkerInsert: vi.fn(),
  mockClaimSingle: vi.fn(),
  mockMarkerMaybeSingle: vi.fn(),
  mockMarkerUpdate: vi.fn(),
  mockUpdateSelect: vi.fn(),
  mockMarkerDelete: vi.fn(),
  mockDeleteEq1: vi.fn(),
  mockDeleteSelect: vi.fn(),
  mockCaptureException: vi.fn(),
  mockCaptureMessage: vi.fn(),
  mockLogger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: mockFrom,
  })),
}));

vi.mock("@/lib/supabase/service", () => ({
  // Service-role client — used ONLY for pending_checkout_sessions.
  getServiceClient: vi.fn(() => ({
    from: (table: string) => {
      if (table !== "pending_checkout_sessions") {
        throw new Error(`unexpected service table: ${table}`);
      }
      // Second-link of a delete chain: the reclaim path calls .select()
      // on it; the release path awaits it bare — so it is thenable AND
      // exposes .select.
      const deleteEq2 = {
        select: mockDeleteSelect,
        then: (res: (v: unknown) => unknown, rej: (e: unknown) => unknown) =>
          Promise.resolve({ error: null }).then(res, rej),
      };
      return {
        insert: (row: unknown) => {
          mockMarkerInsert(row);
          return { select: () => ({ single: mockClaimSingle }) };
        },
        select: () => ({
          eq: () => ({ maybeSingle: mockMarkerMaybeSingle }),
        }),
        update: (patch: unknown) => {
          mockMarkerUpdate(patch);
          return {
            eq: () => ({ eq: () => ({ select: mockUpdateSelect }) }),
          };
        },
        delete: () => {
          mockMarkerDelete();
          return {
            eq: (...a: unknown[]) => {
              mockDeleteEq1(...a);
              return {
                // session-reclaim: .eq("session_id", v) — thenable +
                // .select so release (bare await) and reclaim both work.
                eq: () => deleteEq2,
                // stale-null: .is("session_id", null).eq("created_at").select()
                is: () => ({
                  eq: () => ({ select: mockDeleteSelect }),
                }),
              };
            },
          };
        },
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

function claimSingleOk() {
  return { data: { created_at: new Date().toISOString() }, error: null };
}

function claimSingleUniqueViolation() {
  return { data: null, error: { code: "23505" } };
}

describe("POST /api/checkout — pending-claim idempotency (#8918)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubEnv("NEXT_PUBLIC_APP_URL", "https://test.example");
    setupAuthenticatedUser();
    // Default: claim succeeds (own the slot); Stripe create returns a session.
    mockClaimSingle.mockResolvedValue(claimSingleOk());
    mockUpdateSelect.mockResolvedValue({
      data: [{ user_id: USER_ID }],
      error: null,
    });
    mockDeleteSelect.mockResolvedValue({
      data: [{ user_id: USER_ID }],
      error: null,
    });
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
    // The fenced session_id update ran to its select() terminal.
    expect(mockMarkerUpdate).toHaveBeenCalledWith(
      expect.objectContaining({ session_id: SESSION_ID }),
    );
    expect(mockUpdateSelect).toHaveBeenCalled();
    const body = await res.json();
    expect(body.clientSecret).toBe("cs_new_secret");
  });

  test("marker-hit + open session + same tier: reuses the existing session, create NOT called", async () => {
    mockClaimSingle.mockResolvedValue(claimSingleUniqueViolation());
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

  test("marker-hit + open session + null client_secret: 409 without reclaiming", async () => {
    mockClaimSingle.mockResolvedValue(claimSingleUniqueViolation());
    mockMarkerMaybeSingle.mockResolvedValue({ data: markerRow(), error: null });
    mockRetrieveSession.mockResolvedValue({
      id: SESSION_ID,
      status: "open",
      client_secret: null,
      url: null,
    });

    const res = await POST(makeRequest({ targetTier: "startup" }));
    const body = await res.json();

    expect(res.status).toBe(409);
    expect(body.code).toBe("checkout_in_progress");
    expect(mockCreateSession).not.toHaveBeenCalled();
    expect(mockMarkerDelete).not.toHaveBeenCalled();
  });

  test("marker-hit + complete session: fenced delete, re-claims, creates a NEW session", async () => {
    mockClaimSingle
      .mockResolvedValueOnce(claimSingleUniqueViolation())
      .mockResolvedValueOnce(claimSingleOk());
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
    expect(mockMarkerDelete).toHaveBeenCalledTimes(1);
    expect(mockDeleteEq1).toHaveBeenCalledWith("user_id", USER_ID);
    expect(mockMarkerInsert).toHaveBeenCalledTimes(2);
    expect(mockCreateSession).toHaveBeenCalledTimes(1);
  });

  test("marker-hit + expired session: fenced delete, re-claims, creates a NEW session", async () => {
    mockClaimSingle
      .mockResolvedValueOnce(claimSingleUniqueViolation())
      .mockResolvedValueOnce(claimSingleOk());
    mockMarkerMaybeSingle.mockResolvedValue({ data: markerRow(), error: null });
    mockRetrieveSession.mockResolvedValue({
      id: SESSION_ID,
      status: "expired",
      client_secret: null,
      url: null,
    });

    const res = await POST(makeRequest({ targetTier: "startup" }));

    expect(res.status).toBe(200);
    expect(mockMarkerDelete).toHaveBeenCalledTimes(1);
    expect(mockCreateSession).toHaveBeenCalledTimes(1);
  });

  test("null-session marker younger than 90s: 409 checkout_in_progress, no Stripe call", async () => {
    mockClaimSingle.mockResolvedValue(claimSingleUniqueViolation());
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
    expect(mockMarkerDelete).not.toHaveBeenCalled();
  });

  test("null-session marker older than 90s: fenced reclaim + new session", async () => {
    mockClaimSingle
      .mockResolvedValueOnce(claimSingleUniqueViolation())
      .mockResolvedValueOnce(claimSingleOk());
    mockMarkerMaybeSingle.mockResolvedValue({
      data: markerRow({
        session_id: null,
        created_at: new Date(Date.now() - 120_000).toISOString(),
      }),
      error: null,
    });

    const res = await POST(makeRequest({ targetTier: "startup" }));

    expect(res.status).toBe(200);
    expect(mockMarkerDelete).toHaveBeenCalledTimes(1);
    expect(mockCreateSession).toHaveBeenCalledTimes(1);
  });

  test("fenced reclaim returns 0 rows (sibling won): does NOT create a second session", async () => {
    mockClaimSingle.mockResolvedValue(claimSingleUniqueViolation());
    mockMarkerMaybeSingle.mockResolvedValue({
      data: markerRow({
        session_id: null,
        created_at: new Date(Date.now() - 120_000).toISOString(),
      }),
      error: null,
    });
    // Fenced delete deletes nothing — a sibling replaced the marker under us.
    mockDeleteSelect.mockResolvedValue({ data: [], error: null });
    // Second marker-hit: fresh null marker owned by the sibling → 409.
    mockMarkerMaybeSingle
      .mockResolvedValueOnce({
        data: markerRow({
          session_id: null,
          created_at: new Date(Date.now() - 120_000).toISOString(),
        }),
        error: null,
      })
      .mockResolvedValueOnce({
        data: markerRow({ session_id: null }),
        error: null,
      });

    const res = await POST(makeRequest({ targetTier: "startup" }));
    const body = await res.json();

    expect(res.status).toBe(409);
    expect(body.code).toBe("checkout_in_progress");
    expect(mockCreateSession).not.toHaveBeenCalled();
  });

  test("marker vanished between 23505 and select: retries claim and creates", async () => {
    mockClaimSingle
      .mockResolvedValueOnce(claimSingleUniqueViolation())
      .mockResolvedValueOnce(claimSingleOk());
    mockMarkerMaybeSingle.mockResolvedValue({ data: null, error: null });

    const res = await POST(makeRequest({ targetTier: "startup" }));

    expect(res.status).toBe(200);
    expect(mockMarkerInsert).toHaveBeenCalledTimes(2);
    expect(mockCreateSession).toHaveBeenCalledTimes(1);
  });

  test("claim + reclaim budget exhausted: 409 checkout_in_progress", async () => {
    // Both attempts 23505; first marker-hit sees a vanished marker (continue),
    // second sees a fresh null marker → 409 without a third claim.
    mockClaimSingle.mockResolvedValue(claimSingleUniqueViolation());
    mockMarkerMaybeSingle
      .mockResolvedValueOnce({ data: null, error: null })
      .mockResolvedValueOnce({
        data: markerRow({ session_id: null }),
        error: null,
      });

    const res = await POST(makeRequest({ targetTier: "startup" }));
    const body = await res.json();

    expect(res.status).toBe(409);
    expect(body.code).toBe("checkout_in_progress");
    expect(mockMarkerInsert).toHaveBeenCalledTimes(2);
    expect(mockCreateSession).not.toHaveBeenCalled();
  });

  test("Stripe create throws after claim won: fenced release before the 5xx", async () => {
    mockCreateSession.mockRejectedValue(new Error("stripe down"));

    const res = await POST(makeRequest({ targetTier: "startup" }));

    expect(res.status).toBe(500);
    expect(mockMarkerDelete).toHaveBeenCalledTimes(1);
    expect(mockDeleteEq1).toHaveBeenCalledWith("user_id", USER_ID);
    expect(mockCaptureException).toHaveBeenCalled();
  });

  test("session_id UPDATE fails: session expired, marker released, 5xx — never returns an unrecorded live session", async () => {
    mockUpdateSelect.mockResolvedValue({ data: null, error: { code: "XX000" } });
    mockExpireSession.mockResolvedValue({ id: SESSION_ID, status: "expired" });

    const res = await POST(makeRequest({ targetTier: "startup" }));

    expect(res.status).toBe(500);
    expect(mockExpireSession).toHaveBeenCalledWith(SESSION_ID);
    expect(mockMarkerDelete).toHaveBeenCalledTimes(1);
    expect(mockCaptureException).toHaveBeenCalled();
  });

  test("session_id UPDATE fenced out (claim reclaimed mid-create): session expired + 409", async () => {
    mockUpdateSelect.mockResolvedValue({ data: [], error: null });
    mockExpireSession.mockResolvedValue({ id: SESSION_ID, status: "expired" });

    const res = await POST(makeRequest({ targetTier: "startup" }));
    const body = await res.json();

    expect(res.status).toBe(409);
    expect(body.code).toBe("checkout_in_progress");
    expect(mockExpireSession).toHaveBeenCalledWith(SESSION_ID);
    expect(mockMarkerDelete).not.toHaveBeenCalled();
  });

  test("retrieve throws on marker-hit: 500 + Sentry, marker NOT deleted", async () => {
    mockClaimSingle.mockResolvedValue(claimSingleUniqueViolation());
    mockMarkerMaybeSingle.mockResolvedValue({ data: markerRow(), error: null });
    mockRetrieveSession.mockRejectedValue(new Error("stripe 503"));

    const res = await POST(makeRequest({ targetTier: "startup" }));

    expect(res.status).toBe(500);
    expect(mockCaptureException).toHaveBeenCalled();
    expect(mockMarkerDelete).not.toHaveBeenCalled();
  });

  test("marker-hit + open session + DIFFERENT tier: fenced reclaim wins, then expires + creates", async () => {
    mockClaimSingle
      .mockResolvedValueOnce(claimSingleUniqueViolation())
      .mockResolvedValueOnce(claimSingleOk());
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
    // Fenced delete wins BEFORE the expire call — assert call order.
    const deleteIdx = mockMarkerDelete.mock.invocationCallOrder[0];
    const expireIdx = mockExpireSession.mock.invocationCallOrder[0];
    expect(deleteIdx).toBeLessThan(expireIdx);
    expect(mockExpireSession).toHaveBeenCalledWith(SESSION_ID);
    expect(mockCreateSession).toHaveBeenCalledTimes(1);
    expect(body.clientSecret).toBe("cs_new_secret");
  });

  test("non-23505 claim error: 500 + Sentry", async () => {
    mockClaimSingle.mockResolvedValue({
      data: null,
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
