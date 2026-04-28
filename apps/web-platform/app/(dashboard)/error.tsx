"use client";
import { useEffect } from "react";
import { reportSilentFallback } from "@/lib/client-observability";

// Segment-scoped error boundary for the (dashboard) route group. A throw inside
// any /dashboard, /knowledge-base, /chat, or /settings render is caught here
// instead of bubbling to app/error.tsx, so the Sentry event carries
// `segment: dashboard` and the layout chrome above the boundary stays mounted.
export default function DashboardSegmentError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    reportSilentFallback(error, {
      feature: "dashboard-error-boundary",
      op: "render",
      extra: {
        segment: "dashboard",
        digest: error.digest ?? null,
        route:
          typeof window !== "undefined" ? window.location.pathname : null,
      },
    });
  }, [error]);

  return (
    <div className="flex min-h-[50vh] flex-col items-center justify-center gap-4">
      <h2 className="text-xl font-semibold text-white">Something went wrong</h2>
      <p className="text-sm text-neutral-400">
        {error.digest ? `Error ID: ${error.digest}` : "An unexpected error occurred."}
      </p>
      <button
        onClick={reset}
        className="rounded-lg border border-neutral-700 px-4 py-2 text-sm text-neutral-300 transition-colors hover:border-neutral-500 hover:text-white"
      >
        Try again
      </button>
    </div>
  );
}
