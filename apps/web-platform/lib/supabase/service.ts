import { createClient } from "@supabase/supabase-js";

const DEV_PLACEHOLDER_URL = "https://placeholder.supabase.co";
let warnedMissing = false;

/** Server-side Supabase URL: prefer direct project URL over custom domain. */
export function serverUrl(): string {
  const url = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!url) {
    if (process.env.NODE_ENV === "development") {
      if (!warnedMissing) {
        warnedMissing = true;
        console.warn(
          "[supabase] Missing SUPABASE_URL and NEXT_PUBLIC_SUPABASE_URL — " +
            "Supabase calls will fail. Run with: doppler run -c dev -- npm run dev",
        );
      }
      return DEV_PLACEHOLDER_URL;
    }
    throw new Error("Missing SUPABASE_URL and NEXT_PUBLIC_SUPABASE_URL");
  }
  return url;
}

export function createServiceClient() {
  return createClient(
    serverUrl(),
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    },
  );
}
