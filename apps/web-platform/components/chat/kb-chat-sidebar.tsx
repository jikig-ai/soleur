"use client";

import { useCallback, useEffect, useState } from "react";
import { Sheet } from "@/components/ui/sheet";
import { ChatSurface } from "@/components/chat/chat-surface";
import { useKbChat } from "@/components/kb/kb-chat-context";
import { track } from "@/lib/analytics-client";
import type { ConversationContext } from "@/lib/types";

export interface KbChatSidebarProps {
  open: boolean;
  onClose: () => void;
  contextPath: string;
}

export function KbChatSidebar({ open, onClose, contextPath }: KbChatSidebarProps) {
  const { setMessageCount } = useKbChat();
  const [resumedBanner, setResumedBanner] = useState<{ timestamp: string } | null>(null);
  const [openedEmitted, setOpenedEmitted] = useState<string | null>(null);

  // Reset banner + re-arm analytics when the document path changes.
  useEffect(() => {
    setResumedBanner(null);
    setOpenedEmitted(null);
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
    (count: number) => setMessageCount(count),
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
          />
        </div>
      </div>
    </Sheet>
  );
}
