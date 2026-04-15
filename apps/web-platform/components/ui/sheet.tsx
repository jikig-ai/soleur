"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { useMediaQuery } from "@/hooks/use-media-query";

export type SheetSnap = "collapsed" | "default" | "full";

// vh fractions for snap points.
const SNAP_VH: Record<SheetSnap, number> = {
  collapsed: 0.2,
  default: 0.6,
  full: 1.0,
};
// Drag end threshold: below 10vh of sheet height = close.
const CLOSE_THRESHOLD_VH = 0.1;

type Side = "right" | "bottom";

export interface SheetProps {
  open: boolean;
  onClose: () => void;
  side?: Side;
  "aria-label": string;
  children: ReactNode;
  onSnapChange?: (snap: SheetSnap) => void;
}

export function Sheet({
  open,
  onClose,
  side,
  "aria-label": ariaLabel,
  children,
  onSnapChange,
}: SheetProps) {
  const isDesktop = useMediaQuery("(min-width: 768px)");
  const resolvedSide: Side = side ?? (isDesktop ? "right" : "bottom");

  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const [snap, setSnap] = useState<SheetSnap>("default");
  const panelRef = useRef<HTMLDivElement | null>(null);
  const dragStateRef = useRef<{ startY: number; startHeight: number } | null>(null);
  const [dragHeight, setDragHeight] = useState<number | null>(null);

  useEffect(() => {
    onSnapChange?.(snap);
  }, [snap, onSnapChange]);

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
    "fixed right-0 top-0 z-40 flex h-[100dvh] w-[380px] flex-col border-l border-neutral-800 bg-neutral-950 shadow-2xl";

  const mobileHeight =
    dragHeight !== null ? dragHeight : Math.round(vh * SNAP_VH[snap]);

  const mobileClasses =
    "fixed bottom-0 left-0 right-0 z-40 flex flex-col rounded-t-2xl border-t border-neutral-800 bg-neutral-950 shadow-2xl";

  function onPointerDown(e: React.PointerEvent<HTMLButtonElement>) {
    if (resolvedSide !== "bottom") return;
    (e.target as Element).setPointerCapture?.(e.pointerId);
    dragStateRef.current = {
      startY: e.clientY,
      startHeight: Math.round(vh * SNAP_VH[snap]),
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

    // Below 10vh = close.
    if (releasedHeight < vh * CLOSE_THRESHOLD_VH) {
      onClose();
      return;
    }
    // Snap to nearest of three points.
    const candidates: SheetSnap[] = ["collapsed", "default", "full"];
    const nearest = candidates.reduce((best, s) => {
      const target = vh * SNAP_VH[s];
      const bestTarget = vh * SNAP_VH[best];
      return Math.abs(target - releasedHeight) < Math.abs(bestTarget - releasedHeight)
        ? s
        : best;
    }, "default" as SheetSnap);
    setSnap(nearest);
  }

  const panel = (
    <div
      ref={panelRef}
      role="dialog"
      aria-modal="false"
      aria-label={ariaLabel}
      className={resolvedSide === "right" ? desktopClasses : mobileClasses}
      style={resolvedSide === "bottom" ? { height: `${mobileHeight}px` } : undefined}
    >
      {resolvedSide === "bottom" && (
        <button
          type="button"
          aria-label="Resize panel"
          title="Drag to expand"
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

  return createPortal(panel, document.body);
}
