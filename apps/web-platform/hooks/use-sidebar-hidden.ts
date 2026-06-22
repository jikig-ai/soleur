"use client";

import { useState, useEffect, useCallback } from "react";

// Full-hide ("0px") sidebar state — ORTHOGONAL to collapse. Collapse
// (`useSidebarCollapse`, key `soleur:sidebar.main.collapsed`) toggles the rail
// between its 224px expanded width and the 56px icon rail; HIDE drives the
// desktop rail all the way to `md:w-0` (fully off-canvas, every pixel of
// horizontal space reclaimed for the main content). `hidden` takes precedence
// over collapse, and because the in-rail re-entry affordances are clipped at
// 0px, the floating reveal hamburger + ⌘⇧B are the way back (see
// (dashboard)/layout.tsx).
//
// Distinct localStorage key so the two states persist independently and neither
// corrupts the other's boolean contract. NOTE: this hook deliberately does NOT
// copy useSidebarCollapse's `cleanupOrphanCollapseKeys()` sweep — that is
// collapse-key-unification (ADR-047) cruft and would risk deleting unrelated
// keys here.
export const SIDEBAR_HIDDEN_KEY = "soleur:sidebar.main.hidden";

/**
 * Manages full-hide sidebar state with localStorage persistence.
 *
 * Mirrors useSidebarCollapse's SSR-safe hydration: starts visible (`false`),
 * then reads localStorage in a post-hydration useEffect, so the server HTML and
 * the first client render both produce `false` (no hydration mismatch / no
 * first-paint flash). Encoding matches the codebase convention — `hidden=true`
 * persists the string `"1"`; `hidden=false` REMOVES the key (it never stores
 * `"0"`, which is a truthy string that would hydrate straight back to hidden).
 */
export function useSidebarHidden(
  storageKey: string = SIDEBAR_HIDDEN_KEY,
): [hidden: boolean, toggle: () => void] {
  const [hidden, setHidden] = useState(false);

  // Hydrate hidden state from localStorage (client-only).
  useEffect(() => {
    try {
      if (localStorage.getItem(storageKey) === "1") {
        setHidden(true);
      }
    } catch {
      // localStorage unavailable (private mode, etc.) — keep default false.
    }
  }, [storageKey]);

  const toggle = useCallback(() => {
    setHidden((prev) => {
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

  return [hidden, toggle];
}
