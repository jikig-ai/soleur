"use client";

// feat-support-interface — scrollable conversation region. Empty state shows the
// persona greeting + preview note + 3 starter chips. Once a conversation starts,
// chips are gone and messages render (auto-scroll to latest; aria-live announces
// new replies).

import { useEffect, useRef } from "react";
import { SupportAvatar } from "./support-avatar";
import { SupportMessage } from "./support-message";
import {
  SUPPORT_GREETING,
  SUPPORT_PREVIEW_NOTE,
  SUPPORT_STARTER_CHIPS,
} from "./support-persona";
import type { SupportMessage as SupportMessageType } from "./use-support-chat";

export function SupportConversation({
  messages,
  onChipSelect,
}: {
  messages: SupportMessageType[];
  onChipSelect: (label: string, chipKey: string) => void;
}) {
  const bottomRef = useRef<HTMLDivElement>(null);
  const hasConversation = messages.length > 0;

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ block: "end" });
  }, [messages.length]);

  return (
    <div className="min-w-0 flex-1 overflow-y-auto px-4 py-4">
      {!hasConversation && (
        <div className="flex flex-col gap-4">
          <div className="flex items-start gap-2">
            <SupportAvatar size="md" />
            <p className="text-sm leading-relaxed text-soleur-text-primary">
              {SUPPORT_GREETING}
            </p>
          </div>
          <p className="rounded-lg border border-amber-700/40 bg-soleur-bg-accent-surface px-3 py-2 text-xs text-amber-500">
            {SUPPORT_PREVIEW_NOTE}
          </p>
          <div className="flex flex-col gap-2">
            {SUPPORT_STARTER_CHIPS.map((chip) => (
              <button
                key={chip.key}
                type="button"
                onClick={() => onChipSelect(chip.label, chip.key)}
                className="w-fit max-w-full rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-3 py-2 text-left text-sm text-soleur-text-secondary transition-colors hover:border-soleur-border-emphasized hover:text-soleur-text-primary"
              >
                {chip.label}
              </button>
            ))}
          </div>
        </div>
      )}
      {/* Live region is ALWAYS mounted (even while empty) so the FIRST reply is
          observed as a mutation and announced — a region that mounts already
          populated stays silent on its initial content. */}
      <div className="flex flex-col gap-4" aria-live="polite">
        {messages.map((message) => (
          <SupportMessage key={message.id} message={message} />
        ))}
        <div ref={bottomRef} />
      </div>
    </div>
  );
}
