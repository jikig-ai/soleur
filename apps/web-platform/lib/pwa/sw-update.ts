// Service-worker update-lifecycle helpers.
//
// Observability layer 3 (browser). Until #7084 this whole path was unobservable:
// no Sentry, no logger, anywhere in sw-update.ts or pwa-controls.tsx. A user could
// click Reload and have nothing happen — the waiting worker never activating, the
// page never reloading — and neither the user nor the operator would learn anything.
// `watchUpdateAcceptance` closes that: an accepted update that produces no
// `controllerchange` inside a bounded window reports to Sentry.
//
// The service worker (public/sw.js) no longer calls skipWaiting() on install —
// a new version installs and then WAITS. These helpers detect the waiting
// worker, tell it to activate when the user accepts, and reload the page once
// (guarded) when the new worker takes control.

import { reportSilentFallback } from "@/lib/client-observability";

export type WaitingListener = (worker: ServiceWorker) => void;

/**
 * How long an accepted update may take to produce a `controllerchange` before we
 * treat it as stuck. Generous: skipWaiting → activate → claim is normally well
 * under a second, but a slow device mid-activation should not page anyone.
 */
export const UPDATE_ACCEPT_TIMEOUT_MS = 10_000;

/**
 * Watch a registration for a waiting worker (a new SW version that installed
 * but has not yet activated because it is waiting for the current one to be
 * released). Fires `onUpdate` with the waiting worker:
 *   - immediately, if one is already waiting when this is called, and
 *   - on `updatefound` → the new worker reaching `installed` while a controller
 *     is already active (the "there was already a worker, so this is an update"
 *     signal — a first install has no controller yet and must NOT prompt).
 * Returns an unsubscribe function.
 */
export function watchForUpdate(
  registration: ServiceWorkerRegistration,
  onUpdate: WaitingListener,
): () => void {
  if (registration.waiting && navigator.serviceWorker.controller) {
    onUpdate(registration.waiting);
  }

  // Track the installing worker + its statechange handler so the unsubscribe can
  // detach BOTH listeners (the returned cleanup must honor "detaches everything").
  let installingWorker: ServiceWorker | null = null;
  let onStateChange: (() => void) | null = null;

  const onUpdateFound = () => {
    const installing = registration.installing;
    if (!installing) return;
    installingWorker = installing;
    onStateChange = () => {
      if (installing.state === "installed" && navigator.serviceWorker.controller) {
        // registration.waiting is the newly-installed worker at this point.
        onUpdate(registration.waiting ?? installing);
      }
    };
    installing.addEventListener("statechange", onStateChange);
  };

  registration.addEventListener("updatefound", onUpdateFound);
  return () => {
    registration.removeEventListener("updatefound", onUpdateFound);
    if (installingWorker && onStateChange) {
      installingWorker.removeEventListener("statechange", onStateChange);
    }
  };
}

/** Ask the waiting worker to activate (it calls self.skipWaiting()). */
export function postSkipWaiting(worker: ServiceWorker): void {
  worker.postMessage({ type: "SKIP_WAITING" });
}

/**
 * Reload the page exactly once when the active service worker changes
 * (i.e. the new worker took control after skipWaiting). The reload is guarded
 * so a browser that fires `controllerchange` more than once cannot loop.
 * `container` and `reload` are injectable for testing.
 * Returns an unsubscribe function.
 */
export function reloadOnControllerChange(
  container: ServiceWorkerContainer = navigator.serviceWorker,
  reload: () => void = () => window.location.reload(),
): () => void {
  let reloaded = false;
  // On a FIRST, uncontrolled visit the initial activate → clients.claim() fires
  // a `controllerchange` on this page. That is NOT an update taking over — it's
  // the initial claim — and must be consumed WITHOUT reloading, or every new
  // visitor gets a spurious full-page reload on first load. Only reload when a
  // controller already existed when we started watching (a genuine update).
  const hadController = Boolean(container.controller);
  const handler = () => {
    if (reloaded) return;
    reloaded = true;
    if (hadController) reload();
  };
  container.addEventListener("controllerchange", handler);
  return () => container.removeEventListener("controllerchange", handler);
}

/**
 * Report when an accepted update never takes effect.
 *
 * Call immediately after `postSkipWaiting`. If `controllerchange` does not fire within
 * `timeoutMs`, the update is stuck — the user clicked Reload and the app did not
 * update — and that is reported to Sentry under `feature: "pwa-update"`,
 * `op: "accept-timeout"`. A cleared timer on success means the healthy path is silent.
 *
 * Returns an unsubscribe function; calling it cancels the watchdog (used when the
 * component unmounts before either outcome).
 *
 * `container`, `setTimer` and `clearTimer` are injectable so the existing
 * makeContainer/fire harness in test/pwa/sw-update.test.ts can drive both arms without
 * real timers.
 */
export function watchUpdateAcceptance(
  container: ServiceWorkerContainer = navigator.serviceWorker,
  timeoutMs: number = UPDATE_ACCEPT_TIMEOUT_MS,
  setTimer: (fn: () => void, ms: number) => unknown = (fn, ms) => setTimeout(fn, ms),
  clearTimer: (handle: unknown) => void = (h) => clearTimeout(h as ReturnType<typeof setTimeout>),
): () => void {
  let settled = false;

  const onControllerChange = () => {
    if (settled) return;
    settled = true;
    clearTimer(handle);
    container.removeEventListener("controllerchange", onControllerChange);
  };

  const handle = setTimer(() => {
    if (settled) return;
    settled = true;
    container.removeEventListener("controllerchange", onControllerChange);
    reportSilentFallback(
      new Error("pwa update accepted but no controllerchange within timeout"),
      {
        feature: "pwa-update",
        op: "accept-timeout",
        extra: { timeoutMs, hadController: Boolean(container.controller) },
      },
    );
  }, timeoutMs);

  container.addEventListener("controllerchange", onControllerChange);

  return () => {
    if (settled) return;
    settled = true;
    clearTimer(handle);
    container.removeEventListener("controllerchange", onControllerChange);
  };
}
