"use client";

import { useState, useRef, useCallback, useEffect } from "react";

interface ChatInputProps {
  onSend: (message: string) => void;
  onAtTrigger: (query: string, cursorPosition: number) => void;
  onAtDismiss: () => void;
  disabled?: boolean;
  placeholder?: string;
  /** Insert text at the current cursor position (used by AtMentionDropdown selection). */
  insertRef?: React.MutableRefObject<((text: string, replaceFrom: number) => void) | null>;
}

export function ChatInput({
  onSend,
  onAtTrigger,
  onAtDismiss,
  disabled = false,
  placeholder = "Ask your team anything... or @mention a leader",
  insertRef,
}: ChatInputProps) {
  const [value, setValue] = useState("");
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Expose insert function to parent for @-mention selection
  useEffect(() => {
    if (insertRef) {
      insertRef.current = (text: string, replaceFrom: number) => {
        const textarea = textareaRef.current;
        if (!textarea) return;

        const cursor = textarea.selectionStart;
        const before = value.slice(0, replaceFrom);
        const after = value.slice(cursor);
        const newValue = before + text + " " + after;
        setValue(newValue);

        // Set cursor after inserted text + space
        const newCursor = replaceFrom + text.length + 1;
        requestAnimationFrame(() => {
          textarea.selectionStart = newCursor;
          textarea.selectionEnd = newCursor;
          textarea.focus();
        });
      };
    }
  }, [insertRef, value]);

  const handleSubmit = useCallback(() => {
    const trimmed = value.trim();
    if (!trimmed) return;
    onSend(trimmed);
    setValue("");
    onAtDismiss();
  }, [value, onSend, onAtDismiss]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        handleSubmit();
      }
    },
    [handleSubmit],
  );

  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLTextAreaElement>) => {
      const newValue = e.target.value;
      setValue(newValue);

      const textarea = e.target;
      const cursor = textarea.selectionStart;

      // Find the most recent @ before the cursor that isn't preceded by a word character
      const textBeforeCursor = newValue.slice(0, cursor);
      const atMatch = textBeforeCursor.match(/(?:^|[^@\w])@(\w*)$/);

      if (atMatch) {
        const query = atMatch[1];
        const atPosition = textBeforeCursor.lastIndexOf("@" + query);
        onAtTrigger(query, atPosition);
      } else {
        onAtDismiss();
      }
    },
    [onAtTrigger, onAtDismiss],
  );

  const handleAtButtonClick = useCallback(() => {
    const textarea = textareaRef.current;
    if (!textarea) return;

    const cursor = textarea.selectionStart;
    const before = value.slice(0, cursor);
    const after = value.slice(cursor);
    const newValue = before + "@" + after;
    setValue(newValue);

    const newCursor = cursor + 1;
    requestAnimationFrame(() => {
      textarea.selectionStart = newCursor;
      textarea.selectionEnd = newCursor;
      textarea.focus();
    });

    onAtTrigger("", cursor);
  }, [value, onAtTrigger]);

  return (
    <div className="flex items-end gap-2">
      <div className="relative flex-1">
        <textarea
          ref={textareaRef}
          value={value}
          onChange={handleChange}
          onKeyDown={handleKeyDown}
          placeholder={placeholder}
          disabled={disabled}
          rows={1}
          className="w-full resize-none rounded-xl border border-neutral-700 bg-neutral-900 px-4 py-3 pr-12 text-sm text-white placeholder:text-neutral-500 focus:border-neutral-500 focus:outline-none disabled:opacity-50"
        />
        {/* Mobile @ button */}
        <button
          type="button"
          onClick={handleAtButtonClick}
          disabled={disabled}
          className="absolute bottom-2.5 right-2 rounded-md p-1 text-neutral-500 transition-colors hover:text-neutral-300 disabled:opacity-50 md:hidden"
          aria-label="Mention a leader"
        >
          <span className="text-sm font-medium">@</span>
        </button>
      </div>
      <button
        type="button"
        onClick={handleSubmit}
        disabled={disabled || !value.trim()}
        className="flex h-[44px] w-[44px] shrink-0 items-center justify-center rounded-xl bg-amber-600 text-white transition-colors hover:bg-amber-500 disabled:opacity-50 disabled:hover:bg-amber-600"
        aria-label="Send message"
      >
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <line x1="12" y1="19" x2="12" y2="5" />
          <polyline points="5 12 12 5 19 12" />
        </svg>
      </button>
    </div>
  );
}
