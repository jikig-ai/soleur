import type { PlanTier } from "@/lib/types";
import { warnSilentFallback } from "@/server/observability";

/**
 * Maps Stripe price IDs ⇄ plan tier. Loaded lazily on first call so that
 * modules (e.g. route files, WS handler) can import this file even in test
 * environments without the four env vars configured.
 *
 * Missing env vars throw on first `getPriceTier`/`priceIdForTier` call with a
 * clear "STRIPE_PRICE_ID_* missing: <KEY>" message.
 */

const REQUIRED_ENV_KEYS = [
  "STRIPE_PRICE_ID_SOLO",
  "STRIPE_PRICE_ID_STARTUP",
  "STRIPE_PRICE_ID_SCALE",
  "STRIPE_PRICE_ID_ENTERPRISE",
] as const;

type PaidTier = Exclude<PlanTier, "free">;

interface PriceTierMap {
  byPriceId: Record<string, PaidTier>;
  byTier: Record<PaidTier, string>;
}

let cached: PriceTierMap | null = null;
let unknownWarned = false;

function loadMap(): PriceTierMap {
  for (const key of REQUIRED_ENV_KEYS) {
    if (!process.env[key]) {
      throw new Error(
        `Missing required Stripe env var: ${key}. Set via ` +
        `\`doppler secrets set ${key}=price_... -p soleur -c <dev|prd>\` ` +
        `then re-run under \`doppler run -p soleur -c <env> -- ...\`. See ` +
        `apps/web-platform/.env.example and scripts/verify-stripe-prices.ts.`
      );
    }
  }
  const soloId = process.env.STRIPE_PRICE_ID_SOLO!;
  const startupId = process.env.STRIPE_PRICE_ID_STARTUP!;
  const scaleId = process.env.STRIPE_PRICE_ID_SCALE!;
  const enterpriseId = process.env.STRIPE_PRICE_ID_ENTERPRISE!;

  return {
    byPriceId: {
      [soloId]: "solo",
      [startupId]: "startup",
      [scaleId]: "scale",
      [enterpriseId]: "enterprise",
    },
    byTier: {
      solo: soloId,
      startup: startupId,
      scale: scaleId,
      enterprise: enterpriseId,
    },
  };
}

function ensureLoaded(): PriceTierMap {
  if (!cached) cached = loadMap();
  return cached;
}

/**
 * Resolve a Stripe price ID to a plan tier. Falls back to `"free"` for
 * unknown IDs (emits a single Sentry warning per process) so a misconfigured
 * price does not brick the WS path.
 */
export function getPriceTier(priceId: string): PlanTier {
  const map = ensureLoaded();
  const tier = map.byPriceId[priceId];
  if (tier) return tier;
  if (!unknownWarned) {
    unknownWarned = true;
    warnSilentFallback(null, {
      feature: "concurrency",
      op: "getPriceTier",
      message: "unknown Stripe price id mapped to 'free'",
      extra: { priceId },
    });
  }
  return "free";
}

/**
 * Reverse lookup: tier → price id. Returns `null` for `"free"` (no paid
 * price) so callers (e.g. the checkout route) can 400 cleanly.
 */
export function priceIdForTier(tier: PlanTier): string | null {
  if (tier === "free") return null;
  const map = ensureLoaded();
  return map.byTier[tier] ?? null;
}

/** Test-only: reset the lazy cache so each test can mutate env vars. */
export function __resetPriceTierMapCacheForTests(): void {
  cached = null;
  unknownWarned = false;
}
