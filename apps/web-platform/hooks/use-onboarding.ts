"use client";

import { useState, useRef, useEffect, useCallback } from "react";
import { createClient } from "@/lib/supabase/client";

/**
 * Encapsulates onboarding state management: fetch, display, complete, PWA dismiss.
 *
 * Improvements over inline implementation (PR #1451):
 * - Stores the initial getUser() result in a ref to avoid duplicate calls
 * - Extracts updateUserField() helper for the repeated Supabase update pattern
 * - Separates onboarding concerns from the dashboard page layout
 */
export function useOnboarding() {
  const [onboardingLoaded, setOnboardingLoaded] = useState(false);
  const [showOnboarding, setShowOnboarding] = useState(false);
  const [pwaDismissed, setPwaDismissed] = useState(true); // default hidden until fetch
  const userIdRef = useRef<string | null>(null);

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
          if (error) console.error(`[onboarding] ${field} update error:`, error.message);
        });
    },
    [],
  );

  // Fetch onboarding state on mount, store user ID for later reuse
  useEffect(() => {
    const supabase = createClient();
    supabase.auth.getUser().then(({ data: { user } }) => {
      if (!user) {
        setOnboardingLoaded(true);
        return;
      }
      userIdRef.current = user.id;
      supabase
        .from("users")
        .select("onboarding_completed_at, pwa_banner_dismissed_at")
        .eq("id", user.id)
        .single()
        .then(({ data, error }) => {
          if (error) {
            console.error("[onboarding] fetch error:", error.message);
          } else if (data) {
            if (!data.onboarding_completed_at) setShowOnboarding(true);
            setPwaDismissed(!!data.pwa_banner_dismissed_at);
          }
          setOnboardingLoaded(true);
        });
    });
  }, []);

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

  return {
    onboardingLoaded,
    showOnboarding,
    pwaDismissed,
    completeOnboarding,
    dismissPwaBanner,
  };
}
