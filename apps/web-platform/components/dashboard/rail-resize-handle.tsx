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

export interface RailResizeHandleProps {
  width: number;
  min: number;
  max: number;
  /** Transient update during a drag (no persist). */
  onWidthChange: (px: number) => void;
  /** Persisted commit (pointerup / keyboard nudge). */
  onCommit: (px: number) => void;
}

export function RailResizeHandle({
  width,
  min,
  max,
  onWidthChange,
  onCommit,
}: RailResizeHandleProps) {
  const dragging = useRef(false);
  const startX = useRef(0);
  const startWidth = useRef(width);
  const latest = useRef(width);

  function clamp(px: number): number {
    return Math.min(max, Math.max(min, Math.round(px)));
  }

  function handlePointerDown(e: React.PointerEvent<HTMLDivElement>) {
    e.preventDefault();
    dragging.current = true;
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
    onCommit(latest.current);
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
      onKeyDown={handleKeyDown}
      className="group absolute inset-y-0 right-0 z-10 hidden w-1 cursor-col-resize touch-none bg-transparent transition-colors duration-150 hover:bg-soleur-text-secondary/50 focus-visible:bg-amber-500/50 focus-visible:outline-none active:bg-amber-500/50 md:block"
    >
      <div className="pointer-events-none absolute inset-y-0 left-1/2 flex -translate-x-1/2 items-center justify-center">
        <span
          data-testid="kb-rail-resize-grip"
          className="h-8 w-0.5 bg-soleur-text-muted group-hover:bg-soleur-text-secondary"
        />
      </div>
    </div>
  );
}
