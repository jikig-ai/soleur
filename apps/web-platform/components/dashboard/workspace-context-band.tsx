"use client";

import Link from "next/link";
import { OrgSwitcherContainer } from "@/components/dashboard/org-switcher-container";
import { LiveRepoBadge } from "@/components/dashboard/live-repo-badge";
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

function BackChevronIcon({ className }: { className?: string }) {
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
        d="M15.75 19.5 8.25 12l7.5-7.5"
      />
    </svg>
  );
}

export function WorkspaceContextBand({
  pathname,
  variant = "rail",
  collapsed = false,
}: {
  pathname: string;
  /** "rail" mounts in the sidebar; "mobile" mounts in the mobile top bar. */
  variant?: "rail" | "mobile";
  /** Rail-only: when the sidebar is collapsed (md:w-14) render the icon-only
   *  form. Ignored for variant="mobile" (the mobile top bar never collapses). */
  collapsed?: boolean;
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
        className="flex flex-col items-center gap-3 border-b border-soleur-border-default px-2 py-3"
      >
        {drill ? (
          <Link
            href="/dashboard"
            aria-label="Back to menu"
            data-testid="nav-back-chevron"
            className="flex h-7 w-7 shrink-0 items-center justify-center rounded text-soleur-accent-gold-fg hover:bg-soleur-bg-surface-2"
          >
            <BackChevronIcon className="h-4 w-4" />
          </Link>
        ) : null}
        <span
          data-testid="workspace-identity-icon"
          aria-label="Active workspace"
          title="Active workspace"
          className="h-6 w-6 shrink-0 rounded-sm bg-soleur-accent-gold-fg/60"
        />
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
      <div className="flex items-center gap-2 px-3 pt-3">
        {/* Back chevron — synchronous (first render, never async-gated) and
            shown only when drilled. When not drilled an invisible placeholder
            of the same size reserves the slot so the identity row does not
            shift between top-level and drilled states (AC3). */}
        {drill ? (
          <Link
            href="/dashboard"
            aria-label="Back to menu"
            data-testid="nav-back-chevron"
            className="flex h-7 w-7 shrink-0 items-center justify-center rounded text-soleur-accent-gold-fg hover:bg-soleur-bg-surface-2"
          >
            <BackChevronIcon className="h-4 w-4" />
          </Link>
        ) : (
          <span aria-hidden="true" className="invisible h-7 w-7 shrink-0">
            <BackChevronIcon className="h-4 w-4" />
          </span>
        )}
        <div className="min-w-0 flex-1">
          <OrgSwitcherContainer />
        </div>
      </div>

      <div className="px-3 pb-2 pt-1">
        <LiveRepoBadge />
      </div>

      {drill && (
        <div
          data-testid="nav-section-title"
          className="flex items-center gap-2 border-b border-soleur-border-default px-3 pb-3 text-sm font-medium text-soleur-text-primary"
        >
          {SECTION_LABELS[drill]}
        </div>
      )}
    </div>
  );
}
