// Cloudflare cache-purge helper for /api/shared/<token> URLs.
//
// Called from server/kb-share.ts::revokeShare immediately after the DB row
// is marked revoked, so a previously-cached 200 response cannot keep
// serving for the s-maxage TTL. See #2568 (security: revoked KB shares
// served from CF edge cache).
//
// Failure modes are mirrored to Sentry via reportSilentFallback under the
// canonical tags `feature: "kb-share"` + `op: "revoke-purge"`. The caller
// maps any non-ok result to a 502 so the operator sees the partial-failure
// state instead of a 200 + silent leak.
//
// SECURITY: APP_ORIGIN is hard-coded to https://app.soleur.ai. Reading
// NEXT_PUBLIC_APP_URL would let a misconfigured preview env purge the
// wrong host (no leak, but a prod misconfig could leave the prod cache
// populated). Hard-coded is safer than env-derived for a security helper.
// Do NOT replace with a configurable value without security review.

import { reportSilentFallback } from "@/server/observability";

export type PurgeResult =
  | { ok: true }
  | { ok: false; error: "missing-config" | "timeout" | "cf-api" | "network" };

const PURGE_TIMEOUT_MS = 5000;
// SECURITY: do NOT replace with process.env — see file header.
const APP_ORIGIN = "https://app.soleur.ai";

// Single source of truth for Sentry tags. Hoisted so a future tag-typo
// in one branch can't silently split a dashboard alert into two filters.
const PURGE_TAG = { feature: "kb-share", op: "revoke-purge" } as const;

export async function purgeSharedToken(token: string): Promise<PurgeResult> {
  const apiToken = process.env.CF_API_TOKEN_PURGE;
  const zoneId = process.env.CF_ZONE_ID;
  if (!apiToken || !zoneId) {
    reportSilentFallback(null, {
      ...PURGE_TAG,
      message: "CF_API_TOKEN_PURGE or CF_ZONE_ID not set",
      extra: { hasToken: !!apiToken, hasZone: !!zoneId },
    });
    return { ok: false, error: "missing-config" };
  }

  const tokenPrefix = token.slice(0, 8);
  const url = `https://api.cloudflare.com/client/v4/zones/${zoneId}/purge_cache`;
  const body = JSON.stringify({ files: [`${APP_ORIGIN}/api/shared/${token}`] });

  // Manual AbortController + setTimeout (rather than AbortSignal.timeout)
  // so vi.useFakeTimers can reliably intercept the abort timer in tests.
  // AbortSignal.timeout uses a runtime-internal timer that vitest does
  // not consistently intercept across Node versions.
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), PURGE_TIMEOUT_MS);

  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiToken}`,
        "Content-Type": "application/json",
      },
      body,
      signal: controller.signal,
    });

    let payload: {
      success?: boolean;
      errors?: Array<{ code: number; message: string }>;
    } = {};
    try {
      payload = await res.json();
    } catch {
      // Non-JSON body (e.g., HTML 5xx from CF edge). Fall through to the
      // ok=false branch so the Sentry message records status + the
      // `success=undefined` signal that distinguishes "parse failed" from
      // "CF returned success=false".
    }

    if (res.ok && payload.success === true) return { ok: true };

    reportSilentFallback(
      new Error(
        `CF purge failed: status=${res.status} success=${payload.success} ` +
          `errors=${JSON.stringify(payload.errors ?? [])}`,
      ),
      {
        ...PURGE_TAG,
        extra: {
          status: res.status,
          errors: payload.errors,
          tokenPrefix,
        },
      },
    );
    return { ok: false, error: "cf-api" };
  } catch (err) {
    if ((err as Error)?.name === "AbortError") {
      reportSilentFallback(err, {
        ...PURGE_TAG,
        extra: { reason: "timeout", tokenPrefix },
      });
      return { ok: false, error: "timeout" };
    }
    reportSilentFallback(err, {
      ...PURGE_TAG,
      extra: { reason: "network", tokenPrefix },
    });
    return { ok: false, error: "network" };
  } finally {
    clearTimeout(timer);
  }
}
