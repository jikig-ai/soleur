"use client";

import { useState, useRef, useCallback, useEffect, useLayoutEffect as reactUseLayoutEffect } from "react";

const useIsomorphicLayoutEffect =
  typeof window !== "undefined" ? reactUseLayoutEffect : useEffect;
import Link from "next/link";
import { SpinnerIcon } from "@/components/icons";
import type { AttachmentRef } from "@/lib/types";
import type { StreamState } from "@/lib/ws-client";
import { validateFiles } from "@/lib/validate-files";
import { uploadWithProgress } from "@/lib/upload-with-progress";
import { safeSession } from "@/lib/safe-session";
import { detectImagePlaceholders } from "@/lib/image-placeholder-detect";

interface PendingAttachment {
  id: string;
  file: File;
  preview?: string;
  progress: number;
  error?: string;
  uploaded?: AttachmentRef;
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
  /** Callback ref that invokes insertQuote for the KB selection-toolbar flow. */
  quoteRef?: React.MutableRefObject<((text: string) => void) | null>;
  /** Callback ref that focuses the textarea imperatively. */
  focusRef?: React.MutableRefObject<(() => void) | null>;
  /** When set, the draft text is persisted to sessionStorage under this key
   *  and rehydrated on mount. Used by the KB sidebar to preserve drafts
   *  per-document across navigation. */
  draftKey?: string;
  /** When true, Enter key defers to the @mention dropdown instead of sending. */
  atMentionVisible?: boolean;
  /** Stage 4 (#2886): when true, force-disable the input and show the
   *  workflow-ended placeholder. Set by `<ChatSurface>` from the
   *  `conversation.workflow_ended_at` column / lifecycle bar's "ended" state.
   *  Per `cq-jsdom-no-layout-gated-assertions`, the test hook is the
   *  textarea's `placeholder` attribute, which is structural. */
  workflowEnded?: boolean;
  /** #3448 PR2: per-turn stream lifecycle. When `"streaming"` or
   *  `"stopping"`, the Send button is replaced by a Stop button that
   *  invokes `onStop`. While `"stopping"`, the Stop button is disabled and
   *  labeled "Stopping…" until `session_ended` lands and the parent flips
   *  this back to `"idle"`. Defaults to `"idle"` for callers that do not
   *  yet thread the lifecycle (chat-input is reused outside the chat
   *  surface — e.g. the KB sidebar passes the value directly). */
  streamState?: StreamState;
  /** #3448 PR2: invoked when the user clicks Stop. Wired to
   *  `useWebSocket.abort()` by ChatSurface. */
  onStop?: () => void;
  /** #5394 Layer B: the active workspace's repo-setup state, mapped by
   *  `<ChatSurface>` from `useActiveRepo().data.repoStatus`. While `"cloning"`
   *  the composer is disabled and shows a "Setting up your repository…" state;
   *  on `"error"` it shows a reconnect CTA to Settings → Repository. `null`/
   *  undefined (ready / not-connected) is the normal composer. Server-side the
   *  dispatch is gated independently (Layer A); this is the UX so a founder
   *  never types into a composer whose turn will be blocked. */
  repoSetupState?: "cloning" | "error" | null;
}

