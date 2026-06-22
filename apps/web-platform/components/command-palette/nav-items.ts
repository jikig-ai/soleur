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
  { href: "/dashboard/kb", label: "Knowledge Base" },
  { href: "/dashboard/routines", label: "Routines" },
] as const;

export const ADMIN_NAV_ITEMS: readonly NavItem[] = [
  { href: "/dashboard/admin/analytics", label: "Analytics" },
] as const;

// Destinations reachable from the palette that are NOT in the rail's primary
// nav (footer/secondary surfaces). Kept here so the palette's navigation group
// is dense without duplicating literals across components.
export const SECONDARY_NAV_ITEMS: readonly NavItem[] = [
  { href: "/dashboard/settings", label: "Settings" },
  { href: "/dashboard/settings/team", label: "Team Settings" },
  { href: "/dashboard/billing", label: "Billing" },
  { href: "/dashboard/audit", label: "Audit Log" },
] as const;
