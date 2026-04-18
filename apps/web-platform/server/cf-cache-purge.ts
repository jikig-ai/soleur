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
// APP_ORIGIN is hard-coded to https://app.soleur.ai — reading
// NEXT_PUBLIC_APP_URL would let a misconfigured preview env purge the
// wrong host (no leak, but a prod misconfig could leave the prod cache
// populated). Hard-coded is safer than env-derived for a security helper.

import { reportSilentFallback } from "@/server/observability";

export type PurgeResult =
  | { ok: true }
  | { ok: false; error: "missing-config" | "timeout" | "cf-api" | "network" };

const PURGE_TIMEOUT_MS = 5000;
const APP_ORIGIN = "https://app.soleur.ai";

export async function purgeSharedToken(token: string): Promise<PurgeResult> {
  const apiToken = process.env.CF_API_TOKEN_PURGE;
  const zoneId = process.env.CF_ZONE_ID;
  if (!apiToken || !zoneId) {
    reportSilentFallback(null, {
      feature: "kb-share",
      op: "revoke-purge",
      message: "CF_API_TOKEN_PURGE or CF_ZONE_ID not set",
      extra: { hasToken: !!apiToken, hasZone: !!zoneId },
    });
    return { ok: false, error: "missing-config" };
  }

  const tokenPrefix = token.slice(0, 8);
  const url = `https://api.cloudflare.com/client/v4/zones/${zoneId}/purge_cache`;
  const body = JSON.stringify({ files: [`${APP_ORIGIN}/api/shared/${token}`] });

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
      // Plaintext error body (rare) — fall through to ok=false branch.
    }

    if (res.ok && payload.success === true) return { ok: true };

    reportSilentFallback(
      new Error(
        `CF purge failed: status=${res.status} success=${payload.success} ` +
          `errors=${JSON.stringify(payload.errors ?? [])}`,
      ),
      {
        feature: "kb-share",
        op: "revoke-purge",
        extra: {
          status: res.status,
          errors: payload.errors,
          tokenPrefix,
        },
      },
    );
    return { ok: false, error: "cf-api" };
  } catch (err) {
    if ((err as Error).name === "AbortError") {
      reportSilentFallback(err, {
        feature: "kb-share",
        op: "revoke-purge",
        extra: { reason: "timeout", tokenPrefix },
      });
      return { ok: false, error: "timeout" };
    }
    reportSilentFallback(err, {
      feature: "kb-share",
      op: "revoke-purge",
      extra: { reason: "network", tokenPrefix },
    });
    return { ok: false, error: "network" };
  } finally {
    clearTimeout(timer);
  }
}
