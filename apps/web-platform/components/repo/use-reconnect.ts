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
 * FIX 1b (reconnect recovery) — when `options.repoStatus !== "ready"` and a
 * connected `options.repoUrl` is present, the button does what its own error
 * copy promises: after `detect-installation { installed:true }`, it confirms
 * the connected repo is reachable (in the returned repo list), issues the
 * canonical `POST /api/repo/setup { repoUrl }` (wipe-and-reclone), then polls
 * `GET /api/repo/status` until terminal (`ready` → `onReconnected`; `error` →
 * surface a terminal actionable state via `resetupError`). Without the poll the
 * recovery would be invisible (spinner-forever), since only the Settings card
 * renders a static server snapshot. The poll is bounded (max attempts +
 * interval), mirroring `connect-repo/page.tsx`.
 *
 * No `.catch(noop)` — every branch is code-traced. A setup-POST failure falls
 * LOUD via the browser Sentry SDK (`reportSilentFallback`, tagged
 * `feature:kb-reconnect op:reconnect-resetup`) but STILL resolves so the button
 * is never dead (#4712).
 */

export type ReconnectRepoStatus =
  | "not_connected"
  | "ready"
  | "error"
  | "cloning";

export interface UseReconnectOptions {
  /** The connected repo URL (e.g. `https://github.com/owner/repo`). */
  repoUrl: string | null;
  /** The current persisted repo status (server snapshot). */
  repoStatus: ReconnectRepoStatus;
  /** Bounded status-poll interval. Default 2000ms (matches connect-repo). */
  pollIntervalMs?: number;
  /** Bounded status-poll attempt cap. Default 60 (≈2min at 2s). */
  maxPollAttempts?: number;
}

interface UseReconnectResult {
  reconnect: () => Promise<void>;
  isPending: boolean;
  /**
   * True once a re-setup poll reached a terminal `error` (the background clone
   * failed). The surface renders an actionable terminal state instead of a
   * spinner-forever. Reset to false on the next `reconnect()`.
   */
  resetupError: boolean;
}

const DEFAULT_POLL_INTERVAL_MS = 2000;
const DEFAULT_MAX_POLL_ATTEMPTS = 60;

export function useReconnect(
  onReconnected: () => void,
  options?: UseReconnectOptions,
): UseReconnectResult {
  const [isPending, setIsPending] = useState(false);
  const [resetupError, setResetupError] = useState(false);

  const reconnect = useCallback(async () => {
    setIsPending(true);
    setResetupError(false);
    try {
      const res = await fetch("/api/repo/detect-installation", {
        method: "POST",
      });

      if (res.ok) {
        const data = (await res.json()) as {
          installed?: boolean;
          repos?: Array<{ fullName: string }>;
        };
        if (data.installed === true) {
          // FIX 1b — re-setup path. Only when the surface supplied a connected
          // repo AND the persisted status is not already `ready`.
          if (
            options &&
            options.repoUrl &&
            options.repoStatus !== "ready"
          ) {
            const handled = await attemptResetup(
              options.repoUrl,
              data.repos ?? [],
              {
                pollIntervalMs:
                  options.pollIntervalMs ?? DEFAULT_POLL_INTERVAL_MS,
                maxPollAttempts:
                  options.maxPollAttempts ?? DEFAULT_MAX_POLL_ATTEMPTS,
                onReady: onReconnected,
                onResetupError: () => setResetupError(true),
              },
            );
            // `handled === false` → reachability guard failed (repo not in the
            // installation's reachable set); fall through to the connect-repo
            // redirect so the user can re-select the repo.
            if (handled) return;
            redirectToConnectRepo();
            return;
          }
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
  }, [onReconnected, options]);

  return { reconnect, isPending, resetupError };
}

/**
 * Convert a connected `repoUrl` to its `owner/repo` slug for matching against
 * the `detect-installation` repo list (whose entries carry `fullName`).
 */
function repoUrlToFullName(repoUrl: string): string | null {
  const match = repoUrl.match(/github\.com\/([^/]+\/[^/]+?)\/?$/);
  return match?.[1] ?? null;
}

interface ResetupHandlers {
  pollIntervalMs: number;
  maxPollAttempts: number;
  onReady: () => void;
  onResetupError: () => void;
}

/**
 * The FIX 1b re-setup flow. Returns:
 *  - `true`  — handled (setup issued + poll ran, OR a setup failure was
 *    reported loud and surfaced; the button is done, no connect-repo redirect).
 *  - `false` — the reachability guard rejected (connected repo not in the
 *    installation's reachable list); the caller redirects to `/connect-repo`.
 *
 * Never throws — a setup-POST failure is reported via the client Sentry SDK and
 * surfaced as a terminal `resetupError` so the button is never dead (#4712).
 */
async function attemptResetup(
  repoUrl: string,
  repos: Array<{ fullName: string }>,
  handlers: ResetupHandlers,
): Promise<boolean> {
  // Reachability guard (spec-flow P2): detect aggregates the reachable set, but
  // does not prove THIS repo is covered. If absent, the repo must be
  // re-selected — redirect to /connect-repo rather than POST a 400/403 setup.
  const fullName = repoUrlToFullName(repoUrl);
  const reachable =
    fullName != null && repos.some((r) => r.fullName === fullName);
  if (!reachable) return false;

  try {
    const res = await fetch("/api/repo/setup", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ repoUrl }),
    });
    if (!res.ok) {
      // Fall LOUD via the browser Sentry SDK (server reportSilentFallback is
      // server-only). Still resolve — no dead button (#4712).
      reportSilentFallback(
        new Error(`/api/repo/setup returned HTTP ${res.status}`),
        { feature: "kb-reconnect", op: "reconnect-resetup" },
      );
      handlers.onResetupError();
      return true;
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "kb-reconnect",
      op: "reconnect-resetup",
    });
    handlers.onResetupError();
    return true;
  }

  // Bounded poll until terminal (mirrors connect-repo/page.tsx's poll shape).
  await pollStatusToTerminal(handlers);
  return true;
}

/**
 * Poll `GET /api/repo/status` until it reports a terminal `ready`/`error`, or
 * the bounded attempt cap is hit (treated as a soft error — actionable state,
 * never spinner-forever). Network blips keep polling.
 */
async function pollStatusToTerminal(handlers: ResetupHandlers): Promise<void> {
  const { pollIntervalMs, maxPollAttempts, onReady, onResetupError } = handlers;
  for (let attempt = 0; attempt < maxPollAttempts; attempt++) {
    if (pollIntervalMs > 0) {
      await new Promise((r) => setTimeout(r, pollIntervalMs));
    }
    let status: string | undefined;
    try {
      const res = await fetch("/api/repo/status");
      if (res.ok) {
        const data = (await res.json()) as { status?: string };
        status = data.status;
      }
    } catch {
      // Network blip — keep polling.
      continue;
    }
    if (status === "ready") {
      onReady();
      return;
    }
    if (status === "error") {
      onResetupError();
      return;
    }
    // `cloning` / transient — keep polling.
  }
  // Exhausted attempts without a terminal state — surface an actionable state
  // rather than leaving the spinner forever.
  onResetupError();
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
