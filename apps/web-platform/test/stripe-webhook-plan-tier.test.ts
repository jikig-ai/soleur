import { describe, test, expect, vi, beforeEach } from "vitest";
import type Stripe from "stripe";
import {
  configureSupabaseUpdateChain,
  configureSupabaseInsertChain,
} from "./helpers/supabase-update-chain";

const {
  mockConstructEvent,
  mockUpdate,
  mockEq,
  mockIn,
  mockSelect,
  mockMaybeSingle,
  mockInsert,
  mockDeleteEq,
  mockForceDisconnect,
  mockInvalidateTierMemo,
} = vi.hoisted(() => ({
  mockConstructEvent: vi.fn(),
  mockUpdate: vi.fn(),
  mockEq: vi.fn(),
  mockIn: vi.fn(),
  mockSelect: vi.fn(),
  mockMaybeSingle: vi.fn(),
  mockInsert: vi.fn(),
  mockDeleteEq: vi.fn(),
  mockForceDisconnect: vi.fn(() => true),
  mockInvalidateTierMemo: vi.fn(),
}));

const { priceTier } = vi.hoisted(() => ({ priceTier: { value: "startup" as string } }));

vi.mock("@/lib/stripe", () => ({
  getStripe: () => ({ webhooks: { constructEvent: mockConstructEvent } }),
  invalidateTierMemo: mockInvalidateTierMemo,
}));

vi.mock("@/lib/stripe-price-tier-map", () => ({
  getPriceTier: () => priceTier.value,
  priceIdForTier: () => null,
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
          eq: () => ({ maybeSingle: mockMaybeSingle }),
        }),
      };
    },
  }),
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }),
}));

vi.mock("@/server/ws-handler", () => ({
  forceDisconnectForTierChange: mockForceDisconnect,
}));

vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn(), captureMessage: vi.fn() }));

import { POST } from "@/app/api/webhooks/stripe/route";

function makeRequest(): Request {
  return new Request("https://app.soleur.ai/api/webhooks/stripe", {
    method: "POST",
    headers: { "stripe-signature": "sig_test" },
    body: "raw-body",
  });
}

function makeSubUpdatedEvent(opts: {
  priceId: string;
  status?: string;
  created?: number;
}): Stripe.Event {
  return {
    type: "customer.subscription.updated",
    created: opts.created ?? Math.floor(Date.now() / 1_000),
    data: {
      object: {
        customer: "cus_test",
        status: opts.status ?? "active",
        cancel_at_period_end: false,
        current_period_end: 1_700_000_000,
        items: { data: [{ price: { id: opts.priceId } }] },
      },
    },
  } as unknown as Stripe.Event;
}

describe("Stripe webhook — plan_tier writes", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    priceTier.value = "startup";
    configureSupabaseUpdateChain({ mockUpdate, mockEq, mockIn, mockSelect });
    configureSupabaseInsertChain({ mockInsert, mockDeleteEq });
    mockMaybeSingle.mockResolvedValue({
      data: {
        id: "user-123",
        plan_tier: "free",
        concurrency_override: null,
        subscription_status: "none",
      },
      error: null,
    });
  });

  test("upgrade free → startup writes plan_tier='startup' and clears downgrade timestamp", async () => {
    priceTier.value = "startup";
    mockConstructEvent.mockReturnValue(makeSubUpdatedEvent({ priceId: "price_startup" }));
    const res = await POST(makeRequest());
    expect(res.status).toBe(200);
    expect(mockUpdate).toHaveBeenCalledWith(
      expect.objectContaining({ plan_tier: "startup", subscription_downgraded_at: null }),
    );
    expect(mockForceDisconnect).not.toHaveBeenCalled();
  });

  test("downgrade scale → solo sets subscription_downgraded_at + force-disconnects", async () => {
    priceTier.value = "solo";
    mockMaybeSingle.mockResolvedValue({
      data: {
        id: "user-123",
        plan_tier: "scale",
        concurrency_override: null,
        subscription_status: "active",
      },
      error: null,
    });
    const eventCreated = 1_700_000_500;
    mockConstructEvent.mockReturnValue(
      makeSubUpdatedEvent({ priceId: "price_solo", created: eventCreated }),
    );
    const res = await POST(makeRequest());
    expect(res.status).toBe(200);
    expect(mockUpdate).toHaveBeenCalledWith(
      expect.objectContaining({
        plan_tier: "solo",
        subscription_downgraded_at: new Date(eventCreated * 1_000).toISOString(),
      }),
    );
    expect(mockForceDisconnect).toHaveBeenCalledWith("user-123", {
      type: "tier_changed",
      previousTier: "scale",
      newTier: "solo",
    });
    // Memo invalidation is load-bearing: without it, the cap-hit Stripe
    // fallback memo (60s TTL) serves a stale tier and a just-downgraded user
    // continues to bypass the new cap until the TTL expires. Without this
    // assertion, a regression that drops the invalidateTierMemo call would
    // ship green.
    expect(mockInvalidateTierMemo).toHaveBeenCalledWith("user-123");
  });

  test("incomplete status skips plan_tier write entirely", async () => {
    mockConstructEvent.mockReturnValue(
      makeSubUpdatedEvent({ priceId: "price_startup", status: "incomplete" }),
    );
    const res = await POST(makeRequest());
    expect(res.status).toBe(200);
    expect(mockUpdate).not.toHaveBeenCalled();
  });

  test("atomic update uses .in(subscription_status, pre-states) for idempotency", async () => {
    // Post-#2701: cancelled is terminal and explicitly excluded from the
    // pre-state guard — a stale .updated arriving after .deleted must never
    // resurrect a cancelled row.
    mockConstructEvent.mockReturnValue(makeSubUpdatedEvent({ priceId: "price_startup" }));
    await POST(makeRequest());
    expect(mockIn).toHaveBeenCalledWith(
      "subscription_status",
      ["none", "active", "past_due", "unpaid"],
    );
  });
});
