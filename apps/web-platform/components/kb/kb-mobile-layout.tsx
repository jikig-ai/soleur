"use client";

import type { ReactNode } from "react";
import dynamic from "next/dynamic";
import type { UseKbLayoutStateResult } from "@/hooks/use-kb-layout-state";
import { KbDocShell } from "@/components/kb/kb-doc-shell";
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
  } = state;
  const { needsReconnect, refreshTree } = useKb();

  // ADR-047: the file tree lives in the single nav rail's secondary slot
  // (the mobile drawer), portaled from kb/layout.tsx — it no longer competes
  // with the doc viewer for the content column. The doc always fills the
  // content area here.
  return (
    <div className="flex h-full flex-col">
      {needsReconnect && (
        <div className="shrink-0 p-4">
          <ReconnectNotice variant="banner" onReconnected={refreshTree} />
        </div>
      )}
      <div className="flex min-h-0 flex-1">
        <div className="flex min-w-0 flex-1 flex-col">
          <KbDocShell isContentView={isContentView}>
            {children}
          </KbDocShell>
        </div>

        {chatCtxValue.enabled && contextPath && (
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
