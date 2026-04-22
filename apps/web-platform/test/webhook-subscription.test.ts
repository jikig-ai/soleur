import { describe, test, expect, vi, beforeEach } from "vitest";
import type Stripe from "stripe";
import { configureSupabaseUpdateChain } from "./helpers/supabase-update-chain";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const { mockConstructEvent, mockUpdate, mockEq, mockIn, mockSelect, mockLogger } =
  vi.hoisted(() => ({
    mockConstructEvent: vi.fn(),
    mockUpdate: vi.fn(),
    mockEq: vi.fn(),
    mockIn: vi.fn(),
    mockSelect: vi.fn(),
    mockLogger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  }));

vi.mock("@/lib/stripe", () => ({
  getStripe: () => ({
    webhooks: { constructEvent: mockConstructEvent },
  }),
  invalidateTierMemo: vi.fn(),
}));

vi.mock("@/lib/stripe-price-tier-map", () => ({
  getPriceTier: () => "startup",
  priceIdForTier: () => "price_startup",
}));

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: () => ({
    from: () => ({
      update: mockUpdate,
      select: () => ({
        eq: () => ({
          maybeSingle: vi.fn().mockResolvedValue({
            data: { id: "user-uuid-123", plan_tier: "free", concurrency_override: null, subscription_status: "none" },
            error: null,
          }),
        }),
      }),
    }),
  }),
}));

vi.mock("@/server/logger", () => ({
  default: mockLogger,
  createChildLogger: () => mockLogger,
}));

vi.mock("@/server/ws-handler", () => ({
  forceDisconnectForTierChange: vi.fn(() => false),
}));

// ---------------------------------------------------------------------------
// Import route handler AFTER mocks
// ---------------------------------------------------------------------------

import { POST } from "@/app/api/webhooks/stripe/route";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const CUSTOMER_ID = "cus_test123";
const SUBSCRIPTION_ID = "sub_test456";
const USER_ID = "user-uuid-123";

function makeRequest(body = "raw-body"): Request {
  return new Request("https://app.soleur.ai/api/webhooks/stripe", {
    method: "POST",
    headers: { "stripe-signature": "sig_test" },
    body,
  });
}

