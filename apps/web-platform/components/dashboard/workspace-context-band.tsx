"use client";

import Link from "next/link";
import { OrgSwitcherContainer } from "@/components/dashboard/org-switcher-container";
import { LiveRepoBadge } from "@/components/dashboard/live-repo-badge";
import { BackArrowIcon } from "@/components/dashboard/nav-icons";
import {
  segmentToDrillLevel,
  type DrillLevel,
} from "@/hooks/segment-to-drill-level";

// Persistent workspace context band (ADR-047). Mounted directly in
// (dashboard)/layout.tsx ABOVE the rail swap region and NEVER gated on
// `collapsed` — so the active-workspace identity is visible in EVERY drill
// state on EVERY breakpoint (brand invariant 1). The band is the sole render
// site for OrgSwitcherContainer + LiveRepoBadge (AC4b single-mount): it does
// NOT reimplement identity/solo/poll logic, it RELOCATES those components. The
// only net-new render code here is the back chevron + section-title label +
// layout shell.
//
// `pathname` is passed in (not read via usePathname) so the band shares the
// single pathname read the layout already owns and stays trivially testable.

const SECTION_LABELS: Record<DrillLevel, string> = {
  kb: "Knowledge Base",
  settings: "Settings",
  chat: "Chat",
};

export function WorkspaceContextBand({
  pathname,
  variant = "rail",
  collapsed = false,
  suppressBack = false,
  suppressSectionTitle = false,
}: {
  pathname: string;
  /** "rail" mounts in the sidebar; "mobile" mounts in the mobile top bar. */
  variant?: "rail" | "mobile";
  /** Rail-only: when the sidebar is collapsed (md:w-14) render the icon-only
   *  form. Ignored for variant="mobile" (the mobile top bar never collapses).
   *  The band renders ONE subtree in both states — it threads `collapsed` into
   *  the persistent OrgSwitcherContainer and varies presentation by className,
   *  rather than early-returning a structurally-divergent tree that omits the
   *  container (the former remount-on-collapse bug; ADR-047 Amendment 2026-06-22). */
  collapsed?: boolean;
  /** Suppress the band's "Back to menu" affordance (Phase 3, #4915). The layout
   *  sets this on the MOBILE band in the KB doc view, where kb-content-header
   *  already owns the only back ("Back to file tree") — so the two backs no
   *  longer co-render. The band derives nothing from pathname here: the decision
   *  is computed by the layout (the sole pathname owner) and passed in, keeping
   *  segmentToDrillLevel the sole drill authority (ADR-047 AC4c). */
  suppressBack?: boolean;
  /** Suppress the band's section-title row (Phase 4, #4915). The layout sets
   *  this on the MOBILE band for KB, where the page body owns the "Knowledge
   *  Base" title — so the two don't double-render on mobile. The desktop rail
   *  band keeps its section title. KB-scoped, so Settings/Chat are unaffected. */
  suppressSectionTitle?: boolean;
}) {
  const drill = segmentToDrillLevel(pathname);

  // The rail collapses to an icon-only column at md:w-14 (56px). CRITICAL: the
  // band renders ONE subtree across collapse/expand — the data-bearing
  // OrgSwitcherContainer stays at a STABLE tree position so React never unmounts
  // it, preserving its membership fetch + switch-confirm state (ADR-047
  // Amendment 2026-06-22: the "never gated on `collapsed`" invariant extends to
  // the band's INTERNAL render path). Only presentation varies by `collapsed`,
  // via className branches on these persistent elements — never an element swap.
  // The icon-only identity tile is now a MODE of the mounted container/switcher
  // (OrgSwitcher `collapsed`), not a separate WorkspaceIdentityTile rendered here.
  const isRailCollapsed = variant === "rail" && collapsed;

  return (
    <div
      data-testid="workspace-context-band"
      data-variant={variant}
      data-collapsed={isRailCollapsed ? "true" : undefined}
      className={
        isRailCollapsed
          ? // pt-16 (not py-3) reserves top clearance for the floated collapse
            // toggle (layout.tsx, `absolute left-1/2 -translate-x-1/2 top-3` when
            // collapsed) so it no longer reads as crowding the identity tile.
            "flex flex-col items-center gap-3 px-2 pb-3 pt-16"
          : variant === "mobile"
            ? "flex min-w-0 flex-1 flex-col gap-0.5"
            : "flex flex-col"
      }
    >
      {/* Workspace pill LEADS the band — the persistent workspace identity is
          the orientation anchor, so it sits above the "Back to menu" nav
          affordance. The pill face also surfaces the active repo as a muted
          subtitle (folded in from the old standalone "Working on:" row). When
          collapsed the SAME container renders an icon-only identity tile instead.

          md:pr-20 (expanded only) reserves right clearance for the floated
          collapse toggle (`absolute right-3 top-10`) so the switcher's `▾`
          chevron never sits under it. md:min-h-[64px] (drill === null, expanded
          only) reserves the toggle's full vertical footprint so the not-yet-
          loaded band — whose only content is the async pill — cannot collapse
          below the toggle and let the nav rise into its footprint. */}
      <div
        className={
          isRailCollapsed
            ? "flex w-full justify-center"
            : `flex items-center gap-2 px-3 pt-2 md:pr-20${
                drill === null ? " md:min-h-[64px]" : ""
              }`
        }
      >
        <div className="min-w-0 flex-1">
          <OrgSwitcherContainer collapsed={isRailCollapsed} />
        </div>
      </div>

      {/* J5 revocation interstitial only — LiveRepoBadge no longer renders the
          repo name (that moved into the pill subtitle above). It stays mounted
          here so the band remains its sole importer (nav-single-mount invariant)
          and the access-revocation alert keeps a home. Renders null on the happy
          path. */}
      <LiveRepoBadge />

      {/* Back-to-menu affordance — shown only when drilled. Expanded: its OWN
          labelled row following the pill. Collapsed: an icon-only chevron (no
          text) so the 56px rail never overflows. Synchronous (first render,
          never async-gated). The distinct BackArrowIcon stops it reading as a
          duplicate of the collapse chevron (#4810 follow-up Bug 2). */}
      {drill && !suppressBack ? (
        <Link
          href="/dashboard"
          aria-label="Back to menu"
          data-testid="nav-back-chevron"
          className={
            isRailCollapsed
              ? "flex h-7 w-7 shrink-0 items-center justify-center rounded text-soleur-accent-gold-fg hover:bg-soleur-bg-surface-2"
              : "flex min-w-0 items-center gap-2 px-3 pt-2 text-sm text-soleur-accent-gold-fg hover:text-soleur-text-primary"
          }
        >
          <BackArrowIcon className="h-4 w-4 shrink-0" />
          {!isRailCollapsed && <span className="truncate">Back to menu</span>}
        </Link>
      ) : null}

      {/* Section title. Hidden when collapsed (no horizontal room at 56px — the
          section's own collapsed nav icon carries the orientation). Sidebar-UX
          follow-up Issue 3: pt-3 adds a clear gap between the back link and the
          section heading (shared band → applies to both Settings and KB). */}
      {drill && !suppressSectionTitle && !isRailCollapsed && (
        <div
          data-testid="nav-section-title"
          className="flex items-center gap-2 px-3 pb-3 pt-3 text-sm font-medium text-soleur-text-primary"
        >
          {SECTION_LABELS[drill]}
        </div>
      )}
    </div>
  );
}
