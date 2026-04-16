"use client";

import { useState, useRef, useCallback, useEffect, useLayoutEffect } from "react";
import type { AttachmentRef } from "@/lib/types";
import { validateFiles } from "@/lib/validate-files";
import { uploadWithProgress } from "@/lib/upload-with-progress";

interface PendingAttachment {
  id: string;
  file: File;
  preview?: string;
  progress: number;
  error?: string;
  uploaded?: AttachmentRef;
}

export interface ChatInputQuoteHandle {
  insertQuote: (text: string) => void;
}

interface ChatInputProps {
  onSend: (message: string, attachments?: AttachmentRef[]) => void;
  onAtTrigger: (query: string, cursorPosition: number) => void;
  onAtDismiss: () => void;
  disabled?: boolean;
  placeholder?: string;
  /** Conversation ID for presigning uploads. */
  conversationId?: string;
  /** Insert text at the current cursor position (used by AtMentionDropdown selection). */
  insertRef?: React.MutableRefObject<((text: string, replaceFrom: number) => void) | null>;
  /** Imperative handle exposing `insertQuote(text)` for the KB selection flow. */
  quoteRef?: React.MutableRefObject<ChatInputQuoteHandle | null>;
  /** When set, the draft text is persisted to sessionStorage under this key
   *  and rehydrated on mount. Used by the KB sidebar to preserve drafts
   *  per-document across navigation. */
  draftKey?: string;
  /** When true, Enter key defers to the @mention dropdown instead of sending. */
  atMentionVisible?: boolean;
}

