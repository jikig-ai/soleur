"use client";

import { useState, useEffect, useCallback } from "react";

/**
 * Manages sidebar collapse state with localStorage persistence.
 * Follows the PaymentWarningBanner hydration pattern: starts expanded (false),
 * then reads localStorage in a post-hydration useEffect.
 */
export function useSidebarCollapse(
  storageKey: string,
): [collapsed: boolean, toggle: () => void] {
  const [collapsed, setCollapsed] = useState(false);

  // Hydrate collapse state from localStorage (client-only).
  useEffect(() => {
    try {
      if (localStorage.getItem(storageKey) === "1") {
        setCollapsed(true);
      }
    } catch {
      // localStorage unavailable (private mode, etc.) — keep default false.
    }
  }, [storageKey]);

  const toggle = useCallback(() => {
    setCollapsed((prev) => {
      const next = !prev;
      try {
        if (next) {
          localStorage.setItem(storageKey, "1");
        } else {
          localStorage.removeItem(storageKey);
        }
      } catch {
        // Persistence failed (quota, private mode) — in-memory state still
        // toggles the sidebar for the current mount.
      }
      return next;
    });
  }, [storageKey]);

  return [collapsed, toggle];
}
