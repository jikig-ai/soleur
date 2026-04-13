import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { cookies } from "next/headers";

// Re-export serverUrl and createServiceClient from the standalone module.
// Custom server files (ws-handler, agent-runner, etc.) import from
// @/lib/supabase/service directly to avoid pulling in next/headers.
export { serverUrl, createServiceClient } from "./service";

const DEV_PLACEHOLDER_URL = "https://placeholder.supabase.co";
const DEV_PLACEHOLDER_KEY = "placeholder-anon-key";
let warnedMissing = false;

export async function createClient() {
  const cookieStore = await cookies();
  if (!process.env.NEXT_PUBLIC_SUPABASE_URL) {
    if (process.env.NODE_ENV === "production") {
      throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL");
    }
    if (!warnedMissing) {
      warnedMissing = true;
      console.warn(
        "[supabase] Missing NEXT_PUBLIC_SUPABASE_URL — " +
          "server auth will fail. Run with: doppler run -c dev -- npm run dev",
      );
    }
  }
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL || DEV_PLACEHOLDER_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || DEV_PLACEHOLDER_KEY;

  return createServerClient(
    url,
    key,
    {
      cookieOptions: {
        sameSite: "lax" as const, // SECURITY: blocks cross-site cookie transmission
        secure: process.env.NODE_ENV === "production", // SECURITY: HTTPS-only in production
        path: "/",
      },
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(
          cookiesToSet: {
            name: string;
            value: string;
            options: CookieOptions;
          }[],
        ) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options),
            );
          } catch {
            // Server component — can't set cookies
          }
        },
      },
    },
  );
}
