import * as Sentry from "@sentry/nextjs";
import {
  getRuntimeFlag,
  ANON_IDENTITY,
} from "@/lib/feature-flags/server";

export async function emitByokDelegationsBootBreadcrumb(): Promise<void> {
  if (process.env.NODE_ENV !== "production") return;
  const flagOn = await getRuntimeFlag("byok-delegations", ANON_IDENTITY);
  if (!flagOn) return;
  Sentry.addBreadcrumb({
    category: "feature-flag",
    level: "info",
    message: "byok-delegations single-control gate ON in production",
  });
}
