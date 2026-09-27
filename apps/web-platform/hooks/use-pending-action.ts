"use client";

import { useCallback, useEffect, useRef, useState, useTransition } from "react";
import { reportSilentFallback } from "@/lib/client-observability";

export const PENDING_WATCHDOG_MS = 30_000;

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
      clearWatchdog();
      watchdogRef.current = setTimeout(() => {
        watchdogRef.current = null;
        reportSilentFallback(null, {
          feature: "ui-action-feedback",
          op: "pending-watchdog",
          extra: { latched: String(latchedRef.current) },
          message: "usePendingAction pending exceeded 30s — hung action",
        });
        // A latched episode is NOT released — the promised document teardown
        // may still be in flight, and re-enabling in that gap reopens the
        // double-submit window the latch exists to close.
        if (!latchedRef.current) {
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
          setError(err instanceof Error ? err : new Error(String(err)));
        } finally {
          // A failed episode always releases — the user must be able to
          // retry. A latched-and-resolved episode keeps pending through
          // teardown and keeps the watchdog armed, so a latch() whose
          // navigation never lands still produces a Sentry signal.
          if (failed || !latchedRef.current) {
            release();
          }
        }
      });
    },
    [asyncFn, clearWatchdog, release],
  );

  return { run, pending, error, latch };
}
