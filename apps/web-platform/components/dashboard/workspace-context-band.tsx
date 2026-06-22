"use client";

import Link from "next/link";
import { OrgSwitcherContainer } from "@/components/dashboard/org-switcher-container";
import { LiveRepoBadge } from "@/components/dashboard/live-repo-badge";
import { WorkspaceIdentityTile } from "@/components/dashboard/workspace-identity-tile";
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
  activeWorkspaceName,
  activeWorkspaceId,
  activeWorkspaceHasLogo,
  suppressBack = false,
  suppressSectionTitle = false,
}: {
  pathname: string;
  /** "rail" mounts in the sidebar; "mobile" mounts in the mobile top bar. */
  variant?: "rail" | "mobile";
  /** Rail-only: when the sidebar is collapsed (md:w-14) render the icon-only
   *  form. Ignored for variant="mobile" (the mobile top bar never collapses). */
  collapsed?: boolean;
  /** Suppress the band's "Back to menu" affordance (Phase 3, #4915). The layout
   *  sets this on the MOBILE band in the KB doc view, where kb-content-header
   *  already owns the only back ("Back to file tree") — so the two backs no
   *  longer co-render. The band derives nothing from pathname here: the decision
   *  is computed by the layout (the sole pathname owner) and passed in, keeping
   *  segmentToDrillLevel the sole drill authority (ADR-047 AC4c). */
  suppressBack?: boolean;
  /** Collapsed-rail only: the active workspace name. The collapsed band does
   *  NOT mount OrgSwitcherContainer, so it has no name in scope — the layout
   *  threads it in (P0-3) so the monogram tile + full-name tooltip can render
   *  as the authoritative disambiguator for shared-initial workspaces. */
  activeWorkspaceName?: string;
  /** Collapsed-rail only: the active workspace id + hasLogo, threaded from the
   *  layout's useActiveWorkspace hook so the collapsed band's tile can render
   *  the custom logo (via the stable proxy `src`) instead of the monogram
   *  (#4916). Same single fetch as the name. */
  activeWorkspaceId?: string;
  activeWorkspaceHasLogo?: boolean;
  /** Suppress the band's section-title row (Phase 4, #4915). The layout sets
   *  this on the MOBILE band for KB, where the page body owns the "Knowledge
   *  Base" title — so the two don't double-render on mobile. The desktop rail
   *  band keeps its section title. KB-scoped, so Settings/Chat are unaffected. */
  suppressSectionTitle?: boolean;
}) {
  const drill = segmentToDrillLevel(pathname);

  // #4810 Bug 2: at md:w-14 (56px) the verbose org chip + "Working on:" repo +
  // section title overflow into an unreadable strip. Render an icon-only column
  // when collapsed — just the back chevron (drilled) + the workspace identity
  // tile — so the rail never overflows horizontally. The earlier decorative gold
  // repo dot and single-letter section monogram were removed (sidebar declutter):
  // both carried no information the identity tile + the section's own collapsed
  // nav icon don't already carry. The identity is never FULLY unmounted
  // (ADR-047): the data-bearing OrgSwitcherContainer + LiveRepoBadge stay mounted
  // in the CSS-exclusive mobile band, and the identity tile's hover title recovers
  // orientation. Verbose labels return verbatim on expand.
  if (variant === "rail" && collapsed) {
    return (
      <div
        data-testid="workspace-context-band"
        data-variant="rail"
        data-collapsed="true"
        // pt-16 (not py-3) reserves top clearance for the floated collapse toggle
        // (layout.tsx, `absolute left-1/2 -translate-x-1/2 top-10` when collapsed):
        // in the 56px collapsed rail the centered toggle (top-10=40px, bottom edge
        // 64px from the aside top) shares this tile's vertical center axis, so the
        // only thing keeping them disjoint is vertical separation. This band sits
        // ~12px below the aside top, so the toggle's bottom edge is 64-12 = 52px in
        // band-relative space; pt-16 (64px) drops the first icon ~12px below it — a
        // clear gap so the toggle no longer reads as crowding the logo. The collapsed
        // rail has ample vertical room, so the larger top pad costs nothing the user
        // notices. (Was pt-14 = 56px → only ~4px gap, which read as "too close".)
        className="flex flex-col items-center gap-3 px-2 pb-3 pt-16"
      >
        {drill && !suppressBack ? (
          <Link
            href="/dashboard"
            aria-label="Back to menu"
            data-testid="nav-back-chevron"
            className="flex h-7 w-7 shrink-0 items-center justify-center rounded text-soleur-accent-gold-fg hover:bg-soleur-bg-surface-2"
          >
            <BackArrowIcon className="h-4 w-4" />
          </Link>
        ) : null}
        <span
          data-testid="workspace-identity-icon"
          aria-label={activeWorkspaceName ?? "Active workspace"}
          title={activeWorkspaceName ?? "Active workspace"}
          className="flex shrink-0"
        >
          <WorkspaceIdentityTile
            name={activeWorkspaceName ?? ""}
            size="sm"
            variant="identity"
            workspaceId={activeWorkspaceId}
            hasLogo={activeWorkspaceHasLogo}
          />
        </span>
      </div>
    );
  }

  return (
    <div
      data-testid="workspace-context-band"
      data-variant={variant}
      className={
        variant === "mobile"
          ? "flex min-w-0 flex-1 flex-col gap-0.5"
          : "flex flex-col"
      }
    >
      {/* Workspace pill LEADS the band — the persistent workspace identity is
          the orientation anchor, so it sits above the "Back to menu" nav
          affordance. The pill face now also surfaces the active repo as a muted
          subtitle (folded in from the old standalone "Working on:" row), so the
          band no longer burns a separate row on it. Sidebar-UX follow-up Issue 1:
          the leading top room is pt-2 (was pt-3) so — together with the tightened
          brand-row padding above — the gap between the collapse toggle and this
          pill no longer reads as a large empty band. */}
      {/* md:pr-20 reserves right clearance for the TWO floated controls
          (layout.tsx): the collapse toggle (`absolute right-3 top-10` → the right
          12–36px) and, just left of it, the full-hide toggle (`right-10 top-10` →
          40–64px). pr-20 (80px) clears the leftmost (hide) edge at 64px with a
          16px margin. Without it the multi-workspace switcher's `▾` chevron
          (org-switcher.tsx, `shrink-0` at the card's right edge) sits under a
          toggle. Desktop-only (md:) — the mobile band is below the md breakpoint
          and unaffected. (Was md:pr-10 when only the collapse toggle floated.)

          md:min-h-[64px] (drill === null only) reserves the floated toggle's full
          vertical footprint — top-10 (40px) + h-6 (24px) = 64px from the aside top
          — so the not-yet-loaded band cannot collapse below it. On the top-level
          route the band's ONLY content is the async pill, and OrgSwitcherContainer
          returns null until /api/workspace/list-memberships resolves
          (org-switcher-container.tsx:214); without a reserved height the band
          shrinks to ~8px and the nav (pt-3 below) rises into the toggle's footprint
          — the toggle then paints over the "Dashboard" nav link during page load.
          Scoped to drill === null because drilled (Settings/KB/Chat) bands already
          exceed 64px via the back-link + section-title rows; md: because the mobile
          band is below the breakpoint (inert there); the collapsed icon-only form
          returns early above and never reaches this div. Idiom precedent:
          components/shared/cta-banner.tsx min-h-[1rem]. */}
      <div
        className={`flex items-center gap-2 px-3 pt-2 md:pr-20${
          drill === null ? " md:min-h-[64px]" : ""
        }`}
      >
        <div className="min-w-0 flex-1">
          <OrgSwitcherContainer />
        </div>
      </div>

      {/* J5 revocation interstitial only — LiveRepoBadge no longer renders the
          repo name (that moved into the pill subtitle above). It stays mounted
          here so the band remains its sole importer (nav-single-mount invariant)
          and the access-revocation alert keeps a home. Renders null on the happy
          path, so the pill is visually adjacent to "Back to menu" below. */}
      <LiveRepoBadge />

      {/* Back-to-menu affordance — its OWN labelled row (not inline beside the
          pill), shown only when drilled. Now FOLLOWS the pill (tighter pt-2,
          since the pill above already supplied the band's top breathing room).
          Synchronous (first render, never async-gated). Left gutter (px-3)
          matches the brand-row collapse toggle so the two controls share the
          same px-3 border-box gutter. The label + distinct BackArrowIcon stop it
          reading as a duplicate of the collapse chevron (#4810 follow-up Bug 2). */}
      {drill && !suppressBack ? (
        <Link
          href="/dashboard"
          aria-label="Back to menu"
          data-testid="nav-back-chevron"
          className="flex min-w-0 items-center gap-2 px-3 pt-2 text-sm text-soleur-accent-gold-fg hover:text-soleur-text-primary"
        >
          <BackArrowIcon className="h-4 w-4 shrink-0" />
          <span className="truncate">Back to menu</span>
        </Link>
      ) : null}

      {/* Section title. Sidebar-UX follow-up Issue 3: the title used to sit
          directly under "Back to menu" (back pt-2 → title pb-3, no inter-row
          gap), so "Back to menu" and "Settings" / "Knowledge Base" read as one
          cramped block. pt-3 adds a clear gap between the back link and the
          section heading (shared band → applies to both Settings and KB). */}
      {drill && !suppressSectionTitle && (
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
