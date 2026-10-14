"use client";

import { useEffect, useState } from "react";

/**
 * Post-first-paint gate (#9178 / ADR-067 amendment). Returns `false` until the
 * browser has painted and gone idle, then `true` for the rest of the mount.
 * Consumers pass a `null` SWR key while it is false so non-critical data
 * (nav-badge counts, releases, team names) does not contend with first paint.
 * The gated consumers all live in the persistent dashboard shell, so this
 * only bites on a cold document load — where the in-memory SWR cache is
 * empty anyway (`useSWR(null)` yields `data: undefined` regardless of cache
 * warmth; warm-repeat renders come from the persisted cache surviving route
 * transitions, not from this hook).
 *
 * `requestIdleCallback` (bounded by `timeout` so a saturated main thread can't
 * starve the gate) is the primary signal; `requestAnimationFrame → setTimeout`
 * is the fallback for engines without it (Safari), landing after the first
 * paint opportunity. Neither observes a real FCP entry — the contract is
 * "after first render + one paint opportunity", which is what the mount
 * fan-out needs.
 */
export function usePostFcp(): boolean {
  const [pastFcp, setPastFcp] = useState(false);

  useEffect(() => {
    if (typeof window.requestIdleCallback === "function") {
      // `timeout` bounds the deferral: without it an idle callback can starve
      // indefinitely on a saturated main thread, and the gated keys would
      // stay null for the whole mount (silent badge/count omission).
      const id = window.requestIdleCallback(() => setPastFcp(true), {
        timeout: 2_000,
      });
      return () => window.cancelIdleCallback?.(id);
    }
    // Engines without rIC (Safari): rAF lands just before the next paint,
    // then a macrotask lands after it — a closer "post-paint" approximation
    // than a bare setTimeout(0), which can fire before the first frame.
    if (typeof window.requestAnimationFrame === "function") {
      let timeoutId: ReturnType<typeof setTimeout> | undefined;
      const rafId = window.requestAnimationFrame(() => {
        timeoutId = setTimeout(() => setPastFcp(true), 0);
      });
      return () => {
        window.cancelAnimationFrame(rafId);
        if (timeoutId !== undefined) clearTimeout(timeoutId);
      };
    }
    const id = setTimeout(() => setPastFcp(true), 0);
    return () => clearTimeout(id);
  }, []);

  return pastFcp;
}
