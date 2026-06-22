"use client";

import { useRef } from "react";

// Widenable KB rail (amendment). A thin right-edge drag handle that resizes the
// EXPANDED KB nav rail (`aside`). The rail is a single fixed-width `aside`, not
// a react-resizable-panels `Panel`, so the library's `Separator` cannot drive
// it; this handle reuses that component's amber-active hover/active idiom
// (`kb-desktop-layout.tsx`) without importing it — no new dependency. The grip
// affordance is a single straight vertical bar (sharp 0px corners, brand
// mandate) centered on the right edge — clearer than the old faint dot triad.
//
// a11y: role="separator" + aria-orientation + aria-valuenow/min/max + keyboard
// Arrow nudge so non-pointer / AT users can widen too (Web Interface Guidelines:
// resize handles must be keyboard-operable).
//
// Persistence discipline: transient drag deltas fire `onWidthChange` (state
// only, no storage write) and the committed value persists once on pointerup
// (and on each keyboard nudge) via `onCommit` — avoids thrashing localStorage.
// A no-op pointerup (no actual movement) skips `onCommit` entirely.
//
// Double-click toggle: double-clicking the handle calls `onCollapse` to toggle
// the rail's collapse state (expand when collapsed, collapse when expanded). The
// slider is the SOLE collapse/expand affordance — the dedicated button was
// removed as a duplicate. No drag-vs-click guard is needed: a real resize drag
// moves the pointer past the browser's click threshold, so it never emits the two
// `click` events a `dblclick` requires — dragging therefore cannot fire
// `onDoubleClick`, and a genuine double-click (negligible movement) toggles.

export interface RailResizeHandleProps {
  width: number;
  min: number;
  max: number;
  /** Transient update during a drag (no persist). */
  onWidthChange: (px: number) => void;
  /** Persisted commit (pointerup / keyboard nudge). */
  onCommit: (px: number) => void;
  /** Fired ONCE per drag, on the first genuine pointer movement (not on a bare
   * pointerdown — so it does not fire for a double-click, which has negligible
   * movement). Lets a collapsed rail un-collapse the moment a real resize drag
   * begins, so the width override engages. Optional. */
  onResizeStart?: () => void;
  /** Double-click accelerator: toggle rail collapse (expand when collapsed,
   * collapse when expanded). The resize slider is the sole collapse/expand
   * affordance. Optional. */
  onCollapse?: () => void;
  /** Accessible name for the handle. Defaults to the KB rail's literal; pass a
   * generic label (e.g. "Resize sidebar") when the grip drives a non-KB rail. */
  ariaLabel?: string;
}

export function RailResizeHandle({
  width,
  min,
  max,
  onWidthChange,
  onCommit,
  onResizeStart,
  onCollapse,
  ariaLabel = "Resize knowledge base sidebar",
}: RailResizeHandleProps) {
  const dragging = useRef(false);
  const startX = useRef(0);
  const startWidth = useRef(width);
  const latest = useRef(width);
  // Latches `onResizeStart` to fire once per drag, on the first real move only.
  const startedResize = useRef(false);

  function clamp(px: number): number {
    return Math.min(max, Math.max(min, Math.round(px)));
  }

  function handlePointerDown(e: React.PointerEvent<HTMLDivElement>) {
    e.preventDefault();
    dragging.current = true;
    startedResize.current = false;
    startX.current = e.clientX;
    startWidth.current = width;
    latest.current = width;
    // setPointerCapture may be absent in some test DOMs — best-effort.
    try {
      e.currentTarget.setPointerCapture(e.pointerId);
    } catch {
      // no-op: drag still tracked via the `dragging` ref.
    }
  }

  function handlePointerMove(e: React.PointerEvent<HTMLDivElement>) {
    if (!dragging.current) return;
    // First genuine move of this drag — let the caller react (e.g. un-collapse a
    // collapsed rail). Gated on actual displacement so a click/double-click
    // (negligible movement) never trips it.
    if (!startedResize.current && e.clientX !== startX.current) {
      startedResize.current = true;
      onResizeStart?.();
    }
    const next = clamp(startWidth.current + (e.clientX - startX.current));
    latest.current = next;
    onWidthChange(next);
  }

  function endDrag(e: React.PointerEvent<HTMLDivElement>) {
    if (!dragging.current) return;
    dragging.current = false;
    try {
      e.currentTarget.releasePointerCapture(e.pointerId);
    } catch {
      // no-op.
    }
    // Skip the redundant localStorage write when the rail never actually moved.
    if (latest.current !== startWidth.current) {
      onCommit(latest.current);
    }
  }

  function handleDoubleClick() {
    onCollapse?.();
  }

  function handleKeyDown(e: React.KeyboardEvent<HTMLDivElement>) {
    if (e.key === "ArrowRight") {
      e.preventDefault();
      onCommit(clamp(width + 16));
    } else if (e.key === "ArrowLeft") {
      e.preventDefault();
      onCommit(clamp(width - 16));
    }
  }

  return (
    <div
      role="separator"
      aria-orientation="vertical"
      aria-label={ariaLabel}
      aria-valuenow={width}
      aria-valuemin={min}
      aria-valuemax={max}
      tabIndex={0}
      data-testid="kb-rail-resize-handle"
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={endDrag}
      onPointerCancel={endDrag}
      onDoubleClick={handleDoubleClick}
      onKeyDown={handleKeyDown}
      // Active/focus wash is brand gold (`soleur-accent-gold-fill`) at /70 alpha
      // — /70 clears the 3:1 non-text contrast bar on the dark surface where /50
      // does not (AC11). Hover stays grey (`soleur-text-secondary`); gold appears
      // only while you click/drag or keyboard-focus, never on hover.
      className="group absolute inset-y-0 right-0 z-10 hidden w-1 cursor-col-resize touch-none bg-transparent transition-colors duration-150 hover:bg-soleur-text-secondary/50 focus-visible:bg-soleur-accent-gold-fill/70 focus-visible:outline-none active:bg-soleur-accent-gold-fill/70 md:block"
    >
      <span
        data-testid="kb-rail-resize-grip"
        className="pointer-events-none absolute left-1/2 top-1/2 h-8 w-0.5 -translate-x-1/2 -translate-y-1/2 bg-soleur-text-muted group-hover:bg-soleur-text-secondary"
      />
    </div>
  );
}
