"use client";

// feat-ui-action-feedback Layer 2 trigger (b) — drop-in useRouter() wrapper.
// push/replace start the pending episode only when the target is NOT the
// current document (same-URL pushes still delegate — they carry scroll-to-top
// semantics, kieran #12). refresh/back/forward/prefetch and every other
// member pass through untouched — refresh must NEVER fire the bar (it has
// ~22+ live callers and is a revalidation, not a navigation).

import { useMemo } from "react";
import { useRouter } from "next/navigation";
import { isSameDocTarget, startNavPending } from "@/lib/nav-pending-store";

type AppRouter = ReturnType<typeof useRouter>;

export function usePendingRouter(): AppRouter {
  const router = useRouter();
  return useMemo<AppRouter>(
    () => ({
      push: (href, options) => {
        if (!isSameDocTarget(href)) startNavPending("router");
        // Forward `options` only when defined — a literal trailing `undefined`
        // breaks consumer tests asserting toHaveBeenCalledWith(href) arity.
        if (options === undefined) router.push(href);
        else router.push(href, options);
      },
      replace: (href, options) => {
        if (!isSameDocTarget(href)) startNavPending("router");
        if (options === undefined) router.replace(href);
        else router.replace(href, options);
      },
      back: () => router.back(),
      forward: () => router.forward(),
      refresh: () => router.refresh(),
      prefetch: (href, options) => router.prefetch(href, options),
      get bfcacheId() {
        return router.bfcacheId;
      },
      ...(router.experimental_gesturePush
        ? {
            experimental_gesturePush: (
              href: string,
              options?: Parameters<
                NonNullable<AppRouter["experimental_gesturePush"]>
              >[1],
            ) => router.experimental_gesturePush?.(href, options),
          }
        : {}),
    }),
    [router],
  );
}
