"use client";

import type { ReactNode } from "react";
import { DesktopPlaceholder, KbErrorBoundary } from "@/components/kb";

interface KbDocShellProps {
  children: ReactNode;
  collapsed: boolean;
  isContentView: boolean;
  onExpand: () => void;
}

/**
 * KB document viewer shell — optional "expand file tree" button when the
 * sidebar is collapsed, plus the scrollable content well that wraps either
 * the route's children or the desktop placeholder. Pure presentation; state
 * lives in `useKbLayoutState`.
 */
export function KbDocShell({
  children,
  collapsed,
  isContentView,
  onExpand,
}: KbDocShellProps) {
  return (
    <>
      {collapsed && (
        <button
          onClick={onExpand}
          aria-label="Expand file tree"
          title="Expand file tree (⌘B)"
          className="absolute left-2 top-5 z-10 flex h-6 w-6 items-center justify-center rounded text-soleur-text-secondary hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
        >
          <svg
            className="h-4 w-4"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            strokeWidth={1.5}
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              d="m8.25 4.5 7.5 7.5-7.5 7.5"
            />
          </svg>
        </button>
      )}
      <div
        className={`min-h-0 flex-1 overflow-y-auto ${collapsed ? "pl-10" : ""}`}
      >
        <KbErrorBoundary>
          {isContentView ? children : <DesktopPlaceholder />}
        </KbErrorBoundary>
      </div>
    </>
  );
}
