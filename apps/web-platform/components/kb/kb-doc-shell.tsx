"use client";

import type { ReactNode } from "react";
import { DesktopPlaceholder, KbErrorBoundary } from "@/components/kb";
import { RAIL_EXPAND_EVENT } from "@/components/dashboard/rail-slot";

interface KbDocShellProps {
  children: ReactNode;
  isContentView: boolean;
}

/**
 * KB document viewer shell — the scrollable content well that wraps either the
 * route's children or the desktop placeholder. Pure presentation; state lives
 * in `useKbLayoutState`. The file tree (and its collapse) now live in the
 * unified nav rail (ADR-047), so this shell carries no expand control.
 */
export function KbDocShell({ children, isContentView }: KbDocShellProps) {
  return (
    <div className="min-h-0 flex-1 overflow-y-auto">
      <KbErrorBoundary>
        {isContentView ? (
          children
        ) : (
          <>
            {/* Desktop: the tree is in the always-visible rail, so a passive
                placeholder suffices. Mobile: the tree lives in the hamburger
                drawer, so the content pane would be BLANK — show a visible
                empty state with a button that opens the drawer to the file
                tree (via RAIL_EXPAND_EVENT, handled in the dashboard layout). */}
            <DesktopPlaceholder />
            <div className="flex h-full flex-col items-center justify-center px-6 text-center md:hidden">
              <p className="text-sm text-soleur-text-secondary">
                Open a file to see it here
              </p>
              <p className="mt-1 text-xs text-soleur-text-muted">
                Browse the Knowledge Base directory to pick a file.
              </p>
              <button
                type="button"
                onClick={() =>
                  window.dispatchEvent(new CustomEvent(RAIL_EXPAND_EVENT))
                }
                className="mt-4 min-h-11 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-4 py-2 text-sm text-soleur-text-primary hover:bg-soleur-bg-surface-2"
              >
                Browse files
              </button>
            </div>
          </>
        )}
      </KbErrorBoundary>
    </div>
  );
}