export function ChatInput({
  onSend,
  onAtTrigger,
  onAtDismiss,
  disabled: rawDisabled = false,
  placeholder: rawPlaceholder = "Ask your team anything... or @mention a leader",
  conversationId,
  insertRef,
  quoteRef,
  focusRef,
  draftKey,
  atMentionVisible = false,
  workflowEnded = false,
  streamState = "idle",
  onStop,
  repoSetupState = null,
}: ChatInputProps) {
  // #3448 PR2 (review fix): exhaustive narrowing on the StreamState union
  // per AGENTS.md `cq-union-widening-grep-three-patterns`. A future widening
  // (e.g., adding `"queued"`) fails build here instead of silently flowing
  // into the Send branch.
  const buttonMode: "send" | "stop" | "stopping" = (() => {
    switch (streamState) {
      case "idle":
        return "send";
      case "streaming":
        return "stop";
      case "stopping":
        return "stopping";
      default: {
        const _exhaustive: never = streamState;
        void _exhaustive;
        return "send";
      }
    }
  })();
  const showStop = buttonMode !== "send";
  const isStopping = buttonMode === "stopping";
  // #5394 — repo-setup gates. Cloning AND error both disable the composer (the
  // server-side Layer A gate would block the turn anyway); error additionally
  // surfaces a reconnect CTA. Cloning swaps the placeholder to the setting-up
  // copy. These take precedence over the normal placeholder but not over the
  // workflow-ended terminal state.
  const repoCloning = repoSetupState === "cloning";
  const repoError = repoSetupState === "error";
  const disabled = rawDisabled || workflowEnded || repoCloning || repoError;
  const placeholder = workflowEnded
    ? "This conversation has ended"
    : repoCloning
      ? "Setting up your repository…"
      : rawPlaceholder;
  const [value, setValue] = useState<string>(() => {
    // Rehydrate from sessionStorage on mount when a draftKey is given.
    if (!draftKey) return "";
    return safeSession(draftKey) ?? "";
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
    if (!draftKey) { setValue(""); return; }
    setValue(safeSession(draftKey) ?? "");
  }, [draftKey]);

  // Persist current draft whenever value changes (9C: 250ms trailing
  // debounce so rapid typing coalesces into one sessionStorage write).
  // Pending write is held in a ref so (a) flush-on-unmount can complete
  // the final keystroke, (b) a draftKey change cancels + rehydrates.
  const pendingDraftRef = useRef<{ key: string; value: string } | null>(null);
  const persistTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (!draftKey) return;
    // Queue the next trailing write. Each rerender clears the prior timer
    // via cleanup; the pendingRef captures the latest (key, value) so the
    // unmount-flush effect can write it synchronously.
    pendingDraftRef.current = { key: draftKey, value };
    if (persistTimerRef.current !== null) {
      clearTimeout(persistTimerRef.current);
    }
    persistTimerRef.current = setTimeout(() => {
      const pending = pendingDraftRef.current;
      if (!pending) return;
      safeSession(pending.key, pending.value || null);
      pendingDraftRef.current = null;
      persistTimerRef.current = null;
    }, 250);
    return () => {
      if (persistTimerRef.current !== null) {
        clearTimeout(persistTimerRef.current);
        persistTimerRef.current = null;
      }
    };
  }, [draftKey, value]);

  // Flush the pending draft write on unmount so the final keystroke reaches
  // sessionStorage even if the component tears down inside the 250ms window
  // (see test/chat-input-draft-debounce.test.tsx "flushes pending write on
  // unmount"). Runs exactly once at unmount via the [] dep list + ref.
  useEffect(() => {
    return () => {
      const pending = pendingDraftRef.current;
      if (pending) {
        safeSession(pending.key, pending.value || null);
        pendingDraftRef.current = null;
      }
    };
  }, []);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const activeXhrs = useRef<Map<string, XMLHttpRequest>>(new Map());
  // Timer owned by the insertQuote callback. Tracked via ref so each
  // invocation can cancel the prior pending flash (no queue growth under
  // rapid selection-to-quote bursts) and the effect's cleanup can cancel
  // any pending callback on unmount (no unmounted-setState warnings).
  const flashTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Auto-resize textarea height based on content (default ~2 lines, capped at ~6 lines / 140px).
  // useIsomorphicLayoutEffect prevents flicker on the client while avoiding
  // SSR warnings; keying on `value` covers typing, paste, programmatic changes.
  useIsomorphicLayoutEffect(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = "auto"; // Reset to measure true scrollHeight
    el.style.height = `${Math.min(el.scrollHeight, 140)}px`;
  }, [value]);

  // Clear error after 3 seconds
  useEffect(() => {
    if (!attachError) return;
    const timer = setTimeout(() => setAttachError(null), 3_000);
    return () => clearTimeout(timer);
  }, [attachError]);

  // Expose insert function to parent for @-mention selection.
  // Functional setValue avoids a stale-closure dependency on `value`; the
  // effect depends only on [insertRef]. Cursor restoration is kept inside
  // the single retained requestAnimationFrame — it must run after React
  // commits the new value so selectionStart/End target the post-commit DOM.
  useEffect(() => {
    if (!insertRef) return;
    insertRef.current = (text: string, replaceFrom: number) => {
      const textarea = textareaRef.current;
      if (!textarea) return;

      const cursor = textarea.selectionStart;
      const newCursor = replaceFrom + text.length + 1;
      setValue((prev) => {
        const before = prev.slice(0, replaceFrom);
        const after = prev.slice(cursor);
        return before + text + " " + after;
      });

      requestAnimationFrame(() => {
        textarea.selectionStart = newCursor;
        textarea.selectionEnd = newCursor;
        textarea.focus();
      });
    };
    return () => {
      if (insertRef) insertRef.current = null;
    };
  }, [insertRef]);

  // Expose `insertQuote` for the KB selection-toolbar flow (Phase 4.3) as a
  // callback ref: `quoteRef.current?.(text)`. Prepends "> <text>\n\n" when
  // the draft is empty, or inserts the quoted block at the current cursor
  // position when there is existing draft text. Does NOT auto-send.
  useEffect(() => {
    if (!quoteRef) return;
    quoteRef.current = (text: string) => {
      const textarea = textareaRef.current;
      const quoted = `> ${text}\n\n`;
      setValue((prev) => {
        if (!prev) return quoted;
        const cursor = textarea ? textarea.selectionStart : prev.length;
        return prev.slice(0, cursor) + quoted + prev.slice(cursor);
      });
      setFlashQuote(true);
      if (textarea) {
        textarea.focus();
        textarea.scrollIntoView({ block: "nearest" });
      }
      if (flashTimerRef.current !== null) {
        clearTimeout(flashTimerRef.current);
      }
      flashTimerRef.current = setTimeout(() => {
        setFlashQuote(false);
        flashTimerRef.current = null;
      }, 400);
    };
    return () => {
      if (flashTimerRef.current !== null) {
        clearTimeout(flashTimerRef.current);
        flashTimerRef.current = null;
      }
      if (quoteRef) quoteRef.current = null;
    };
  }, [quoteRef]);

  // Separate callback ref for imperative focus() from portal-mounted parents.
  useEffect(() => {
    if (!focusRef) return;
    focusRef.current = () => {
      textareaRef.current?.focus();
    };
    return () => {
      if (focusRef) focusRef.current = null;
    };
  }, [focusRef]);

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
    const newCursor = cursor + 1;
    setValue((prev) => {
      const before = prev.slice(0, cursor);
      const after = prev.slice(cursor);
      return before + "@" + after;
    });
    // Focus restoration is safe to do synchronously here — the next render
    // commits the new value and the textarea stays mounted.
    textarea.selectionStart = newCursor;
    textarea.selectionEnd = newCursor;
    textarea.focus();

    onAtTrigger("", cursor);
  }, [onAtTrigger]);

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
        return;
      }

      // #3254 — guard against `[Image #N]` SDK-CLI placeholders flattened
      // to `text/plain`. The image bytes never reached the clipboard;
      // accepting the text would persist a known-broken artifact and
      // trigger a hallucinated agent response. Server-side strip is the
      // backstop; this is a friendlier UX layer.
      const text = e.clipboardData.getData("text/plain") ?? "";
      if (text.length > 0) {
        const { count } = detectImagePlaceholders(text);
        if (count > 0) {
          e.preventDefault();
          const noun = count === 1 ? "image placeholder" : "image placeholders";
          setAttachError(
            `Pasted text contained ${count} ${noun} — paste the image file directly.`,
          );
        }
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
              className="relative flex items-center gap-2 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2 px-2 py-1.5"
            >
              {att.preview ? (
                <img
                  src={att.preview}
                  alt=""
                  className="h-8 w-8 rounded object-cover"
                />
              ) : (
                <div className="flex h-8 w-8 items-center justify-center rounded bg-soleur-bg-surface-2 text-xs text-soleur-text-secondary">
                  PDF
                </div>
              )}
              <div className="flex flex-col">
                <span className="max-w-[120px] truncate text-xs text-soleur-text-secondary">
                  {att.file.name}
                </span>
                {att.error ? (
                  <span className="text-xs text-red-400">{att.error}</span>
                ) : att.progress > 0 && att.progress < 100 ? (
                  <div className="mt-0.5 flex items-center gap-1.5">
                    <div className="h-1 w-16 overflow-hidden rounded-full bg-soleur-bg-surface-2">
                      <div
                        className="h-full bg-amber-500"
                        style={{
                          width: `${att.progress}%`,
                          transition: "width 150ms ease",
                        }}
                      />
                    </div>
                    <span className="text-[10px] tabular-nums text-soleur-text-secondary">
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
                className="ml-1 rounded p-0.5 text-soleur-text-muted hover:text-soleur-text-secondary"
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

      {/* #5394 — repo cloning: slim inline "setting up" indicator (voice from
          the connect-repo SettingUpState). Static "less than a minute" copy
          satisfies the issue's "elapsed indicator" without a per-second timer. */}
      {repoCloning && (
        <div className="mb-2 flex items-center gap-2 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-2 text-xs text-soleur-text-secondary">
          <SpinnerIcon className="h-4 w-4 shrink-0 text-soleur-accent-gold-fg/70" />
          <span>
            Setting up your repository…{" "}
            <span className="text-soleur-text-muted">
              This usually takes less than a minute.
            </span>
          </span>
        </div>
      )}

      {/* #5394 — repo setup error: inline reconnect CTA (voice from the
          connect-repo FailedState) to Settings → Repository. */}
      {repoError && (
        <div className="mb-2 rounded-lg border border-red-800/50 bg-red-950/30 px-3 py-2 text-xs text-red-300">
          Your repository setup failed.{" "}
          <Link
            href="/dashboard/settings"
            className="font-medium text-red-200 underline hover:text-red-100"
          >
            Reconnect in Settings → Repository
          </Link>
        </div>
      )}

      {/* Unified input box: the attach + send controls live *inside* one
          bordered container alongside the borderless textarea (ChatGPT-style)
          rather than as separate boxes floating beside the field. `items-end`
          keeps the buttons pinned to the bottom edge as the textarea grows;
          the focus ring + quote-flash live on the container now that the
          textarea itself is transparent and borderless. */}
      <div
        className={
          "flex items-end gap-1.5 rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1 px-2 py-1.5 transition-shadow focus-within:border-soleur-text-secondary" +
          (flashQuote ? " ring-2 ring-amber-400" : "")
        }
      >
        {/* Paperclip / attach button */}
        <button
          type="button"
          onClick={() => fileInputRef.current?.click()}
          disabled={disabled || isUploading}
          className="flex h-[36px] w-[36px] min-h-11 min-w-11 shrink-0 items-center justify-center rounded-lg text-soleur-text-secondary transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary disabled:opacity-50 md:min-h-0 md:min-w-0"
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
            enterKeyHint="send"
            data-quote-flashing={flashQuote ? "true" : undefined}
            className="w-full resize-none border-none bg-transparent px-1 py-2 pr-11 text-base text-soleur-text-primary placeholder:text-soleur-text-muted focus:outline-none focus-visible:shadow-none disabled:opacity-50 min-h-[36px] max-h-[140px] overflow-y-auto md:pr-8 md:text-sm"
          />
          {/* Mobile @ button */}
          <button
            type="button"
            onClick={handleAtButtonClick}
            disabled={disabled}
            className="absolute bottom-1 right-0 flex min-h-11 min-w-11 items-center justify-center rounded-md text-soleur-text-muted transition-colors hover:text-soleur-text-secondary disabled:opacity-50 md:hidden"
            aria-label="Mention a leader"
          >
            <span className="text-sm font-medium">@</span>
          </button>
        </div>
        {showStop ? (
          // #3448 PR2: Stop button replaces Send while a turn is in flight
          // (`streaming`) and stays mounted but disabled while waiting for
          // the server's `session_ended` ack (`stopping`). The accessible
          // name + visible label both transition to "Stopping…" so the
          // user has a single source of truth on the Stop affordance.
          <button
            type="button"
            onClick={onStop}
            disabled={isStopping || onStop === undefined}
            className="flex h-[36px] min-h-11 min-w-11 shrink-0 items-center justify-center rounded-lg border border-amber-700/50 bg-soleur-bg-surface-2 px-3 text-soleur-text-primary transition-colors hover:border-amber-600 hover:bg-soleur-bg-surface-1 disabled:opacity-60 md:min-h-0 md:min-w-0"
            aria-label={isStopping ? "Stopping" : "Stop"}
            data-testid="chat-stop-button"
          >
            <span className="text-xs font-medium">
              {isStopping ? "Stopping…" : "Stop"}
            </span>
          </button>
        ) : (
          <button
            type="button"
            onClick={handleSubmit}
            disabled={disabled || isUploading || (!value.trim() && attachments.length === 0)}
            className="flex h-[36px] w-[36px] min-h-11 min-w-11 shrink-0 items-center justify-center rounded-lg bg-amber-600 text-soleur-text-on-accent transition-colors hover:bg-amber-500 disabled:opacity-50 disabled:hover:bg-amber-600 md:min-h-0 md:min-w-0"
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
        )}
      </div>
    </div>
  );
}
