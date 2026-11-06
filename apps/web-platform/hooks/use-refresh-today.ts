"use client";

import { useSWRConfig } from "swr";
import { swrKeys } from "@/lib/swr-config";

// #11569/#11572 (D22): drop an acted-on card from the in-memory Today list, then revalidate.
// A bare `mutate(key)` only revalidates and keeps the stale value until the (no-store) response lands, so a
// remount in that window would render the discarded card again. The optimistic filter makes the drop real
// (ADR-067). Pass no id to just revalidate (a "forbidden" 403 means the card is already gone server-side).
export function useRefreshToday(): (removeId?: string) => void {
  const { mutate } = useSWRConfig();
  return (removeId?: string) => {
    if (removeId === undefined) {
      void mutate(swrKeys.dashboardToday());
      return;
    }
    void mutate(
      swrKeys.dashboardToday(),
      (items?: Array<{ id: string }>) => items?.filter((i) => i.id !== removeId),
      { revalidate: true },
    );
  };
}
