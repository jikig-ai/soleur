"use client";

// feat-guided-tour (#5743): owns tour state, auto-first-run gating, persistence,
// and analytics. Mounted in app/(dashboard)/layout.tsx wrapping the subtree that
// holds <HelpOverlay/> + <SupportLauncher/> (mirrors ShortcutsProvider), so both
// launch surfaces — and the auto-first-run — drive the SAME startTour().
//
// Flag-gated: when `guided-tour` is OFF the provider passes children through with
// an unavailable no-op context (launch points hide) and mounts no overlay.

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
} from "react";
import { usePathname } from "next/navigation";
import { useOptionalFeatureFlag } from "@/components/feature-flags/provider";
import { useOnboarding } from "@/hooks/use-onboarding";
import { track } from "@/lib/analytics-client";
import { RAIL_EXPAND_EVENT } from "@/components/dashboard/rail-slot";
import { GuidedTour } from "./guided-tour";
import { TOUR_STEP_COUNT } from "./tour-steps";

export interface TourContextValue {
  /** True only when the guided-tour flag is on (launch points gate on this). */
  available: boolean;
  active: boolean;
  stepIndex: number;
  startTour: (source?: string) => void;
  next: () => void;
  back: () => void;
  skip: () => void;
  finish: () => void;
}

const NOOP: TourContextValue = {
  available: false,
  active: false,
  stepIndex: 0,
  startTour: () => {},
  next: () => {},
  back: () => {},
  skip: () => {},
  finish: () => {},
};

const TourContext = createContext<TourContextValue | null>(null);

/** Non-throwing: returns a no-op when no provider is mounted (flag-off / tests). */
export function useTour(): TourContextValue {
  return useContext(TourContext) ?? NOOP;
}

export function TourProvider({ children }: { children: React.ReactNode }) {
  const enabled = useOptionalFeatureFlag("guided-tour");
  const pathname = usePathname();
  const { onboardingLoaded, onboardingCompletedAt, tourCompletedAt } =
    useOnboarding();

  const [active, setActive] = useState(false);
  const [stepIndex, setStepIndex] = useState(0);
  // Local suppression so the tour never re-auto-starts once run this session,
  // even before the persisted tour_completed_at round-trips.
  const completedRef = useRef(false);
  const autoStartedRef = useRef(false);

  const persistComplete = useCallback(() => {
    completedRef.current = true;
    // Fire-and-forget; the route mirrors a 0-row/failed write to Sentry. The UI
    // has already closed optimistically — never block or loop on this.
    void fetch("/api/tour/complete", {
      method: "POST",
      headers: { "content-type": "application/json" },
      keepalive: true,
    }).catch(() => {});
  }, []);

  const startTour = useCallback(
    (source = "manual") => {
      if (!enabled) return;
      // Force-expand a collapsed rail so the spotlight targets full-width rows.
      if (typeof window !== "undefined") {
        window.dispatchEvent(new CustomEvent(RAIL_EXPAND_EVENT));
      }
      setStepIndex(0);
      setActive(true);
      track("tour_started", { path: "/dashboard", source });
    },
    [enabled],
  );

  const next = useCallback(() => {
    setStepIndex((i) => {
      const ni = Math.min(i + 1, TOUR_STEP_COUNT - 1);
      track("tour_step_viewed", { path: "/dashboard", step: ni });
      return ni;
    });
  }, []);

  const back = useCallback(() => {
    setStepIndex((i) => Math.max(i - 1, 0));
  }, []);

  const finish = useCallback(() => {
    setActive(false);
    persistComplete();
    track("tour_completed", { path: "/dashboard" });
  }, [persistComplete]);

  const skip = useCallback(() => {
    setActive(false);
    persistComplete();
    track("tour_skipped", { path: "/dashboard", step: stepIndex });
  }, [persistComplete, stepIndex]);

  // Auto-start once: flag on, onboarding loaded, first-run naming already done,
  // tour never completed, on /dashboard, and no blocking modal open. Deferred a
  // tick so a concurrent first-run modal can claim the screen first.
  useEffect(() => {
    if (!enabled || autoStartedRef.current || completedRef.current) return;
    if (!onboardingLoaded) return;
    if (tourCompletedAt) return;
    if (!onboardingCompletedAt) return; // naming/first-run not finished yet
    if (pathname !== "/dashboard") return;
    const t = setTimeout(() => {
      if (autoStartedRef.current || completedRef.current) return;
      // Don't stack on a modal (sign-out, support panel — both aria-modal dialogs).
      if (document.querySelector('[role="dialog"][aria-modal="true"]')) return;
      autoStartedRef.current = true;
      startTour("auto");
    }, 600);
    return () => clearTimeout(t);
  }, [
    enabled,
    onboardingLoaded,
    onboardingCompletedAt,
    tourCompletedAt,
    pathname,
    startTour,
  ]);

  const value: TourContextValue = {
    available: enabled,
    active,
    stepIndex,
    startTour,
    next,
    back,
    skip,
    finish,
  };

  return (
    <TourContext.Provider value={value}>
      {children}
      {enabled && active && (
        <GuidedTour
          stepIndex={stepIndex}
          onNext={next}
          onBack={back}
          onSkip={skip}
          onFinish={finish}
        />
      )}
    </TourContext.Provider>
  );
}
