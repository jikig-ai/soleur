"use client";

import { useState, useEffect, useCallback } from "react";

// Widenable KB rail (amendment). Persisted width of the EXPANDED KB nav rail so
// deeply-nested folder/file names stop truncating at the fixed 224px default.
// Mirrors useSidebarCollapse's shape: a useState default, a post-hydration
// localStorage read, and a setter that clamps then persists — all localStorage
// access in try/catch (private-mode safe). Distinct key + clamp, so it is a new
// hook rather than a widening of useSidebarCollapse's boolean tuple.

export const RAIL_WIDTH_KEY = "soleur:sidebar.kb.width";
/** Default = today's fixed `md:w-56` (14rem = 224px) — widening never narrows. */
export const RAIL_DEFAULT_PX = 224;
export const RAIL_MIN_PX = 224;
/** Absolute ceiling; the effective max is also bounded to 40vw (see railMaxPx). */
export const RAIL_MAX_ABS_PX = 480;
export const RAIL_MAX_VW = 0.4;

/**
 * Effective max width: the smaller of the absolute ceiling and 40% of the
 * viewport, but never below RAIL_MIN_PX (so a tiny viewport cannot invert the
 * clamp). Pure given an explicit `viewportWidth` (deterministic in tests);
 * falls back to `window.innerWidth` at runtime, or 1280 during SSR.
 */
export function railMaxPx(viewportWidth?: number): number {
  const vw =
    viewportWidth ??
    (typeof window !== "undefined" ? window.innerWidth : 1280);
  return Math.max(
    RAIL_MIN_PX,
    Math.min(RAIL_MAX_ABS_PX, Math.floor(vw * RAIL_MAX_VW)),
  );
}

/** Clamp `px` to [RAIL_MIN_PX, railMaxPx()], rounding; NaN → default. */
export function clampRailWidth(px: number, viewportWidth?: number): number {
  if (Number.isNaN(px)) return RAIL_DEFAULT_PX;
  const max = railMaxPx(viewportWidth);
  return Math.min(max, Math.max(RAIL_MIN_PX, Math.round(px)));
}

/**
 * Manage the KB rail's persisted width. Returns `[widthPx, setWidth]`.
 * `setWidth(px)` clamps + persists; `setWidth(px, false)` updates state only
 * (transient drag preview — the handle commits once on pointerup).
 */
export function useRailWidth(
  storageKey: string = RAIL_WIDTH_KEY,
): [number, (px: number, persist?: boolean) => void] {
  const [width, setWidthState] = useState(RAIL_DEFAULT_PX);

  // Hydrate from localStorage post-mount (client-only), clamping the STORED
  // value on read so a stale/corrupt entry cannot swallow the content area.
  useEffect(() => {
    try {
      const raw = localStorage.getItem(storageKey);
      if (raw !== null) {
        const parsed = parseInt(raw, 10);
        if (!Number.isNaN(parsed)) setWidthState(clampRailWidth(parsed));
      }
    } catch {
      // localStorage unavailable (private mode, etc.) — keep the default.
    }
  }, [storageKey]);

  const setWidth = useCallback(
    (px: number, persist = true) => {
      const clamped = clampRailWidth(px);
      setWidthState(clamped);
      if (persist) {
        try {
          localStorage.setItem(storageKey, String(clamped));
        } catch {
          // Persistence failed (quota, private mode) — in-memory width still
          // applies for this mount.
        }
      }
    },
    [storageKey],
  );

  return [width, setWidth];
}
