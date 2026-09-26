"use client";

import { useState, useEffect } from "react";

const BANNER_DISMISS_KEY = "soleur:past_due_banner_dismissed";

/**
 * Past-due payment warning banner with sessionStorage-backed dismiss.
 *
 * Persists dismissal within a tab session so a page refresh does not re-show
 * the banner, while a new tab still surfaces the warning (sessionStorage is
 * tab-scoped).
 *
 * SSR-safe: the `window.sessionStorage` read is gated in a `useEffect` so the
 * initial render (`dismissed = false`) matches the server output and hydrates
 * cleanly; the post-hydration effect may flip state to `true`, which React
 * reconciles as a client-only update.
 *
 * Moved verbatim out of app/(dashboard)/layout.tsx in Phase 6 of
 * perf-dashboard-section-load-latency — the subscriptionStatus now arrives as
 * a server-resolved prop instead of a post-hydration mount effect (#5532).
 */
export function PaymentWarningBanner({
  subscriptionStatus,
}: {
  subscriptionStatus: string | null;
}) {
  // `null` = not yet hydrated — renders nothing until the sessionStorage
  // read below resolves the dismiss flag. Without the third state the SSR
  // pass (subscriptionStatus now arrives server-side) ships visible banner
  // HTML to a user who already dismissed this tab session — a false warning
  // flash on every first paint.
  const [dismissed, setDismissed] = useState<boolean | null>(null);

  // Hydrate dismiss state from sessionStorage (client-only).
  useEffect(() => {
    try {
      setDismissed(sessionStorage.getItem(BANNER_DISMISS_KEY) === "1");
    } catch {
      // sessionStorage unavailable (private mode, etc.) — treat as not
      // dismissed so the warning still shows (fail toward visibility).
      setDismissed(false);
    }
  }, []);

  function dismissBanner() {
    setDismissed(true);
    try {
      sessionStorage.setItem(BANNER_DISMISS_KEY, "1");
    } catch {
      // Persistence failed (quota, private mode) — in-memory state still hides
      // the banner for the current mount, which is acceptable degradation.
    }
  }

  if (subscriptionStatus !== "past_due" || dismissed !== false) {
    return null;
  }

  return (
    <div className="border-b border-orange-800/50 bg-orange-950/30 px-4 py-3">
      <div className="mx-auto flex max-w-4xl items-center justify-between gap-3">
        <p className="text-sm text-soleur-text-primary">
          <span className="font-medium text-orange-400">Your last payment failed.</span>{" "}
          Update your payment method to avoid service interruption.
        </p>
        <div className="flex shrink-0 items-center gap-2">
          <a
            href="/dashboard/settings"
            className="rounded-lg bg-orange-600 px-3 py-1.5 text-xs font-medium text-soleur-text-on-accent hover:bg-orange-500"
          >
            Update Payment
          </a>
          <button
            onClick={dismissBanner}
            aria-label="Dismiss payment warning"
            className="rounded p-1 text-soleur-text-secondary hover:text-soleur-text-primary"
          >
            <XIcon className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
}

function XIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      fill="none"
      viewBox="0 0 24 24"
      stroke="currentColor"
      strokeWidth={1.5}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M6 18 18 6M6 6l12 12"
      />
    </svg>
  );
}
