"use client";

import type { ReactNode } from "react";
import dynamic from "next/dynamic";
import { Group, Panel, Separator } from "react-resizable-panels";
import type { UseKbLayoutStateResult } from "@/hooks/use-kb-layout-state";
import { KbSidebarShell } from "@/components/kb/kb-sidebar-shell";
import { KbDocShell } from "@/components/kb/kb-doc-shell";

const KbChatContent = dynamic(
  () =>
    import("@/components/chat/kb-chat-content").then((m) => m.KbChatContent),
  { ssr: false, loading: () => null },
);

function ResizeHandle(props: { style?: React.CSSProperties }) {
  return (
    <Separator
      className="group relative w-1 bg-transparent transition-colors duration-150 hover:bg-soleur-text-secondary/50 active:bg-amber-500/50 data-[resize-handle-active]:bg-amber-500/50"
      style={props.style}
    >
      <div className="absolute inset-y-0 left-1/2 flex -translate-x-1/2 flex-col items-center justify-center gap-0.5">
        <span className="h-0.5 w-0.5 rounded-full bg-soleur-text-muted group-hover:bg-soleur-text-secondary" />
        <span className="h-0.5 w-0.5 rounded-full bg-soleur-text-muted group-hover:bg-soleur-text-secondary" />
        <span className="h-0.5 w-0.5 rounded-full bg-soleur-text-muted group-hover:bg-soleur-text-secondary" />
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
    chatPanelRef,
    showChat,
    contextPath,
    closeSidebar,
    kbCollapsed,
    isContentView,
    toggleKbCollapsed,
  } = state;

  return (
    <div className="flex h-full">
      {/* File-tree sidebar — animated width transition mirrors SettingsShell.
          Padding lives on the inner wrapper (NOT the aside) so md:w-0 +
          box-border collapses fully (#3585). Transition classes are
          unconditional so React keeps the animation across state changes
          (#3573). */}
      <aside
        inert={kbCollapsed || undefined}
        className={`hidden shrink-0 border-r border-soleur-border-default md:block md:overflow-hidden md:transition-[width] md:duration-200 md:ease-out ${
          kbCollapsed ? "md:w-0 md:border-r-0" : "md:w-72"
        }`}
      >
        <div className="w-72 h-full">
          <KbSidebarShell onCollapse={toggleKbCollapsed} />
        </div>
      </aside>

      {/* Doc viewer + (optional) chat — resizable against each other. */}
      <Group orientation="horizontal" className="h-full flex-1 min-w-0">
        <Panel minSize="40%">
          <div className="relative min-w-0 flex flex-1 flex-col h-full">
            <KbDocShell
              collapsed={kbCollapsed}
              isContentView={isContentView}
              onExpand={toggleKbCollapsed}
            >
              {children}
            </KbDocShell>
          </div>
        </Panel>

        {showChat && contextPath && (
          <>
            <ResizeHandle />
            <Panel
              panelRef={chatPanelRef}
              defaultSize="22%"
              minSize="20%"
              maxSize="40%"
            >
              <div className="min-w-0 h-full border-l border-soleur-border-default">
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
    </div>
  );
}
