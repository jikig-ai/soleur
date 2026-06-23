"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
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
 * Sentry, then router.push("/login") runs unconditionally in finally. When
 * the server signOut fails (network blip or 5xx) the local cookies/storage
 * may still be valid — we follow up with `signOut({ scope: "local" })` to
 * force-clear local state and close the shared-device leak named in the
 * plan's User-Brand Impact section.
 */
export function useSignOut() {
  const router = useRouter();
  const { mutate } = useSWRConfig();
  const [isSigningOut, setIsSigningOut] = useState(false);

  // Defense-in-depth (ADR-067 FR4): clear the in-memory SWR cache on ANY
  // SIGNED_OUT auth transition, not just the explicit button path below —
  // covers token expiry and a sign-out triggered in another tab. The explicit
  // clear in `handleSignOut`'s finally is the load-bearing, awaited guarantee
  // (it runs BEFORE navigation); this listener is the belt-and-suspenders catch
  // for sign-outs that don't route through that handler.
  useEffect(() => {
    const supabase = createClient();
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event) => {
      if (event === "SIGNED_OUT") {
        void clearSwrCache(mutate).catch((err) => {
          reportSilentFallback(err, {
            feature: "auth",
            op: "signOut",
            extra: { stage: "onAuthStateChange.clearSwrCache" },
          });
        });
      }
    });
    return () => subscription.unsubscribe();
  }, [mutate]);

  const handleSignOut = useCallback(async () => {
    setIsSigningOut(true);
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
      // principal's first paint — closes the cross-user leak window that a soft
      // router.push("/login") would otherwise leave open.
      try {
        await clearSwrCache(mutate);
      } catch (err) {
        reportSilentFallback(err, {
          feature: "auth",
          op: "signOut",
          extra: { stage: "clearSwrCache" },
        });
      }
      router.push("/login");
      // Do NOT setIsSigningOut(false): the route push unmounts the layout
      // and the unmount IS the reset. Resetting here briefly re-enables
      // the Sign out button between navigation start and unmount.
    }
  }, [router, mutate]);

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
