import { createBrowserClient } from "@supabase/ssr";
import { reportSilentFallback } from "@/lib/client-observability";
import { assertProdSupabaseUrl } from "./validate-url";
import { assertProdSupabaseAnonKey } from "./validate-anon-key";

const DEV_PLACEHOLDER_URL = "https://placeholder.supabase.co";
const DEV_PLACEHOLDER_KEY = "placeholder-anon-key";
let warnedMissing = false;

// Mirror to Sentry before re-throw — the page may unload before the React
// error boundary's captureException flushes. Fail-closed posture preserved.
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
