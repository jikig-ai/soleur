"use client";

// ADR-067 Option A (operator-approved): an ambient ~2px gold top shimmer shown
// ONLY while a warm cache hit is revalidating in the background
// (`isValidating && data`). No layout shift, no input block, no "from cache"
// status text anywhere — the cache is invisible; only this shimmer hints that
// fresh data is on the way. Brand palette tokens only (no raw hex).
//
// The bar is absolutely positioned against the nearest positioned ancestor; the
// surfaces that mount it (inbox/routines) are normal-flow blocks, so it rides
// the top edge of the viewport content without displacing anything. `aria-hidden`
// keeps it out of the a11y tree — it is decoration, not status.

export function RefreshShimmer({ active }: { active: boolean }) {
  if (!active) return null;
  return (
    <div
      aria-hidden="true"
      data-testid="refresh-shimmer"
      className="pointer-events-none fixed inset-x-0 top-0 z-50 h-[2px] overflow-hidden"
    >
      <div className="h-full w-1/3 animate-[refresh-shimmer_1.1s_ease-in-out_infinite] bg-soleur-accent-gold-fill/80" />
    </div>
  );
}
