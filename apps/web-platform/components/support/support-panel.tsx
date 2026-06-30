"use client";

// feat-support-interface — right-side slide-over support panel. Dim backdrop,
// focus trap, Escape + backdrop-click close, focus returns to the launcher.
// Reduced-motion aware. Mobile: full-width bottom-anchored sheet.

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { SupportComposer } from "./support-composer";
import { SupportConversation } from "./support-conversation";
import { SUPPORT_NAME, SUPPORT_PANEL_SUBTITLE } from "./support-persona";
import type { SupportMessage } from "./use-support-chat";

export function SupportPanel({
  open,
  onClose,
  messages,
  onSend,
}: {
  open: boolean;
  onClose: () => void;
  messages: SupportMessage[];
  onSend: (text: string, chipKey?: string) => void;
}) {
  const panelRef = useRef<HTMLDivElement>(null);
  const onCloseRef = useRef(onClose);
  const router = useRouter();
  const [entered, setEntered] = useState(false);
  useEffect(() => {
    onCloseRef.current = onClose;
  });

  // Reply links render via MarkdownRenderer, which opens every anchor in a new
  // tab (correct for the main chat's external links). For an INTERNAL app path
  // (e.g. the knowledge-base link) that's wrong — intercept the click and do a
  // same-tab client-side navigation, closing the panel so the user lands on it.
  function handleReplyLinkClick(e: React.MouseEvent<HTMLDivElement>) {
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey) return;
    const anchor = (e.target as HTMLElement).closest("a");
    const href = anchor?.getAttribute("href");
    if (href && href.startsWith("/") && !href.startsWith("//")) {
      e.preventDefault();
      onClose();
      router.push(href);
    }
  }

  useEffect(() => {
    if (!open) {
      setEntered(false);
      return;
    }
    // Trigger the slide-in on the next frame so the transition runs.
    setEntered(true);

    // Move focus into the panel (composer is the first useful control).
    const trigger = document.activeElement as HTMLElement | null;
    const textarea = panelRef.current?.querySelector("textarea");
    textarea?.focus();

    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") {
        onCloseRef.current();
        return;
      }
      if (e.key === "Tab" && panelRef.current) {
        const focusable = panelRef.current.querySelectorAll<HTMLElement>(
          'button:not(:disabled), [href], input:not(:disabled), select:not(:disabled), textarea:not(:disabled), [tabindex]:not([tabindex="-1"])',
        );
        if (focusable.length === 0) return;
        const first = focusable[0];
        const last = focusable[focusable.length - 1];
        const active = document.activeElement;
        // If focus escaped the dialog (e.g. Send became disabled after submit, or
        // a starter chip unmounted), it lands on <body> — pull it back in so Tab
        // can't reach the dimmed app behind the panel.
        if (!active || active === document.body || !panelRef.current.contains(active)) {
          e.preventDefault();
          first?.focus();
        } else if (e.shiftKey && active === first) {
          e.preventDefault();
          last?.focus();
        } else if (!e.shiftKey && active === last) {
          e.preventDefault();
          first?.focus();
        }
      }
    }

    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      trigger?.focus();
    };
  }, [open]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-[60]">
      <div
        className="absolute inset-0 bg-black/60 transition-opacity motion-reduce:transition-none"
        onClick={onClose}
        role="presentation"
      />
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="support-panel-heading"
        tabIndex={-1}
        className={`absolute inset-x-0 bottom-0 flex h-[80vh] flex-col rounded-t-2xl border-t border-soleur-border-default bg-soleur-bg-base shadow-2xl transition-transform duration-200 motion-reduce:transition-none sm:inset-y-0 sm:right-0 sm:left-auto sm:h-full sm:w-[400px] sm:rounded-none sm:border-l sm:border-t-0 ${
          entered ? "translate-y-0 sm:translate-x-0" : "translate-y-full sm:translate-x-full sm:translate-y-0"
        }`}
      >
        <header className="flex shrink-0 items-center justify-between border-b border-soleur-border-default px-4 py-3">
          <div className="min-w-0">
            <h2
              id="support-panel-heading"
              className="text-sm font-semibold text-soleur-text-primary"
            >
              {SUPPORT_NAME}
            </h2>
            <p className="text-xs text-soleur-text-muted">
              {SUPPORT_PANEL_SUBTITLE}
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close support"
            className="flex h-8 w-8 items-center justify-center rounded-lg text-soleur-text-secondary transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              className="h-4 w-4"
              aria-hidden="true"
            >
              <line x1="18" y1="6" x2="6" y2="18" />
              <line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          </button>
        </header>

        {/* display:contents keeps the flex layout while letting the click
            handler intercept internal reply links (bubbles from descendants). */}
        <div style={{ display: "contents" }} onClick={handleReplyLinkClick}>
          <SupportConversation
            messages={messages}
            onChipSelect={(label, chipKey) => onSend(label, chipKey)}
          />
        </div>

        <SupportComposer onSend={(text) => onSend(text)} />
      </div>
    </div>
  );
}
