"use client";

import { useCallback, useEffect, useRef, useState, useTransition } from "react";
import { reportSilentFallback } from "@/lib/client-observability";

// Canonical home: lib/pending-timing.ts — re-exported so hook consumers and
// fetch-abort call sites keep a single import shape.
import { PENDING_WATCHDOG_MS } from "@/lib/pending-timing";
export { PENDING_WATCHDOG_MS };

export type PendingAction<A extends unknown[]> = {
  run: (...args: A) => void;
  pending: boolean;
  error: Error | null;
  /**
   * Mark the in-flight episode terminal: the asyncFn ends in a hard
   * navigation or an unmount of the invoking surface, so `pending` must NOT
   * release on resolve — the document teardown (or unmount) IS the reset.
   * Call `latch()` immediately before `window.location.*` (or the unmounting
   * callback). Terminality is explicit, never inferred from resolution: an
   * asyncFn that resolves without navigating (a confirm-cancel, a handled
   * !res.ok) releases normally, and a latched episode still reports to Sentry
   * if it outlives the watchdog — the promised teardown never arrived.
   */
  latch: () => void;
};

export function usePendingAction<A extends unknown[] = []>(
  asyncFn: (...args: A) => Promise<unknown> | unknown,
): PendingAction<A> {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const [, startTransition] = useTransition();
  const pendingRef = useRef(false);
  const latchedRef = useRef(false);
  const invokerRef = useRef<HTMLElement | null>(null);
  const watchdogRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  // Episode monotonic: after the watchdog releases a hung episode the user
  // can retry while the zombie asyncFn is still in flight. Without the token,
  // the zombie's finally/setError lands on the NEW episode — releasing its
  // pending mid-flight (double-submit window) and clearing its watchdog.
  // Bounded residual: a zombie that reaches its OWN latch()/hard-nav path
  // after release still executes that nav (JS promises are not abortable —
  // full suppression needs an AbortSignal threaded into asyncFn, a larger
  // API change). Its latch write is semantically correct for its own nav.
  const episodeRef = useRef(0);

  const clearWatchdog = useCallback(() => {
    if (watchdogRef.current != null) {
      clearTimeout(watchdogRef.current);
      watchdogRef.current = null;
    }
  }, []);

  useEffect(() => clearWatchdog, [clearWatchdog]);

  // Focus restore runs after the pending=false commit — calling focus() while
  // the control is still `disabled` is a no-op in every DOM implementation.
  const wasPendingRef = useRef(false);
  useEffect(() => {
    if (wasPendingRef.current && !pending) {
      const invoker = invokerRef.current;
      invokerRef.current = null;
      if (
        invoker &&
        invoker.isConnected &&
        (document.activeElement === document.body ||
          document.activeElement == null)
      ) {
        invoker.focus();
      }
    }
    wasPendingRef.current = pending;
  }, [pending]);

  const release = useCallback(() => {
    clearWatchdog();
    pendingRef.current = false;
    setPending(false);
  }, [clearWatchdog]);

  const latch = useCallback(() => {
    latchedRef.current = true;
  }, []);

  const run = useCallback(
    (...args: A) => {
      if (pendingRef.current || latchedRef.current) return;
      pendingRef.current = true;
      invokerRef.current =
        typeof document !== "undefined" &&
        document.activeElement instanceof HTMLElement
          ? document.activeElement
          : null;
      setError(null);
      setPending(true);
      const episode = ++episodeRef.current;
      clearWatchdog();
      watchdogRef.current = setTimeout(() => {
        watchdogRef.current = null;
        if (episode !== episodeRef.current) return;
        const latched = latchedRef.current;
        reportSilentFallback(null, {
          feature: "ui-action-feedback",
          // A latched episode that outlives the horizon is the higher-severity
          // class — the promised teardown never arrived — so it gets its own
          // op for queryable separation from a plain hung action.
          op: latched ? "pending-watchdog-latch-held" : "pending-watchdog",
          extra: { latched: String(latched) },
          message: latched
            ? `usePendingAction latched pending exceeded ${PENDING_WATCHDOG_MS}ms — teardown never arrived`
            : `usePendingAction pending exceeded ${PENDING_WATCHDOG_MS}ms — hung action`,
        });
        // A latched episode is NOT released — the promised document teardown
        // may still be in flight, and re-enabling in that gap reopens the
        // double-submit window the latch exists to close.
        if (!latched) {
          pendingRef.current = false;
          setPending(false);
        }
      }, PENDING_WATCHDOG_MS);

      // The transition's own isPending is deliberately discarded — `pending`
      // is the episode state (covers the whole async flight), not the render
      // window; the transition exists so asyncFn's internal state updates
      // can't trigger a Suspense fallback mid-flight.
      startTransition(async () => {
        let failed = false;
        try {
          await asyncFn(...args);
        } catch (err) {
          failed = true;
          // Superseded zombie: don't surface a stale error over the current
          // episode.
          if (episode === episodeRef.current) {
            setError(err instanceof Error ? err : new Error(String(err)));
          }
        } finally {
          // Guarded block, not a `return` — a ReturnStatement inside finally
          // swallows a pending throw (no-unsafe-finally).
          if (episode === episodeRef.current) {
            // A failed episode always releases — the user must be able to
            // retry, and a failed episode is definitionally non-terminal so
            // the latch resets too (otherwise the control renders enabled
            // while run() no-ops forever — a dead-looking button, worse than
            // a disabled one). A latched-and-resolved episode keeps pending
            // through teardown and keeps the watchdog armed, so a latch()
            // whose navigation never lands still produces a Sentry signal.
            if (failed || !latchedRef.current) {
              if (failed) latchedRef.current = false;
              release();
            }
          }
        }
      });
    },
    [asyncFn, clearWatchdog, release],
  );

  return { run, pending, error, latch };
}
