"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useSWRConfig } from "swr";
import { createClient } from "@/lib/supabase/client";
import { clearSwrCache } from "@/lib/swr-config";
import { reportSilentFallback } from "@/lib/client-observability";

/**
 * Encapsulates the dashboard sign-out teardown contract.
 *
 * Single canonical sign-out call site keeps drift-guard scope (`AUTH_DIRS`
 * in `test/auth/sentry-tag-coverage.test.ts`) tight to `components/auth/`
 * rather than widening to every (dashboard) route.
 *
 * Teardown invariant: removeAllChannels + signOut errors are mirrored to
 * Sentry, then a HARD navigation to /login runs unconditionally in finally.
 * The hard nav (`window.location.assign`, GAP C) — not a soft
 * `router.push` — is load-bearing under ADR-067's Router-Cache staleTimes:
 * a soft push would leave the App Router Router Cache warm, so the next
 * principal on this device could soft-navigate the prior user's cached RSC
 * shell (middleware does not re-run on a cache hit). A full document load is
 * the only Router-Cache wipe. When the server signOut fails (network blip or
 * 5xx) the local cookies/storage may still be valid — we follow up with
 * `signOut({ scope: "local" })` to force-clear local state and close the
 * shared-device leak named in the plan's User-Brand Impact section.
 */
export function useSignOut() {
  const { mutate } = useSWRConfig();
  const [isSigningOut, setIsSigningOut] = useState(false);
  // Set true when THIS tab's button path (handleSignOut) has taken ownership of
  // the sign-out navigation, so the SIGNED_OUT listener below does not fire a
  // SECOND `window.location.assign("/login")` in the same tab. Two rapid assigns
  // to the same URL abort each other's navigation (observable as Playwright's
  // `net::ERR_ABORTED; maybe frame was detached?`), so the button path must own
  // exactly one hard nav. A ref (not state) because the listener reads it
  // synchronously and it must not trigger a re-render.
  const buttonPathNavigatingRef = useRef(false);

  // Defense-in-depth (ADR-067 FR4): clear the in-memory SWR cache AND hard-nav
  // to /login on ANY SIGNED_OUT auth transition, not just the explicit button
  // path below — covers token expiry and a sign-out triggered in another tab
  // (GAP D). A sign-out in tab A fires SIGNED_OUT in sibling tab B; without the
  // hard nav here, tab B keeps its warm Router Cache and a new principal could
  // ride the prior user's cached RSC shell. The explicit clear in
  // `handleSignOut`'s finally is the load-bearing, awaited guarantee for the
  // button path (it runs BEFORE navigation); this listener is the
  // belt-and-suspenders catch (SWR clear + Router-Cache wipe) for sign-outs
  // that don't route through that handler.
  useEffect(() => {
    const supabase = createClient();
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event) => {
      if (event === "SIGNED_OUT") {
        void clearSwrCache(mutate)
          .catch((err) => {
            reportSilentFallback(err, {
              feature: "auth",
              op: "signOut",
              extra: { stage: "onAuthStateChange.clearSwrCache" },
            });
          })
          .finally(() => {
            // GAP D: hard-nav the sibling tab so its Router Cache is wiped too.
            // Skip when THIS tab's button path already owns the nav
            // (`buttonPathNavigatingRef` — avoids the double-assign that aborts
            // the first navigation) OR when the tab is already on /login (a
            // repeat SIGNED_OUT on an already-signed-out sibling). In a sibling
            // tab that did NOT click sign out, the ref is false → it hard-navs.
            if (
              !buttonPathNavigatingRef.current &&
              window.location.pathname !== "/login"
            ) {
              window.location.assign("/login");
            }
          });
      }
    });
    return () => subscription.unsubscribe();
  }, [mutate]);

  const handleSignOut = useCallback(async () => {
    setIsSigningOut(true);
    // Take ownership of the sign-out nav BEFORE `supabase.auth.signOut()` fires
    // SIGNED_OUT, so the listener above suppresses its redundant assign in this
    // tab and the button path performs exactly one hard nav.
    buttonPathNavigatingRef.current = true;
    try {
      const supabase = createClient();
      try {
        await supabase.removeAllChannels();
      } catch (err) {
        reportSilentFallback(err, {
          feature: "auth",
          op: "signOut",
          extra: { stage: "removeAllChannels" },
        });
      }
      try {
        const { error } = await supabase.auth.signOut();
        if (error) {
          reportSilentFallback(error, {
            feature: "auth",
            op: "signOut",
            extra: { stage: "signOut.resultError" },
          });
          await forceLocalSignOut(supabase);
        }
      } catch (err) {
        reportSilentFallback(err, {
          feature: "auth",
          op: "signOut",
          extra: { stage: "signOut.throw" },
        });
        await forceLocalSignOut(supabase);
      }
    } catch (err) {
      reportSilentFallback(err, {
        feature: "auth",
        op: "signOut",
        extra: { stage: "outer.throw" },
      });
    } finally {
      // Clear the in-memory SWR cache BEFORE navigating (FR4, CPO C2, GAP A).
      // Awaited so the module-singleton cache is provably empty before the next
      // principal's first paint — closes the cross-user leak window in the SWR
      // (data) layer.
      try {
        await clearSwrCache(mutate);
      } catch (err) {
        reportSilentFallback(err, {
          feature: "auth",
          op: "signOut",
          extra: { stage: "clearSwrCache" },
        });
      }
      // GAP C (ADR-067 staleTimes amendment): HARD navigation, not a soft
      // router.push. A full document load is the only wipe of the App Router
      // Router Cache; a soft push would leave the prior user's cached RSC shell
      // warm for the next principal on this device (middleware does not re-run
      // on a Router-Cache hit). Mirrors the workspace-switch precedent at
      // components/dashboard/org-switcher-container.tsx.
      window.location.assign("/login");
      // Do NOT setIsSigningOut(false): the document load tears down the layout
      // and that IS the reset. Resetting here briefly re-enables the Sign out
      // button between navigation start and teardown.
    }
  }, [mutate]);

  return { handleSignOut, isSigningOut };
}

async function forceLocalSignOut(
  supabase: ReturnType<typeof createClient>,
): Promise<void> {
  try {
    await supabase.auth.signOut({ scope: "local" });
  } catch (localErr) {
    reportSilentFallback(localErr, {
      feature: "auth",
      op: "signOut",
      extra: { stage: "signOut.localFallback" },
    });
  }
}
