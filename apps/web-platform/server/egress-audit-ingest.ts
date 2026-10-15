// #9545 PR1 / ADR-288 — ingest of the egress gateway's 15-minute rollup.
//
// Caller: the Vector sink on the same host (POST /api/internal/egress-audit-ingest, a
// JSON array of closed buckets). Everything the route does is ordered so that no input
// can make Vector retry forever and so that, before the bearer check, a caller learns only "401"
// (the one exception is an unset secret, which answers 202: there is nothing to compare against):
//
//   1. loopback Host and no proxy marker             -> 401 (the app is published on
//      0.0.0.0:3000 and reachable through Cloudflare; a request that came through it
//      carries CF-Ray / CF-Connecting-IP and is not Vector)
//   2. no configured secret                          -> 2xx drop (never 5xx)
//   3. wrong or missing bearer (current OR previous) -> 401
//      3b. the global env mirror of the flag on in production -> 2xx drop (after the bearer, so an
//      unauthenticated caller cannot learn that setting)
//   4. body cap (bytes, streamed) / JSON / array     -> 413 / 400
//   5. per-row zod                                   -> bad rows dropped and counted
//   6. per-row bucket bounds                         -> rows dropped and counted
//   7. workspace -> organisation, chunked queries    -> unknown workspaces dropped
//   8. runtime flag, evaluated PER ORG               -> rows of orgs with it off dropped
//   9. ingest_egress_audit_rollup RPC                -> 5xx only on a database error
//
// Next.js adds x-forwarded-for / -host / -proto / -port to EVERY request it serves (measured on
// 16.3.8, review of PR #10349), so those four are NOT a proxy signal and are not rejected; the
// signals are the Cloudflare headers, `Forwarded`, `X-Real-IP`, and an x-forwarded-for chain
// of more than one hop (Vector's own request arrives with the single hop Next appends).
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
import { mirrorWarnWithDebounce, mirrorWithDebounce } from "@/server/observability";

const FEATURE = "egress-audit-ingest";
const FLAG = "egress-audit-collection" as const;

export const MAX_BODY_BYTES = 512 * 1024;
export const MAX_ROWS = 500;
const BUCKET_RETENTION_MS = 30 * 86_400_000;
// One bucket plus clock skew between the gateway host and the app host.
const BUCKET_FUTURE_MS = 15 * 60_000 + 15 * 60_000;

const LOOPBACK_HOST = /^(127\.0\.0\.1|localhost|\[::1\])(:\d{1,5})?$/i;
// Cloudflare adds the first two on every proxied request; the others are the usual
// reverse-proxy set. Vector's request carries none of them. (x-forwarded-* are added by
// Next.js itself and are handled separately, see the header comment.)
const PROXY_MARKER_HEADERS = ["forwarded", "cf-connecting-ip", "cf-ray", "x-real-ip"] as const;

// The same shapes Vector's egress_audit_prep and migration 162 enforce, so a row that passes
// here cannot be rejected by a CHECK. z.string().uuid() is deliberately not used: it accepts
// the nil/max UUIDs and version-variant forms the VRL filter does not.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const HOST = /^([a-z0-9._:[\]-]+|\(other\))$/;

const rowSchema = z
  .object({
    workspace_id: z.string().regex(UUID),
    bucket_start: z.string().datetime(),
    requested_host: z.string().min(1).max(253).regex(HOST),
    decision: z.enum(["allowed", "denied", "other"]),
    source_host: z.string().regex(/^[a-z0-9][a-z0-9-]{0,62}$/),
    request_count: z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER),
    bytes_out: z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER),
    first_seen: z.string().datetime(),
    last_seen: z.string().datetime(),
  })
  .strict();
type Row = z.infer<typeof rowSchema>;

// PostgREST puts the id list in the URL: keep each lookup well under the length limit.
const LOOKUP_CHUNK = 100;
const FLAG_CONCURRENCY = 20;

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

