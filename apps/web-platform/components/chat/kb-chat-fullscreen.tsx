"use client";

import { useEffect, type ReactNode } from "react";
import { ResponsiveModal } from "@/components/ui/responsive-modal";

// #7222 — the mobile KB chat takeover.
//
// ONE chrome shared by the two surfaces that can host a document-scoped
// conversation on a phone: the markdown viewer's side panel
// (`kb-chat-sidebar.tsx`) and the C4 workspace's embedded Concierge
// (`c4-workspace.tsx`). Both used to render as a split/partial surface that left
// the conversation and its subject fighting over ~390px. Sharing the chrome is
// what keeps the two from drifting into two different "full screen"s.
//
// Design decisions this encodes (wireframe:
// knowledge-base/product/design/kb-mobile-chat/kb-mobile-fullscreen-chat.pen,
// screenshots/05-decisions-and-deltas.png is the authoritative list):
//
//  * It COVERS the 56px mobile top bar rather than sitting below it. The nav
//    drawer is also `z-50`, so leaving the hamburger tappable would let the
//    drawer slide over an open conversation with no defined winner — and a
//    visible top bar implies the document is still reachable when it is not.
//  * The close affordance is a 44x44 chevron-left labelled "Back to document",
//    pinned left in the overlay's own 56px header. Escape also dismisses (the
//    ResponsiveModal shell owns that), and focus returns to the trigger.
//  * The header carries an "ASKING ABOUT <filename>" context block. That block
//    is not decoration: it is what replaces the ambient context the user lost
//    when the document stopped being visible.

/**
 * Broadcast when the takeover opens, so `(dashboard)/layout.tsx` can close the
 * nav drawer. Belt AND braces: the overlay already wins on paint order (it
 * portals to <body> after the drawer), but making the two `z-50` surfaces
 * mutually exclusive by STATE means the invariant survives a future DOM-order
 * change that no test would otherwise catch.
 */
export const CHAT_OVERLAY_OPEN_EVENT = "soleur:chat-overlay-open";

export interface KbChatFullScreenProps {
  open: boolean;
  onClose: () => void;
  /** KB-relative path — its basename is the header's context line. */
  contextPath: string;
  children: ReactNode;
}

export function KbChatFullScreen({
  open,
  onClose,
  contextPath,
  children,
}: KbChatFullScreenProps) {
  const filename = contextPath.split("/").pop() ?? contextPath;

  useEffect(() => {
    if (!open) return;
    window.dispatchEvent(new Event(CHAT_OVERLAY_OPEN_EVENT));
  }, [open]);

  return (
    <ResponsiveModal
      open={open}
      onClose={onClose}
      mobileFullScreen
      // A takeover has no backdrop to click — the panel IS the viewport — so the
      // header chevron and Escape are the whole dismiss surface. Disabling this
      // stops a stray tap that lands on the 1px gutter from dropping a composer
      // draft.
      closeOnBackdrop={false}
      aria-label={`Conversation about ${filename}`}
    >
      <header
        data-testid="kb-chat-fullscreen-header"
        className="flex min-h-14 shrink-0 items-center gap-2 border-b border-soleur-border-default px-2"
      >
        <button
          type="button"
          onClick={onClose}
          aria-label="Back to document"
          data-testid="kb-chat-fullscreen-back"
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-lg text-soleur-accent-gold-fg transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
        >
          <svg
            width="20"
            height="20"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden="true"
          >
            <polyline points="15 18 9 12 15 6" />
          </svg>
        </button>
        <div className="min-w-0 flex-1">
          <div className="text-[10px] font-semibold uppercase tracking-wider text-soleur-text-muted">
            Asking about
          </div>
          <div className="truncate text-sm text-soleur-text-primary">
            {filename}
          </div>
        </div>
      </header>
      <div className="flex min-h-0 min-w-0 flex-1 flex-col">{children}</div>
    </ResponsiveModal>
  );
}
