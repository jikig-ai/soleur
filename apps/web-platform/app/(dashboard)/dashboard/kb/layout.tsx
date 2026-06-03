"use client";

import type { ReactNode } from "react";
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
  } = state;

  const fullWidth = loading || error || (!loading && !hasTreeContent);

  return (
    <KbContext value={ctxValue}>
      <KbChatContext value={chatCtxValue}>
        <KbChatQuoteBridgeProvider onOpenSidebar={openSidebar}>
          {/* ADR-047: the file tree is lifted into the single nav rail's
              secondary slot via a portal. It stays inside the KbContext
              provider here (React context follows the React tree through the
              portal) so FileTree's useKb() still resolves — ONE /api/kb/tree
              fetch shared with the doc viewer + chat panel. Collapse is owned
              by the unified rail, so no in-shell collapse button. */}
          <RailSlotPortal>
            <KbSidebarShell />
          </RailSlotPortal>

          {fullWidth ? (
            <>
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
            </>
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
