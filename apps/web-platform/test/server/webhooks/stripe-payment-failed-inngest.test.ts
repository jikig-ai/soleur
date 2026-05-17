import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import type Stripe from "stripe";

// PR-F (#3244, #3940) Phase 4 — Stripe webhook → Inngest bridge for
// invoice.payment_failed. Gated by SOLEUR_FR5_ENABLED (default false at
// merge per Phase 0 ops task).
//
// Test contract:
//   - SOLEUR_FR5_ENABLED unset/false → existing log behavior, NO inngest.send.
//   - SOLEUR_FR5_ENABLED=true       → inngest.send fires with envelope
//     {id: `stripe-${event.id}`, name: "finance.payment_failed", v: "1"}
//     AFTER the processed_stripe_events dedup insert (which already lives
//     in the route at lines 116-118).
//   - Stripe redelivery (same event.id twice) → inngest.send fires ONCE
//     because dedup short-circuits the second call with 200 before reaching
//     the switch.
//   - Minimization (RV7): `data.payload` carries no `@`, no `payment_method`,
//     keeps amount/currency/failureCode/invoiceId.
//   - Inngest unreachable → reportSilentFallback fires; webhook STILL
//     returns 200 (Stripe redelivery handles eventual delivery).

const {
  mockConstructEvent,
  mockInsert,
  mockDeleteEq,
  mockMaybeSingle,
  mockLogger,
  mockReportSilentFallback,
  mockInngestSend,
} = vi.hoisted(() => ({
  mockConstructEvent: vi.fn(),
  mockInsert: vi.fn(),
  mockDeleteEq: vi.fn(),
  mockMaybeSingle: vi.fn(),
  mockLogger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  mockReportSilentFallback: vi.fn(),
  mockInngestSend: vi.fn(),
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
      // users table — looked up by stripe_customer_id for founderId.
      return {
        update: vi.fn(),
        select: () => ({
          eq: () => ({ maybeSingle: mockMaybeSingle }),
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

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

vi.mock("@/server/inngest/client", () => ({
  inngest: { send: mockInngestSend },
}));

// Avoid pulling in ws-handler's full transitive closure (#3244 unrelated).
vi.mock("@/server/ws-handler", () => ({
  forceDisconnectForTierChange: vi.fn(() => false),
}));

import { POST } from "@/app/api/webhooks/stripe/route";

const CUSTOMER_ID = "cus_test_pf_001";
const FOUNDER_ID = "founder-uuid-001";

function makeRequest(): Request {
  return new Request("https://app.soleur.ai/api/webhooks/stripe", {
    method: "POST",
    headers: { "stripe-signature": "sig_test" },
    body: "raw-body",
  });
}

function makePaymentFailedEvent(overrides: Partial<Stripe.Invoice> = {}, eventId = "evt_pf_001"): Stripe.Event {
  return {
    id: eventId,
    type: "invoice.payment_failed",
    data: {
      object: {
        id: "in_pf_001",
        customer: CUSTOMER_ID,
        customer_email: "founder@example.com",
        amount_due: 4200,
        currency: "usd",
        last_finalization_error: { code: "card_declined" },
        // Sensitive field we MUST drop in minimization.
        payment_method: "pm_test_secret_001",
        ...overrides,
      },
    },
  } as unknown as Stripe.Event;
}

const ORIGINAL_ENV = {
  SOLEUR_FR5_ENABLED: process.env.SOLEUR_FR5_ENABLED,
};

function restoreEnv(key: keyof typeof ORIGINAL_ENV) {
  if (ORIGINAL_ENV[key] === undefined) delete process.env[key];
  else process.env[key] = ORIGINAL_ENV[key];
}

beforeEach(() => {
  vi.clearAllMocks();
  // Default dedup success (no existing row).
  mockInsert.mockResolvedValue({ data: null, error: null });
  // Default founder lookup hit.
  mockMaybeSingle.mockResolvedValue({
    data: { id: FOUNDER_ID, stripe_customer_id: CUSTOMER_ID },
    error: null,
  });
  delete process.env.SOLEUR_FR5_ENABLED;
});

afterEach(() => {
  restoreEnv("SOLEUR_FR5_ENABLED");
});

describe("Stripe invoice.payment_failed → Inngest bridge (FR5)", () => {
  test("SOLEUR_FR5_ENABLED unset → returns 200, does NOT call inngest.send", async () => {
    mockConstructEvent.mockReturnValue(makePaymentFailedEvent());
    const res = await POST(makeRequest());
    expect(res.status).toBe(200);
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  test("SOLEUR_FR5_ENABLED=false → does NOT call inngest.send", async () => {
    process.env.SOLEUR_FR5_ENABLED = "false";
    mockConstructEvent.mockReturnValue(makePaymentFailedEvent());
    const res = await POST(makeRequest());
    expect(res.status).toBe(200);
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  test("SOLEUR_FR5_ENABLED=true → fires inngest.send exactly once with v=1 envelope", async () => {
    process.env.SOLEUR_FR5_ENABLED = "true";
    mockConstructEvent.mockReturnValue(makePaymentFailedEvent());
    const res = await POST(makeRequest());
    expect(res.status).toBe(200);
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
    const envelope = mockInngestSend.mock.calls[0][0] as {
      id: string;
      name: string;
      v: string;
      data: Record<string, unknown>;
    };
    expect(envelope.id).toBe("stripe-evt_pf_001");
    expect(envelope.name).toBe("finance.payment_failed");
    expect(envelope.v).toBe("1");
    expect(envelope.data.founderId).toBe(FOUNDER_ID);
  });

  test("Stripe redelivery (same event.id twice) → inngest.send fires only ONCE", async () => {
    process.env.SOLEUR_FR5_ENABLED = "true";
    mockConstructEvent.mockReturnValue(makePaymentFailedEvent());

    // First delivery: dedup row inserted → handler runs.
    await POST(makeRequest());
    expect(mockInngestSend).toHaveBeenCalledTimes(1);

    // Redelivery: dedup INSERT fails with unique violation → handler
    // short-circuits with 200 BEFORE the switch fires again.
    mockInsert.mockResolvedValueOnce({
      data: null,
      error: { code: "23505", message: "duplicate key" },
    });
    const res2 = await POST(makeRequest());
    expect(res2.status).toBe(200);
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
  });

  test("Minimization (RV7): event.data.payload contains NO `@`, NO `payment_method`, keeps 4 fields", async () => {
    process.env.SOLEUR_FR5_ENABLED = "true";
    mockConstructEvent.mockReturnValue(makePaymentFailedEvent());
    await POST(makeRequest());

    const envelope = mockInngestSend.mock.calls[0][0] as {
      data: { payload: Record<string, unknown> };
    };
    const payloadJson = JSON.stringify(envelope.data.payload);
    expect(payloadJson).not.toContain("@");
    expect(envelope.data.payload).not.toHaveProperty("payment_method");
    expect(envelope.data.payload).toMatchObject({
      founderId: FOUNDER_ID,
      invoiceId: "in_pf_001",
      amount: 4200,
      currency: "usd",
      failureCode: "card_declined",
    });
    // customerEmailHash present and is a sha256-shaped hex string (64 chars).
    expect(envelope.data.payload.customerEmailHash).toMatch(/^[0-9a-f]{64}$/);
  });

  test("Inngest unreachable → reportSilentFallback fires, webhook returns 200", async () => {
    process.env.SOLEUR_FR5_ENABLED = "true";
    mockConstructEvent.mockReturnValue(makePaymentFailedEvent());
    mockInngestSend.mockRejectedValueOnce(new Error("ECONNREFUSED 127.0.0.1:8288"));

    const res = await POST(makeRequest());
    expect(res.status).toBe(200);
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    const ctx = mockReportSilentFallback.mock.calls[0][1] as {
      feature: string;
      op?: string;
    };
    expect(ctx.feature).toBe("inngest-emit");
    expect(ctx.op).toBe("finance.payment_failed");
  });

  test("No founder row for stripe_customer_id → does NOT call inngest.send (logs only)", async () => {
    process.env.SOLEUR_FR5_ENABLED = "true";
    mockConstructEvent.mockReturnValue(makePaymentFailedEvent());
    mockMaybeSingle.mockResolvedValueOnce({ data: null, error: null });

    const res = await POST(makeRequest());
    expect(res.status).toBe(200);
    expect(mockInngestSend).not.toHaveBeenCalled();
  });
});
