// Manual-trigger allowlist (#4734).
//
// The set of `cron/<name>.manual-trigger` events that POST /api/internal/
// trigger-cron is permitted to dispatch. Derived from EXPECTED_CRON_FUNCTIONS
// (the drift-guarded cron manifest) — there is NO second hardcoded list to
// maintain, so adding/removing a cron-*.ts automatically updates the allowlist
// via function-registry-count.test.ts (e).
//
// Imports from the CLIENT-FREE cron-manifest.ts leaf — NOT from
// cron-inngest-cron-watchdog.ts, which statically imports @/server/inngest/
// client and would throw on missing INNGEST_SIGNING_KEY at module load.
//
// Kept in lib/ (not the route file) per cq-nextjs-route-files-http-only-exports,
// and so the allowlist is unit-testable without importing the route.

import {
  EXPECTED_CRON_FUNCTIONS,
  manualTriggerEventFor,
} from "@/server/inngest/cron-manifest";

export const MANUAL_TRIGGER_EVENTS: ReadonlySet<string> = new Set(
  EXPECTED_CRON_FUNCTIONS.map(manualTriggerEventFor),
);

export function isAllowlistedManualTrigger(name: unknown): name is string {
  return typeof name === "string" && MANUAL_TRIGGER_EVENTS.has(name);
}
