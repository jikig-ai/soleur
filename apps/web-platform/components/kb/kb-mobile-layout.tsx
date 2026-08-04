"use client";

import type { ReactNode } from "react";
import dynamic from "next/dynamic";
import type { UseKbLayoutStateResult } from "@/hooks/use-kb-layout-state";
import { KbDocShell } from "@/components/kb/kb-doc-shell";
import { KbSidebarShell } from "@/components/kb/kb-sidebar-shell";
import { KbMobilePageHeader } from "@/components/kb/kb-mobile-page-header";
import { useKb } from "@/components/kb/kb-context";
import { ReconnectNotice } from "@/components/repo/reconnect-notice";

const KbChatSidebar = dynamic(
  () =>
    import("@/components/chat/kb-chat-sidebar").then((m) => m.KbChatSidebar),
  { ssr: false, loading: () => null },
);

interface KbMobileLayoutProps {
  children: ReactNode;
  state: UseKbLayoutStateResult;
}

export function KbMobileLayout({ children, state }: KbMobileLayoutProps) {
  const {
    isContentView,
    contextPath,
    chatCtxValue,
    closeSidebar,
    treeHost,
    showChat,
  } = state;
  const { needsReconnect, refreshTree } = useKb();

  // #7186 — list → detail drill-in. `treeHost` is the single authority (derived
  // in useKbLayoutState); it is "content" only on a populated mobile landing
  // render, and in that one cell the rail portal renders nothing, so exactly one
  // tree is mounted. Every other mobile cell (document route, and all the
  // fullWidth states, which never reach this component) keeps the ADR-047
  // behaviour: the tree stays portaled into the drawer and the doc fills the
  // content area.
  const browse = treeHost === "content";

  return (
    <div className="flex h-full flex-col">
      {needsReconnect && (
        <div className="shrink-0 p-4">
          <ReconnectNotice variant="banner" onReconnected={refreshTree} />
        </div>
      )}
      <div className="flex min-h-0 flex-1">
        <div className="flex min-w-0 flex-1 flex-col">
          {browse ? (
            <>
              {/* DC1, operator-approved 2026-08-03: the browse view owns its
                  own back. The persistent band's back is unconditionally
                  suppressed inside the mobile drawer, so without this the
                  mobile KB landing has no reachable in-page back at all. It
                  lives HERE — on the populated browse view only — never in the
                  shared fullWidth block, which must stay viewport-invariant. */}
              <KbMobilePageHeader showBack />
              <div className="min-h-0 flex-1">
                <KbSidebarShell host={treeHost} />
              </div>
            </>
          ) : (
            <KbDocShell isContentView={isContentView}>
              {children}
            </KbDocShell>
          )}
        </div>

        {/* #7222 — gate on `showChat`, matching kb-desktop-layout. The old
            `enabled && contextPath` predicate ignored BOTH `suppressSidebar` and
            `sidebarOpen`, so on a C4 document with a restored-open session this
            side panel and the workspace's embedded Concierge could mount two
            ChatSurfaces on the same contextPath — sharing one sessionStorage
            draft key, each overwriting the other's composer. */}
        {showChat && contextPath && (
          <KbChatSidebar
            open={chatCtxValue.open}
            onClose={closeSidebar}
            contextPath={contextPath}
          />
        )}
      </div>
    </div>
  );
}
