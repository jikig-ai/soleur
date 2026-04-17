"use client";

import { createContext, useCallback, useContext, useMemo, useRef, type ReactNode } from "react";

/**
 * Imperative quote-bridge between the KB selection-toolbar (caller of
 * `submitQuote`) and the active KB chat sidebar (caller of
 * `registerQuoteHandler`). Split out of `KbChatContext` (#2388 task 8B) so
 * quote-handler swaps don't re-render consumers that only care about sidebar
 * lifecycle state (open/close, contextPath, messageCount).
 */
export interface KbChatQuoteBridgeValue {
  /** Insert quoted text into the active sidebar's chat input and open if closed. */
  submitQuote: (text: string) => void;
  /** Register an insertQuote handler from the active sidebar. Pass null to clear. */
  registerQuoteHandler: (handler: ((text: string) => void) | null) => void;
}

/**
 * Exported to allow tests to inject a value directly (e.g. a spy on
 * `registerQuoteHandler`). Production code should wrap children in
 * `<KbChatQuoteBridgeProvider>` and consume via `useKbChatQuoteBridge()`.
 */
export const KbChatQuoteBridgeContext = createContext<KbChatQuoteBridgeValue | null>(null);

export function useKbChatQuoteBridge(): KbChatQuoteBridgeValue {
  const ctx = useContext(KbChatQuoteBridgeContext);
  if (!ctx) {
    throw new Error("useKbChatQuoteBridge must be used within KbChatQuoteBridgeProvider");
  }
  return ctx;
}

export interface KbChatQuoteBridgeProviderProps {
  /**
   * Called when a quote is submitted. The provider will invoke the currently
   * registered handler after opening the sidebar (if a caller supplies
   * `onOpenSidebar`, it fires before the handler dispatch).
   */
  onOpenSidebar: () => void;
  children: ReactNode;
}

/**
 * Provider that owns the registered quote handler via a ref (avoids
 * re-renders on register/unregister) and exposes a stable `submitQuote`
 * callback.
 */
export function KbChatQuoteBridgeProvider({
  onOpenSidebar,
  children,
}: KbChatQuoteBridgeProviderProps) {
  const quoteHandlerRef = useRef<((text: string) => void) | null>(null);

  const registerQuoteHandler = useCallback(
    (handler: ((text: string) => void) | null) => {
      quoteHandlerRef.current = handler;
    },
    [],
  );

  const submitQuote = useCallback(
    (text: string) => {
      onOpenSidebar();
      // Give the sidebar a tick to mount + register its handler before inserting.
      queueMicrotask(() => {
        quoteHandlerRef.current?.(text);
      });
    },
    [onOpenSidebar],
  );

  const value = useMemo<KbChatQuoteBridgeValue>(
    () => ({ submitQuote, registerQuoteHandler }),
    [submitQuote, registerQuoteHandler],
  );

  return (
    <KbChatQuoteBridgeContext value={value}>
      {children}
    </KbChatQuoteBridgeContext>
  );
}