function makeEvent(
  type: string,
  object: Record<string, unknown>,
): Stripe.Event {
  return {
    type,
    data: { object },
  } as unknown as Stripe.Event;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("Stripe webhook — subscription lifecycle", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Default chain: 1 matched row, no error at any level. Tests override
    // individual mock return values to assert zero-match or error paths.
    configureSupabaseUpdateChain({ mockUpdate, mockEq, mockIn, mockSelect });
  });

  describe("checkout.session.completed", () => {
    test("stores stripe_customer_id, subscription_status, and stripe_subscription_id", async () => {
      const event = makeEvent("checkout.session.completed", {
        customer: CUSTOMER_ID,
        subscription: SUBSCRIPTION_ID,
        metadata: { supabase_user_id: USER_ID },
      });
      mockConstructEvent.mockReturnValue(event);

      const res = await POST(makeRequest());

      expect(res.status).toBe(200);
      expect(mockUpdate).toHaveBeenCalledWith(
        expect.objectContaining({
          stripe_customer_id: CUSTOMER_ID,
          subscription_status: "active",
          stripe_subscription_id: SUBSCRIPTION_ID,
        }),
      );
      expect(mockEq).toHaveBeenCalledWith("id", USER_ID);
    });
  });

  describe("customer.subscription.updated", () => {
    test("updates subscription_status, cancel_at_period_end, and current_period_end", async () => {
      const periodEnd = Math.floor(Date.now() / 1_000) + 86_400 * 30;
      const event = makeEvent("customer.subscription.updated", {
        customer: CUSTOMER_ID,
        status: "active",
        cancel_at_period_end: true,
        current_period_end: periodEnd,
      });
      mockConstructEvent.mockReturnValue(event);

      const res = await POST(makeRequest());

      expect(res.status).toBe(200);
      expect(mockUpdate).toHaveBeenCalledWith(
        expect.objectContaining({
          subscription_status: "active",
          cancel_at_period_end: true,
          current_period_end: new Date(periodEnd * 1_000).toISOString(),
        }),
      );
      expect(mockEq).toHaveBeenCalledWith("stripe_customer_id", CUSTOMER_ID);
    });

    test("handles string customer ID from subscription object", async () => {
      const event = makeEvent("customer.subscription.updated", {
        customer: CUSTOMER_ID,
        status: "active",
        cancel_at_period_end: false,
        current_period_end: 1_700_000_000,
      });
      mockConstructEvent.mockReturnValue(event);

      const res = await POST(makeRequest());

      expect(res.status).toBe(200);
      expect(mockEq).toHaveBeenCalledWith("stripe_customer_id", CUSTOMER_ID);
    });
  });

  describe("customer.subscription.deleted", () => {
    test("sets cancelled status, clears cancel_at_period_end and current_period_end", async () => {
      const event = makeEvent("customer.subscription.deleted", {
        customer: CUSTOMER_ID,
      });
      mockConstructEvent.mockReturnValue(event);

      const res = await POST(makeRequest());

      expect(res.status).toBe(200);
      expect(mockUpdate).toHaveBeenCalledWith(
        expect.objectContaining({
          subscription_status: "cancelled",
          cancel_at_period_end: false,
          current_period_end: null,
        }),
      );
      expect(mockEq).toHaveBeenCalledWith("stripe_customer_id", CUSTOMER_ID);
    });
  });

  describe("signature verification", () => {
    test("returns 400 when stripe-signature header is missing", async () => {
      const req = new Request("https://app.soleur.ai/api/webhooks/stripe", {
        method: "POST",
        body: "raw-body",
      });

      const res = await POST(req);

      expect(res.status).toBe(400);
      const body = await res.json();
      expect(body.error).toMatch(/missing/i);
    });

    test("returns 400 when signature verification fails", async () => {
      mockConstructEvent.mockImplementation(() => {
        throw new Error("Invalid signature");
      });

      const res = await POST(makeRequest());

      expect(res.status).toBe(400);
    });
  });

  describe("status mapping", () => {
    test("maps Stripe 'trialing' to DB 'active'", async () => {
      const event = makeEvent("customer.subscription.updated", {
        customer: CUSTOMER_ID,
        status: "trialing",
        cancel_at_period_end: false,
        current_period_end: 1_700_000_000,
      });
      mockConstructEvent.mockReturnValue(event);

      await POST(makeRequest());

      expect(mockUpdate).toHaveBeenCalledWith(
        expect.objectContaining({ subscription_status: "active" }),
      );
    });

    test("maps Stripe 'past_due' to DB 'past_due'", async () => {
      const event = makeEvent("customer.subscription.updated", {
        customer: CUSTOMER_ID,
        status: "past_due",
        cancel_at_period_end: false,
        current_period_end: 1_700_000_000,
      });
      mockConstructEvent.mockReturnValue(event);

      await POST(makeRequest());

      expect(mockUpdate).toHaveBeenCalledWith(
        expect.objectContaining({ subscription_status: "past_due" }),
      );
    });

    test("maps Stripe 'canceled' to DB 'cancelled'", async () => {
      const event = makeEvent("customer.subscription.updated", {
        customer: CUSTOMER_ID,
        status: "canceled",
        cancel_at_period_end: false,
        current_period_end: 1_700_000_000,
      });
      mockConstructEvent.mockReturnValue(event);

      await POST(makeRequest());

      expect(mockUpdate).toHaveBeenCalledWith(
        expect.objectContaining({ subscription_status: "cancelled" }),
      );
    });
  });

  describe("error handling", () => {
    test("returns 500 when DB update fails on checkout.session.completed", async () => {
      const event = makeEvent("checkout.session.completed", {
        customer: CUSTOMER_ID,
        subscription: SUBSCRIPTION_ID,
        metadata: { supabase_user_id: USER_ID },
      });
      mockConstructEvent.mockReturnValue(event);
      mockEq.mockResolvedValue({ error: { message: "constraint violation" } });

      const res = await POST(makeRequest());

      expect(res.status).toBe(500);
      expect(mockLogger.error).toHaveBeenCalled();
    });

    test("returns 500 when DB update fails on subscription.updated", async () => {
      const event = makeEvent("customer.subscription.updated", {
        customer: CUSTOMER_ID,
        status: "active",
        cancel_at_period_end: false,
        current_period_end: 1_700_000_000,
      });
      mockConstructEvent.mockReturnValue(event);
      // New chain: error surfaces from .select(), not .eq()
      mockSelect.mockResolvedValue({ data: null, error: { message: "connection lost" } });

      const res = await POST(makeRequest());

      expect(res.status).toBe(500);
    });
  });

  describe("out-of-order event guards (#2190)", () => {
    test(".updated guard filters by SUBSCRIPTION_UPDATABLE_STATUSES regardless of newStatus", async () => {
      // P1 fix: the guard must fire for every newStatus, not only "active".
      // A stale .updated(past_due) replayed after .deleted must also no-op.
      const event = makeEvent("customer.subscription.updated", {
        customer: CUSTOMER_ID,
        status: "past_due",
        cancel_at_period_end: false,
        current_period_end: 1_700_000_000,
      });
      mockConstructEvent.mockReturnValue(event);

      const res = await POST(makeRequest());

      expect(res.status).toBe(200);
      expect(mockIn).toHaveBeenCalledWith("subscription_status", [
        "none",
        "active",
        "past_due",
        "unpaid",
      ]);
    });

    test(".updated guard filter applies on active transitions too", async () => {
      const event = makeEvent("customer.subscription.updated", {
        customer: CUSTOMER_ID,
        status: "active",
        cancel_at_period_end: false,
        current_period_end: 1_700_000_000,
      });
      mockConstructEvent.mockReturnValue(event);

      await POST(makeRequest());

      expect(mockIn).toHaveBeenCalledWith("subscription_status", [
        "none",
        "active",
        "past_due",
        "unpaid",
      ]);
    });

    test(".deleted guard filter excludes 'none' and 'cancelled'", async () => {
      const event = makeEvent("customer.subscription.deleted", {
        customer: CUSTOMER_ID,
      });
      mockConstructEvent.mockReturnValue(event);

      await POST(makeRequest());

      expect(mockIn).toHaveBeenCalledWith("subscription_status", [
        "active",
        "past_due",
        "unpaid",
      ]);
    });

    test(".updated against cancelled row is a no-op (zero matched) — AC #3", async () => {
      // Simulate a cancelled row: the .in() filter returns an empty rowset.
      mockSelect.mockResolvedValueOnce({ data: [], error: null });
      const event = makeEvent("customer.subscription.updated", {
        customer: CUSTOMER_ID,
        status: "active",
        cancel_at_period_end: false,
        current_period_end: 1_700_000_000,
      });
      mockConstructEvent.mockReturnValue(event);

      const res = await POST(makeRequest());

      expect(res.status).toBe(200);
      expect(mockLogger.warn).toHaveBeenCalledWith(
        expect.objectContaining({ customerId: CUSTOMER_ID, newStatus: "active" }),
        expect.stringContaining("guard no-op"),
      );
      expect(mockLogger.info).not.toHaveBeenCalled();
    });

    test(".deleted against already-cancelled row is a no-op (zero matched) — AC #4", async () => {
      mockSelect.mockResolvedValueOnce({ data: [], error: null });
      const event = makeEvent("customer.subscription.deleted", {
        customer: CUSTOMER_ID,
      });
      mockConstructEvent.mockReturnValue(event);

      const res = await POST(makeRequest());

      expect(res.status).toBe(200);
      expect(mockLogger.warn).toHaveBeenCalledWith(
        expect.objectContaining({ customerId: CUSTOMER_ID }),
        expect.stringContaining("guard no-op"),
      );
      expect(mockLogger.info).not.toHaveBeenCalled();
    });

    test("matched .updated logs info with matched count", async () => {
      const event = makeEvent("customer.subscription.updated", {
        customer: CUSTOMER_ID,
        status: "active",
        cancel_at_period_end: false,
        current_period_end: 1_700_000_000,
      });
      mockConstructEvent.mockReturnValue(event);

      await POST(makeRequest());

      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({ customerId: CUSTOMER_ID, matched: 1 }),
        expect.stringContaining("applied"),
      );
    });
  });

  describe("unhandled events", () => {
    test("returns 200 for unhandled event types", async () => {
      const event = makeEvent("payment_intent.succeeded", { id: "pi_123" });
      mockConstructEvent.mockReturnValue(event);

      const res = await POST(makeRequest());

      expect(res.status).toBe(200);
      expect(mockUpdate).not.toHaveBeenCalled();
    });
  });
});
