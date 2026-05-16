"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { ChatSurface } from "@/components/chat/chat-surface";
import { useKbChat } from "@/components/kb/kb-chat-context";
import { useKbChatQuoteBridge } from "@/components/kb/kb-chat-quote-bridge";
import { track } from "@/lib/analytics-client";
import type { ConversationContext } from "@/lib/types";

export interface KbChatContentProps {
  contextPath: string;
  onClose: () => void;
  /** Whether the chat panel is visible. Controls focus and quote-handler registration. */
  visible: boolean;
}

export function KbChatContent({ contextPath, onClose, visible }: KbChatContentProps) {
  const { setMessageCount } = useKbChat();
  const { registerQuoteHandler } = useKbChatQuoteBridge();
  const [resumedBanner, setResumedBanner] = useState<{ timestamp: string } | null>(null);
  // Tracks which contextPaths have already emitted kb.chat.opened in THIS
  // mount session. Ref (not state) so two handlers firing in the same React
  // batch see each other's write synchronously — prevents #2385 double fire.
  // NOTE: monotonically accumulates for the component's lifetime — bounded
  // in practice by distinct KB docs visited in a single session. A user who
  // navigates hundreds of docs in one session would grow the Set; cleared
  // on unmount (useRef reset).
  const openedPathsRef = useRef<Set<string>>(new Set());
  // Signals that drive the consolidated emit effect. Both handlers set
  // these scalar flags; a single effect keyed on (contextPath, hasReal,
  // hasResumed) performs the guarded `track` call exactly once per path.
  const [hasRealConversation, setHasRealConversation] = useState(false);
  const [hasResumed, setHasResumed] = useState(false);
  const historicalCountRef = useRef<number>(0);
  const quoteRef = useRef<((text: string) => void) | null>(null);
  const focusRef = useRef<(() => void) | null>(null);

  // Register an insertQuote handler with KbChatContext while visible.
  useEffect(() => {
    if (!visible) return;
    registerQuoteHandler((text: string) => {
      quoteRef.current?.(text);
    });
    return () => registerQuoteHandler(null);
  }, [visible, registerQuoteHandler]);

  // Focus management: when visible, move focus to the ChatInput textarea.
  // Use the imperative handle instead of a DOM query so focus is scoped to
  // this component's own input even when another [data-kb-chat] scope
  // exists in the document (e.g., a leftover from a prior mount). The rAF
  // defers focus until after the Sheet portal mounts on mobile — removing
  // it would focus a node that has not yet attached to document.
  useEffect(() => {
    if (!visible) return;
    const id = requestAnimationFrame(() => {
      focusRef.current?.();
    });
    return () => cancelAnimationFrame(id);
  }, [visible]);

  const handleBeforeSend = useCallback(
    (message: string) => {
      if (/^\s*>/.test(message)) {
        // `source: "human"` since this fires from the KbChatContent surface
        // (humans clicking the quote pill or typing a blockquote in the
        // sidebar). Agent-seeded quotes will emit `source: "agent"` when
        // the HTTP message-post path lands — tagging now prevents
        // retroactive metric-drift (no server-side record of per-event
        // source exists).
        void track("kb.chat.selection_sent", {
          path: contextPath,
          source: "human",
        });
      }
    },
    [contextPath],
  );

  // Reset banner + re-arm analytics when the document path changes.
  // Skip the initial mount: on mount the state is already null and the
  // child ChatSurface effect fires first to set resumedBanner via
  // onThreadResumed — resetting here would overwrite it.
  const prevContextPathRef = useRef(contextPath);
  useEffect(() => {
    if (prevContextPathRef.current === contextPath) return;
    prevContextPathRef.current = contextPath;
    setResumedBanner(null);
    setHasRealConversation(false);
    setHasResumed(false);
    historicalCountRef.current = 0;
  }, [contextPath]);

  // Consolidated emit: fires kb.chat.opened at most once per (mount-session,
  // contextPath) as soon as EITHER signal arrives, and pairs it with
  // kb.chat.thread_resumed when the opening was a resume. Using a ref Set
  // means two handlers invoked in the same batch both observe the same
  // guard — the legacy useState-based guard read stale null on the second
  // handler and double-fired (#2385).
  useEffect(() => {
    if (!hasRealConversation && !hasResumed) return;
    if (openedPathsRef.current.has(contextPath)) return;
    openedPathsRef.current.add(contextPath);
    void track("kb.chat.opened", { path: contextPath });
    if (hasResumed) void track("kb.chat.thread_resumed", { path: contextPath });
  }, [contextPath, hasRealConversation, hasResumed]);

  const filename = contextPath.split("/").pop() ?? contextPath;

  const initialContext: ConversationContext = useMemo(() => ({
    path: contextPath,
    type: "kb-viewer" as const,
  }), [contextPath]);

  const handleThreadResumed = useCallback(
    (_conversationId: string, timestamp: string, messageCount: number) => {
      setResumedBanner({ timestamp });
      historicalCountRef.current = messageCount;
      setMessageCount(messageCount);
      setHasResumed(true);
    },
    [setMessageCount],
  );

  const handleRealConversationId = useCallback((_conversationId: string) => {
    setHasRealConversation(true);
  }, []);

  const handleMessageCountChange = useCallback(
    (count: number) => {
      // Invariant owned by this consumer: once handleThreadResumed has set
      // historicalCountRef to N>0 (server confirmed a resumed thread of N
      // messages), messageCount must never regress below that floor for the
      // life of this mount. The KB sidebar has no "clear thread" code path
      // today — messages only grow via filter_prepend or stream events — so
      // a `count === 0` write after a confirmed resume is necessarily
      // transient (race with hydration). If a future feature adds an
      // explicit clear, replace this guard with a `resumed`-flag check.
      if (count === 0 && historicalCountRef.current > 0) return;
      setMessageCount(count);
      if (count > historicalCountRef.current) {
        setResumedBanner(null);
      }
    },
    [setMessageCount],
  );

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col" data-kb-chat>
      <header className="flex shrink-0 items-center justify-between border-b border-soleur-border-default px-3 py-2">
        <div className="min-w-0 flex-1 truncate">
          <span
            className="truncate font-mono text-xs text-soleur-text-secondary"
            title={filename}
          >
            {filename}
          </span>
        </div>
        <button
          type="button"
          aria-label="Close panel"
          onClick={onClose}
          className="ml-2 shrink-0 rounded p-1 text-soleur-text-secondary hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <line x1="18" y1="6" x2="6" y2="18" />
            <line x1="6" y1="6" x2="18" y2="18" />
          </svg>
        </button>
      </header>
      {resumedBanner && (
        <div className="shrink-0 border-b border-soleur-border-default bg-soleur-bg-surface-1/60 px-3 py-1.5 text-xs text-soleur-text-secondary">
          Continuing from {new Date(resumedBanner.timestamp).toLocaleString(undefined, { dateStyle: "short", timeStyle: "short" })}
        </div>
      )}
      <div className="flex min-h-0 min-w-0 flex-1 flex-col">
        <ChatSurface
          conversationId="new"
          variant="sidebar"
          initialContext={initialContext}
          onClose={onClose}
          sidebarProps={{
            resumeByContextPath: contextPath,
            onThreadResumed: handleThreadResumed,
            onRealConversationId: handleRealConversationId,
            onMessageCountChange: handleMessageCountChange,
            quoteRef,
            focusRef,
            onBeforeSend: handleBeforeSend,
            placeholder: "Ask about this document — ⌘⇧L to quote selection",
            draftKey: `kb.chat.draft:${contextPath}`,
          }}
        />
      </div>
    </div>
  );
}
