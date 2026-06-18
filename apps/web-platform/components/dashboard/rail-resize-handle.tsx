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
// Double-click accelerator: double-clicking the handle calls `onCollapse` to
// collapse the rail (an additive shortcut beside the kept collapse button —
// FR3-Alternative). A double-click that immediately follows a real drag
// (> DRAG_THRESHOLD_PX of pointer travel) is ignored so dragging never
// accidentally collapses the rail.

/** Pointer travel (px) above which a gesture counts as a drag, not a click. */
const DRAG_THRESHOLD_PX = 5;

export interface RailResizeHandleProps {
  width: number;
  min: number;
  max: number;
  /** Transient update during a drag (no persist). */
  onWidthChange: (px: number) => void;
  /** Persisted commit (pointerup / keyboard nudge). */
  onCommit: (px: number) => void;
  /** Double-click accelerator: collapse the rail. Optional — the floated
   * collapse button remains the primary affordance. */
  onCollapse?: () => void;
}

export function RailResizeHandle({
  width,
  min,
  max,
  onWidthChange,
  onCommit,
  onCollapse,
}: RailResizeHandleProps) {
  const dragging = useRef(false);
  const startX = useRef(0);
  const startWidth = useRef(width);
  const latest = useRef(width);
  // Max pointer travel during the current gesture — used to distinguish a
  // genuine double-click from the tail of a drag (AC6).
  const travel = useRef(0);

  function clamp(px: number): number {
    return Math.min(max, Math.max(min, Math.round(px)));
  }

  function handlePointerDown(e: React.PointerEvent<HTMLDivElement>) {
    e.preventDefault();
    dragging.current = true;
    startX.current = e.clientX;
    startWidth.current = width;
    latest.current = width;
    travel.current = 0;
    // setPointerCapture may be absent in some test DOMs — best-effort.
    try {
      e.currentTarget.setPointerCapture(e.pointerId);
    } catch {
      // no-op: drag still tracked via the `dragging` ref.
    }
  }

  function handlePointerMove(e: React.PointerEvent<HTMLDivElement>) {
    if (!dragging.current) return;
    travel.current = Math.max(
      travel.current,
      Math.abs(e.clientX - startX.current),
    );
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
    // Ignore a double-click that is really the tail end of a drag.
    if (travel.current > DRAG_THRESHOLD_PX) return;
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
      aria-label="Resize knowledge base sidebar"
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
