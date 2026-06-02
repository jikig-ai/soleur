"use client";

import { useState, useEffect, useCallback } from "react";

// ADR-047 collapse-key unification: the single nav rail uses ONE collapse key
// (`soleur:sidebar.main.collapsed`, owned by (dashboard)/layout.tsx). The
// per-section keys are orphaned once the Settings sub-nav and Conversations
// rail lifted into the unified rail; sweep them once so stale "1" values don't
// linger. KB collapse was always ephemeral (in-memory useState), so it has no
// key to clean.
const ORPHAN_COLLAPSE_KEYS = [
  "soleur:sidebar.settings.collapsed",
  "soleur:sidebar.chat-rail.collapsed",
] as const;
let orphansCleaned = false;
function cleanupOrphanCollapseKeys() {
  if (orphansCleaned) return;
  orphansCleaned = true;
  try {
    for (const key of ORPHAN_COLLAPSE_KEYS) localStorage.removeItem(key);
  } catch {
    // localStorage unavailable (private mode, etc.) — nothing to clean.
  }
}

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
    cleanupOrphanCollapseKeys();
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
