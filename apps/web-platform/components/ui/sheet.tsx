"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { useMediaQuery } from "@/hooks/use-media-query";

// Mobile sheet is a constant 60vh by default. Dragging below 10vh closes.
const MOBILE_HEIGHT_VH = 0.6;
const CLOSE_THRESHOLD_VH = 0.1;

export interface SheetProps {
  open: boolean;
  onClose: () => void;
  "aria-label": string;
  children: ReactNode;
}

export function Sheet({
  open,
  onClose,
  "aria-label": ariaLabel,
  children,
}: SheetProps) {
  const isDesktop = useMediaQuery("(min-width: 768px)");

  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const panelRef = useRef<HTMLDivElement | null>(null);
  const dragStateRef = useRef<{ startY: number; startHeight: number } | null>(null);
  const [dragHeight, setDragHeight] = useState<number | null>(null);

  // Escape closes the sheet.
  useEffect(() => {
    if (!open) return;
    const handler = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      if (e.defaultPrevented) return;
      const panel = panelRef.current;
      if (!panel) return;
      if (panel.contains(document.activeElement) || document.activeElement === document.body) {
        onClose();
      }
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, [open, onClose]);

  if (!open || !mounted) return null;

  const vh = typeof window !== "undefined" ? window.innerHeight : 800;

  const desktopClasses =
    "z-40 flex h-full w-[380px] shrink-0 flex-col border-l border-neutral-800 bg-neutral-950 shadow-2xl";

  const mobileHeight =
    dragHeight !== null ? dragHeight : Math.round(vh * MOBILE_HEIGHT_VH);

  const mobileClasses =
    "fixed bottom-0 left-0 right-0 z-40 flex flex-col rounded-t-2xl border-t border-neutral-800 bg-neutral-950 shadow-2xl";

  function onPointerDown(e: React.PointerEvent<HTMLButtonElement>) {
    if (isDesktop) return;
    (e.target as Element).setPointerCapture?.(e.pointerId);
    dragStateRef.current = {
      startY: e.clientY,
      startHeight: Math.round(vh * MOBILE_HEIGHT_VH),
    };
  }

  function onPointerMove(e: React.PointerEvent<HTMLButtonElement>) {
    const state = dragStateRef.current;
    if (!state) return;
    const delta = state.startY - e.clientY; // drag up = positive
    const next = Math.max(0, Math.min(vh, state.startHeight + delta));
    setDragHeight(next);
  }

  function onPointerUp(e: React.PointerEvent<HTMLButtonElement>) {
    const state = dragStateRef.current;
    dragStateRef.current = null;
    if (!state) return;
    (e.target as Element).releasePointerCapture?.(e.pointerId);
    const delta = state.startY - e.clientY;
    const releasedHeight = Math.max(0, Math.min(vh, state.startHeight + delta));
    setDragHeight(null);

    // Below 10vh = close. Otherwise snap back to the default 60vh height.
    if (releasedHeight < vh * CLOSE_THRESHOLD_VH) {
      onClose();
    }
  }

  const panel = (
    <div
      ref={panelRef}
      role="dialog"
      aria-modal="false"
      aria-label={ariaLabel}
      className={isDesktop ? desktopClasses : mobileClasses}
      style={!isDesktop ? { height: `${mobileHeight}px` } : undefined}
    >
      {!isDesktop && (
        <button
          type="button"
          aria-label="Resize panel"
          title="Drag to close"
          className="mx-auto mt-2 h-1.5 w-10 shrink-0 rounded-full bg-neutral-700 touch-none"
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onPointerCancel={onPointerUp}
        />
      )}
      <div className="flex min-h-0 min-w-0 flex-1 flex-col">{children}</div>
    </div>
  );

  // Desktop: render inline as a flex child so the content area shrinks.
  // Mobile: portal to body for bottom-sheet overlay behavior.
  if (isDesktop) return panel;
  return createPortal(panel, document.body);
}
