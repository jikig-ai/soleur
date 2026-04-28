"use client";
import { useEffect } from "react";
import { reportSilentFallback } from "@/lib/client-observability";

// Shared body for `app/error.tsx` and `app/(dashboard)/error.tsx`. The
// `data-error-boundary` attribute is the canary contract — `infra/ci-deploy.sh`
// greps the rendered HTML for it; copy edits cannot disable the gate.
//
// Sentry: passing `feature` from each boundary keeps alert rules scopable.
// Never put `error.message` into `extra` — validator throws may include a JWT
// preview (see `lib/supabase/validate-anon-key.ts`). The Error itself is
// captured automatically; Sentry's `beforeSend` redacts message-body JWTs.
export function ErrorBoundaryView({
  error,
  reset,
  feature,
  segment,
}: {
  error: Error & { digest?: string };
  reset: () => void;
  feature: string;
  segment?: string;
}) {
  useEffect(() => {
    reportSilentFallback(error, {
      feature,
      op: "render",
      extra: {
        ...(segment ? { segment } : {}),
        digest: error.digest ?? null,
      },
    });
  }, [error, feature, segment]);

  return (
    <div
      data-error-boundary={segment ?? "root"}
      className="flex min-h-[50vh] flex-col items-center justify-center gap-4"
    >
      <h2 className="text-xl font-semibold text-white">Something went wrong</h2>
      <p className="text-sm text-neutral-400">
        {error.digest
          ? `Error ID: ${error.digest}`
          : "An unexpected error occurred."}
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
