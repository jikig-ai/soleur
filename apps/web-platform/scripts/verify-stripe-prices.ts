#!/usr/bin/env bun
/**
 * Verify the four STRIPE_PRICE_ID_* env vars resolve to live Stripe prices.
 *
 * Exit code is non-zero if any key is missing or any price 404s. Intended to
 * run as a Phase 0 preflight gate before the concurrency-enforcement PR
 * ships:
 *
 *   doppler run -p soleur -c dev -- bun run scripts/verify-stripe-prices.ts
 *   doppler run -p soleur -c prd -- bun run scripts/verify-stripe-prices.ts
 *
 * Success output:
 *   ✓ STRIPE_PRICE_ID_SOLO        price_... ($49.00 /month)
 *   ✓ STRIPE_PRICE_ID_STARTUP     price_... ($149.00 /month)
 *   ✓ STRIPE_PRICE_ID_SCALE       price_... ($499.00 /month)
 *   ✓ STRIPE_PRICE_ID_ENTERPRISE  price_... (custom)
 */

import Stripe from "stripe";

const KEYS = [
  "STRIPE_PRICE_ID_SOLO",
  "STRIPE_PRICE_ID_STARTUP",
  "STRIPE_PRICE_ID_SCALE",
  "STRIPE_PRICE_ID_ENTERPRISE",
] as const;

function die(msg: string): never {
  console.error(`✗ ${msg}`);
  process.exit(1);
}

async function main() {
  if (!process.env.STRIPE_SECRET_KEY) {
    die("STRIPE_SECRET_KEY not set — run under doppler run");
  }
  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

  const missing = KEYS.filter((k) => !process.env[k]);
  if (missing.length > 0) {
    die(`missing env vars: ${missing.join(", ")}`);
  }

  let failures = 0;
  for (const key of KEYS) {
    const id = process.env[key]!;
    try {
      const price = await stripe.prices.retrieve(id);
      const amount =
        price.unit_amount != null
          ? `$${(price.unit_amount / 100).toFixed(2)}`
          : "(custom)";
      const interval = price.recurring?.interval ?? "—";
      console.log(`✓ ${key.padEnd(28)} ${id.padEnd(30)} ${amount.padEnd(12)} /${interval}`);
    } catch (err) {
      failures += 1;
      const message = err instanceof Error ? err.message : String(err);
      console.error(`✗ ${key.padEnd(28)} ${id.padEnd(30)} ${message}`);
    }
  }

  if (failures > 0) {
    die(`${failures} price id(s) failed to resolve`);
  }
  console.log(`\nAll ${KEYS.length} Stripe price IDs resolved ✓`);
}

main().catch((err) => die(err instanceof Error ? err.message : String(err)));
