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

  // Full-width states: loading, errors, or empty KB (no sidebar needed)
  if (loading || error || (!loading && !hasTreeContent)) {
    return (
      <KbContext value={ctxValue}>
        <KbChatContext value={chatCtxValue}>
          <KbChatQuoteBridgeProvider onOpenSidebar={openSidebar}>
            {loading && <LoadingSkeleton />}
            {error === "workspace-not-ready" && <WorkspaceNotReady />}
            {error === "not-found" && <NoProjectState />}
            {error === "unknown" && <UnknownError />}
            {!loading && !error && !hasTreeContent && <EmptyState />}
          </KbChatQuoteBridgeProvider>
        </KbChatContext>
      </KbContext>
    );
  }

  return (
    <KbContext value={ctxValue}>
      <KbChatContext value={chatCtxValue}>
        <KbChatQuoteBridgeProvider onOpenSidebar={openSidebar}>
          {isDesktop ? (
            <KbDesktopLayout state={state}>{children}</KbDesktopLayout>
          ) : (
            <KbMobileLayout state={state}>{children}</KbMobileLayout>
          )}
        </KbChatQuoteBridgeProvider>
      </KbChatContext>
    </KbContext>
  );
}
