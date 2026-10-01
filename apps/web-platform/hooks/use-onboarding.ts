"use client";

import { useState, useRef, useEffect, useCallback } from "react";
import useSWR from "swr";
import { createClient } from "@/lib/supabase/client";
import { swrKeys } from "@/lib/swr-config";

/**
 * Encapsulates onboarding state management: fetch, display, complete, PWA dismiss.
 *
 * Improvements over inline implementation (PR #1451):
 * - Stores the resolved user id in a ref to avoid duplicate calls
 * - Extracts updateUserField() helper for the repeated Supabase update pattern
 * - Separates onboarding concerns from the dashboard page layout
 *
 * #9180/#9178 mount-fetch contract: the mount read rides the SHARED SWR key
 * `swrKeys.onboardingState()` — this hook is instantiated by BOTH
 * `dashboard/page.tsx` and `tour-provider.tsx` at every dashboard mount, so a
 * per-instance useEffect fetch issued the same getSession+PostgREST read
 * twice. The shared key makes SWR's in-flight coalescing own the dedup (the
 * PostgREST transport differs from the /api/* census but the duplicate class
 * is identical). Mutations stay fire-and-forget writes + a revalidate.
 */
export function useOnboarding() {
  const [showOnboarding, setShowOnboarding] = useState(false);
  const [pwaDismissed, setPwaDismissed] = useState(true); // default hidden until fetch
  // PR-G (#3947): runtime explainer banner state. Default `true` (hidden)
  // until the fetch confirms `runtime_explainer_dismissed_at IS NULL`,
  // mirroring the pwa-banner pattern above.
  const [runtimeExplainerDismissed, setRuntimeExplainerDismissed] =
    useState(true);
  // feat-guided-tour (#5743): the onboarding-tour completion timestamp and the
  // first-run-onboarding timestamp. Both null until the fetch resolves. The tour
  // auto-starts only when tour_completed_at IS NULL AND onboarding_completed_at is
  // set (i.e. the naming/first-run flow is done) — so the two overlays never stack.
  const [tourCompletedAt, setTourCompletedAt] = useState<string | null>(null);
  const [onboardingCompletedAt, setOnboardingCompletedAt] = useState<
    string | null
  >(null);
  const userIdRef = useRef<string | null>(null);

  const { data, error: swrError, mutate: revalidate } =
    useSWR<OnboardingState | null>(swrKeys.onboardingState(), fetchOnboardingState);

  // `onboardingLoaded` = "initial read settled" — resolved data (incl. the
  // no-user null) OR a settled error. The raw-fetch version always released
  // the latch on error; SWR's error channel carries the same release.
  const onboardingLoaded = data !== undefined || swrError !== undefined;

  // Hydrate the optimistic-overlay state from the shared cache entry. Same
  // re-seed contract as use-team-names: revalidations re-seed server truth.
  useEffect(() => {
    if (!data) return;
    userIdRef.current = data.userId;
    if (!data.onboarding_completed_at) setShowOnboarding(true);
    setOnboardingCompletedAt(data.onboarding_completed_at ?? null);
    setPwaDismissed(!!data.pwa_banner_dismissed_at);
    setRuntimeExplainerDismissed(!!data.runtime_explainer_dismissed_at);
    setTourCompletedAt(data.tour_completed_at ?? null);
  }, [data]);

  useEffect(() => {
    if (swrError) {
      console.error("[onboarding] fetch error:", swrError);
    }
  }, [swrError]);

  /** Fire-and-forget update of a single field on the users table. */
  const updateUserField = useCallback(
    (field: string, value: string) => {
      const userId = userIdRef.current;
      if (!userId) return;
      const supabase = createClient();
      supabase
        .from("users")
        .update({ [field]: value })
        .eq("id", userId)
        .then(({ error }) => {
          if (error) {
            console.error(`[onboarding] ${field} update error:`, error.message);
          } else {
            // Converge the shared key on server truth so BOTH hook instances
            // (page + tour-provider) re-seed from the post-write row.
            void revalidate();
          }
        });
    },
    [revalidate],
  );

  /** Mark onboarding as complete (fire-and-forget). */
  const completeOnboarding = useCallback(() => {
    setShowOnboarding(false);
    updateUserField("onboarding_completed_at", new Date().toISOString());
    console.debug("[onboarding]", "first_message_sent");
  }, [updateUserField]);

  /** Dismiss the PWA install banner (fire-and-forget). */
  const dismissPwaBanner = useCallback(() => {
    setPwaDismissed(true);
    updateUserField("pwa_banner_dismissed_at", new Date().toISOString());
    console.debug("[onboarding]", "pwa_banner_dismissed");
  }, [updateUserField]);

  /** Dismiss the runtime explainer banner (fire-and-forget). PR-G (#3947). */
  const dismissRuntimeExplainer = useCallback(() => {
    setRuntimeExplainerDismissed(true);
    updateUserField(
      "runtime_explainer_dismissed_at",
      new Date().toISOString(),
    );
    console.debug("[onboarding]", "runtime_explainer_dismissed");
  }, [updateUserField]);

  return {
    onboardingLoaded,
    showOnboarding,
    pwaDismissed,
    runtimeExplainerDismissed,
    tourCompletedAt,
    onboardingCompletedAt,
    completeOnboarding,
    dismissPwaBanner,
    dismissRuntimeExplainer,
  };
}

interface OnboardingState {
  userId: string;
  onboarding_completed_at: string | null;
  pwa_banner_dismissed_at: string | null;
  runtime_explainer_dismissed_at: string | null;
  tour_completed_at: string | null;
}

// The mount read: getSession() is the local cookie read — the former
// getUser() was a browser→Supabase RTT for an id-only read (Phase 5);
// authorization stays server-side (middleware + RLS). Errors throw so SWR
// routes the failure to `error` (consumers read last-known/defaults).
async function fetchOnboardingState(): Promise<OnboardingState | null> {
  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  const user = session?.user;
  if (!user) return null;
  const { data, error } = await supabase
    .from("users")
    .select(
      "onboarding_completed_at, pwa_banner_dismissed_at, runtime_explainer_dismissed_at, tour_completed_at",
    )
    .eq("id", user.id)
    .single();
  if (error) throw new Error(error.message);
  return { userId: user.id, ...data };
}
