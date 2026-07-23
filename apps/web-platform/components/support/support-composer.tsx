"use client";

// feat-support-interface — message composer. Textarea + gold send button.
// Enter sends, Shift+Enter newline. Disabled+no-op on empty/whitespace.
// Auto-grows up to a max height (then scrolls); soft character cap.

import { useId, useState } from "react";
import { GOLD_GRADIENT } from "@/components/ui/constants";
import {
  SUPPORT_COMPOSER_FOOTNOTE,
  SUPPORT_COMPOSER_FOOTNOTE_LIVE,
} from "./support-persona";

const MAX_CHARS = 2000;

export function SupportComposer({
  onSend,
  live = false,
}: {
  onSend: (text: string) => void;
  live?: boolean;
}) {
  const [value, setValue] = useState("");
  const textareaId = useId();
  const canSend = value.trim().length > 0;

  function submit() {
    if (!canSend) return;
    onSend(value);
    setValue("");
  }

  function handleKeyDown(e: React.KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      submit();
    }
  }

  return (
    <div className="shrink-0 border-t border-soleur-border-default bg-soleur-bg-base p-3">
      <div className="flex items-end gap-2">
        <label htmlFor={textareaId} className="sr-only">
          Message Soleur Support
        </label>
        <textarea
          id={textareaId}
          value={value}
          onChange={(e) => setValue(e.target.value.slice(0, MAX_CHARS))}
          onKeyDown={handleKeyDown}
          rows={1}
          placeholder="Ask a question…"
          enterKeyHint="send"
          className="max-h-32 min-h-[2.5rem] flex-1 resize-none overflow-y-auto rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-3 py-2 text-base text-soleur-text-primary placeholder:text-soleur-text-muted focus:border-soleur-border-emphasized focus:outline-none md:text-sm"
        />
        <button
          type="button"
          onClick={submit}
          disabled={!canSend}
          aria-label="Send message"
          className="rounded-lg px-4 py-2 text-sm font-medium text-black transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50"
          style={{ background: GOLD_GRADIENT }}
        >
          Send
        </button>
      </div>
      <p className="mt-1.5 text-[11px] text-soleur-text-muted">
        {live ? SUPPORT_COMPOSER_FOOTNOTE_LIVE : SUPPORT_COMPOSER_FOOTNOTE}
      </p>
    </div>
  );
}
