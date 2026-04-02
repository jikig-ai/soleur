"use client";
import * as Sentry from "@sentry/nextjs";
import { useEffect } from "react";

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
      <body className="bg-neutral-950 text-white">
        <div className="flex min-h-screen flex-col items-center justify-center gap-4">
          <h2 className="text-xl font-semibold">Something went wrong</h2>
          <p className="text-sm text-neutral-400">
            A critical error occurred. Please try refreshing the page.
          </p>
          <button
            onClick={reset}
            className="rounded-lg border border-neutral-700 px-4 py-2 text-sm text-neutral-300 hover:border-neutral-500"
          >
            Try again
          </button>
        </div>
      </body>
    </html>
  );
}
