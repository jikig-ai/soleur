import { NextResponse } from "next/server";
import { bearerMatches } from "@/lib/internal-auth";
import { readNamedBearerSecret } from "@/lib/internal-auth-named";
import { isUuid } from "@/lib/is-uuid";
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
import { reportLegalOp, type StoreFailedStage } from "@/server/approval/ops";

/**
 * GET /api/internal/legal-acceptance/[key]?hash=<64 hex> — the read-only check endpoint (#12011 PR-D, ADR-319).
 *
 * Answers, for the ONE founder named in configuration, what they decided on the text `hash` of `key`:
 * exactly `{status, text_hash, decided_at, row_ok}` and nothing else (never the note). Check order:
 *   503 token or founder id unset/malformed · 401 wrong token · 400 malformed key or hash · 404 key not in the registry ·
 *   503 the registry could not be read (a read error or a malformed committed text, anything but a missing file; this is
 *   step 4, after 401 and 400, never first) · lookup. 502: the database answered something that is not a documented shape. 503 also covers a failed
 *   database call. The statuses are the closed set VERIFY_ENDPOINT_STATUSES.
 * `invalid` (the stored row failed its checksum) passes through as `invalid` with `row_ok:false` and emits `record_invalid`;
 * it is never collapsed into `none`. When a row exists and is unacknowledged and at least ROW_WITHOUT_EVENT_GRACE_SECONDS
 * (>= 120 s) old, `row_without_event` is emitted. row_without_event is alert-only; if the reconciliation read fails or
 * disagrees with the verify read, the endpoint answers 503 or 502 and never a partial 200.
 *
 * Observability: a registry read failure, a failed verify or ack_state call and a set-but-malformed configuration value
 * each emit ONE `store_failed` (tags.stage registry | verify | ack_state | config; for `registry`, extra.code says which: read_failed,
 * or a malformed text such as bad_bytes, no_front_matter, bad_version, bad_valid_until). An unset value stays silent: that is
 * the dark state. The configuration report is once per process for this module (`surface.ts` reports a malformed founder id on its own, so up to two) and names only the variable, never a value or a length.
 *
 * Auth: a bearer token separate from the Inngest one (LEGAL_ACCEPTANCE_VERIFY_TOKEN, read through
 * lib/internal-auth-named.ts so lib/internal-auth.ts stays byte-identical to the CLO-discharged census sha). The founder
 * id comes ONLY from LEGAL_ACCEPTANCE_FOUNDER_ID: no query value or header can name another user. PUBLIC_PATHS has a prefix
 * entry (dynamic [key] segment); every handler under it must check the bearer first (verify-route-census.test.ts).
 * Thin HTTP-only export.
 */

export const dynamic = "force-dynamic";

/**
 * The shape a configured token must have: no whitespace or quote that could end up in a config file, and 48 to 256
 * characters (the minted length is 48). The same bounds are in the shell helper (bc_shape_ok); cross-layer-limits.test.ts
 * extracts both and compares them.
 */
const TOKEN_RE = /^[A-Za-z0-9._~+/=-]{48,256}$/;

/** One configuration report per process: the 503 itself repeats on every call, the Sentry event must not. */
let configReported = false;
function reportBadConfig(variables: string[]): void {
  if (configReported) return;
  configReported = true;
  reportLegalOp("storeFailed", null, { tags: { stage: "config" }, extra: { step: "config", variables } });
}

function respond(status: VerifyEndpointStatus, body: unknown): Response {
  return NextResponse.json(body, { status, headers: { "Cache-Control": "no-store" } });
}
const unavailable = () => respond(503, { error: "Not available" });

function storeFailed(stage: StoreFailedStage, err: unknown, key: string): Response {
  reportLegalOp("storeFailed", err, { tags: { stage }, extra: { key, step: stage } });
  // An answer that is not a documented shape is a bad gateway; a failed or thrown call is unavailable. Never a 200.
  return err instanceof LegalServiceError && err.code === "bad_payload" ? respond(502, { error: "Bad gateway" }) : unavailable();
}

export async function GET(req: Request, ctx: { params: Promise<{ key: string }> }): Promise<Response> {
  // 1. Configuration. Unset or malformed is indistinguishable from "route disabled" to the caller. Unset is the dark
  // state and stays silent; a value that is SET but fails its shape is a misconfiguration and is reported (once).
  const token = readNamedBearerSecret("LEGAL_ACCEPTANCE_VERIFY_TOKEN");
  const founderRaw = process.env.LEGAL_ACCEPTANCE_FOUNDER_ID;
  const badConfig: string[] = [];
  if (token !== null && !TOKEN_RE.test(token)) badConfig.push("LEGAL_ACCEPTANCE_VERIFY_TOKEN");
  if (founderRaw && !isUuid(founderRaw)) badConfig.push("LEGAL_ACCEPTANCE_FOUNDER_ID");
  if (badConfig.length > 0) reportBadConfig(badConfig);
  if (token === null || !TOKEN_RE.test(token) || !isUuid(founderRaw)) return unavailable();
  const founderId = founderRaw.toLowerCase();

  // 2. Token, before any lookup of any kind.
  if (!bearerMatches(req.headers.get("authorization"), token)) return respond(401, { error: "Unauthorized" });

  // 3. Shapes: the same predicates as the database CHECKs and the shell gate.
  const { key } = await ctx.params;
  const hashes = new URL(req.url).searchParams.getAll("hash");
  if (!KEY_RE.test(key) || hashes.length !== 1 || !TEXT_HASH_RE.test(hashes[0])) {
    return respond(400, { error: "Bad request" });
  }
  const textHash = hashes[0];

  // 4. The key must be in the registry. Only a missing file is 404; a registry that cannot be read, or whose committed text
  // is malformed (extra.code: read_failed, bad_bytes, no_front_matter, bad_version, bad_valid_until), is reported
  // (store_failed, stage registry) and answered 503. This is after 401 and 400: an unauthenticated caller learns nothing.
  try {
    getLegalText(key);
  } catch (err) {
    if (err instanceof LegalTextError && err.code === "unknown_key") return respond(404, { error: "Not found" });
    return storeFailed("registry", err, key);
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
    reportLegalOp("recordInvalid", null, { extra: { key, textHash } });
  }

  // 6. Reconciliation, for the one row that was read. `none` has no row and so no gap.
  if (result.status !== "none") {
    try {
      const state = await ackState(service, { founderId, key, textHash });
      // verify saw a row and ack_state saw none: the two reads disagree, which is not a documented shape.
      if (state.outcome !== "row") throw new LegalServiceError("legal_acceptance_ack_state", "bad_payload");
      if (!state.acked && state.age_seconds >= ROW_WITHOUT_EVENT_GRACE_SECONDS) {
        reportLegalOp("rowWithoutEvent", null, { extra: { key, textHash, ageSeconds: state.age_seconds, status: result.status } });
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
