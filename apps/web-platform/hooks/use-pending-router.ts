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

// Explicit six-method surface — members NOT listed here (e.g. bfcacheId,
// experimental_gesturePush) do not pass through: a future nav-shaped member
// must be wrapped deliberately, not forwarded sight-unseen (review P3 — the
// forwarded-but-unconsumed members only existed to satisfy a shape test).
export type PendingRouter = Pick<
  AppRouter,
  "push" | "replace" | "back" | "forward" | "refresh" | "prefetch"
>;

export function usePendingRouter(): PendingRouter {
  const router = useRouter();
  return useMemo<PendingRouter>(
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
      prefetch: (href, options) =>
        options === undefined
          ? router.prefetch(href)
          : router.prefetch(href, options),
    }),
    [router],
  );
}
