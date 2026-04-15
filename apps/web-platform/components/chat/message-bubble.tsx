"use client";

import React, { memo } from "react";
import { MarkdownRenderer } from "@/components/ui/markdown-renderer";
import { DOMAIN_LEADERS } from "@/server/domain-leaders";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { LEADER_COLORS } from "@/components/chat/leader-colors";
import { LeaderAvatar } from "@/components/leader-avatar";
import { AttachmentDisplay } from "@/components/chat/attachment-display";
import type { AttachmentRef, MessageState } from "@/lib/types";

export function ThinkingDots() {
  return (
    <div className="flex items-center gap-1.5 py-1" data-testid="thinking-dots">
      <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-neutral-400" style={{ animationDelay: "0ms" }} />
      <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-neutral-400" style={{ animationDelay: "150ms" }} />
      <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-neutral-400" style={{ animationDelay: "300ms" }} />
    </div>
  );
}

export function ToolStatusChip({ label }: { label: string }) {
  return (
    <div className="flex items-center gap-2 py-0.5">
      <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-amber-500" />
      <span className="text-sm text-neutral-400">{label}</span>
    </div>
  );
}

// Wrapped in React.memo so token streaming (10-50 Hz) doesn't re-render every
// bubble in a long thread. `getDisplayName`/`getIconPath` are already
// `useCallback`-stable in `use-team-names.tsx`; other props are primitives or
// references that only change for the active bubble. See #2137.
export const MessageBubble = memo(function MessageBubble({
  role,
  content,
  leaderId,
  showFullTitle = false,
  messageState,
  toolLabel,
  toolsUsed,
  getDisplayName,
  getIconPath,
  attachments,
}: {
  role: "user" | "assistant";
  content: string;
  leaderId?: DomainLeaderId;
  showFullTitle?: boolean;
  messageState?: MessageState;
  toolLabel?: string;
  toolsUsed?: string[];
  getDisplayName?: (id: DomainLeaderId) => string;
  getIconPath?: (id: DomainLeaderId) => string | null;
  attachments?: AttachmentRef[];
}) {
  const isUser = role === "user";
  const leader = leaderId ? DOMAIN_LEADERS.find((l) => l.id === leaderId) : null;
  const colorClass = leaderId ? (LEADER_COLORS[leaderId] ?? "border-l-neutral-500") : "";
  const displayName = leaderId && getDisplayName ? getDisplayName(leaderId) : leader?.name;
  const customIconPath = leaderId && getIconPath ? getIconPath(leaderId) : null;

  const isActive = messageState === "thinking" || messageState === "tool_use" || messageState === "streaming";
  const isError = messageState === "error";
  const isDone = messageState === "done";

  const borderStyle = isError
    ? "border-2 border-red-900/60"
    : isActive
      ? "message-bubble-active border-2 border-amber-600/70"
      : isDone
        ? "border border-neutral-800/60"
        : "border border-neutral-800";

  return (
    <div className={`flex ${isUser ? "justify-end" : "justify-start"}`}>
      <div className={`flex min-w-0 max-w-[90%] gap-3 md:max-w-[80%] ${isUser ? "flex-row-reverse" : ""}`}>
        {leader && (
          <LeaderAvatar leaderId={leaderId!} size="md" className="mt-1" customIconPath={customIconPath} />
        )}

        <div
          className={`relative min-w-0 rounded-xl px-4 py-3 text-sm leading-relaxed ${
            isUser
              ? "bg-neutral-800 text-neutral-100"
              : `bg-neutral-900 text-neutral-200 ${borderStyle} ${leader && !isActive && !isError ? `border-l-2 ${colorClass}` : ""}`
          }`}
        >
          {(messageState === "tool_use" || messageState === "streaming") && (
            <span className="absolute -top-2.5 right-3 rounded-full border border-amber-700/50 bg-neutral-900 px-2 py-0.5 text-[10px] font-medium text-amber-500">
              {messageState === "tool_use" ? "Working" : "Streaming"}
            </span>
          )}

          {isDone && role === "assistant" && (
            <span
              className="absolute -top-2.5 right-3 flex h-5 w-5 items-center justify-center rounded-full bg-neutral-900 text-amber-600"
              aria-label="Response complete"
            >
              <svg width="12" height="12" viewBox="0 0 12 12" fill="none" aria-hidden="true">
                <path d="M2 6.5L4.5 9L10 3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </span>
          )}

          {leader && (
            <div className="mb-1 flex items-center gap-2">
              <span className="text-xs font-semibold text-neutral-300">
                {displayName}
              </span>
              {showFullTitle && (
                <span className="text-xs text-neutral-500">{leader.title}</span>
              )}
            </div>
          )}

          {renderBubbleContent({ isUser, messageState, content, toolLabel, toolsUsed, isDone })}

          {attachments && attachments.length > 0 && (
            <AttachmentDisplay attachments={attachments} />
          )}
        </div>
      </div>
    </div>
  );
});

/** Render the inner content of a MessageBubble based on its state. Extracted
 *  to collapse the previous 7-branch ternary chain into a readable switch.
 *  User bubbles render through MarkdownRenderer so sent blockquotes render
 *  as blockquotes (not raw `>` text) — spec TR for kb-chat-sidebar. See #2139.
 */
function renderBubbleContent({
  isUser,
  messageState,
  content,
  toolLabel,
  toolsUsed,
  isDone,
}: {
  isUser: boolean;
  messageState: MessageState | undefined;
  content: string;
  toolLabel: string | undefined;
  toolsUsed: string[] | undefined;
  isDone: boolean;
}): React.ReactNode {
  if (isUser) {
    return (
      <div className="min-w-0 [overflow-wrap:anywhere]">
        <MarkdownRenderer content={content} />
      </div>
    );
  }
  switch (messageState) {
    case "thinking":
      return <ThinkingDots />;
    case "tool_use":
      return toolLabel ? <ToolStatusChip label={toolLabel} /> : <ThinkingDots />;
    case "streaming":
      return (
        <p className="whitespace-pre-wrap [overflow-wrap:anywhere]">
          {content}
          <span className="animate-pulse text-amber-500">&#x258C;</span>
        </p>
      );
    case "error":
      return (
        <div className="flex items-center gap-2 text-red-400">
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true">
            <circle cx="7" cy="7" r="6" stroke="currentColor" strokeWidth="1.2" />
            <path d="M7 4v3.5M7 9.5v.01" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" />
          </svg>
          <span className="text-sm">Agent stopped responding</span>
        </div>
      );
    case "done":
      if (content === "" && toolsUsed && toolsUsed.length > 0) {
        return (
          <div className="flex items-center gap-1.5 text-xs text-neutral-500">
            <span>Used:</span>
            {toolsUsed.map((t, i) => (
              <span key={i} className="rounded bg-neutral-800 px-1.5 py-0.5">
                {t}
              </span>
            ))}
          </div>
        );
      }
      return <MarkdownRenderer content={content} />;
    default:
      void isDone;
      return <MarkdownRenderer content={content} />;
  }
}
