import { describe, test, expect, vi, beforeEach } from "vitest";
import type Stripe from "stripe";
import {
  configureSupabaseUpdateChain,
  configureSupabaseInsertChain,
} from "./helpers/supabase-update-chain";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const {
  mockConstructEvent,
  mockUpdate,
  mockEq,
  mockIn,
  mockSelect,
  mockInsert,
  mockDeleteEq,
  mockLogger,
} = vi.hoisted(() => ({
  mockConstructEvent: vi.fn(),
  mockUpdate: vi.fn(),
  mockEq: vi.fn(),
  mockIn: vi.fn(),
  mockSelect: vi.fn(),
  mockInsert: vi.fn(),
  mockDeleteEq: vi.fn(),
  mockLogger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

vi.mock("@/lib/stripe", () => ({
  getStripe: () => ({
    webhooks: { constructEvent: mockConstructEvent },
  }),
  invalidateTierMemo: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: () => ({
    from: (table: string) => {
      if (table === "processed_stripe_events") {
        return {
          insert: mockInsert,
          delete: () => ({ eq: mockDeleteEq }),
        };
      }
      return {
        update: mockUpdate,
        select: () => ({
          eq: () => ({
            maybeSingle: vi.fn().mockResolvedValue({
              data: { id: "user-123", plan_tier: "free", concurrency_override: null, subscription_status: "active" },
              error: null,
            }),
          }),
        }),
      };
    },
  }),
}));

vi.mock("@/lib/stripe-price-tier-map", () => ({
  getPriceTier: () => "free",
  priceIdForTier: () => null,
}));

vi.mock("@/server/logger", () => ({
  default: mockLogger,
  createChildLogger: () => mockLogger,
}));

// Avoid pulling in ws-handler's full transitive closure (agent-runner etc.).
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
    configureSupabaseUpdateChain({ mockUpdate, mockEq, mockIn, mockSelect });
    configureSupabaseInsertChain({ mockInsert, mockDeleteEq });
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
    test("sets subscription_status to 'active' filtered by past_due/unpaid", async () => {
      const event = makeEvent("invoice.paid", {
        id: "inv_paid_123",
        customer: CUSTOMER_ID,
        subscription: "sub_test456",
      });
      mockConstructEvent.mockReturnValue(event);

      const res = await POST(makeRequest());

      expect(res.status).toBe(200);
      expect(mockUpdate).toHaveBeenCalledWith(
        expect.objectContaining({ subscription_status: "active" }),
      );
      expect(mockEq).toHaveBeenCalledWith("stripe_customer_id", CUSTOMER_ID);
      expect(mockIn).toHaveBeenCalledWith("subscription_status", [
        "past_due",
        "unpaid",
      ]);
    });

    test("returns 500 when DB update fails", async () => {
      const event = makeEvent("invoice.paid", {
        id: "inv_paid_123",
        customer: CUSTOMER_ID,
        subscription: "sub_test456",
      });
      mockConstructEvent.mockReturnValue(event);
      mockSelect.mockResolvedValue({
        data: null,
        error: { message: "db error" },
      });

      const res = await POST(makeRequest());

      expect(res.status).toBe(500);
      expect(mockLogger.error).toHaveBeenCalled();
    });

    test("no-op when current status is 'cancelled' (the bug fix)", async () => {
      // Simulate a replayed invoice.paid arriving for an already-cancelled
      // subscription. The atomic UPDATE ... WHERE status IN ('past_due','unpaid')
      // matches zero rows. PostgREST returns { data: [], error: null } — NOT a 500.
      const event = makeEvent("invoice.paid", {
        id: "inv_paid_replay",
        customer: CUSTOMER_ID,
        subscription: "sub_test456",
      });
      mockConstructEvent.mockReturnValue(event);
      // 0 rows matched — no error returned by PostgREST.
      mockSelect.mockResolvedValue({ data: [], error: null });

      const res = await POST(makeRequest());

      expect(res.status).toBe(200);
      expect(mockIn).toHaveBeenCalledWith("subscription_status", [
        "past_due",
        "unpaid",
      ]);
      expect(mockLogger.error).not.toHaveBeenCalled();
      // Observability: matched=0 gets logged at info level for Better Stack alerts.
      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({ customerId: CUSTOMER_ID, matched: 0 }),
        expect.stringContaining("invoice.paid applied"),
      );
    });

    test("applies update when current status is 'past_due'", async () => {
      const event = makeEvent("invoice.paid", {
        id: "inv_paid_pastdue",
        customer: CUSTOMER_ID,
        subscription: "sub_test456",
      });
      mockConstructEvent.mockReturnValue(event);
      mockSelect.mockResolvedValue({
        data: [{ id: "user-123" }],
        error: null,
      });

      const res = await POST(makeRequest());

      expect(res.status).toBe(200);
      expect(mockUpdate).toHaveBeenCalledWith(
        expect.objectContaining({ subscription_status: "active" }),
      );
      expect(mockEq).toHaveBeenCalledWith("stripe_customer_id", CUSTOMER_ID);
      expect(mockIn).toHaveBeenCalledWith("subscription_status", [
        "past_due",
        "unpaid",
      ]);
      expect(mockLogger.info).toHaveBeenCalledWith(
        expect.objectContaining({ customerId: CUSTOMER_ID, matched: 1 }),
        expect.stringContaining("invoice.paid applied"),
      );
    });

    test("applies update when current status is 'unpaid'", async () => {
      const event = makeEvent("invoice.paid", {
        id: "inv_paid_unpaid",
        customer: CUSTOMER_ID,
        subscription: "sub_test456",
      });
      mockConstructEvent.mockReturnValue(event);
      mockSelect.mockResolvedValue({
        data: [{ id: "user-123" }],
        error: null,
      });

      const res = await POST(makeRequest());

      expect(res.status).toBe(200);
      expect(mockUpdate).toHaveBeenCalledWith(
        expect.objectContaining({ subscription_status: "active" }),
      );
      expect(mockEq).toHaveBeenCalledWith("stripe_customer_id", CUSTOMER_ID);
      expect(mockIn).toHaveBeenCalledWith("subscription_status", [
        "past_due",
        "unpaid",
      ]);
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
