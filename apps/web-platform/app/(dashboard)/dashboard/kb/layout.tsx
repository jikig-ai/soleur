"use client";

import type { ReactNode } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { isKbDocView } from "@/hooks/segment-to-drill-level";
import { BackArrowIcon } from "@/components/dashboard/nav-icons";
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

  // One back per state (#4915): the mobile page header shows its own "Back to
  // menu" ONLY in the KB doc view, where the persistent band's back is
  // suppressed (layout.tsx keys `suppressBack` on the SAME isKbDocView
  // predicate). On the KB landing (and its fullWidth sub-states) the band keeps
  // its back, so the page header renders the title only — no duplicate back.
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
              by the unified rail, so no in-shell collapse button. */}
          <RailSlotPortal>
            <KbSidebarShell />
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
              <header
                data-testid="kb-page-mobile-header"
                className="flex shrink-0 items-center gap-2 border-b border-soleur-border-default px-4 py-3 md:hidden"
              >
                {showHeaderBack && (
                  <Link
                    href="/dashboard"
                    aria-label="Back to menu"
                    className="flex items-center text-soleur-text-secondary hover:text-soleur-text-primary"
                  >
                    <BackArrowIcon className="h-5 w-5" />
                  </Link>
                )}
                {/* Mobile page title — the band's mobile section title is
                    suppressed for KB so this is the single "Knowledge Base"
                    title on mobile (P2-4). */}
                <h1 className="text-sm font-medium text-soleur-text-primary">
                  Knowledge Base
                </h1>
              </header>
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
