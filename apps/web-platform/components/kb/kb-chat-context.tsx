"use client";

import { createContext, useContext } from "react";

/**
 * Sidebar-lifecycle state for the KB chat panel. The imperative quote
 * bridge (submitQuote / registerQuoteHandler) lives in a separate context
 * — see `kb-chat-quote-bridge.tsx` — so quote-handler swaps don't re-render
 * consumers that only read open/closed state.
 */
export interface KbChatContextValue {
  open: boolean;
  openSidebar: () => void;
  closeSidebar: () => void;
  /** Current KB document path the sidebar is scoped to (null if not in a file view). */
  contextPath: string | null;
  /** True when feature flag FLAG_KB_CHAT_SIDEBAR is enabled (runtime, fetched from /api/flags). */
  enabled: boolean;
  /** Thread state for stateful trigger labels ("Ask" vs "Continue thread"). */
  messageCount: number;
  setMessageCount: (n: number) => void;
}

export const KbChatContext = createContext<KbChatContextValue | null>(null);

export function useKbChat(): KbChatContextValue {
  const ctx = useContext(KbChatContext);
  if (!ctx) throw new Error("useKbChat must be used within KbLayout");
  return ctx;
}
