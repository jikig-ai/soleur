import { createClient } from "@supabase/supabase-js";

// `mirrorWithDebounce` is intentionally lazy-imported inside
// probeHookRegistration() — pulling @/server/observability at module
// load adds ~3s to vitest's resetModules() cycle in unit tests
// (pino + sentry init). The probe only fires once per process in
// production NODE_ENV, so the import cost is paid then.

const DEV_PLACEHOLDER_URL = "https://placeholder.supabase.co";
let warnedMissing = false;

/**
 * One-shot probe of the Supabase project's Custom Access Token Hook
 * registration (#3363 Resolution C, plan §2.8). Fires on the first
 * getServiceClient() call in production NODE_ENV.
 *
 * The hook (public.runtime_jwt_mint_hook, migration 047) injects the
 * precheck-issued jti/exp/iat/aud into runtime JWTs. If the hook is
 * unregistered (rollback, fresh-project drift, Mgmt API misconfig),
 * verifyOtp returns JWTs missing those claims and tenant.ts:mintFounderJwt
 * throws RuntimeAuthError({cause:"jwt_mint"}) — first-mint-time defense.
 * This probe gives operators an earlier Sentry signal at process boot.
 *
 * Soft-fail design: if SUPABASE_MGMT_API_TOKEN is not present in the Node
 * runtime env (typical for prd — the Mgmt API token is plan-phase only),
 * the probe skips silently. Mint-time defense remains active.
 *
 * Fires once per process — guarded by `hookProbeFired` flag.
 */
let hookProbeFired = false;

async function probeHookRegistration(): Promise<void> {
  if (hookProbeFired) return;
  hookProbeFired = true;

  if (process.env.NODE_ENV !== "production") return;

  const mgmtToken = process.env.SUPABASE_MGMT_API_TOKEN;
  if (!mgmtToken) {
    // Runtime env intentionally doesn't hold the Mgmt API token (plan-phase
    // only). Mint-time defense in tenant.ts:mintFounderJwt catches an
    // unregistered hook via the decodeJwtPayloadUnsafe jti check.
    return;
  }

  // Lazy-import — see top-of-file note. Only paid in production NODE_ENV
  // with the Mgmt API token present.
  const { mirrorWithDebounce } = await import("@/server/observability");

  const url = serverUrl();
  // Parse the project ref from "https://<ref>.supabase.co/...".
  const refMatch = url.match(/^https:\/\/([^.]+)\.supabase\.co/i);
  const projectRef = refMatch?.[1];
  if (!projectRef) {
    mirrorWithDebounce(
      new Error("hook_probe: cannot parse project ref from SUPABASE_URL"),
      { feature: "tenant-jwt", op: "hook_probe.parse_error", extra: { url } },
      "system",
      "hook_probe.parse_error",
    );
    return;
  }

  try {
    const resp = await fetch(
      `https://api.supabase.com/v1/projects/${projectRef}/config/auth`,
      { headers: { Authorization: `Bearer ${mgmtToken}` } },
    );
    if (!resp.ok) {
      mirrorWithDebounce(
        new Error(`hook_probe: Mgmt API ${resp.status}`),
        {
          feature: "tenant-jwt",
          op: "hook_probe.fetch_error",
          extra: { projectRef, status: resp.status },
        },
        "system",
        "hook_probe.fetch_error",
      );
      return;
    }
    const cfg: {
      hook_custom_access_token_enabled?: boolean;
      hook_custom_access_token_uri?: string;
    } = await resp.json();
    const enabled = cfg.hook_custom_access_token_enabled === true;
    const uri = cfg.hook_custom_access_token_uri ?? "";
    const expected = "pg-functions://postgres/public/runtime_jwt_mint_hook";
    if (!enabled || uri !== expected) {
      mirrorWithDebounce(
        new Error("hook_unregistered_at_startup"),
        {
          feature: "tenant-jwt",
          op: "hook_unregistered_at_startup",
          extra: { projectRef, enabled, uri, expected },
        },
        "system",
        "hook_unregistered_at_startup",
      );
      // Hard-fail per plan §2.8 — operator should restart only after
      // re-registering the hook. process.exit kills the worker; the
      // process supervisor restarts and the probe re-fires.
      // eslint-disable-next-line no-console -- intentional crash log
      console.error(
        "[supabase] hook_unregistered_at_startup: runtime_jwt_mint_hook " +
          `not registered on project ${projectRef} ` +
          "(see #3363 Deploy-Order Runbook §c)",
      );
      process.exit(1);
    }
  } catch (err) {
    mirrorWithDebounce(
      err,
      { feature: "tenant-jwt", op: "hook_probe.network_error" },
      "system",
      "hook_probe.network_error",
    );
  }
}

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
 * Service-role usage is privileged — it bypasses RLS. Consult the
 * `.service-role-allowlist` gate (added in PR-B) before introducing new
 * call sites; most surfaces should use a per-tenant JWT-scoped client
 * instead.
 *
 * @deprecated for new code. Prefer {@link getServiceClient} — the lazy
 *   memoized accessor is the canonical entry point for new call sites
 *   (see #2962). `createServiceClient` is retained for existing callers
 *   that wrap their own per-module memoization (agent-runner.ts,
 *   cc-dispatcher.ts, ws-handler.ts, conversation-writer.ts); migrating
 *   those is part of the tenant-isolation rollout (PR-B / PR-C).
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
    // Fire-and-forget: probe runtime_jwt_mint_hook registration on first
    // service-client construction. See probeHookRegistration() above for
    // the soft-fail vs hard-fail decision matrix. Catch errors so an
    // unhandled rejection at boot doesn't crash the process — the probe
    // itself logs to Sentry via mirrorWithDebounce.
    void probeHookRegistration().catch(() => {});
  }
  return serviceClientSingleton;
}
