// Shared sidebar navigation data — the single source of truth for both the
// dashboard rail (app/(dashboard)/layout.tsx) and the ⌘K command palette
// registry (use-shortcuts.tsx). Extracted from layout.tsx (was module-local,
// not exported) so the registry can import it without pulling the layout's
// "use client" tree. Icons stay in layout.tsx (keyed by href via NAV_ICONS) —
// this module carries only the route + label data the palette needs.

export type NavItem = {
  readonly href: string;
  readonly label: string;
  /**
   * Optional two-key "go-to" sequence (e.g. `"g d"` — the `g` prefix then `d`).
   * The SINGLE source of truth for this destination's global keyboard binding:
   * the resolver, the palette key hint, and the `?` overlay row all derive from
   * it, so a documented key can never drift from the live binding (no separate
   * NAV_SEQUENCES table). `g`-prefixed sequences (never a bare letter) are
   * collision-free with browser chords — the wireframe's design, un-deferred
   * from #5636.
   */
  readonly seq?: string;
  /**
   * Optional single-letter Super/Meta accelerator (e.g. `"d"` → ⌘D). The SINGLE
   * source for this destination's `metaKey`-only binding: the `resolveNavChord`
   * map, the palette accel hint, and the `?` overlay accel row all derive from
   * it, so a documented key can never drift from the live binding. Absent ⇔
   * intentionally unbound (⌘W closes the tab before JS runs; ⌘K is already the
   * palette). Mirrors `seq`; named `accel` NOT `metaKey` (which collides with the
   * DOM `metaKey: boolean` on `ShortcutKeyEvent`).
   */
  readonly accel?: string;
};

export const NAV_ITEMS: readonly NavItem[] = [
  { href: "/dashboard", label: "Dashboard", seq: "g d", accel: "d" },
  { href: "/dashboard/inbox", label: "Inbox", seq: "g i", accel: "i" },
  { href: "/dashboard/workstream", label: "Workstream", seq: "g w" }, // NO accel — ⌘W unbindable
  { href: "/dashboard/kb", label: "Knowledge Base", seq: "g k" }, // NO accel — ⌘K = palette
  { href: "/dashboard/routines", label: "Routines", seq: "g r", accel: "r" },
  { href: "/dashboard/releases", label: "Releases", seq: "g l" }, // NO accel — ⌘L is browser-reserved (address bar)
] as const;

export const ADMIN_NAV_ITEMS: readonly NavItem[] = [
  { href: "/dashboard/admin/analytics", label: "Analytics", seq: "g a", accel: "a" },
] as const;

// Settings destinations — surfaced under the palette's "Settings" drill-in
// sub-page (NOT flat in the root command list), so the root stays scannable and
// Settings reads like Knowledge Base / Workflows: click in to see the items.
export const SETTINGS_NAV_ITEMS: readonly NavItem[] = [
  { href: "/dashboard/settings", label: "All settings" },
  { href: "/dashboard/settings/team", label: "Team" },
  { href: "/dashboard/billing", label: "Billing" },
  { href: "/dashboard/audit", label: "Audit log" },
] as const;
