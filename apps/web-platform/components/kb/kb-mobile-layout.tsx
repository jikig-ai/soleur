"use client";

import type { ReactNode } from "react";
import dynamic from "next/dynamic";
import type { UseKbLayoutStateResult } from "@/hooks/use-kb-layout-state";
import { KbSidebarShell } from "@/components/kb/kb-sidebar-shell";
import { KbDocShell } from "@/components/kb/kb-doc-shell";

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
    kbCollapsed,
    isContentView,
    contextPath,
    chatCtxValue,
    closeSidebar,
    toggleKbCollapsed,
  } = state;

  return (
    <div className="flex h-full">
      <aside
        inert={kbCollapsed || undefined}
        className={`w-full shrink-0 overflow-y-auto border-r border-neutral-800
          ${isContentView ? "hidden" : "block"}`}
      >
        <KbSidebarShell onCollapse={toggleKbCollapsed} />
      </aside>

      <div
        className={`min-w-0 flex-1 ${
          isContentView ? "" : "hidden"
        } flex flex-col`}
      >
        <KbDocShell
          collapsed={kbCollapsed}
          isContentView={isContentView}
          onExpand={toggleKbCollapsed}
        >
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
  );
}
