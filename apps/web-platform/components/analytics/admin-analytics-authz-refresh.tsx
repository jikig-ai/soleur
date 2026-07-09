"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";

/**
 * GAP H (ADR-067 staleTimes amendment): warm-cache authz re-validation for the
 * admin analytics route.
 *
 * `admin/analytics/page.tsx` bakes ALL-tenant data (every user's email + all
 * conversations, read via the RLS-bypassing `createServiceClient()`) into its
 * RSC payload, gated only by an `ADMIN_USER_IDS` env check that runs *server*
 * side. With ADR-067's `staleTimes.dynamic = 30`, the App Router Router Cache
 * can serve that all-tenant RSC on a soft return WITHOUT a server round-trip —
 * so a user removed from `ADMIN_USER_IDS` (env-deprovision) with a warm cache
 * could soft-navigate back into the stale all-tenant page. Neither the #4307
 * jti-revocation gate nor RLS covers this (it is an env check on a service-role
 * read), making it the highest-blast-radius vector in this change.
 *
 * This mounts inside the analytics page and calls `router.refresh()` on mount,
 * which forces a fresh RSC fetch from the server on every entry (including a
 * Router-Cache restore) — re-running the page's `isAdmin` gate so a
 * de-provisioned admin is `redirect("/dashboard")`-ed instead of being served
 * the cached all-tenant RSC. `router.refresh()` does not remount client
 * components, so the mount-only effect never loops. The per-entry re-fetch
 * deliberately forfeits the tab-switch perf win for this one rarely-visited
 * admin route in exchange for always-fresh authz + data.
 */
export function AdminAnalyticsAuthzRefresh() {
  const router = useRouter();
  const refreshed = useRef(false);
  useEffect(() => {
    if (refreshed.current) return;
    refreshed.current = true;
    router.refresh();
  }, [router]);
  return null;
}
