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
    <html>
      <body className="bg-neutral-950 text-neutral-100 flex items-center justify-center min-h-screen">
        <div className="text-center">
          <h2 className="text-xl mb-4">Something went wrong</h2>
          <button
            onClick={reset}
            className="px-4 py-2 bg-neutral-800 rounded"
          >
            Try again
          </button>
        </div>
      </body>
    </html>
  );
}
