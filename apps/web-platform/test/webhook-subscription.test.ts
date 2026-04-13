import { describe, test, expect, vi, beforeEach } from "vitest";
import type Stripe from "stripe";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const { mockConstructEvent, mockUpdate, mockEq, mockLogger } = vi.hoisted(
  () => ({
    mockConstructEvent: vi.fn(),
    mockUpdate: vi.fn(),
    mockEq: vi.fn(),
    mockLogger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  }),
);

vi.mock("@/lib/stripe", () => ({
  getStripe: () => ({
    webhooks: { constructEvent: mockConstructEvent },
  }),
}));

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: () => ({
    from: () => ({
      update: mockUpdate,
    }),
  }),
}));

vi.mock("@/server/logger", () => ({ default: mockLogger }));

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
    // Default: update chain resolves successfully
    mockEq.mockResolvedValue({ error: null });
    mockUpdate.mockReturnValue({ eq: mockEq });
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

  describe("unhandled events", () => {
    test("returns 200 for unhandled event types", async () => {
      const event = makeEvent("invoice.paid", { id: "inv_123" });
      mockConstructEvent.mockReturnValue(event);

      const res = await POST(makeRequest());

      expect(res.status).toBe(200);
      expect(mockUpdate).not.toHaveBeenCalled();
    });
  });
});
