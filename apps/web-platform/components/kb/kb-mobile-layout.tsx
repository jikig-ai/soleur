"use client";

import type { ReactNode } from "react";
import dynamic from "next/dynamic";
import type { UseKbLayoutStateResult } from "@/hooks/use-kb-layout-state";

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
    sidebarContent,
    docContent,
  } = state;

  return (
    <div className="flex h-full">
      <aside
        inert={kbCollapsed || undefined}
        className={`w-full shrink-0 overflow-y-auto border-r border-neutral-800
          ${isContentView ? "hidden" : "block"}`}
      >
        {sidebarContent}
      </aside>

      <div
        className={`min-w-0 flex-1 ${
          isContentView ? "" : "hidden"
        } flex flex-col`}
      >
        {docContent(children)}
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
