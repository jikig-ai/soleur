import { describe, test, expect, vi, beforeEach } from "vitest";

const { mockRetrieve } = vi.hoisted(() => ({ mockRetrieve: vi.fn() }));

vi.mock("stripe", () => {
  class StripeCtor {
    subscriptions = { retrieve: mockRetrieve };
  }
  return { default: StripeCtor };
});

const ORIGINAL_ENV = { ...process.env };

async function importFresh() {
  vi.resetModules();
  process.env = {
    ...ORIGINAL_ENV,
    STRIPE_SECRET_KEY: "sk_test",
    STRIPE_PRICE_ID_SOLO: "price_solo",
    STRIPE_PRICE_ID_STARTUP: "price_startup",
    STRIPE_PRICE_ID_SCALE: "price_scale",
    STRIPE_PRICE_ID_ENTERPRISE: "price_enterprise",
  };
  return await import("../lib/stripe");
}

describe("retrieveSubscriptionTier", () => {
  beforeEach(() => {
    mockRetrieve.mockReset();
  });

  test("maps first item's price id to tier + returns status", async () => {
    mockRetrieve.mockResolvedValue({
      items: { data: [{ price: { id: "price_startup" } }] },
      status: "active",
    });
    const { retrieveSubscriptionTier } = await importFresh();
    const out = await retrieveSubscriptionTier("user-1", "sub_1");
    expect(out).toEqual({ tier: "startup", status: "active" });
  });

  test("memo cache hits within 60s — Stripe not called twice", async () => {
    mockRetrieve.mockResolvedValue({
      items: { data: [{ price: { id: "price_scale" } }] },
      status: "active",
    });
    const { retrieveSubscriptionTier } = await importFresh();
    await retrieveSubscriptionTier("user-2", "sub_2");
    await retrieveSubscriptionTier("user-2", "sub_2");
    expect(mockRetrieve).toHaveBeenCalledTimes(1);
  });

  test("invalidateTierMemo forces a fresh retrieve on next call", async () => {
    mockRetrieve.mockResolvedValue({
      items: { data: [{ price: { id: "price_solo" } }] },
      status: "active",
    });
    const { retrieveSubscriptionTier, invalidateTierMemo } = await importFresh();
    await retrieveSubscriptionTier("user-3", "sub_3");
    invalidateTierMemo("user-3");
    await retrieveSubscriptionTier("user-3", "sub_3");
    expect(mockRetrieve).toHaveBeenCalledTimes(2);
  });

  test("unknown price id falls back to free", async () => {
    mockRetrieve.mockResolvedValue({
      items: { data: [{ price: { id: "price_ghost" } }] },
      status: "active",
    });
    const { retrieveSubscriptionTier } = await importFresh();
    const out = await retrieveSubscriptionTier("user-4", "sub_4");
    expect(out.tier).toBe("free");
  });
});
