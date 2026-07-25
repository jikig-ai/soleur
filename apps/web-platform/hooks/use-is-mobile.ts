"use client";

import { useEffect, useState } from "react";

/**
 * Hydration-safe "is this a narrow (mobile) viewport?" gate for responsive
 * dual-layouts (e.g. a desktop `<table>` vs a mobile card list).
 *
 * WHY NOT `useMediaQuery` directly: `useMediaQuery` seeds its initial state from
 * `window.matchMedia(...).matches`, which is `false` during SSR (no `window`) but
 * the REAL value on the client's first render — so an SSR'd component whose first
 * client render differs (desktop) mismatches the server HTML (mobile) and React
 * throws a hydration error, then patches the DOM. That is the exact regression
 * that broke the mobile kanban board (CSS dual-render variant); see
 * `knowledge-base/project/learnings/2026-07-23-mobile-responsive-dual-render-and-tablist-a11y.md`.
 *
 * This hook instead seeds `false` (desktop-first) on BOTH the server and the
 * first client render — so hydration always matches — then flips to the true
 * viewport value in an effect after mount. The cost is a one-frame desktop→mobile
 * swap on phones for components that are server-rendered with data already
 * present; components mounted client-only (behind a data/skeleton gate) never
 * flash because `mounted` is already true by the time they paint.
 */
export function useIsMobile(query = "(max-width: 767px)"): boolean {
  const [isMobile, setIsMobile] = useState(false);

  useEffect(() => {
    const mq = window.matchMedia(query);
    setIsMobile(mq.matches);
    const onChange = () => setIsMobile(mq.matches);
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, [query]);

  return isMobile;
}