export function ChatInput({
  onSend,
  onAtTrigger,
  onAtDismiss,
  disabled = false,
  placeholder = "Ask your team anything... or @mention a leader",
  conversationId,
  insertRef,
  quoteRef,
  draftKey,
  atMentionVisible = false,
}: ChatInputProps) {
  const [value, setValue] = useState<string>(() => {
    // Rehydrate from sessionStorage on mount when a draftKey is given.
    if (typeof window === "undefined" || !draftKey) return "";
    try {
      return window.sessionStorage.getItem(draftKey) ?? "";
    } catch {
      return "";
    }
  });
  const [attachments, setAttachments] = useState<PendingAttachment[]>([]);
  const [attachError, setAttachError] = useState<string | null>(null);
  const [isUploading, setIsUploading] = useState(false);
  const [isDragOver, setIsDragOver] = useState(false);
  const [flashQuote, setFlashQuote] = useState(false);

  // AC5 per-path drafts: when `draftKey` changes (e.g. KB doc A → doc B),
  // rehydrate the textarea with the new key's stored value. Skip on the
  // very first render because the initial useState reader already handled
  // it without triggering a re-render that could clobber a parent-supplied
  // `value` prop (we don't have one, but it keeps the effect idempotent).
  const prevDraftKeyRef = useRef<string | undefined>(draftKey);
  useEffect(() => {
    if (prevDraftKeyRef.current === draftKey) return;
    prevDraftKeyRef.current = draftKey;
    if (typeof window === "undefined") return;
    if (!draftKey) { setValue(""); return; }
    try {
      setValue(window.sessionStorage.getItem(draftKey) ?? "");
    } catch { /* noop */ }
  }, [draftKey]);

  // Persist current draft whenever value changes (and a draftKey is set).
  useEffect(() => {
    if (typeof window === "undefined" || !draftKey) return;
    try {
      if (value) {
        window.sessionStorage.setItem(draftKey, value);
      } else {
        window.sessionStorage.removeItem(draftKey);
      }
    } catch { /* noop */ }
  }, [draftKey, value]);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const activeXhrs = useRef<Map<string, XMLHttpRequest>>(new Map());

  // Auto-resize textarea height based on content (capped at ~5 lines / 100px).
  // useLayoutEffect prevents flicker; keying on `value` covers typing, paste,
  // programmatic changes (quote insertion, draft rehydration, @-mention).
  useLayoutEffect(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = "auto"; // Reset to measure true scrollHeight
    el.style.height = `${Math.min(el.scrollHeight, 100)}px`;
  }, [value]);

  // Clear error after 3 seconds
  useEffect(() => {
    if (!attachError) return;
    const timer = setTimeout(() => setAttachError(null), 3_000);
    return () => clearTimeout(timer);
  }, [attachError]);

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

        const newCursor = replaceFrom + text.length + 1;
        requestAnimationFrame(() => {
          textarea.selectionStart = newCursor;
          textarea.selectionEnd = newCursor;
          textarea.focus();
        });
      };
    }
  }, [insertRef, value]);

  // Expose `insertQuote` for the KB selection-toolbar flow (Phase 4.3).
  // Prepends "> <text>\n\n" when the draft is empty, or inserts the quoted
  // block at the current cursor position when there is existing draft text.
  // Does NOT auto-send; user edits and presses Enter.
  useEffect(() => {
    if (!quoteRef) return;
    quoteRef.current = {
      insertQuote: (text: string) => {
        const textarea = textareaRef.current;
        const quoted = `> ${text}\n\n`;
        setValue((prev) => {
          if (!prev) return quoted;
          const cursor = textarea ? textarea.selectionStart : prev.length;
          return prev.slice(0, cursor) + quoted + prev.slice(cursor);
        });
        setFlashQuote(true);
        if (textarea) {
          requestAnimationFrame(() => {
            textarea.focus();
            textarea.scrollIntoView({ block: "nearest" });
          });
        }
        setTimeout(() => setFlashQuote(false), 400);
      },
    };
  }, [quoteRef]);

  const validateAndAddFiles = useCallback(
    (files: FileList | File[]) => {
      const { valid, error } = validateFiles(files, attachments.length);

      if (error) setAttachError(error);
      if (valid.length > 0) {
        setAttachments((prev) => [
          ...prev,
          ...valid.map((file) => ({
            id: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
            file,
            preview: file.type.startsWith("image/") ? URL.createObjectURL(file) : undefined,
            progress: 0,
          })),
        ]);
      }
    },
    [attachments.length],
  );

  const removeAttachment = useCallback((id: string) => {
    const xhr = activeXhrs.current.get(id);
    if (xhr) xhr.abort();
    activeXhrs.current.delete(id);
    setAttachments((prev) => {
      const item = prev.find((a) => a.id === id);
      if (item?.preview) URL.revokeObjectURL(item.preview);
      return prev.filter((a) => a.id !== id);
    });
  }, []);

  const uploadAttachments = useCallback(async (): Promise<AttachmentRef[]> => {
    const promises = attachments.map(async (att): Promise<AttachmentRef | null> => {
      if (att.uploaded) return att.uploaded;

      try {
        // Step 1: Get presigned URL
        const presignRes = await fetch("/api/attachments/presign", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            filename: att.file.name,
            contentType: att.file.type,
            sizeBytes: att.file.size,
            conversationId,
          }),
        });

        if (!presignRes.ok) {
          const err = await presignRes.json().catch(() => ({}));
          throw new Error(err.error || "Presign failed");
        }

        const { uploadUrl, storagePath } = await presignRes.json();

        // Step 2: Upload to Storage with progress tracking
        const { promise, xhr } = uploadWithProgress(
          uploadUrl,
          att.file,
          att.file.type,
          (percent) => {
            setAttachments((prev) =>
              prev.map((a) => (a.id === att.id ? { ...a, progress: percent } : a)),
            );
          },
        );
        activeXhrs.current.set(att.id, xhr);
        await promise;
        activeXhrs.current.delete(att.id);

        const ref: AttachmentRef = {
          storagePath,
          filename: att.file.name,
          contentType: att.file.type,
          sizeBytes: att.file.size,
        };

        setAttachments((prev) =>
          prev.map((a) =>
            a.id === att.id ? { ...a, progress: 100, uploaded: ref } : a,
          ),
        );

        return ref;
      } catch (err) {
        setAttachments((prev) =>
          prev.map((a) =>
            a.id === att.id
              ? { ...a, error: err instanceof Error ? err.message : "Upload failed" }
              : a,
          ),
        );
        return null;
      }
    });

    const settled = await Promise.allSettled(promises);
    return settled
      .filter(
        (r): r is PromiseFulfilledResult<AttachmentRef> =>
          r.status === "fulfilled" && r.value !== null,
      )
      .map((r) => r.value);
  }, [attachments]);

  const handleSubmit = useCallback(async () => {
    const trimmed = value.trim();
    if (!trimmed && attachments.length === 0) return;

    let sent = false;
    if (attachments.length > 0) {
      setIsUploading(true);
      try {
        const uploaded = await uploadAttachments();
        if (uploaded.length > 0) {
          onSend(trimmed, uploaded);
          sent = true;
        } else if (trimmed) {
          onSend(trimmed);
          sent = true;
        }
      } finally {
        setIsUploading(false);
        setAttachments((prev) => prev.filter((a) => a.error));
      }
    } else {
      onSend(trimmed);
      sent = true;
    }

    if (sent) {
      setValue("");
      onAtDismiss();
    }
  }, [value, attachments, onSend, onAtDismiss, uploadAttachments]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
      if (e.key === "Enter" && !e.shiftKey) {
        if (atMentionVisible) return;
        e.preventDefault();
        handleSubmit();
      }
    },
    [handleSubmit, atMentionVisible],
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

  // Drag-and-drop handlers
  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(true);
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(false);
  }, []);

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault();
      setIsDragOver(false);
      if (e.dataTransfer.files.length > 0) {
        validateAndAddFiles(e.dataTransfer.files);
      }
    },
    [validateAndAddFiles],
  );

  // Clipboard paste handler
  const handlePaste = useCallback(
    (e: React.ClipboardEvent) => {
      const files = e.clipboardData.files;
      if (files.length > 0) {
        e.preventDefault();
        validateAndAddFiles(files);
      }
    },
    [validateAndAddFiles],
  );

  return (
    <div
      className="relative"
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      {/* Drag overlay */}
      {isDragOver && (
        <div className="absolute inset-0 z-10 flex items-center justify-center rounded-xl border-2 border-dashed border-amber-500 bg-amber-500/10">
          <span className="text-sm font-medium text-amber-400">Drop files here</span>
        </div>
      )}

      {/* Attachment preview strip */}
      {attachments.length > 0 && (
        <div className="mb-2 flex flex-wrap gap-2">
          {attachments.map((att) => (
            <div
              key={att.id}
              data-testid="attachment-preview"
              className="relative flex items-center gap-2 rounded-lg border border-neutral-700 bg-neutral-800 px-2 py-1.5"
            >
              {att.preview ? (
                <img
                  src={att.preview}
                  alt=""
                  className="h-8 w-8 rounded object-cover"
                />
              ) : (
                <div className="flex h-8 w-8 items-center justify-center rounded bg-neutral-700 text-xs text-neutral-400">
                  PDF
                </div>
              )}
              <div className="flex flex-col">
                <span className="max-w-[120px] truncate text-xs text-neutral-300">
                  {att.file.name}
                </span>
                {att.error ? (
                  <span className="text-xs text-red-400">{att.error}</span>
                ) : att.progress > 0 && att.progress < 100 ? (
                  <div className="mt-0.5 flex items-center gap-1.5">
                    <div className="h-1 w-16 overflow-hidden rounded-full bg-neutral-700">
                      <div
                        className="h-full bg-amber-500"
                        style={{
                          width: `${att.progress}%`,
                          transition: "width 150ms ease",
                        }}
                      />
                    </div>
                    <span className="text-[10px] tabular-nums text-neutral-400">
                      {att.progress}%
                    </span>
                  </div>
                ) : att.progress === 100 ? (
                  <span className="text-xs text-green-400">Uploaded</span>
                ) : null}
              </div>
              <button
                type="button"
                onClick={() => removeAttachment(att.id)}
                className="ml-1 rounded p-0.5 text-neutral-500 hover:text-neutral-300"
                aria-label={`Remove ${att.file.name}`}
              >
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <line x1="18" y1="6" x2="6" y2="18" />
                  <line x1="6" y1="6" x2="18" y2="18" />
                </svg>
              </button>
            </div>
          ))}
        </div>
      )}

      {/* Error toast */}
      {attachError && (
        <div className="mb-2 rounded-lg border border-red-800/50 bg-red-950/30 px-3 py-2 text-xs text-red-300">
          {attachError}
        </div>
      )}

      <div className="flex items-center gap-2">
        {/* Paperclip / attach button */}
        <button
          type="button"
          onClick={() => fileInputRef.current?.click()}
          disabled={disabled || isUploading}
          className="flex h-[44px] w-[44px] shrink-0 items-center justify-center rounded-xl border border-neutral-700 text-neutral-400 transition-colors hover:border-neutral-500 hover:text-white disabled:opacity-50"
          aria-label="Attach file"
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48" />
          </svg>
        </button>

        <input
          ref={fileInputRef}
          type="file"
          multiple
          accept="image/png,image/jpeg,image/gif,image/webp,application/pdf"
          className="hidden"
          onChange={(e) => {
            if (e.target.files) validateAndAddFiles(e.target.files);
            e.target.value = "";
          }}
        />

        <div className="relative flex-1">
          <textarea
            ref={textareaRef}
            value={value}
            onChange={handleChange}
            onKeyDown={handleKeyDown}
            onPaste={handlePaste}
            placeholder={placeholder}
            disabled={disabled || isUploading}
            rows={1}
            className={
              "w-full resize-none rounded-xl border border-neutral-700 bg-neutral-900 px-4 py-2.5 pr-12 text-sm text-white placeholder:text-neutral-500 focus:border-neutral-500 focus:outline-none disabled:opacity-50 min-h-[44px] max-h-[100px] overflow-y-auto transition-shadow" +
              (flashQuote ? " ring-2 ring-amber-400" : "")
            }
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
          disabled={disabled || isUploading || (!value.trim() && attachments.length === 0)}
          className="flex h-[44px] w-[44px] shrink-0 items-center justify-center rounded-xl bg-amber-600 text-white transition-colors hover:bg-amber-500 disabled:opacity-50 disabled:hover:bg-amber-600"
          aria-label="Send message"
        >
          {isUploading ? (
            <svg width="18" height="18" viewBox="0 0 24 24" className="animate-spin" fill="none" stroke="currentColor" strokeWidth="2">
              <circle cx="12" cy="12" r="10" strokeOpacity="0.25" />
              <path d="M12 2a10 10 0 0 1 10 10" strokeLinecap="round" />
            </svg>
          ) : (
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <line x1="12" y1="19" x2="12" y2="5" />
              <polyline points="5 12 12 5 19 12" />
            </svg>
          )}
        </button>
      </div>
    </div>
  );
}
