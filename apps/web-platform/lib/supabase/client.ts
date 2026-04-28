import { createBrowserClient } from "@supabase/ssr";
import { reportSilentFallback } from "@/lib/client-observability";
import { assertProdSupabaseUrl } from "./validate-url";
import { assertProdSupabaseAnonKey } from "./validate-anon-key";

const DEV_PLACEHOLDER_URL = "https://placeholder.supabase.co";
const DEV_PLACEHOLDER_KEY = "placeholder-anon-key";
let warnedMissing = false;

// Validate once at module load. `NEXT_PUBLIC_SUPABASE_URL` and
// `NEXT_PUBLIC_SUPABASE_ANON_KEY` are statically inlined by Next.js
// DefinePlugin, so the values cannot change at runtime — re-validating per
// `createClient()` is wasted work and would emit one Sentry event per call
// site if a bad bundle ships. Throwing here surfaces in the Next.js error
// overlay before any UI tries to mount.
//
// Call order is load-bearing: `assertProdSupabaseUrl` runs first because
// `assertProdSupabaseAnonKey`'s JWT-ref cross-check anchors on the URL's
// canonical first label.
//
// The try/catch is observability-only: it captures a Sentry event with the
// failed-claim context BEFORE re-throwing, so the throw surfaces at Sentry
// even if the React error boundary's own captureException never gets a
// chance to run (page unloads before the queue flushes). The fail-closed
// posture is preserved — the validator throw still aborts module load and
// every authenticated visitor sees the boundary, which is the correct
// security behavior for a service-role-paste scenario.
try {
  assertProdSupabaseUrl(process.env.NEXT_PUBLIC_SUPABASE_URL);
  assertProdSupabaseAnonKey(
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    process.env.NEXT_PUBLIC_SUPABASE_URL,
  );
} catch (err) {
  reportSilentFallback(err, {
    feature: "supabase-validator-throw",
    op: "module-load",
  });
  throw err;
}

export function createClient() {
  if (!process.env.NEXT_PUBLIC_SUPABASE_URL) {
    if (!warnedMissing) {
      warnedMissing = true;
      console.warn(
        "[supabase] Missing NEXT_PUBLIC_SUPABASE_URL — " +
          "browser auth will fail. Run with: doppler run -c dev -- npm run dev",
      );
    }
  }
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL || DEV_PLACEHOLDER_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || DEV_PLACEHOLDER_KEY;
  return createBrowserClient(url, key);
}
