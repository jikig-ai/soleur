import { describe, test, expect, vi, beforeEach } from "vitest";
import type Stripe from "stripe";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const {
  mockConstructEvent,
  mockUpdate,
  mockUpdateEq,
  mockSelect,
  mockSelectEq,
  mockSingle,
  mockLogger,
} = vi.hoisted(() => ({
  mockConstructEvent: vi.fn(),
  mockUpdate: vi.fn(),
  mockUpdateEq: vi.fn(),
  mockSelect: vi.fn(),
  mockSelectEq: vi.fn(),
  mockSingle: vi.fn(),
  mockLogger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

vi.mock("@/lib/stripe", () => ({
  getStripe: () => ({
    webhooks: { constructEvent: mockConstructEvent },
  }),
}));

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: () => ({
    from: () => ({
      update: mockUpdate,
      select: mockSelect,
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
// Tests — invoice payment recovery webhook events
// ---------------------------------------------------------------------------

describe("Stripe webhook — invoice payment recovery", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Wire select chain: from().select().eq().single()
    mockSingle.mockResolvedValue({
      data: { subscription_status: "past_due" },
      error: null,
    });
    mockSelectEq.mockReturnValue({ single: mockSingle });
    mockSelect.mockReturnValue({ eq: mockSelectEq });
    // Wire update chain: from().update().eq()
    mockUpdateEq.mockResolvedValue({ error: null });
    mockUpdate.mockReturnValue({ eq: mockUpdateEq });
  });

  describe("customer.subscription.updated — unpaid status", () => {
    test("maps Stripe 'unpaid' to DB 'unpaid' (not 'past_due')", async () => {
      const event = makeEvent("customer.subscription.updated", {
        customer: CUSTOMER_ID,
        status: "unpaid",
        cancel_at_period_end: false,
        current_period_end: 1_700_000_000,
      });
      mockConstructEvent.mockReturnValue(event);

      await POST(makeRequest());

      expect(mockUpdate).toHaveBeenCalledWith(
        expect.objectContaining({ subscription_status: "unpaid" }),
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

    test("maps Stripe 'active' restores DB 'active'", async () => {
      const event = makeEvent("customer.subscription.updated", {
        customer: CUSTOMER_ID,
        status: "active",
        cancel_at_period_end: false,
        current_period_end: 1_700_000_000,
      });
      mockConstructEvent.mockReturnValue(event);

      await POST(makeRequest());

      expect(mockUpdate).toHaveBeenCalledWith(
        expect.objectContaining({ subscription_status: "active" }),
      );
    });
  });

  describe("invoice.payment_failed", () => {
    test("does NOT change subscription_status (log only)", async () => {
      const event = makeEvent("invoice.payment_failed", {
        id: "inv_fail_123",
        customer: CUSTOMER_ID,
        subscription: "sub_test456",
      });
      mockConstructEvent.mockReturnValue(event);

      const res = await POST(makeRequest());

      expect(res.status).toBe(200);
      expect(mockUpdate).not.toHaveBeenCalled();
      expect(mockLogger.warn).toHaveBeenCalledWith(
        expect.objectContaining({ customerId: CUSTOMER_ID }),
        expect.stringContaining("payment_failed"),
      );
    });
  });

  describe("invoice.paid", () => {
    test("sets subscription_status to 'active' when user is past_due", async () => {
      const event = makeEvent("invoice.paid", {
        id: "inv_paid_123",
        customer: CUSTOMER_ID,
        subscription: "sub_test456",
      });
      mockConstructEvent.mockReturnValue(event);

      const res = await POST(makeRequest());

      expect(res.status).toBe(200);
      expect(mockSelect).toHaveBeenCalledWith("subscription_status");
      expect(mockSelectEq).toHaveBeenCalledWith(
        "stripe_customer_id",
        CUSTOMER_ID,
      );
      expect(mockUpdate).toHaveBeenCalledWith(
        expect.objectContaining({ subscription_status: "active" }),
      );
    });

    test("skips update when user is already active", async () => {
      mockSingle.mockResolvedValue({
        data: { subscription_status: "active" },
        error: null,
      });
      const event = makeEvent("invoice.paid", {
        id: "inv_paid_123",
        customer: CUSTOMER_ID,
        subscription: "sub_test456",
      });
      mockConstructEvent.mockReturnValue(event);

      const res = await POST(makeRequest());

      expect(res.status).toBe(200);
      expect(mockUpdate).not.toHaveBeenCalled();
    });

    test("skips update when user is cancelled", async () => {
      mockSingle.mockResolvedValue({
        data: { subscription_status: "cancelled" },
        error: null,
      });
      const event = makeEvent("invoice.paid", {
        id: "inv_paid_123",
        customer: CUSTOMER_ID,
        subscription: "sub_test456",
      });
      mockConstructEvent.mockReturnValue(event);

      const res = await POST(makeRequest());

      expect(res.status).toBe(200);
      expect(mockUpdate).not.toHaveBeenCalled();
    });

    test("returns 500 when DB fetch fails", async () => {
      mockSingle.mockResolvedValue({
        data: null,
        error: { message: "db error" },
      });
      const event = makeEvent("invoice.paid", {
        id: "inv_paid_123",
        customer: CUSTOMER_ID,
        subscription: "sub_test456",
      });
      mockConstructEvent.mockReturnValue(event);

      const res = await POST(makeRequest());

      expect(res.status).toBe(500);
      expect(mockLogger.error).toHaveBeenCalled();
      expect(mockUpdate).not.toHaveBeenCalled();
    });

    test("returns 500 when DB update fails", async () => {
      const event = makeEvent("invoice.paid", {
        id: "inv_paid_123",
        customer: CUSTOMER_ID,
        subscription: "sub_test456",
      });
      mockConstructEvent.mockReturnValue(event);
      mockUpdateEq.mockResolvedValue({ error: { message: "db error" } });

      const res = await POST(makeRequest());

      expect(res.status).toBe(500);
      expect(mockLogger.error).toHaveBeenCalled();
    });
  });

  describe("idempotency", () => {
    test("duplicate event with same status is a no-op update (returns 200)", async () => {
      const event = makeEvent("customer.subscription.updated", {
        customer: CUSTOMER_ID,
        status: "unpaid",
        cancel_at_period_end: false,
        current_period_end: 1_700_000_000,
      });
      mockConstructEvent.mockReturnValue(event);

      const res1 = await POST(makeRequest());
      const res2 = await POST(makeRequest());

      expect(res1.status).toBe(200);
      expect(res2.status).toBe(200);
    });
  });

  describe("signature verification", () => {
    test("returns 400 when signature verification fails", async () => {
      mockConstructEvent.mockImplementation(() => {
        throw new Error("Invalid signature");
      });

      const res = await POST(makeRequest());

      expect(res.status).toBe(400);
    });
  });
});
