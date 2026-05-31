"use client";

import { useCallback, useState } from "react";
import {
  reportSilentFallback,
  warnSilentFallback,
} from "@/lib/client-observability";

/**
 * Shared reconnect action for the #4712 affordance. Drives a real GitHub-App
 * re-auth via the already-existing `/api/repo/detect-installation` →
 * `/connect-repo` fallback.
 *
 * On `reconnect()`:
 *  - POST `/api/repo/detect-installation`.
 *  - `{ installed: true }`  → call `onReconnected()` (surface-specific refresh).
 *  - `{ installed: false }` / non-200 / thrown → fall LOUD to both the user
 *    (redirect to `/connect-repo`) AND ops (client-observability → Sentry)
 *    before redirecting; persist `soleur_return_to` so the post-OAuth
 *    `consumeReturnTo` lands the user back where they froze.
 *
 * No `.catch(noop)` — every branch is code-traced.
 */
export function useReconnect(onReconnected: () => void): {
  reconnect: () => Promise<void>;
  isPending: boolean;
} {
  const [isPending, setIsPending] = useState(false);

  const reconnect = useCallback(async () => {
    setIsPending(true);
    try {
      const res = await fetch("/api/repo/detect-installation", {
        method: "POST",
      });

      if (res.ok) {
        const data = (await res.json()) as { installed?: boolean };
        if (data.installed === true) {
          onReconnected();
          return;
        }
        // Clean `{ installed: false }` — expected re-auth path. WARN level so
        // the redirect rate is queryable in Sentry without paging ops.
        warnSilentFallback(
          new Error("detect-installation returned installed:false"),
          { feature: "kb-reconnect", op: "detect-installation-fallback" },
        );
      } else {
        warnSilentFallback(
          new Error(`detect-installation returned HTTP ${res.status}`),
          { feature: "kb-reconnect", op: "detect-installation-fallback" },
        );
      }
      redirectToConnectRepo();
    } catch (err) {
      // Thrown / network error — ERROR level (unexpected).
      reportSilentFallback(err, {
        feature: "kb-reconnect",
        op: "detect-installation-fallback",
      });
      redirectToConnectRepo();
    } finally {
      setIsPending(false);
    }
  }, [onReconnected]);

  return { reconnect, isPending };
}

function redirectToConnectRepo(): void {
  // Pass `pathname` only (not href/search) so `safeReturnTo`'s allowlist
  // (`/dashboard` prefix, rejects `..`/`//`) passes. The query param alone is
  // dropped on the auto-detect path, so persist to sessionStorage too.
  const returnTo = window.location.pathname;
  // Non-essential nicety: persist where to land post-OAuth. In Safari private
  // mode `setItem` throws (QuotaExceededError); swallow it so the throw can
  // never preempt the essential redirect below (#4712 dead-button guard).
  try {
    sessionStorage.setItem("soleur_return_to", returnTo);
  } catch {
    /* storage unavailable — return_to is a nicety; redirect is essential */
  }
  window.location.assign(
    "/connect-repo?return_to=" + encodeURIComponent(returnTo),
  );
}
