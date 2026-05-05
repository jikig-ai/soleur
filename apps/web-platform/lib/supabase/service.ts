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

/**
 * Per-call factory. Each invocation constructs a fresh service-role client.
 *
 * Prefer `getServiceClient` for the lazy-singleton accessor — it memoizes
 * a single instance and is the canonical entry point for new call sites
 * (#2962). `createServiceClient` is retained for existing callers that
 * wrap their own per-module memoization (agent-runner.ts, cc-dispatcher.ts,
 * ws-handler.ts, conversation-writer.ts); migrating those is part of the
 * tenant-isolation rollout (PR-B / PR-C).
 *
 * Service-role usage is privileged — it bypasses RLS. Consult the
 * `.service-role-allowlist` gate (added in PR-B) before introducing new
 * call sites; most surfaces should use a per-tenant JWT-scoped client
 * instead.
 */
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

let serviceClientSingleton: ReturnType<typeof createServiceClient> | null = null;

/**
 * Lazy memoized service-role client. Returns the same instance across every
 * call within a process — safe for read-mostly server code that does not
 * need per-request scoping.
 *
 * Privileged: service-role bypasses RLS. Each new call site must be added
 * to `.service-role-allowlist` (CI gate, PR-B) and reviewed for tenant
 * isolation impact. For user-scoped reads, prefer the per-tenant JWT
 * client added in PR-B (`createTenantClient`).
 */
export function getServiceClient() {
  if (serviceClientSingleton === null) {
    serviceClientSingleton = createServiceClient();
  }
  return serviceClientSingleton;
}
