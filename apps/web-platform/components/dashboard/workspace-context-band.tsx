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
}: {
  pathname: string;
  /** "rail" mounts in the sidebar; "mobile" mounts in the mobile top bar. */
  variant?: "rail" | "mobile";
}) {
  const drill = segmentToDrillLevel(pathname);

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
