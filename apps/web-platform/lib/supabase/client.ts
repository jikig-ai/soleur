import { createBrowserClient } from "@supabase/ssr";

const DEV_PLACEHOLDER_URL = "https://placeholder.supabase.co";
const DEV_PLACEHOLDER_KEY = "placeholder-anon-key";
let warnedMissing = false;

export function createClient() {
  if (!process.env.NEXT_PUBLIC_SUPABASE_URL) {
    if (process.env.NODE_ENV === "production") {
      throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL");
    }
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
