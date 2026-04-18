"use client";

import type { ReactNode } from "react";
import dynamic from "next/dynamic";
import { Group, Panel, Separator } from "react-resizable-panels";
import type { UseKbLayoutStateResult } from "@/hooks/use-kb-layout-state";

const KbChatContent = dynamic(
  () =>
    import("@/components/chat/kb-chat-content").then((m) => m.KbChatContent),
  { ssr: false, loading: () => null },
);

function ResizeHandle(props: { style?: React.CSSProperties }) {
  return (
    <Separator
      className="group relative w-1 bg-transparent transition-colors duration-150 hover:bg-neutral-400/50 active:bg-amber-500/50 data-[resize-handle-active]:bg-amber-500/50"
      style={props.style}
    >
      <div className="absolute inset-y-0 left-1/2 flex -translate-x-1/2 flex-col items-center justify-center gap-0.5">
        <span className="h-0.5 w-0.5 rounded-full bg-neutral-600 group-hover:bg-neutral-400" />
        <span className="h-0.5 w-0.5 rounded-full bg-neutral-600 group-hover:bg-neutral-400" />
        <span className="h-0.5 w-0.5 rounded-full bg-neutral-600 group-hover:bg-neutral-400" />
      </div>
    </Separator>
  );
}

interface KbDesktopLayoutProps {
  children: ReactNode;
  state: UseKbLayoutStateResult;
}

export function KbDesktopLayout({ children, state }: KbDesktopLayoutProps) {
  const {
    sidebarPanelRef,
    chatPanelRef,
    showChat,
    contextPath,
    closeSidebar,
    setKbCollapsed,
    sidebarContent,
    docContent,
  } = state;

  return (
    <Group orientation="horizontal" className="h-full">
      {/* Sidebar panel */}
      <Panel
        panelRef={sidebarPanelRef}
        defaultSize={showChat ? "18%" : "22%"}
        minSize="10%"
        maxSize="30%"
        collapsible
        collapsedSize="0%"
        onResize={(size) => {
          setKbCollapsed(size.asPercentage < 1);
        }}
      >
        <div className="min-w-0 h-full overflow-y-auto border-r border-neutral-800">
          {sidebarContent}
        </div>
      </Panel>

      <ResizeHandle />

      {/* Document viewer panel — fills remaining space */}
      <Panel minSize="40%">
        <div className="relative min-w-0 flex flex-1 flex-col h-full">
          {docContent(children)}
        </div>
      </Panel>

      {/* Chat panel — only rendered when active, with its preceding Separator */}
      {showChat && contextPath && (
        <>
          <ResizeHandle />
          <Panel
            panelRef={chatPanelRef}
            defaultSize="22%"
            minSize="20%"
            maxSize="40%"
          >
            <div className="min-w-0 h-full border-l border-neutral-800">
              <KbChatContent
                contextPath={contextPath}
                onClose={closeSidebar}
                visible={true}
              />
            </div>
          </Panel>
        </>
      )}
    </Group>
  );
}
