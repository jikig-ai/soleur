"use client";

import type { ReactNode } from "react";
import { DesktopPlaceholder, KbErrorBoundary } from "@/components/kb";

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
        {isContentView ? children : <DesktopPlaceholder />}
      </KbErrorBoundary>
    </div>
  );
}
