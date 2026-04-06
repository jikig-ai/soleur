import { createClient } from "@supabase/supabase-js";

/** Server-side Supabase URL: prefer direct project URL over custom domain. */
export function serverUrl(): string {
  return process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL!;
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
