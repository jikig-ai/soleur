import { describe, test, expect, vi, beforeEach } from "vitest";

const { mockReport } = vi.hoisted(() => ({ mockReport: vi.fn() }));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReport,
  warnSilentFallback: mockReport,
}));

const ORIGINAL_ENV = { ...process.env };

function resetEnv() {
  process.env = { ...ORIGINAL_ENV };
  delete process.env.STRIPE_PRICE_ID_SOLO;
  delete process.env.STRIPE_PRICE_ID_STARTUP;
  delete process.env.STRIPE_PRICE_ID_SCALE;
  delete process.env.STRIPE_PRICE_ID_ENTERPRISE;
}

async function importFresh() {
  vi.resetModules();
  return await import("../lib/stripe-price-tier-map");
}

describe("stripe-price-tier-map", () => {
  beforeEach(() => {
    resetEnv();
    mockReport.mockReset();
  });

  test("import with no env vars does NOT throw (lazy init)", async () => {
    await expect(importFresh()).resolves.toBeTruthy();
  });

  test("getPriceTier resolves known price ids by tier", async () => {
    process.env.STRIPE_PRICE_ID_SOLO = "price_solo";
    process.env.STRIPE_PRICE_ID_STARTUP = "price_startup";
    process.env.STRIPE_PRICE_ID_SCALE = "price_scale";
    process.env.STRIPE_PRICE_ID_ENTERPRISE = "price_enterprise";
    const { getPriceTier } = await importFresh();
    expect(getPriceTier("price_solo")).toBe("solo");
    expect(getPriceTier("price_startup")).toBe("startup");
    expect(getPriceTier("price_scale")).toBe("scale");
    expect(getPriceTier("price_enterprise")).toBe("enterprise");
  });

  test("missing env var throws on first getPriceTier call", async () => {
    process.env.STRIPE_PRICE_ID_SOLO = "price_solo";
    process.env.STRIPE_PRICE_ID_SCALE = "price_scale";
    process.env.STRIPE_PRICE_ID_ENTERPRISE = "price_enterprise";
    // STRIPE_PRICE_ID_STARTUP intentionally missing
    const { getPriceTier } = await importFresh();
    // Error message names the missing key and points to the Doppler fix —
    // see `loadMap` in stripe-price-tier-map.ts.
    expect(() => getPriceTier("price_solo")).toThrow(
      /Missing required Stripe env var: STRIPE_PRICE_ID_STARTUP.*doppler secrets set STRIPE_PRICE_ID_STARTUP/s,
    );
  });

  test("unknown price id falls back to free + Sentry warning once", async () => {
    process.env.STRIPE_PRICE_ID_SOLO = "price_solo";
    process.env.STRIPE_PRICE_ID_STARTUP = "price_startup";
    process.env.STRIPE_PRICE_ID_SCALE = "price_scale";
    process.env.STRIPE_PRICE_ID_ENTERPRISE = "price_enterprise";
    const { getPriceTier } = await importFresh();
    expect(getPriceTier("price_ghost")).toBe("free");
    expect(mockReport).toHaveBeenCalledTimes(1);
    const [, opts] = mockReport.mock.calls[0];
    expect(opts).toMatchObject({ feature: "concurrency", op: "getPriceTier" });
  });

  test("priceIdForTier returns configured price id", async () => {
    process.env.STRIPE_PRICE_ID_SOLO = "price_solo";
    process.env.STRIPE_PRICE_ID_STARTUP = "price_startup";
    process.env.STRIPE_PRICE_ID_SCALE = "price_scale";
    process.env.STRIPE_PRICE_ID_ENTERPRISE = "price_enterprise";
    const { priceIdForTier } = await importFresh();
    expect(priceIdForTier("startup")).toBe("price_startup");
    expect(priceIdForTier("scale")).toBe("price_scale");
  });

  test("priceIdForTier returns null for free tier", async () => {
    process.env.STRIPE_PRICE_ID_SOLO = "price_solo";
    process.env.STRIPE_PRICE_ID_STARTUP = "price_startup";
    process.env.STRIPE_PRICE_ID_SCALE = "price_scale";
    process.env.STRIPE_PRICE_ID_ENTERPRISE = "price_enterprise";
    const { priceIdForTier } = await importFresh();
    expect(priceIdForTier("free")).toBeNull();
  });
});
