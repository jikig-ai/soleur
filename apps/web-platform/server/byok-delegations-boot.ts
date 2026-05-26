import * as Sentry from "@sentry/nextjs";
import {
  getRuntimeFlag,
  getByokDelegationsAllowlist,
  ANON_IDENTITY,
} from "@/lib/feature-flags/server";

export async function emitByokDelegationsBootBreadcrumb(): Promise<void> {
  if (process.env.NODE_ENV !== "production") return;
  const flagOn = await getRuntimeFlag("byok-delegations", ANON_IDENTITY);
  if (!flagOn) return;
  const allowlist = getByokDelegationsAllowlist();
  if (allowlist.size === 0) return;
  Sentry.addBreadcrumb({
    category: "feature-flag",
    level: "info",
    message: "byok-delegations two-key gate ON in production",
    data: {
      allowlistSize: allowlist.size,
    },
  });
}
