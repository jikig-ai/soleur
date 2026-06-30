"use client";

import { useState } from "react";

// ADR-067 GAP #4 / AC8: when SWR revalidation FAILS while stale-but-valid data
// is still on screen (`error && data`), we keep the stale content visible and
// surface this subtle, dismissible bar instead of a full error screen. The
// operator-approved decision: stale content stays; the user gets an honest
// "couldn't refresh" + a Retry, and can dismiss it. Distinct from ErrorCard,
// which is the first-load (`error && !data`) failure surface.

export function StaleRefreshBar({ onRetry }: { onRetry: () => void }) {
  const [dismissed, setDismissed] = useState(false);
  if (dismissed) return null;
  return (
    <div
      role="status"
      data-testid="stale-refresh-bar"
      className="mb-3 flex items-center justify-between gap-3 rounded-md border border-soleur-border-default bg-soleur-bg-surface-1 px-3 py-2 text-sm text-soleur-text-secondary"
    >
      <span>Couldn&apos;t refresh — showing the last loaded view.</span>
      <div className="flex shrink-0 items-center gap-2">
        <button
          type="button"
          onClick={onRetry}
          className="rounded-md border border-soleur-border-default px-2.5 py-1 font-medium text-soleur-text-primary hover:bg-soleur-bg-surface-2"
        >
          Retry
        </button>
        <button
          type="button"
          onClick={() => setDismissed(true)}
          aria-label="Dismiss refresh warning"
          className="rounded p-1 text-soleur-text-muted hover:text-soleur-text-primary"
        >
          ✕
        </button>
      </div>
    </div>
  );
}
