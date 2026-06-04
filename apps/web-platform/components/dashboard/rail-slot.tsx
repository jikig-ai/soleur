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

// Expand-request channel (Sidebar-UX follow-up Issue 6). A collapsed-rail child
// (the KB shell's "Browse files" affordance) reads collapse state read-only via
// `useRailCollapsed()` and has no setter, so it requests an EXPAND by dispatching
// this window event; the layout — the sole collapse owner (ADR-047) — listens and
// flips. Defined here (the rail-contract module) so the dispatcher, the listener,
// and the test reference one literal instead of three drift-prone copies.
export const RAIL_EXPAND_EVENT = "soleur:rail-expand";

const RailSlotContext = createContext<HTMLElement | null>(null);

export const RailSlotProvider = RailSlotContext.Provider;

export function useRailSlot(): HTMLElement | null {
  return useContext(RailSlotContext);
}

// Sibling collapse context (NOT a widening of RailSlotContext — that value is
// `HTMLElement | null` and is set positionally at two call sites). The portaled
// secondary nav (Settings sub-nav / KB tree / Conversations rail) reads
// `collapsed` through the REACT tree (it stays inside the layout's provider
// subtree even though its DOM lands in the rail slot) so each section can
// render-conditional its content off when the rail is collapsed — hiding the
// secondary nav instead of letting its full-width content clip at the 56px
// collapsed rail. Default `false` so a section rendered outside the provider
// (isolated component tests) behaves as expanded.
const RailCollapsedContext = createContext<boolean>(false);

export const RailCollapsedProvider = RailCollapsedContext.Provider;

export function useRailCollapsed(): boolean {
  return useContext(RailCollapsedContext);
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
