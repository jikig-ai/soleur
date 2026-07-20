"use client";

import useSWR from "swr";
import { AnalyticsDashboard } from "@/components/analytics/analytics-dashboard";
import type { UserMetrics, FunnelResult } from "@/lib/analytics";
import { isRevocationBounce } from "@/lib/auth/revocation-bounce";

interface AnalyticsPayload {
  metrics: UserMetrics[];
  funnel: FunnelResult;
}

/**
 * GAP H (ADR-067 staleTimes amendment): client loader for the all-tenant admin
 * analytics data.
 *
 * The data is fetched from the admin-gated `/api/admin/analytics` route rather
 * than baked into the page RSC, so a warm Router-Cache restore of
 * `admin/analytics` paints only this (data-less) shell — never a stale
 * all-tenant payload. The route's `isAdmin` gate re-runs on every fetch:
 *  - session revoked → middleware 302→/login → `isRevocationBounce` → hard-nav.
 *  - de-provisioned admin → 403 → bounce to the user's own /dashboard (nothing
 *    sensitive was rendered, so a soft replace is sufficient and safe).
 */
async function fetchAnalytics(url: string): Promise<AnalyticsPayload> {
  const res = await fetch(url);
  if (isRevocationBounce(res)) {
    window.location.assign("/login");
    throw new Error("session-revoked");
  }
  if (res.status === 403) {
    // No longer an admin. Nothing sensitive was rendered (data-less shell), so
    // send them to their own dashboard.
    window.location.assign("/dashboard");
    throw new Error("not-admin");
  }
  if (!res.ok) {
    throw new Error(`analytics fetch failed: ${res.status}`);
  }
  return res.json() as Promise<AnalyticsPayload>;
}

export function AnalyticsDashboardLoader() {
  const { data, error } = useSWR<AnalyticsPayload>(
    "/api/admin/analytics",
    fetchAnalytics,
    { revalidateOnFocus: false },
  );

  if (error) {
    return (
      <div className="mx-auto max-w-6xl px-6 py-8 flex flex-col items-center justify-center min-h-[400px] gap-4">
        <p className="text-red-400">
          Failed to load analytics data. Please try again.
        </p>
        <a
          href="/dashboard/admin/analytics"
          className="text-amber-500 underline hover:text-amber-400"
        >
          Retry
        </a>
      </div>
    );
  }

  if (!data) {
    // First-load skeleton (the route's loading.tsx covers the RSC fetch; this
    // covers the SWR data fetch). Gates on data === undefined, never on
    // isValidating, so a background revalidation never re-shows it.
    return (
      <div
        className="mx-auto max-w-6xl px-6 py-8 space-y-6"
        aria-busy="true"
        data-testid="analytics-loading"
      >
        <div className="h-8 w-40 animate-pulse rounded bg-soleur-bg-surface-2" />
        <div className="h-64 w-full animate-pulse rounded bg-soleur-bg-surface-2" />
      </div>
    );
  }

  return <AnalyticsDashboard metrics={data.metrics} funnel={data.funnel} />;
}
