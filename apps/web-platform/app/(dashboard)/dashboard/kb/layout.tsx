"use client";

import type { ReactNode } from "react";
import { usePathname } from "next/navigation";
import { isKbDocView } from "@/hooks/segment-to-drill-level";
import { KbContext } from "@/components/kb/kb-context";
import { KbChatContext } from "@/components/kb/kb-chat-context";
import { KbChatQuoteBridgeProvider } from "@/components/kb/kb-chat-quote-bridge";
import {
  EmptyState,
  LoadingSkeleton,
  NoProjectState,
  UnknownError,
  WorkspaceNotReady,
} from "@/components/kb";
import { useKbLayoutState } from "@/hooks/use-kb-layout-state";
import { KbDesktopLayout } from "@/components/kb/kb-desktop-layout";
import { KbMobileLayout } from "@/components/kb/kb-mobile-layout";
import { KbSidebarShell } from "@/components/kb/kb-sidebar-shell";
import { KbMobilePageHeader } from "@/components/kb/kb-mobile-page-header";
import { ReconnectNotice } from "@/components/repo/reconnect-notice";
import { RailSlotPortal } from "@/components/dashboard/rail-slot";

export default function KbLayout({ children }: { children: ReactNode }) {
  const state = useKbLayoutState();
  const {
    ctxValue,
    chatCtxValue,
    isDesktop,
    loading,
    error,
    hasTreeContent,
    openSidebar,
    fullWidth,
    treeHost,
  } = state;

  // #7186 correction: the previous comment here claimed the mobile band keeps
  // its back on the KB landing and that layout.tsx keys `suppressBack` on this
  // same predicate. Neither was ever true — the mobile band is `suppressBack`
  // unconditionally, and layout.tsx no longer imports isKbDocView at all. What
  // IS true: this fullWidth header renders its own back only on the doc route,
  // because on the landing the browse view (kb-mobile-layout.tsx) owns one.
  const pathname = usePathname();
  const showHeaderBack = isKbDocView(pathname);

  return (
    <KbContext value={ctxValue}>
      <KbChatContext value={chatCtxValue}>
        <KbChatQuoteBridgeProvider onOpenSidebar={openSidebar}>
          {/* ADR-047: the file tree is lifted into the single nav rail's
              secondary slot via a portal. It stays inside the KbContext
              provider here (React context follows the React tree through the
              portal) so FileTree's useKb() still resolves — ONE /api/kb/tree
              fetch shared with the doc viewer + chat panel. Collapse is owned
              by the unified rail, so no in-shell collapse button.

              #7186: on a mobile populated landing render the ONE shell moves to
              the content column instead (KbMobileLayout), so the portal renders
              nothing. This is safe to gate on a viewport-derived value because
              RailSlotPortal already returns null until its container ref
              callback fires — the portal side is never server-rendered, so no
              hydration mismatch is possible here (D1 reason 2). */}
          <RailSlotPortal>
            {treeHost === "rail" ? <KbSidebarShell host={treeHost} /> : null}
          </RailSlotPortal>

          {fullWidth ? (
            // Phase 4 (#4915): page-body chrome for the otherwise-chromeless
            // mobile fullWidth sub-states (loading / workspace-not-ready /
            // no-project / unknown-error / empty). ONE wrapper edit chromes all
            // of them — the identity band is NOT re-mounted here (it already
            // persists above the KB swap; ADR-047 render-outside-swap). The
            // header is mobile-only (md:hidden): desktop orientation comes from
            // the persistent rail band.
            <div className="flex h-full flex-col">
              <KbMobilePageHeader showBack={showHeaderBack} hideOnDesktop />
              <div className="flex min-h-0 flex-1 flex-col">
                {/* #4712 — surface the reconnect banner even on the empty/error
                    branch. Suppressed during loading to avoid flicker. */}
                {!loading && ctxValue.needsReconnect && (
                  <div className="shrink-0 p-4">
                    <ReconnectNotice
                      variant="banner"
                      onReconnected={ctxValue.refreshTree}
                    />
                  </div>
                )}
                {loading && <LoadingSkeleton />}
                {error === "workspace-not-ready" && <WorkspaceNotReady />}
                {error === "not-found" && <NoProjectState />}
                {error === "unknown" && <UnknownError />}
                {!loading && !error && !hasTreeContent && <EmptyState />}
              </div>
            </div>
          ) : isDesktop ? (
            <KbDesktopLayout state={state}>{children}</KbDesktopLayout>
          ) : (
            <KbMobileLayout state={state}>{children}</KbMobileLayout>
          )}
        </KbChatQuoteBridgeProvider>
      </KbChatContext>
    </KbContext>
  );
}
