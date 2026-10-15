// #9545 PR1 / ADR-288 — ingest of the egress gateway's 15-minute rollup.
//
// Caller: the Vector sink on the same host (POST /api/internal/egress-audit-ingest, a
// JSON array of closed buckets). Everything the route does is ordered so that no input
// can make Vector retry forever and so that the only thing a caller learns is "401":
//
//   1. loopback Host and no forwarding header        -> 401 (the app is published on
//      0.0.0.0:3000 and reachable through Cloudflare; a request that came through a
//      proxy carries X-Forwarded-For / CF-Connecting-IP and is not Vector)
//   2. no configured secret                          -> 2xx drop (never 5xx)
//   3. wrong or missing bearer (current OR previous) -> 401
//   4. body cap / JSON / zod                         -> 413 / 400
//   5. per-row bucket bounds                         -> rows dropped and counted
//   6. workspace -> organisation, one query          -> unknown workspaces dropped
//   7. runtime flag, evaluated PER ORG               -> rows of orgs with it off dropped
//   8. ingest_egress_audit_rollup RPC                -> 5xx only on a database error
//
// The flag is evaluated per organisation (ruled by the CTO agent) because collection
// stays off for every external workspace until PR2 and only a Jikigai-owned canary org
// is enabled, through a per-org segment override that a route-level global read could
// not see. Fail-closed throughout: a flag error drops the rows, it never stores them.
//
// Mirrors carry reason codes and counts only, never a host or workspace value.

import { createHash, timingSafeEqual } from "node:crypto";
import { z } from "zod";
import { createServiceClient } from "@/lib/supabase/service";
import { getRuntimeFlag } from "@/lib/feature-flags/server";
import { mirrorWarnWithDebounce, reportSilentFallback } from "@/server/observability";

const FEATURE = "egress-audit-ingest";
const FLAG = "egress-audit-collection" as const;

export const MAX_BODY_BYTES = 512 * 1024;
export const MAX_ROWS = 500;
const BUCKET_RETENTION_MS = 30 * 86_400_000;
// One bucket plus clock skew between the gateway host and the app host.
const BUCKET_FUTURE_MS = 15 * 60_000 + 15 * 60_000;

const LOOPBACK_HOST = /^(127\.0\.0\.1|localhost|\[::1\])(:\d{1,5})?$/i;
// Cloudflare adds the first two on every proxied request; the rest are the usual
// reverse-proxy set. Vector's request carries none of them.
const FORWARDING_HEADERS = [
  "x-forwarded-for",
  "x-forwarded-host",
  "x-forwarded-proto",
  "forwarded",
  "cf-connecting-ip",
  "cf-ray",
  "x-real-ip",
] as const;

const rowSchema = z
  .object({
    workspace_id: z.string().uuid(),
    bucket_start: z.string().datetime(),
    requested_host: z.string().min(1).max(253),
    decision: z.string().min(1).max(32),
    source_host: z.string().regex(/^[a-z0-9][a-z0-9-]{0,62}$/),
    request_count: z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER),
    bytes_out: z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER),
    first_seen: z.string().datetime(),
    last_seen: z.string().datetime(),
  })
  .strict();
const payloadSchema = z.array(rowSchema).max(MAX_ROWS);
type Row = z.infer<typeof rowSchema>;

function json(body: Record<string, unknown>, status: number): Response {
  return Response.json(body, { status });
}

/** Debounced warn: one Sentry event per reason per window, whatever the request rate. */
function mirrorReject(reason: string, extra?: Record<string, unknown>): void {
  mirrorWarnWithDebounce(
    new Error(`egress audit ingest rejected: ${reason}`),
    { feature: FEATURE, op: reason, extra },
    FEATURE,
    reason,
  );
}

function configuredTokens(): string[] {
  const out: string[] = [];
  for (const name of ["EGRESS_AUDIT_INGEST_TOKEN", "EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS"] as const) {
    const v = process.env[name];
    if (v && v.length > 0) out.push(v);
  }
  return out;
}

const digest = (s: string): Buffer => createHash("sha256").update(s, "utf8").digest();

/**
 * Constant-time bearer check against the current and the previous token. Both digests
 * are fixed-length so the comparison leaks neither content nor length, and every
 * configured token is always compared (no early exit on the first match).
 */
function bearerMatches(header: string | null, tokens: string[]): boolean {
  if (!header || !header.startsWith("Bearer ")) return false;
  const presented = digest(header.slice("Bearer ".length));
  let ok = false;
  for (const t of tokens) {
    const eq = timingSafeEqual(presented, digest(t));
    ok = ok || eq;
  }
  return ok;
}

