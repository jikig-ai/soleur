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
//  * The close affordance is pinned top-left in the overlay's own header.
//    Escape also dismisses (the ResponsiveModal shell owns that), and focus
//    returns to the trigger.
//  * The header carries an "ASKING ABOUT <filename>" context block. That block
//    is not decoration: it is what replaces the ambient context the user lost
//    when the document stopped being visible.
//
// #7326 revises two of those (see
// knowledge-base/product/design/mobile-chat-tour-revision/):
//
//  * The exit is now a LABELLED button — "Return to file preview" — not the bare
//    44x44 chevron #7222 shipped. On a surface that covers the entire phone, the
//    single affordance out of it should say where it goes.
//  * This header is now the ONLY one. `KbChatContent` suppresses its own
//    (filename + ✕) when hosted here: it repeated the filename this header
//    already shows and added a second, competing dismiss control. Three stacked
//    bars ate ~140px before the first message.

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
        className="flex shrink-0 flex-col gap-0.5 border-b border-soleur-border-default px-2 pb-1.5 pt-1"
      >
        <button
          type="button"
          onClick={onClose}
          data-testid="kb-chat-fullscreen-back"
          className="flex min-h-11 w-fit shrink-0 items-center gap-1.5 rounded-lg px-2 text-sm font-semibold text-soleur-accent-gold-fg transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary"
        >
          <svg
            width="18"
            height="18"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden="true"
            className="shrink-0"
          >
            <polyline points="15 18 9 12 15 6" />
          </svg>
          Return to file preview
        </button>
        {/* One line, not the two-line block #7222 shipped: with the exit now
            carrying its own row, stacking the label over the filename pushed the
            chrome past 100px on a 390px phone. */}
        <div className="flex min-w-0 items-baseline gap-1.5 px-2">
          <span className="shrink-0 text-[10px] font-semibold uppercase tracking-wider text-soleur-text-muted">
            Asking about
          </span>
          <span className="truncate text-xs text-soleur-text-primary">
            {filename}
          </span>
        </div>
      </header>
      <div className="flex min-h-0 min-w-0 flex-1 flex-col">{children}</div>
    </ResponsiveModal>
  );
}
