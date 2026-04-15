"use client";

import { createContext, useContext } from "react";

export interface KbChatContextValue {
  open: boolean;
  openSidebar: () => void;
  closeSidebar: () => void;
  /** Current KB document path the sidebar is scoped to (null if not in a file view). */
  contextPath: string | null;
  /** True when feature flag NEXT_PUBLIC_KB_CHAT_SIDEBAR is enabled. */
  enabled: boolean;
  /** Insert quoted text into the sidebar's chat input and open if closed. */
  submitQuote: (text: string) => void;
  /** Register an insertQuote handler from the active sidebar (for selection-toolbar). */
  registerQuoteHandler: (handler: ((text: string) => void) | null) => void;
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
