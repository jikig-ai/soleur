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
//     AFTER the processed_stripe_events dedup insert (which runs in the
//     route before the event-type switch).
//   - Stripe redelivery (same event.id twice) → inngest.send fires ONCE
//     because dedup short-circuits the second call with 200 before reaching
//     the switch.
//   - Minimization (RV7): `data.payload` carries no `@`, no `payment_method`,
//     keeps amount/currency/failureCode/invoiceId.
//   - Inngest unreachable → the failure is reported to Sentry, the claimed
//     dedup row is released and the webhook returns 500, so Stripe redelivers
//     and the redelivery is not swallowed by the dedup gate (#10542).

const {
  mockConstructEvent,
  mockInsert,
  mockDeleteEq,
  mockMaybeSingle,
  mockLogger,
  mockReportSilentFallback,
  mockInngestSend,
  mockIsGranted,
  mockIsDenied,
} = vi.hoisted(() => ({
  mockConstructEvent: vi.fn(),
  mockInsert: vi.fn(),
  mockDeleteEq: vi.fn(),
  mockMaybeSingle: vi.fn(),
  mockLogger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  mockReportSilentFallback: vi.fn(),
  mockInngestSend: vi.fn(),
  mockIsGranted: vi.fn(),
  mockIsDenied: vi.fn(),
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

// PR-G (#3947) — per-grant deny-by-default at the webhook predicate.
vi.mock("@/server/scope-grants/is-granted", () => ({
  isGranted: mockIsGranted,
  isDenied: mockIsDenied,
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

// Stateful model of `processed_stripe_events`: the insert claims an id (23505
// when already claimed) and the release (`delete().eq("event_id", id)`)
// frees it. A stateless stub could not tell whether the route ever released
// the row, so a redelivery test would pass against the swallow bug (#10542).
const claimed = new Set<string>();

beforeEach(() => {
  vi.clearAllMocks();
  claimed.clear();
  mockInsert.mockImplementation(async (row: { event_id: string }) => {
    if (claimed.has(row.event_id)) {
      return { data: null, error: { code: "23505", message: "duplicate key" } };
    }
    claimed.add(row.event_id);
    return { data: null, error: null };
  });
  mockDeleteEq.mockImplementation(async (_col: string, id: string) => {
    claimed.delete(id);
    return { error: null };
  });
  // Default founder lookup hit.
  mockMaybeSingle.mockResolvedValue({
    data: { id: FOUNDER_ID, stripe_customer_id: CUSTOMER_ID },
    error: null,
  });
  // PR-G default: founder HAS an active grant at draft_one_click.
  // Individual tests override for no-grant / denylist cases.
  mockIsGranted.mockResolvedValue({ tier: "draft_one_click" });
  mockIsDenied.mockReturnValue(false);
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
    // Success path: the dedup row stays claimed and nothing is reported.
    expect(mockDeleteEq).not.toHaveBeenCalled();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
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

  // T1 (#10542): a failed send must release the dedup row and return 500 so
  // Stripe redelivers; before the fix the route returned 200 with the row
  // still claimed and the CFO draft was lost for good.
  test("T1: Inngest unreachable → reports, releases the dedup row, returns 500", async () => {
    process.env.SOLEUR_FR5_ENABLED = "true";
    mockConstructEvent.mockReturnValue(makePaymentFailedEvent());
    // A plain Error is not matched by isTransientFetchError: one attempt, no timer.
    mockInngestSend.mockRejectedValueOnce(new Error("ECONNREFUSED 127.0.0.1:8288"));

    const res = await POST(makeRequest());
    expect(res.status).toBe(500);
    expect(await res.json()).toEqual({ error: "Dispatch failed" });
    expect(mockDeleteEq).toHaveBeenCalledTimes(1);
    expect(mockDeleteEq).toHaveBeenCalledWith("event_id", "evt_pf_001");
    expect(claimed.has("evt_pf_001")).toBe(false);

    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    // First argument null: the message path. An Error-path report is
    // pre-captured by the pino mirror and the tagged capture is dropped
    // (#8629), so the feature/op tags would not be findable in Sentry.
    expect(mockReportSilentFallback.mock.calls[0][0]).toBeNull();
    const ctx = mockReportSilentFallback.mock.calls[0][1] as {
      feature: string;
      op?: string;
      message?: string;
      extra?: Record<string, unknown>;
    };
    expect(ctx.feature).toBe("stripe-webhook");
    expect(ctx.op).toBe("inngest-send-payment-failed");
    expect(ctx.message).not.toMatch(/will retry/i);
    expect(ctx.message).toMatch(/releasing dedup row/);
    expect(ctx.extra).toMatchObject({
      userId: FOUNDER_ID,
      eventId: "evt_pf_001",
      invoiceId: "in_pf_001",
      errorName: "Error",
    });
    expect(ctx.extra).not.toHaveProperty("founderId");
    expect(ctx.extra).not.toHaveProperty("customerEmailHash");
    // The raw error text can embed hosts or ids; only its name is reported.
    expect(JSON.stringify(ctx.extra)).not.toContain("ECONNREFUSED");
  });

  // T3 (#10542): the behavior the old code lost. The stateful insert mock
  // accepts the redelivery only if the route really released the row.
  test("T3: redelivery after a failed send re-attempts the send and succeeds", async () => {
    process.env.SOLEUR_FR5_ENABLED = "true";
    mockConstructEvent.mockReturnValue(makePaymentFailedEvent());
    mockInngestSend.mockRejectedValueOnce(new Error("ECONNREFUSED 127.0.0.1:8288"));

    const res1 = await POST(makeRequest());
    expect(res1.status).toBe(500);
    expect(claimed.has("evt_pf_001")).toBe(false);

    mockInngestSend.mockResolvedValueOnce(undefined);
    const res2 = await POST(makeRequest());
    expect(res2.status).toBe(200);
    expect(mockInngestSend).toHaveBeenCalledTimes(2);
    // Both attempts carry the same Inngest event id, which Inngest dedups.
    const ids = mockInngestSend.mock.calls.map((c) => (c[0] as { id: string }).id);
    expect(ids).toEqual(["stripe-evt_pf_001", "stripe-evt_pf_001"]);
    // The successful redelivery keeps its claim.
    expect(claimed.has("evt_pf_001")).toBe(true);
  });

  // T4 (#10542): the accepted residual. If the release itself fails the route
  // still answers 500 (a 200 would make the loss worse) and the redelivery is
  // short-circuited by the dedup gate; the release failure is logged.
  test("T4: release fails after a failed send → still 500, release failure logged, redelivery short-circuits", async () => {
    process.env.SOLEUR_FR5_ENABLED = "true";
    mockConstructEvent.mockReturnValue(makePaymentFailedEvent());
    mockInngestSend.mockRejectedValueOnce(new Error("ECONNREFUSED 127.0.0.1:8288"));
    mockDeleteEq.mockResolvedValueOnce({ error: { message: "delete failed" } });

    const res1 = await POST(makeRequest());
    expect(res1.status).toBe(500);
    expect(claimed.has("evt_pf_001")).toBe(true);
    expect(mockLogger.error).toHaveBeenCalledWith(
      expect.objectContaining({ eventId: "evt_pf_001" }),
      expect.stringContaining("failed to release dedup row"),
    );

    const res2 = await POST(makeRequest());
    expect(res2.status).toBe(200);
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
  });

  test("No founder row for stripe_customer_id → does NOT call inngest.send (logs only)", async () => {
    process.env.SOLEUR_FR5_ENABLED = "true";
    mockConstructEvent.mockReturnValue(makePaymentFailedEvent());
    mockMaybeSingle.mockResolvedValueOnce({ data: null, error: null });

    const res = await POST(makeRequest());
    expect(res.status).toBe(200);
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  // PR-G (#3947) — per-grant deny-by-default at the webhook predicate.
  // TR3: flag=on AND founder exists BUT no scope_grants row → fail-closed.
  // This is the load-bearing test that compensates for K14's flip-in-PR-G
  // decision (env flag is now a global kill-switch, not a per-tenant gate).
  test("SOLEUR_FR5_ENABLED=true + founder + NO scope_grants row → does NOT call inngest.send (TR3)", async () => {
    process.env.SOLEUR_FR5_ENABLED = "true";
    mockConstructEvent.mockReturnValue(makePaymentFailedEvent());
    // Override the beforeEach default: this founder has NO active grant.
    mockIsGranted.mockResolvedValueOnce(null);

    const res = await POST(makeRequest());
    expect(res.status).toBe(200);
    expect(mockIsGranted).toHaveBeenCalledWith(
      expect.any(Object),
      FOUNDER_ID,
      "finance.payment_failed",
    );
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  // TR5a: denylist override → no send. PR-G ships with empty denylist
  // (Phase 1.3 is-granted.ts inlines it); this test asserts the gate IS
  // wired so a future denylist entry produces fail-closed behavior.
  test("SOLEUR_FR5_ENABLED=true + grant exists + denylisted action_class → does NOT call inngest.send (TR5)", async () => {
    process.env.SOLEUR_FR5_ENABLED = "true";
    mockConstructEvent.mockReturnValue(makePaymentFailedEvent());
    // isGranted's own denylist check returns null when denied. Simulate
    // that contract here (isDenied is internal to is-granted.ts; we don't
    // wire it directly into route.ts).
    mockIsGranted.mockResolvedValueOnce(null);
    mockIsDenied.mockReturnValueOnce(true);

    const res = await POST(makeRequest());
    expect(res.status).toBe(200);
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  // T2 (#10542): real timers; the retry helper backs off 500 ms then 1000 ms
  // (about 1.5 s, well inside the repo's testTimeout).
  test("T2: transient failure → retries exhaust after 3 attempts, then releases once and returns 500", async () => {
    process.env.SOLEUR_FR5_ENABLED = "true";
    mockConstructEvent.mockReturnValue(makePaymentFailedEvent());
    const fetchError = new TypeError("fetch failed");
    mockInngestSend
      .mockRejectedValueOnce(fetchError)
      .mockRejectedValueOnce(fetchError)
      .mockRejectedValueOnce(fetchError);

    const res = await POST(makeRequest());
    expect(res.status).toBe(500);
    expect(mockInngestSend).toHaveBeenCalledTimes(3);
    expect(mockDeleteEq).toHaveBeenCalledTimes(1);
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    expect(claimed.has("evt_pf_001")).toBe(false);
  });

  test("Inngest transient failure → retries and succeeds on second attempt", async () => {
    process.env.SOLEUR_FR5_ENABLED = "true";
    mockConstructEvent.mockReturnValue(makePaymentFailedEvent());
    mockInngestSend
      .mockRejectedValueOnce(new TypeError("fetch failed"))
      .mockResolvedValueOnce(undefined);

    const res = await POST(makeRequest());
    expect(res.status).toBe(200);
    expect(mockInngestSend).toHaveBeenCalledTimes(2);
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  // TR5b: grant-path with tier pass-through. inngest.send envelope MUST
  // carry data.tier = grant.tier so the CFO function pins
  // grant-tier-at-time-of-event into messages.trust_tier.
  test("SOLEUR_FR5_ENABLED=true + grant exists + not denylisted → inngest.send fires with data.tier from grant", async () => {
    process.env.SOLEUR_FR5_ENABLED = "true";
    mockConstructEvent.mockReturnValue(makePaymentFailedEvent());
    mockIsGranted.mockResolvedValueOnce({ tier: "approve_every_time" });

    const res = await POST(makeRequest());
    expect(res.status).toBe(200);
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
    const envelope = mockInngestSend.mock.calls[0][0] as {
      data: { tier?: string };
    };
    expect(envelope.data.tier).toBe("approve_every_time");
  });
});
