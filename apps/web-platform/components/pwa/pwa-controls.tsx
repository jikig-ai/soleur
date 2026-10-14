"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import {
  postSkipWaiting,
  reloadOnControllerChange,
  watchForUpdate,
  watchUpdateAcceptance,
} from "@/lib/pwa/sw-update";
import {
  isStandalone,
  isIosSafari,
  watchInstallPrompt,
  type BeforeInstallPromptEvent,
} from "@/lib/pwa/install";

const IOS_CARD_DISMISSED_KEY = "soleur:pwa-ios-card-dismissed";

/**
 * Progressive-enhancement PWA chrome mounted once in the dashboard layout:
 *   - an "Update available" pill when a new service worker is waiting,
 *   - an "Install app" button when the browser offered beforeinstallprompt,
 *   - an iOS "Add to Home Screen" guidance card (iOS Safari only).
 *
 * Renders `null` when already running standalone (installed), and each
 * affordance is independently dismissible. Bottom-anchored and safe-area-aware
 * so it clears the home indicator; z-40 keeps it below modals (z-50).
 */
export function PwaControls() {
  const [standalone, setStandalone] = useState(true); // assume standalone → render nothing until proven otherwise (avoids a flash)
  const [waiting, setWaiting] = useState<ServiceWorker | null>(null);
  const [installPrompt, setInstallPrompt] = useState<BeforeInstallPromptEvent | null>(null);
  const [showIosCard, setShowIosCard] = useState(false);
  const [updateDismissed, setUpdateDismissed] = useState(false);

  useEffect(() => {
    if (isStandalone()) return;
    setStandalone(false);

    // iOS Safari cannot use beforeinstallprompt — offer the Share→A2HS card
    // once per session (until dismissed).
    if (isIosSafari()) {
      const dismissed = sessionStorage.getItem(IOS_CARD_DISMISSED_KEY) === "1";
      if (!dismissed) setShowIosCard(true);
    }

    let cancelled = false;
    const cleanups: Array<() => void> = [];

    // Update lifecycle: watch for a waiting worker + reload once when it takes
    // control after the user accepts.
    if ("serviceWorker" in navigator) {
      cleanups.push(reloadOnControllerChange());
      navigator.serviceWorker.ready
        .then((registration) => {
          // If the effect already cleaned up before `ready` resolved, do not
          // register a listener whose unsubscribe would be orphaned — tear it
          // down immediately instead.
          const unsub = watchForUpdate(registration, (worker) => setWaiting(worker));
          if (cancelled) unsub();
          else cleanups.push(unsub);
        })
        .catch(() => {
          // Non-fatal: no SW → no update affordance.
        });
    }

    // Install lifecycle (Chromium): capture the deferred prompt, hide on install.
    cleanups.push(
      watchInstallPrompt(
        (event) => setInstallPrompt(event),
        () => setInstallPrompt(null),
      ),
    );

    return () => {
      cancelled = true;
      cleanups.forEach((fn) => fn());
    };
  }, []);

  if (standalone) return null;

  const showUpdate = waiting !== null && !updateDismissed;
  const showInstall = installPrompt !== null;

  async function handleInstall() {
    if (!installPrompt) return;
    await installPrompt.prompt();
    // Whatever the outcome, the prompt is single-use — clear it.
    setInstallPrompt(null);
  }

  function handleReload() {
    if (!waiting) return;
    // Watch BEFORE posting: skipWaiting can complete fast enough that a listener
    // attached afterwards misses the controllerchange and reports a false timeout.
    watchUpdateAcceptance();
    postSkipWaiting(waiting);
  }

  function dismissIosCard() {
    setShowIosCard(false);
    try {
      sessionStorage.setItem(IOS_CARD_DISMISSED_KEY, "1");
    } catch {
      // sessionStorage can throw in private mode — dismissal just won't persist.
    }
  }

  return (
    <div
      aria-live="polite"
      className="pointer-events-none fixed inset-x-0 bottom-[calc(1rem+env(safe-area-inset-bottom))] z-40 flex flex-col items-center gap-2 px-4"
    >
      {showUpdate && (
        <div className="pointer-events-auto flex items-center gap-3 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2 px-4 py-2 shadow-lg">
          <span className="text-sm text-soleur-text-primary">Update available</span>
          <Button
            variant="gold"
            type="button"
            onClick={handleReload}
            className="min-h-11"
          >
            Reload
          </Button>
          <Button
            variant="ghost"
            type="button"
            aria-label="Dismiss update notice"
            onClick={() => setUpdateDismissed(true)}
            className="min-h-11 min-w-11"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M18 6 6 18M6 6l12 12" />
            </svg>
          </Button>
        </div>
      )}

      {showInstall && (
        <Button
          variant="outlined"
          type="button"
          onClick={handleInstall}
          // The pill floats over page content — the surface-1 fill must be
          // real, so it rides `style` (a bg-* class loses to the variant's
          // bg-transparent under Tailwind emission order).
          style={{ background: "var(--color-soleur-bg-surface-1)" }}
          className="pointer-events-auto min-h-11 shadow-lg"
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="M12 3v12M7 10l5 5 5-5M5 21h14" />
          </svg>
          Install app
        </Button>
      )}

      {showIosCard && (
        <div className="pointer-events-auto flex max-w-sm items-start gap-3 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-4 py-3 shadow-lg">
          <p className="text-sm text-soleur-text-secondary">
            <span className="font-medium text-soleur-text-primary">Install Soleur:</span> tap the
            Share icon, then <span className="font-medium text-soleur-text-primary">Add to Home Screen</span>.
          </p>
          <Button
            variant="ghost"
            type="button"
            aria-label="Dismiss install guidance"
            onClick={dismissIosCard}
            className="min-h-11 min-w-11 shrink-0 hover:text-soleur-text-primary"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M18 6 6 18M6 6l12 12" />
            </svg>
          </Button>
        </div>
      )}
    </div>
  );
}
