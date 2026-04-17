"use client";

import { useEffect, useRef, useState, type RefObject } from "react";
import { createPortal } from "react-dom";

export interface SelectionToolbarProps {
  articleRef: RefObject<HTMLElement | null>;
  onAddToChat: (text: string) => void;
  /** Max selection size in bytes. Defaults to 8KB matching the server cap. */
  maxBytes?: number;
}

interface PillState {
  text: string;
  bytes: number;
  top: number;
  left: number;
}

const DEFAULT_MAX_BYTES = 8 * 1024;

function isShortcutKey(e: KeyboardEvent): boolean {
  if (!e.shiftKey) return false;
  if (!(e.ctrlKey || e.metaKey)) return false;
  return e.key === "l" || e.key === "L";
}

/**
 * Floating "Quote in chat" pill that appears when the user selects text
 * inside `articleRef`. Client-side 8KB preflight renders the pill in a
 * disabled state for oversize selections. Escape dismisses the pill only
 * (stopPropagation so sidebar Escape still works as a second press).
 *
 * iOS Safari: the article element gets `user-select: text` applied by the
 * consumer's CSS; this component additionally suppresses `contextmenu`
 * while a valid selection is active, so the native share menu doesn't
 * compete with the pill.
 */
export function SelectionToolbar({
  articleRef,
  onAddToChat,
  maxBytes = DEFAULT_MAX_BYTES,
}: SelectionToolbarProps) {
  const [pill, setPill] = useState<PillState | null>(null);
  const [mounted, setMounted] = useState(false);
  const pillRef = useRef<HTMLButtonElement | null>(null);
  // One TextEncoder per instance — `new Blob([text]).size` allocates a
  // full Blob per keystroke during drag-select; encode().byteLength reads
  // the same UTF-8 length without the allocation.
  const encoderRef = useRef<TextEncoder | null>(null);
  function measureBytes(text: string): number {
    if (!encoderRef.current) encoderRef.current = new TextEncoder();
    return encoderRef.current.encode(text).byteLength;
  }

  useEffect(() => setMounted(true), []);

  // Subscribe to selectionchange and compute pill state. `selectionchange`
  // fires at mousemove frequency during drag-select; coalesce setPill via
  // a single-slot rAF so React only re-renders once per frame.
  useEffect(() => {
    let rafId: number | null = null;
    function scheduleSetPill(next: PillState | null) {
      if (rafId !== null) cancelAnimationFrame(rafId);
      rafId = requestAnimationFrame(() => {
        rafId = null;
        setPill(next);
      });
    }

    function onSelectionChange() {
      const sel = typeof window !== "undefined" ? window.getSelection() : null;
      const article = articleRef.current;
      if (!sel || !article) {
        scheduleSetPill(null);
        return;
      }
      if (sel.rangeCount === 0 || sel.isCollapsed) {
        scheduleSetPill(null);
        return;
      }
      const text = sel.toString();
      if (!text || !text.trim()) {
        scheduleSetPill(null);
        return;
      }
      // Both endpoints must live inside the article.
      // Element.contains accepts Node | null; returns false on null.
      if (
        !article.contains(sel.anchorNode) ||
        !article.contains(sel.focusNode)
      ) {
        scheduleSetPill(null);
        return;
      }
      let top = 0;
      let left = 0;
      try {
        const range = sel.getRangeAt(0);
        const rect = range.getBoundingClientRect();
        top = rect.top + (typeof window !== "undefined" ? window.scrollY : 0);
        left = rect.left + (typeof window !== "undefined" ? window.scrollX : 0);
      } catch {
        /* jsdom: getBoundingClientRect may throw on detached ranges */
      }
      const bytes = measureBytes(text);
      scheduleSetPill({ text, bytes, top, left });
    }

    document.addEventListener("selectionchange", onSelectionChange);
    return () => {
      document.removeEventListener("selectionchange", onSelectionChange);
      if (rafId !== null) {
        cancelAnimationFrame(rafId);
        rafId = null;
      }
    };
  }, [articleRef]);

  // Escape dismisses the pill; stopPropagation so the sidebar's Escape
  // handler doesn't also close the panel on the same keystroke.
  useEffect(() => {
    if (!pill) return;
    function onKeyDown(e: KeyboardEvent) {
      if (e.key !== "Escape") return;
      e.stopPropagation();
      setPill(null);
    }
    document.addEventListener("keydown", onKeyDown, true);
    return () => document.removeEventListener("keydown", onKeyDown, true);
  }, [pill]);

  // ⌘⇧L / Ctrl+Shift+L inside article triggers the quote action.
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if (!isShortcutKey(e)) return;
      const article = articleRef.current;
      if (!article) return;
      const sel = typeof window !== "undefined" ? window.getSelection() : null;
      const text = sel?.toString() ?? "";
      if (!text.trim()) return;
      if (
        !article.contains(sel?.anchorNode ?? null) ||
        !article.contains(sel?.focusNode ?? null)
      ) {
        return;
      }
      const bytes = measureBytes(text);
      if (bytes > maxBytes) return;
      e.preventDefault();
      e.stopPropagation();
      onAddToChat(text);
      setPill(null);
    }
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [articleRef, onAddToChat, maxBytes]);

  // Suppress contextmenu while pill is visible — avoids iOS Safari's native
  // share menu competing with the pill on touch selection.
  useEffect(() => {
    if (!pill) return;
    const article = articleRef.current;
    if (!article) return;
    function onContextMenu(e: Event) {
      e.preventDefault();
    }
    article.addEventListener("contextmenu", onContextMenu);
    return () => article.removeEventListener("contextmenu", onContextMenu);
  }, [pill, articleRef]);

  if (!mounted || !pill) return null;

  const disabled = pill.bytes > maxBytes;
  const title = disabled
    ? `Selection too long — shorten to under ${Math.round(maxBytes / 1024)}KB`
    : "Add this selection as a quoted block to chat";

  // Anchor ~8px above the selection's top edge.
  const buttonHeight = 32;
  const anchorTop = Math.max(8, pill.top - buttonHeight - 8);
  const anchorLeft = Math.max(8, pill.left);

  const pillEl = (
    <button
      ref={pillRef}
      type="button"
      disabled={disabled}
      title={title}
      onMouseDown={(e) => {
        // Prevent the browser from collapsing the selection on mousedown.
        e.preventDefault();
      }}
      onClick={() => {
        if (disabled) return;
        onAddToChat(pill.text);
        setPill(null);
      }}
      style={{
        position: "absolute",
        top: `${anchorTop}px`,
        left: `${anchorLeft}px`,
        zIndex: 50,
      }}
      className={
        "inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-xs font-medium shadow-lg transition-colors " +
        (disabled
          ? "cursor-not-allowed border-neutral-700 bg-neutral-900 text-neutral-500"
          : "border-amber-500/60 bg-neutral-900 text-amber-300 hover:border-amber-400 hover:text-amber-200")
      }
    >
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <path d="M3 21v-4a4 4 0 0 1 4-4h3" />
        <path d="M21 3v4a4 4 0 0 1-4 4h-3" />
      </svg>
      Quote in chat
      <span
        aria-hidden="true"
        className="ml-1 rounded border border-neutral-700 bg-neutral-800 px-1 py-0.5 text-[10px] text-neutral-400"
      >
        ⌘⇧L
      </span>
    </button>
  );

  return createPortal(pillEl, document.body);
}
