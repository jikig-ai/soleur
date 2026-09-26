"use client";

import { useCallback, useEffect, useRef, useState, useTransition } from "react";
import { reportSilentFallback } from "@/lib/client-observability";

export const PENDING_WATCHDOG_MS = 30_000;

export type PendingActionOptions = {
  latchOnRedirect?: boolean;
};

export type PendingAction<A extends unknown[]> = {
  run: (...args: A) => void;
  pending: boolean;
  error: Error | null;
  pendingRef: { current: boolean };
};

export function usePendingAction<A extends unknown[] = []>(
  asyncFn: (...args: A) => Promise<unknown> | unknown,
  opts?: PendingActionOptions,
): PendingAction<A> {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const [, startTransition] = useTransition();
  const pendingRef = useRef(false);
  const latchedRef = useRef(false);
  const invokerRef = useRef<HTMLElement | null>(null);
  const watchdogRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const latchOnRedirect = opts?.latchOnRedirect === true;

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
          message: "usePendingAction pending exceeded 30s — hung action",
        });
        if (!latchedRef.current) {
          pendingRef.current = false;
          setPending(false);
        }
      }, PENDING_WATCHDOG_MS);

      startTransition(async () => {
        let succeeded = false;
        try {
          await asyncFn(...args);
          succeeded = true;
        } catch (err) {
          setError(err instanceof Error ? err : new Error(String(err)));
        } finally {
          clearWatchdog();
          if (latchOnRedirect && succeeded) {
            latchedRef.current = true;
          } else {
            release();
          }
        }
      });
    },
    [asyncFn, latchOnRedirect, clearWatchdog, release],
  );

  return { run, pending, error, pendingRef };
}
