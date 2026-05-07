// Helpers for the dev-only sign-in route. Underscore-prefixed module is
// excluded from App Router routing per Next.js convention; this lets us
// keep the `route.ts` neighbour conformant with `cq-nextjs-route-files-
// http-only-exports` (HTTP handlers + Next config exports only).
//
// All exports here are dev-only — see `lib/auth/dev-mode.ts` for the
// single gate function both this route and the panel component call.

import { z } from "zod";

export type DevSlot = 1 | 2 | 3;

/** Strict literal-union — Zod rejects 0, 4, NaN, strings, etc. */
export const slotSchema = z.object({
  slot: z.union([z.literal(1), z.literal(2), z.literal(3)]),
});

export function getEmailForSlot(slot: DevSlot): string {
  return `dev-${slot}@example.com`;
}

/**
 * Read the per-slot password from Doppler-injected env. Returns
 * `undefined` if unset; the route handler maps this to a 500 with a
 * scrubbed message — never an error string that names the env var
 * key (the key names are the lever for an authenticated-as-dev-N
 * session if the dev-N users were ever seeded into prd Supabase).
 */
export function getPasswordForSlot(slot: DevSlot): string | undefined {
  switch (slot) {
    case 1:
      return process.env.DEV_USER_1_PASSWORD;
    case 2:
      return process.env.DEV_USER_2_PASSWORD;
    case 3:
      return process.env.DEV_USER_3_PASSWORD;
    default: {
      // Exhaustiveness rail per cq-union-widening-grep-three-patterns —
      // widening DevSlot (e.g., adding slot 4) without adding a branch
      // here triggers a tsc error rather than a silent runtime undefined
      // that the route handler maps to a misconfig 500.
      const _exhaustive: never = slot;
      return _exhaustive;
    }
  }
}
