// Shared sidebar navigation data — the single source of truth for both the
// dashboard rail (app/(dashboard)/layout.tsx) and the ⌘K command palette
// registry (use-shortcuts.tsx). Extracted from layout.tsx (was module-local,
// not exported) so the registry can import it without pulling the layout's
// "use client" tree. Icons stay in layout.tsx (keyed by href via NAV_ICONS) —
// this module carries only the route + label data the palette needs.

export type NavItem = {
  readonly href: string;
  readonly label: string;
};

export const NAV_ITEMS: readonly NavItem[] = [
  { href: "/dashboard", label: "Dashboard" },
  { href: "/dashboard/inbox", label: "Inbox" },
  { href: "/dashboard/workstream", label: "Workstream" },
  { href: "/dashboard/kb", label: "Knowledge Base" },
  { href: "/dashboard/routines", label: "Routines" },
] as const;

export const ADMIN_NAV_ITEMS: readonly NavItem[] = [
  { href: "/dashboard/admin/analytics", label: "Analytics" },
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
