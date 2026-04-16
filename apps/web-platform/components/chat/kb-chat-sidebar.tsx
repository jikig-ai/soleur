"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Sheet } from "@/components/ui/sheet";
import { ChatSurface } from "@/components/chat/chat-surface";
import type { ChatInputQuoteHandle } from "@/components/chat/chat-input";
import { useKbChat } from "@/components/kb/kb-chat-context";
import { track } from "@/lib/analytics-client";
import type { ConversationContext } from "@/lib/types";

const SIDEBAR_PLACEHOLDER =
  "Ask about this document — ⌘⇧L to quote selection";

export interface KbChatSidebarProps {
  open: boolean;
  onClose: () => void;
  contextPath: string;
}

export function KbChatSidebar({ open, onClose, contextPath }: KbChatSidebarProps) {
  const { setMessageCount, registerQuoteHandler } = useKbChat();
  const [resumedBanner, setResumedBanner] = useState<{ timestamp: string } | null>(null);
  const [openedEmitted, setOpenedEmitted] = useState<string | null>(null);
  const historicalCountRef = useRef<number>(0);
  const quoteRef = useRef<ChatInputQuoteHandle | null>(null);

  // Register an insertQuote handler with KbChatContext while mounted.
  useEffect(() => {
    if (!open) return;
    registerQuoteHandler((text: string) => {
      quoteRef.current?.insertQuote(text);
    });
    return () => registerQuoteHandler(null);
  }, [open, registerQuoteHandler]);

  // Focus management (TR9 / AC9): when the sidebar opens, move focus to
  // the ChatInput textarea so keyboard users land in the compose surface
  // without an extra Tab. We query the panel because ChatInput owns the
  // textarea ref internally.
  useEffect(() => {
    if (!open) return;
    const id = requestAnimationFrame(() => {
      const textarea = document.querySelector<HTMLTextAreaElement>(
        "[role=\"dialog\"] textarea",
      );
      textarea?.focus();
    });
    return () => cancelAnimationFrame(id);
  }, [open]);

  const handleBeforeSend = useCallback(
    (message: string) => {
      // "kb.chat.selection_sent" fires when the user sends a message whose
      // content starts with a markdown blockquote — i.e. a quote from the
      // selection-toolbar flow. Domain leakage kept out of ChatInput.
      if (/^\s*>/.test(message)) {
        void track("kb.chat.selection_sent", { path: contextPath });
      }
    },
    [contextPath],
  );

  // Reset banner + re-arm analytics when the document path changes.
  useEffect(() => {
    setResumedBanner(null);
    setOpenedEmitted(null);
    historicalCountRef.current = 0;
  }, [contextPath]);

  // Derive a file name from the context path for the header display.
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
      // AC2+AC7: auto-dismiss the "Continuing from …" banner once the user
      // sends a NEW message — i.e. count exceeds the historical message count.
      // History loading (count going from 0 → historicalCount) must NOT dismiss
      // the banner; only fresh user activity beyond the historical count does.
      if (count > historicalCountRef.current) {
        setResumedBanner(null);
      }
    },
    [setMessageCount],
  );

  const ariaLabel = `Conversation about ${filename}`;

  return (
    <Sheet open={open} onClose={onClose} aria-label={ariaLabel}>
      <div className="flex min-h-0 min-w-0 flex-1 flex-col">
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
            Continuing from {new Date(resumedBanner.timestamp).toLocaleDateString()}
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
    </Sheet>
  );
}
