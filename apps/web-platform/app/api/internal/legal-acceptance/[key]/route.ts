import { NextResponse } from "next/server";
import { bearerMatches, readInternalBearerSecret } from "@/lib/internal-auth";
import { createServiceClient } from "@/lib/supabase/service";
import { KEY_RE, LegalTextError, TEXT_HASH_RE, getLegalText } from "@/server/legal-acceptance/canonical";
import {
  LegalServiceError,
  ROW_WITHOUT_EVENT_GRACE_SECONDS,
  ackState,
  verifyAcceptance,
  type LegalRpcClient,
  type VerifyEndpointStatus,
  type VerifyResult,
} from "@/server/legal-acceptance/service";
import { reportLegalOp } from "@/server/approval/ops";

/**
 * GET /api/internal/legal-acceptance/[key]?hash=<64 hex> — the read-only check endpoint (#12011 PR-D, ADR-319).
 *
 * Answers, for the ONE founder named in configuration, what they decided on the text `hash` of `key`:
 * exactly `{status, text_hash, decided_at, row_ok}` and nothing else (never the note). Check order:
 *   503 token or founder id unset/malformed (also: the registry could not be read) · 401 wrong token · 400 malformed key or
 *   hash · 404 key not in the registry · lookup. 502: the database answered something that is not a documented shape.
 *   503 also covers a failed database call. The statuses are the closed set VERIFY_ENDPOINT_STATUSES.
 * `invalid` (the stored row failed its checksum) passes through as `invalid` with `row_ok:false` and emits `record_invalid`;
 * it is never collapsed into `none`. When a row exists and is unacknowledged at least ROW_WITHOUT_EVENT_GRACE_SECONDS old,
 * `row_without_event` is emitted (alert only: the response is unchanged).
 *
 * Auth: a bearer token separate from the Inngest one (LEGAL_ACCEPTANCE_VERIFY_TOKEN). The founder id comes ONLY from
 * LEGAL_ACCEPTANCE_FOUNDER_ID: no query value or header can name another user. Narrow PUBLIC_PATHS entry (no session cookie).
 * Thin HTTP-only export.
 */

export const dynamic = "force-dynamic";

/** The shape a configured token must have: no whitespace or quote that could end up in a config file, and long enough to be a minted secret. */
const TOKEN_RE = /^[A-Za-z0-9._~+/=-]{32,256}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function respond(status: VerifyEndpointStatus, body: unknown): Response {
  return NextResponse.json(body, { status, headers: { "Cache-Control": "no-store" } });
}
const unavailable = () => respond(503, { error: "Not available" });

function storeFailed(stage: "verify" | "ack_state", err: unknown, key: string): Response {
  reportLegalOp("storeFailed", err, { tags: { stage }, extra: { key } });
  // An answer that is not a documented shape is a bad gateway; a failed or thrown call is unavailable. Never a 200.
  return err instanceof LegalServiceError && err.code === "bad_payload" ? respond(502, { error: "Bad gateway" }) : unavailable();
}

export async function GET(req: Request, ctx: { params: Promise<{ key: string }> }): Promise<Response> {
  // 1. Configuration. Unset or malformed is indistinguishable from "route disabled" to the caller.
  const token = readInternalBearerSecret("LEGAL_ACCEPTANCE_VERIFY_TOKEN");
  const founderRaw = process.env.LEGAL_ACCEPTANCE_FOUNDER_ID;
  if (!token || !TOKEN_RE.test(token) || !founderRaw || !UUID_RE.test(founderRaw)) return unavailable();
  const founderId = founderRaw.toLowerCase();

  // 2. Token, before any lookup of any kind.
  if (!bearerMatches(req.headers.get("authorization"), token)) return respond(401, { error: "Unauthorized" });

  // 3. Shapes: the same predicates as the database CHECKs and the shell gate.
  const { key } = await ctx.params;
  const hashes = new URL(req.url).searchParams.getAll("hash");
  if (typeof key !== "string" || !KEY_RE.test(key) || hashes.length !== 1 || !TEXT_HASH_RE.test(hashes[0])) {
    return respond(400, { error: "Bad request" });
  }
  const textHash = hashes[0];

  // 4. The key must be in the registry. Only a missing file is 404; a registry that cannot be read is 503.
  try {
    getLegalText(key);
  } catch (err) {
    if (err instanceof LegalTextError && err.code === "unknown_key") return respond(404, { error: "Not found" });
    return unavailable();
  }

  // 5. Lookup.
  let service: LegalRpcClient;
  let result: VerifyResult;
  try {
    service = createServiceClient() as unknown as LegalRpcClient;
    result = await verifyAcceptance(service, { founderId, key, textHash });
  } catch (err) {
    return storeFailed("verify", err, key);
  }

  if (result.status === "invalid") {
    reportLegalOp("recordInvalid", null, { extra: { key } });
  }

  // 6. Reconciliation, for the one row that was read. `none` has no row and so no gap.
  if (result.status !== "none") {
    try {
      const state = await ackState(service, { founderId, key, textHash });
      // verify saw a row and ack_state saw none: the two reads disagree, which is not a documented shape.
      if (state.outcome !== "row") throw new LegalServiceError("legal_acceptance_ack_state", "bad_payload");
      if (!state.acked && state.age_seconds >= ROW_WITHOUT_EVENT_GRACE_SECONDS) {
        reportLegalOp("rowWithoutEvent", null, { extra: { key, ageSeconds: state.age_seconds, status: result.status } });
      }
    } catch (err) {
      return storeFailed("ack_state", err, key);
    }
  }

  return respond(200, {
    status: result.status,
    text_hash: result.text_hash,
    decided_at: result.decided_at,
    row_ok: result.row_ok,
  });
}
