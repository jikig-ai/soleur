"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { ChatSurface } from "@/components/chat/chat-surface";
import type { ChatInputQuoteHandle } from "@/components/chat/chat-input";
import { useKbChat } from "@/components/kb/kb-chat-context";
import { track } from "@/lib/analytics-client";
import type { ConversationContext } from "@/lib/types";

const SIDEBAR_PLACEHOLDER =
  "Ask about this document — ⌘⇧L to quote selection";

export interface KbChatContentProps {
  contextPath: string;
  onClose: () => void;
  /** Whether the chat panel is visible. Controls focus and quote-handler registration. */
  visible: boolean;
}

export function KbChatContent({ contextPath, onClose, visible }: KbChatContentProps) {
  const { setMessageCount, registerQuoteHandler } = useKbChat();
  const [resumedBanner, setResumedBanner] = useState<{ timestamp: string } | null>(null);
  const [openedEmitted, setOpenedEmitted] = useState<string | null>(null);
  const historicalCountRef = useRef<number>(0);
  const quoteRef = useRef<ChatInputQuoteHandle | null>(null);

  // Register an insertQuote handler with KbChatContext while visible.
  useEffect(() => {
    if (!visible) return;
    registerQuoteHandler((text: string) => {
      quoteRef.current?.insertQuote(text);
    });
    return () => registerQuoteHandler(null);
  }, [visible, registerQuoteHandler]);

  // Focus management: when visible, move focus to the ChatInput textarea.
  useEffect(() => {
    if (!visible) return;
    const id = requestAnimationFrame(() => {
      const textarea = document.querySelector<HTMLTextAreaElement>(
        "[data-kb-chat] textarea",
      );
      textarea?.focus();
    });
    return () => cancelAnimationFrame(id);
  }, [visible]);

  const handleBeforeSend = useCallback(
    (message: string) => {
      if (/^\s*>/.test(message)) {
        void track("kb.chat.selection_sent", { path: contextPath });
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
    setOpenedEmitted(null);
    historicalCountRef.current = 0;
  }, [contextPath]);

  const filename = contextPath.split("/").pop() ?? contextPath;

  const initialContext: ConversationContext = {
    path: contextPath,
    type: "kb-viewer",
  };

  const handleThreadResumed = useCallback(
    (_conversationId: string, timestamp: string, messageCount: number) => {
      setResumedBanner({ timestamp });
      historicalCountRef.current = messageCount;
      setMessageCount(messageCount);
      if (openedEmitted !== contextPath) {
        void track("kb.chat.opened", { path: contextPath });
        void track("kb.chat.thread_resumed", { path: contextPath });
        setOpenedEmitted(contextPath);
      }
    },
    [contextPath, openedEmitted, setMessageCount],
  );

  const handleRealConversationId = useCallback(
    (_conversationId: string) => {
      if (openedEmitted !== contextPath && !resumedBanner) {
        void track("kb.chat.opened", { path: contextPath });
        setOpenedEmitted(contextPath);
      }
    },
    [contextPath, openedEmitted, resumedBanner],
  );

  const handleMessageCountChange = useCallback(
    (count: number) => {
      setMessageCount(count);
      if (count > historicalCountRef.current) {
        setResumedBanner(null);
      }
    },
    [setMessageCount],
  );

  return (
    <div className="flex min-h-0 min-w-0 flex-1 flex-col" data-kb-chat>
      <header className="flex shrink-0 items-center justify-between border-b border-neutral-800 px-3 py-2">
        <div className="min-w-0 flex-1 truncate">
          <span
            className="truncate font-mono text-xs text-neutral-300"
            title={filename}
          >
            {filename}
          </span>
        </div>
        <button
          type="button"
          aria-label="Close panel"
          onClick={onClose}
          className="ml-2 shrink-0 rounded p-1 text-neutral-400 hover:bg-neutral-800 hover:text-white"
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <line x1="18" y1="6" x2="6" y2="18" />
            <line x1="6" y1="6" x2="18" y2="18" />
          </svg>
        </button>
      </header>
      {resumedBanner && (
        <div className="shrink-0 border-b border-neutral-800 bg-neutral-900/60 px-3 py-1.5 text-xs text-neutral-400">
          Continuing from {new Date(resumedBanner.timestamp).toLocaleString(undefined, { dateStyle: "short", timeStyle: "short" })}
        </div>
      )}
      <div className="flex min-h-0 min-w-0 flex-1 flex-col">
        <ChatSurface
          conversationId="new"
          variant="sidebar"
          initialContext={initialContext}
          resumeByContextPath={contextPath}
          onThreadResumed={handleThreadResumed}
          onRealConversationId={handleRealConversationId}
          onMessageCountChange={handleMessageCountChange}
          onClose={onClose}
          quoteRef={quoteRef}
          onBeforeSend={handleBeforeSend}
          placeholder={SIDEBAR_PLACEHOLDER}
          draftKey={`kb.chat.draft:${contextPath}`}
        />
      </div>
    </div>
  );
}
