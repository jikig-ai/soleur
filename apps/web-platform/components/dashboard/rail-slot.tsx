"use client";

import { createContext, useContext } from "react";
import { createPortal } from "react-dom";

// The single-rail swap region (ADR-047). The (dashboard)/layout.tsx rail
// renders ONE secondary-nav slot below the persistent context band. Each
// drilled section (KB tree / Settings sub-nav / Conversations rail) renders
// its secondary nav into that slot via a React portal.
//
// Why a portal and not "render the nav directly in the layout, keyed by
// segment": the KB file tree depends on KbContext (established in
// kb/layout.tsx via useKbLayoutState — ONE fetch shared with the doc viewer +
// chat panel), and the Settings sub-nav depends on server-resolved
// membersTab/activityTab props (resolved in settings/layout.tsx). A portal
// keeps each nav inside its own provider subtree (React context follows the
// REACT tree, not the DOM tree) while placing its DOM in the unified rail —
// no duplicated fetch, no lifted-context-fetches-on-every-route regression.

const RailSlotContext = createContext<HTMLElement | null>(null);

export const RailSlotProvider = RailSlotContext.Provider;

export function useRailSlot(): HTMLElement | null {
  return useContext(RailSlotContext);
}

/**
 * Render `children` into the dashboard rail's secondary-nav slot. Renders
 * nothing until the slot node is mounted (the layout mounts it only on drilled
 * routes), so a section's nav simply no-ops at the top level.
 */
export function RailSlotPortal({ children }: { children: React.ReactNode }) {
  const slot = useRailSlot();
  if (!slot) return null;
  return createPortal(children, slot);
}
