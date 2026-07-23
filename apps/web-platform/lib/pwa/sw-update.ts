// Service-worker update-lifecycle helpers.
//
// The service worker (public/sw.js) no longer calls skipWaiting() on install —
// a new version installs and then WAITS. These helpers detect the waiting
// worker, tell it to activate when the user accepts, and reload the page once
// (guarded) when the new worker takes control.

export type WaitingListener = (worker: ServiceWorker) => void;

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

  const onUpdateFound = () => {
    const installing = registration.installing;
    if (!installing) return;
    installing.addEventListener("statechange", () => {
      if (installing.state === "installed" && navigator.serviceWorker.controller) {
        // registration.waiting is the newly-installed worker at this point.
        onUpdate(registration.waiting ?? installing);
      }
    });
  };

  registration.addEventListener("updatefound", onUpdateFound);
  return () => registration.removeEventListener("updatefound", onUpdateFound);
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
  const handler = () => {
    if (reloaded) return;
    reloaded = true;
    reload();
  };
  container.addEventListener("controllerchange", handler);
  return () => container.removeEventListener("controllerchange", handler);
}
