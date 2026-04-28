import { createBrowserClient } from "@supabase/ssr";
import { assertProdSupabaseUrl } from "./validate-url";

const DEV_PLACEHOLDER_URL = "https://placeholder.supabase.co";
const DEV_PLACEHOLDER_KEY = "placeholder-anon-key";
let warnedMissing = false;

// Validate once at module load. `NEXT_PUBLIC_SUPABASE_URL` is statically
// inlined by Next.js DefinePlugin, so the value cannot change at runtime —
// re-validating per `createClient()` is wasted work and would emit one Sentry
// event per call site if a bad bundle ships. Throwing here surfaces in the
// Next.js error overlay before any UI tries to mount.
assertProdSupabaseUrl(process.env.NEXT_PUBLIC_SUPABASE_URL);

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