export async function handleEgressAuditIngest(request: Request): Promise<Response> {
  // 1. Surface: loopback Host, no forwarding header.
  const host = request.headers.get("host") ?? "";
  const forwarded = FORWARDING_HEADERS.some((h) => request.headers.has(h));
  if (!LOOPBACK_HOST.test(host) || forwarded) {
    mirrorReject("non-loopback", { forwarded });
    return json({ error: "Unauthorized" }, 401);
  }

  // 2. No secret configured: drop, never 5xx (a 5xx makes Vector retry into a full buffer).
  const tokens = configuredTokens();
  if (tokens.length === 0) {
    mirrorReject("secret-unset");
    return json({ dropped: true }, 202);
  }

  // 3. Bearer.
  if (!bearerMatches(request.headers.get("authorization"), tokens)) {
    mirrorReject("bad-token");
    return json({ error: "Unauthorized" }, 401);
  }

  // 4. Body cap, JSON, schema.
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
    mirrorReject("body-too-large");
    return json({ error: "Payload too large" }, 413);
  }
  let raw: string;
  try {
    raw = await request.text();
  } catch {
    mirrorReject("body-unreadable");
    return json({ error: "Malformed body" }, 400);
  }
  if (raw.length > MAX_BODY_BYTES) {
    mirrorReject("body-too-large");
    return json({ error: "Payload too large" }, 413);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    mirrorReject("malformed-json");
    return json({ error: "Malformed JSON" }, 400);
  }
  const checked = payloadSchema.safeParse(parsed);
  if (!checked.success) {
    mirrorReject("schema", { issues: checked.error.issues.length });
    return json({ error: "Invalid payload" }, 400);
  }

  // 5. Bucket bounds, per row (a buffered backlog after an app outage stays valid).
  const now = Date.now();
  const inBounds: Row[] = [];
  let droppedBounds = 0;
  for (const r of checked.data) {
    const t = Date.parse(r.bucket_start);
    if (t < now - BUCKET_RETENTION_MS || t > now + BUCKET_FUTURE_MS) droppedBounds++;
    else inBounds.push(r);
  }
  if (droppedBounds > 0) mirrorReject("bucket-out-of-bounds", { count: droppedBounds });

  const result = {
    accepted: 0,
    dropped_bounds: droppedBounds,
    skipped_unknown: 0,
    skipped_flag_off: 0,
    skipped_toggle_off: 0,
    skipped_invalid: 0,
  };
  if (inBounds.length === 0) return json(result, 202);

  // 6. Workspace -> organisation, one query for the distinct workspaces.
  const service = createServiceClient();
  const wsIds = [...new Set(inBounds.map((r) => r.workspace_id))];
  const { data: wsRows, error: wsErr } = await service
    .from("workspaces")
    .select("id, organization_id")
    .in("id", wsIds);
  if (wsErr || !wsRows) {
    reportSilentFallback(wsErr ?? new Error("workspace lookup returned no data"), {
      feature: FEATURE,
      op: "workspace-lookup",
      extra: { workspaces: wsIds.length, pgCode: (wsErr as { code?: string } | null)?.code },
    });
    return json({ error: "Temporarily unavailable" }, 503);
  }
  const orgOf = new Map<string, string>(
    (wsRows as { id: string; organization_id: string }[]).map((w) => [w.id, w.organization_id]),
  );

  // 7. Flag, per distinct organisation. A failed evaluation is "off".
  const orgs = [...new Set([...orgOf.values()])];
  const enabled = new Map<string, boolean>();
  await Promise.all(
    orgs.map(async (orgId) => {
      try {
        enabled.set(
          orgId,
          await getRuntimeFlag(FLAG, {
            userId: null,
            role: "prd",
            orgId,
            email: null,
            subscriptionStatus: null,
          }),
        );
      } catch {
        enabled.set(orgId, false);
      }
    }),
  );

  const toWrite: Row[] = [];
  for (const r of inBounds) {
    const org = orgOf.get(r.workspace_id);
    if (!org) result.skipped_unknown++;
    else if (enabled.get(org) !== true) result.skipped_flag_off++;
    else toWrite.push(r);
  }
  if (toWrite.length === 0) return json(result, 202);

  // 8. Write.
  const { data, error } = await service.rpc("ingest_egress_audit_rollup", { p_rows: toWrite });
  if (error) {
    reportSilentFallback(error, {
      feature: FEATURE,
      op: "rpc",
      extra: { rows: toWrite.length, pgCode: (error as { code?: string }).code },
    });
    return json({ error: "Temporarily unavailable" }, 503);
  }
  const counts = (data ?? {}) as Partial<Record<string, number>>;
  result.accepted = counts.accepted ?? 0;
  result.skipped_unknown += counts.skipped_unknown ?? 0;
  result.skipped_toggle_off = counts.skipped_toggle_off ?? 0;
  result.skipped_invalid = counts.skipped_invalid ?? 0;
  return json(result, 202);
}
