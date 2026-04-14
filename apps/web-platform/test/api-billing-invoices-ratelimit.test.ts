import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const { mockGetUser, mockFrom, mockInvoicesList } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
  mockInvoicesList: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: mockFrom,
  })),
}));

vi.mock("@/lib/stripe", () => ({
  getStripe: () => ({
    invoices: { list: mockInvoicesList },
  }),
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }),
}));

// ---------------------------------------------------------------------------
// Import route handler + throttle singleton AFTER mocks
// ---------------------------------------------------------------------------

import { GET } from "@/app/api/billing/invoices/route";
import {
  invoiceEndpointThrottle,
  __resetInvoiceThrottleForTest,
} from "@/server/rate-limiter";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const USER_A = "user-aaa-111";
const USER_B = "user-bbb-222";
const CUSTOMER_ID = "cus_test_abc";

function setupUser(userId: string | null) {
  if (userId === null) {
    mockGetUser.mockResolvedValue({ data: { user: null } });
  } else {
    mockGetUser.mockResolvedValue({ data: { user: { id: userId } } });
  }
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

describe("GET /api/billing/invoices — per-user rate limit", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    __resetInvoiceThrottleForTest();
    // Default: authenticated user with valid Stripe customer, empty invoice list.
    setupUserQuery({ stripe_customer_id: CUSTOMER_ID });
    mockInvoicesList.mockResolvedValue({ data: [] });
  });

  test("first 10 requests in a minute all return 200", async () => {
    setupUser(USER_A);

    for (let i = 0; i < 10; i++) {
      const res = await GET();
      expect(res.status).toBe(200);
    }
  });

  test("11th request within the same minute returns 429 with Retry-After: 60", async () => {
    setupUser(USER_A);

    // Exhaust the bucket.
    for (let i = 0; i < 10; i++) {
      const res = await GET();
      expect(res.status).toBe(200);
    }

    const res = await GET();
    expect(res.status).toBe(429);
    expect(res.headers.get("Retry-After")).toBe("60");
  });

  test("different users don't share the throttle", async () => {
    setupUser(USER_A);
    for (let i = 0; i < 10; i++) {
      const res = await GET();
      expect(res.status).toBe(200);
    }

    // User A is exhausted.
    const resA = await GET();
    expect(resA.status).toBe(429);

    // User B should still have a full bucket.
    setupUser(USER_B);
    const resB = await GET();
    expect(resB.status).toBe(200);
  });

  test("unauthenticated request returns 401 without consuming throttle slot", async () => {
    setupUser(null);

    // 15 unauthenticated requests — more than the 10/min limit.
    for (let i = 0; i < 15; i++) {
      const res = await GET();
      expect(res.status).toBe(401);
    }

    // Now authenticate and verify the authenticated user's slots are untouched.
    setupUser(USER_A);
    for (let i = 0; i < 10; i++) {
      const res = await GET();
      expect(res.status).toBe(200);
    }
  });
});
