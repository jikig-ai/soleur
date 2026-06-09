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
  /**
   * When true, the desktop side chat panel is suppressed (NOT the header
   * trigger). Set by surfaces that embed their own Concierge (e.g. the C4
   * workspace renders the Concierge beside the diagram), so the document chat
   * isn't double-mounted with the same contextPath. Optional for backward-compat
   * with test mocks.
   */
  suppressSidebar?: boolean;
  setSuppressSidebar?: (v: boolean) => void;
  /**
   * Reveal/collapse state for an EMBEDDED Concierge (the C4 workspace's
   * diagram-side panel). DISTINCT from `open` (the desktop side panel) so the
   * header `KbChatTrigger` can drive the C4 embedded panel without re-mounting
   * a second side-panel Concierge — the suppressSidebar mount stays unmounted.
   * Defaults model "open" so the C4 Concierge shows by default (parity with the
   * pre-lift local `conciergeCollapsed = false` initial state). Optional for
   * backward-compat with test mocks.
   */
  embeddedConciergeOpen?: boolean;
  revealEmbeddedConcierge?: () => void;
  collapseEmbeddedConcierge?: () => void;
}

export const KbChatContext = createContext<KbChatContextValue | null>(null);

export function useKbChat(): KbChatContextValue {
  const ctx = useContext(KbChatContext);
  if (!ctx) throw new Error("useKbChat must be used within KbLayout");
  return ctx;
}
