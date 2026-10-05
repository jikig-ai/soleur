"use client";
// <!-- anti-slop:disable MIN-H-SCREEN-CENTERED-HERO reason="Next.js root error boundary; full-viewport centered hero is the canonical pattern for this surface (calibration #4270)" -->
import * as Sentry from "@sentry/nextjs";
import { useEffect } from "react";
import { Button } from "@/components/ui/button";

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    Sentry.captureException(error);
  }, [error]);

  return (
    <html lang="en">
      {/* global-error has no data-theme attribute (no-FOUC script lives in failed root layout); :root:not([data-theme]) defaults to OS preference. */}
      <body className="bg-soleur-bg-base text-soleur-text-primary">
        <div className="flex min-h-screen flex-col items-center justify-center gap-4">
          <h2 className="text-xl font-semibold">Something went wrong</h2>
          <p className="text-sm text-soleur-text-secondary">
            A critical error occurred. Please try refreshing the page.
          </p>
          <Button
            variant="outlined"
            onClick={reset}
            className="text-soleur-text-secondary"
          >
            Try again
          </Button>
        </div>
      </body>
    </html>
  );
}