/** Debounced warn for counts that matter operationally (rows dropped for content). Counts only. */
function mirrorCounts(reason: string, counts: Record<string, number>): void {
  const total = Object.values(counts).reduce((a, b) => a + b, 0);
  if (total > 0) mirrorReject(reason, counts);
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

/** Reads the body as UTF-8 text, counting BYTES; stops as soon as the cap is exceeded. */
async function readBounded(request: Request): Promise<string | "too-large" | "unreadable"> {
  if (!request.body) return "";
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_BODY_BYTES) {
        // review: swallowed on purpose - the body is already being rejected with 413 and a failed
        // cancel only means the connection is already gone.
        await reader.cancel().catch(() => undefined);
        return "too-large";
      }
      chunks.push(value);
    }
  } catch {
    return "unreadable";
  }
  return Buffer.concat(chunks.map((c) => Buffer.from(c))).toString("utf8");
}

export async function handleEgressAuditIngest(request: Request): Promise<Response> {
  // 1. Surface: loopback Host, no forwarding header.
  const host = request.headers.get("host") ?? "";
  const xff = request.headers.get("x-forwarded-for");
  const forwarded =
    PROXY_MARKER_HEADERS.some((h) => request.headers.has(h)) || (xff !== null && xff.includes(","));
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

  // 3b. In production the GLOBAL env mirror of the flag must be off. getRuntimeFlag falls back to
  //     it, role-blind, when Flagsmith is unreachable, so a stale FLAG_EGRESS_AUDIT_COLLECTION=1
  //     would open collection for every organisation on an outage (CTO ruling R6-G). Refuse to
  //     run on it: collection is on only where Flagsmith positively says so. Local dev and tests
  //     may still use the mirror.
  if (process.env.NODE_ENV === "production" && process.env.FLAG_EGRESS_AUDIT_COLLECTION === "1") {
    mirrorReject("env-fallback-on");
    return json({ dropped: true }, 202);
  }

  // 4. Body cap (counted in bytes while streaming: content-length can be absent, chunked or lying),
  //    JSON, array shape.
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
    mirrorReject("body-too-large");
    return json({ error: "Payload too large" }, 413);
  }
  const body = await readBounded(request);
  if (body === "too-large") {
    mirrorReject("body-too-large");
    return json({ error: "Payload too large" }, 413);
  }
  if (body === "unreadable") {
    mirrorReject("body-unreadable");
    return json({ error: "Malformed body" }, 400);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(body);
  } catch {
    mirrorReject("malformed-json");
    return json({ error: "Malformed JSON" }, 400);
  }
  if (!Array.isArray(parsed) || parsed.length > MAX_ROWS) {
    mirrorReject("schema", { rows: Array.isArray(parsed) ? parsed.length : -1 });
    return json({ error: "Invalid payload" }, 400);
  }

  // 5. Per-row schema. A bad row is dropped and counted; it never fails its neighbours (a 400 for
  //    the whole batch would drop up to 500 good rows for one bad one, and 4xx is not retried).
  const valid: Row[] = [];
  let droppedInvalid = 0;
  for (const candidate of parsed) {
    const r = rowSchema.safeParse(candidate);
    if (r.success) valid.push(r.data);
    else droppedInvalid++;
  }
  mirrorCounts("rows-invalid", { dropped_invalid: droppedInvalid });

  // 6. Bucket bounds, per row (a buffered backlog after an app outage stays valid).
  const now = Date.now();
  const inBounds: Row[] = [];
  let droppedBounds = 0;
  for (const r of valid) {
    const t = Date.parse(r.bucket_start);
    if (t < now - BUCKET_RETENTION_MS || t > now + BUCKET_FUTURE_MS) droppedBounds++;
    else inBounds.push(r);
  }
  if (droppedBounds > 0) mirrorReject("bucket-out-of-bounds", { count: droppedBounds });

  const result = {
    accepted: 0,
    dropped_invalid: droppedInvalid,
    dropped_bounds: droppedBounds,
    skipped_unknown: 0,
    skipped_orphan: 0,
    skipped_flag_off: 0,
    skipped_toggle_off: 0,
    skipped_invalid: 0,
  };
  if (inBounds.length === 0) return json(result, 202);

  // 7. Workspace -> organisation, in chunks (the id list travels in the URL).
  const service = createServiceClient();
  const wsIds = [...new Set(inBounds.map((r) => r.workspace_id))];
  const orgOf = new Map<string, string>();
  for (let i = 0; i < wsIds.length; i += LOOKUP_CHUNK) {
    const chunk = wsIds.slice(i, i + LOOKUP_CHUNK);
    const { data: wsRows, error: wsErr } = await service
      .from("workspaces")
      .select("id, organization_id")
      .in("id", chunk);
    if (wsErr || !wsRows) {
      // Debounced: Vector retries a 5xx up to ten times, so an outage would otherwise emit one
      // error event per retry per batch.
      mirrorWithDebounce(
        wsErr ?? new Error("workspace lookup returned no data"),
        {
          feature: FEATURE,
          op: "workspace-lookup",
          extra: { workspaces: chunk.length, pgCode: (wsErr as { code?: string } | null)?.code },
        },
        FEATURE,
        "workspace-lookup",
      );
      return json({ error: "Temporarily unavailable" }, 503);
    }
    for (const w of wsRows as { id: string; organization_id: string }[]) {
      orgOf.set(w.id, w.organization_id);
    }
  }

  // 8. Flag, per distinct organisation, bounded concurrency. A failed evaluation is "off" and is
  //    mirrored. getRuntimeFlag itself never throws on a Flagsmith outage: it falls back to the
  //    GLOBAL, role-blind env mirror FLAG_EGRESS_AUDIT_COLLECTION, which must stay 0 in prd
  //    (ADR-288), otherwise an outage would open collection for every organisation.
  const orgs = [...new Set([...orgOf.values()])];
  const enabled = new Map<string, boolean>();
  for (let i = 0; i < orgs.length; i += FLAG_CONCURRENCY) {
    await Promise.all(
      orgs.slice(i, i + FLAG_CONCURRENCY).map(async (orgId) => {
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
        } catch (err) {
          enabled.set(orgId, false);
          mirrorWarnWithDebounce(
            err,
            { feature: FEATURE, op: "flag-eval" },
            FEATURE,
            "flag-eval",
          );
        }
      }),
    );
  }

  const toWrite: Row[] = [];
  for (const r of inBounds) {
    const org = orgOf.get(r.workspace_id);
    if (!org) result.skipped_unknown++;
    else if (enabled.get(org) !== true) result.skipped_flag_off++;
    else toWrite.push(r);
  }
  if (toWrite.length === 0) return json(result, 202);

  // 9. Write.
  const { data, error } = await service.rpc("ingest_egress_audit_rollup", { p_rows: toWrite });
  if (error) {
    mirrorWithDebounce(
      error,
      {
        feature: FEATURE,
        op: "rpc",
        extra: { rows: toWrite.length, pgCode: (error as { code?: string }).code },
      },
      FEATURE,
      "rpc",
    );
    return json({ error: "Temporarily unavailable" }, 503);
  }
  const counts = (data ?? {}) as Partial<Record<string, number>>;
  result.accepted = counts.accepted ?? 0;
  result.skipped_unknown += counts.skipped_unknown ?? 0;
  result.skipped_orphan = counts.skipped_orphan ?? 0;
  result.skipped_toggle_off = counts.skipped_toggle_off ?? 0;
  result.skipped_invalid = counts.skipped_invalid ?? 0;
  // Content problems the pipeline should not produce (Vector and zod already filter): visible
  // in Sentry as counts, never as host or workspace values.
  mirrorCounts("rows-skipped", {
    skipped_unknown: result.skipped_unknown,
    skipped_orphan: result.skipped_orphan,
    skipped_invalid: result.skipped_invalid,
  });
  return json(result, 202);
}
