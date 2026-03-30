"use client";
import * as Sentry from "@sentry/nextjs";
import { useEffect } from "react";

export default function Error({
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
    <div className="flex items-center justify-center min-h-screen">
      <div className="text-center">
        <h2 className="text-xl mb-4">Something went wrong</h2>
        <button
          onClick={reset}
          className="px-4 py-2 bg-neutral-800 rounded"
        >
          Try again
        </button>
      </div>
    </div>
  );
}
