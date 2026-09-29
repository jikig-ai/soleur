"use client";

import { useEffect, useState } from "react";

/**
 * Post-first-paint gate (#9178 / ADR-067 amendment). Returns `false` until the
 * browser has painted and gone idle, then `true` for the rest of the mount.
 * Consumers pass a `null` SWR key while it is false so non-critical data
 * (nav-badge counts, releases, team names) does not contend with first paint;
 * deferred surfaces still render last-known cached state instantly on repeat
 * navigations (warm cache reads are never gated by this hook — only the fetch
 * is deferred).
 *
 * `requestIdleCallback` is the primary signal; `setTimeout(0)` is the fallback
 * for engines without it (Safari). Neither observes a real FCP entry — the
 * contract is "after first render + one idle slice", which is what the mount
 * fan-out needs.
 */
export function usePostFcp(): boolean {
  const [pastFcp, setPastFcp] = useState(false);

  useEffect(() => {
    if (typeof window.requestIdleCallback === "function") {
      const id = window.requestIdleCallback(() => setPastFcp(true));
      return () => window.cancelIdleCallback(id);
    }
    const id = setTimeout(() => setPastFcp(true), 0);
    return () => clearTimeout(id);
  }, []);

  return pastFcp;
}
