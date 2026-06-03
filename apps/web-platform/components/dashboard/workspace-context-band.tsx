"use client";

import Link from "next/link";
import { OrgSwitcherContainer } from "@/components/dashboard/org-switcher-container";
import { LiveRepoBadge } from "@/components/dashboard/live-repo-badge";
import { WorkspaceIdentityTile } from "@/components/dashboard/workspace-identity-tile";
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

// Distinct from the layout collapse-toggle chevron (ChevronLeftIcon, path
// "M15.75 19.5 8.25 12l7.5-7.5"). The two controls sat at different vertical
// positions with byte-identical glyphs, reading as a broken duplicate (#4810
// follow-up). A long left arrow ("back to menu") is visually unmistakable from
// the rail-collapse chevron.
function BackArrowIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth={1.5}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18"
      />
    </svg>
  );
}

export function WorkspaceContextBand({
  pathname,
  variant = "rail",
  collapsed = false,
  activeWorkspaceName,
}: {
  pathname: string;
  /** "rail" mounts in the sidebar; "mobile" mounts in the mobile top bar. */
  variant?: "rail" | "mobile";
  /** Rail-only: when the sidebar is collapsed (md:w-14) render the icon-only
   *  form. Ignored for variant="mobile" (the mobile top bar never collapses). */
  collapsed?: boolean;
  /** Collapsed-rail only: the active workspace name. The collapsed band does
   *  NOT mount OrgSwitcherContainer, so it has no name in scope — the layout
   *  threads it in (P0-3) so the monogram tile + full-name tooltip can render
   *  as the authoritative disambiguator for shared-initial workspaces. */
  activeWorkspaceName?: string;
}) {
  const drill = segmentToDrillLevel(pathname);

  // #4810 Bug 2: at md:w-14 (56px) the verbose org chip + "Working on:" repo +
  // section title overflow into an unreadable strip. Render an icon-only column
  // when collapsed — back chevron (drilled), an org avatar mark, a repo dot, and
  // a section glyph — so the rail never overflows horizontally. The identity is
  // never FULLY unmounted (ADR-047): the data-bearing OrgSwitcherContainer +
  // LiveRepoBadge stay mounted in the CSS-exclusive mobile band, and hover titles
  // here recover orientation. Verbose labels return verbatim on expand.
  if (variant === "rail" && collapsed) {
    return (
      <div
        data-testid="workspace-context-band"
        data-variant="rail"
        data-collapsed="true"
        className="flex flex-col items-center gap-3 px-2 py-3"
      >
        {drill ? (
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
          <WorkspaceIdentityTile name={activeWorkspaceName ?? ""} size="sm" />
        </span>
        <span
          data-testid="live-repo-dot"
          aria-label="Active repository"
          title="Active repository"
          className="text-base leading-none text-soleur-accent-gold-fg"
        >
          ●
        </span>
        {drill ? (
          <span
            data-testid="nav-section-title"
            title={SECTION_LABELS[drill]}
            className="text-xs font-semibold uppercase text-soleur-text-muted"
          >
            {SECTION_LABELS[drill].charAt(0)}
          </span>
        ) : null}
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
          affordance (the leading element carries the band's top breathing room,
          pt-3). The pill face now also surfaces the active repo as a muted
          subtitle (folded in from the old standalone "Working on:" row), so the
          band no longer burns a separate row on it. */}
      <div className="flex items-center gap-2 px-3 pt-3">
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
      {drill ? (
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

      {drill && (
        <div
          data-testid="nav-section-title"
          className="flex items-center gap-2 px-3 pb-3 text-sm font-medium text-soleur-text-primary"
        >
          {SECTION_LABELS[drill]}
        </div>
      )}
    </div>
  );
}
