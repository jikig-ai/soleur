"use client";

// feat-support-interface — a single message row. User bubble (surface-2, right)
// vs support bubble (surface-1, left, with avatar + name + PREVIEW badge).
// Mirrors components/chat/message-bubble.tsx token usage.

import { MarkdownRenderer } from "@/components/ui/markdown-renderer";
import { SupportAvatar } from "./support-avatar";
import { SUPPORT_NAME } from "./support-persona";
import type { SupportMessage as SupportMessageType } from "./use-support-chat";

export function SupportMessage({ message }: { message: SupportMessageType }) {
  const isUser = message.role === "user";

  if (isUser) {
    return (
      <div className="flex justify-end">
        <div className="w-fit max-w-[85%] rounded-xl bg-soleur-bg-surface-2 px-4 py-3 text-sm leading-relaxed text-soleur-text-primary">
          {message.text}
        </div>
      </div>
    );
  }

  return (
    <div className="flex items-start gap-2">
      <SupportAvatar size="sm" />
      <div className="min-w-0 flex-1">
        <div className="mb-1 flex items-center gap-2">
          <span className="text-xs font-medium text-soleur-text-secondary">
            {SUPPORT_NAME}
          </span>
          <span className="rounded-full border border-amber-700/50 px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide text-amber-500">
            Preview
          </span>
        </div>
        <div className="w-fit max-w-[85%] rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1 px-4 py-3 text-sm leading-relaxed text-soleur-text-primary">
          <MarkdownRenderer content={message.text} />
        </div>
      </div>
    </div>
  );
}
