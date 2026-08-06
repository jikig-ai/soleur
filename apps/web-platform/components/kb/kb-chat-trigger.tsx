"use client";

import Link from "next/link";
import { useContext, useEffect, useRef } from "react";
import { KbChatContext } from "@/components/kb/kb-chat-context";

export interface KbChatTriggerProps {
  /** Legacy URL used when the feature flag is disabled. */
  fallbackHref: string;
}

/**
 * Stateful trigger button for the KB chat sidebar.
 *
 * - Flag on: opens the sidebar via KbChatContext; label reflects thread state
 *   ("Ask about this document" vs "Continue thread").
 * - Flag off (or outside a KbChatContext provider): renders a legacy link
 *   to /dashboard/chat/new for backward compatibility.
 */
export function KbChatTrigger({ fallbackHref }: KbChatTriggerProps) {
  const ctx = useContext(KbChatContext);
  const buttonRef = useRef<HTMLButtonElement | null>(null);
  const wasOpenRef = useRef(false);

  // Focus management (TR9 / AC9): when the panel transitions from open →
  // closed, return focus to this trigger so keyboard users land back on the
  // control that opened it. Tracks the SIDE panel (`open`) for the markdown
  // viewer and the EMBEDDED Concierge (`embeddedConciergeOpen`) for C4, since
  // the same trigger drives whichever surface is active.
  const embeddedOpen = !!ctx?.suppressSidebar && ctx?.embeddedConciergeOpen;
  useEffect(() => {
    const isOpen = !!ctx?.open || !!embeddedOpen;
    if (wasOpenRef.current && !isOpen) {
      buttonRef.current?.focus();
    }
    wasOpenRef.current = isOpen;
  }, [ctx?.open, embeddedOpen]);

  // Gold-gradient primary CTA — first activation of the
  // `--soleur-accent-gradient-{start,end}` theme tokens registered in
  // globals.css `@theme`. Tokens resolve to #d4b36a/#b8923e cross-theme,
  // visually identical to the dashboard "New conversation" CTA at
  // dashboard/page.tsx:526 (which currently uses the literal-hex form).
  // Consolidating those literal-hex sites is tracked as a separate cleanup.
  // #7222 — `min-h-[44px]` below `md`. Once the mobile conversation is a
  // full-screen takeover this pill is the ONLY way back into it, so a 26px
  // target is not acceptable; `md:min-h-0` keeps the compact desktop pill.
  // #7326 — `shrink-0 whitespace-nowrap`: this pill is the fixed side of the
  // header. Half of the off-screen bug was the breadcrumb refusing to yield
  // (fixed in kb-content-header); the other half was this pill being willing to
  // shrink or wrap instead of holding its width. Both halves are needed — either
  // alone still produces an unreachable control.
  const baseClass =
    "inline-flex min-h-[44px] shrink-0 items-center gap-1.5 whitespace-nowrap rounded-lg bg-gradient-to-r from-soleur-accent-gradient-start to-soleur-accent-gradient-end px-3 py-1.5 text-xs font-semibold text-soleur-text-on-accent transition-opacity hover:opacity-90 md:min-h-0";

  const icon = (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="shrink-0">
      <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2Z" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );

  if (!ctx || !ctx.enabled) {
    return (
      <Link href={fallbackHref} className={baseClass}>
        {icon}
        Chat about this
      </Link>
    );
  }

  // A view that embeds its own Concierge (the C4 workspace) suppresses the
  // SIDE PANEL but NOT the trigger: the same top-bar "Ask about this document"
  // control drives the embedded Concierge's reveal (parity with the markdown
  // viewer), instead of opening a redundant second side-panel chat. The
  // suppressSidebar mount stays unmounted (no double-mount).
  const embedded = !!ctx.suppressSidebar;
  const onClick = embedded
    ? ctx.revealEmbeddedConcierge ?? (() => {})
    : ctx.openSidebar;

  // `ctx.messageCount` is the canonical thread-state signal. When the panel
  // is closed, it is seeded by `useKbLayoutState`'s thread-info prefetch
  // (/api/chat/thread-info) BEFORE the sidebar mounts. While the panel is
  // open, ChatSurface keeps it current via `onMessageCountChange`. The
  // trigger does not own this state and must not derive it from any other
  // signal — see the H3 race fix in `chat-surface.tsx` and `kb-chat-content.tsx`.
  const hasThread = ctx.messageCount > 0;
  const label = hasThread ? "Continue thread" : "Ask about this document";
  // #7326 — the VISIBLE label shortens below `md`; the ACCESSIBLE name never
  // does. `aria-label` overrides the element's text content entirely, so screen
  // readers, and any agent driving by accessible name, get the full wording at
  // every width — only the pixels change. Both spans stay in the DOM (CSS swap,
  // not a JS branch) so the header does not need a viewport read to render.
  const shortLabel = hasThread ? "Continue" : "Ask";

  return (
    <button
      ref={buttonRef}
      type="button"
      onClick={onClick}
      aria-label={label}
      className={baseClass}
    >
      {icon}
      <span className="md:hidden">{shortLabel}</span>
      <span className="hidden md:inline">{label}</span>
      {hasThread && (
        <span
          aria-hidden="true"
          data-testid="kb-trigger-thread-indicator"
          className="ml-1 inline-block h-1.5 w-1.5 rounded-full bg-soleur-text-on-accent"
        />
      )}
    </button>
  );
}
