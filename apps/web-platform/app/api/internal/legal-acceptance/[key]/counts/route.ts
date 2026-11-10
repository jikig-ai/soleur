import { NextResponse } from "next/server";
import { bearerMatches } from "@/lib/internal-auth";
import { readNamedBearerSecret } from "@/lib/internal-auth-named";
import { createServiceClient } from "@/lib/supabase/service";
import { KEY_RE, LegalTextError, getLegalText } from "@/server/legal-acceptance/canonical";
import { LegalServiceError, hashCounts, type LegalRpcClient } from "@/server/legal-acceptance/service";
import { reportLegalOp } from "@/server/approval/ops";

/**
 * GET /api/internal/legal-acceptance/[key]/counts — the credential-free pre-flag aggregate (#12429, ADR-319 amendment
 * 2026-11-08). The sibling of the verify route, with its own contract: that route is "exactly four keys, one configured
 * founder" and stays so.
 *
 * Answers, for a key in the registry, exactly `{key, registry_hash, total, by_hash, ok_to_flag}` and nothing else:
 * `total` decision rows exist for the key, `by_hash` is the count per text hash, and `ok_to_flag` is true iff every hash in
 * `by_hash` equals `registry_hash` (vacuously true at `total` 0). It never carries a founder id, a choice, a timestamp or
 * the note: the RPC (migration 186) selects none of them and the parser rebuilds the result from closed fields.
 * `ok_to_flag` is ADVISORY. It measures only the production table for that key: not database backups, not the Sentry
 * `accepted` count, not dev or preview. It does not authorize a flag flip (hr-menu-option-ack-not-prod-write-auth).
 *
 * Check order: 503 token unset or malformed (no founder id is read: this route needs none) · 401 wrong token ·
 * 400 malformed key · 404 key not in the registry · 503 the registry could not be read · RPC. 502: the database answered
 * something that is not the documented shape. 503 also covers a failed or missing RPC (migration 186 not applied). Never a
 * partial 200. There is no small-cell floor: with one data subject today a count of 1 is the answer to the question
 * (CTO T5), and the bearer holder already learns "accepted" from the verify route.
 *
 * Observability: a registry read failure, a failed counts call and a set-but-malformed token each emit ONE `store_failed`
 * (tags.stage registry | counts | config). Recorded, not paged (#12195). An unset token stays silent: that is the dark state.
 * A counts call refused with 54000 (too many distinct hashes) adds the static `extra.reason: "too_many_hashes"` to its
 * report so it is not mistaken for "migration 186 not applied"; the response body is unchanged.
 *
 * Auth: the same bearer as the verify route (LEGAL_ACCEPTANCE_VERIFY_TOKEN through lib/internal-auth-named.ts; a scope
 * widening of one token, not a new credential). PUBLIC_PATHS has a prefix entry for this tree; the bearer check is the first
 * thing after configuration (verify-route-census.test.ts walks this file). Thin HTTP-only export.
 */

export const dynamic = "force-dynamic";

/** The same shape as the verify route's token guard (counts-route.test.ts pins the two lines byte for byte). */
const TOKEN_RE = /^[A-Za-z0-9._~+/=-]{48,256}$/;

/** One configuration report per route module (the verify route has its own flag, so a malformed token yields one event from each route): the 503 itself repeats on every call, the Sentry event must not. */
let configReported = false;
function reportBadConfig(variables: string[]): void {
  if (configReported) return;
  configReported = true;
  reportLegalOp("storeFailed", null, { tags: { stage: "config" }, extra: { step: "config", variables } });
}

function respond(status: 200 | 400 | 401 | 404 | 502 | 503, body: unknown): Response {
  return NextResponse.json(body, { status, headers: { "Cache-Control": "no-store" } });
}
const unavailable = () => respond(503, { error: "Not available" });

export async function GET(req: Request, ctx: { params: Promise<{ key: string }> }): Promise<Response> {
  // 1. Configuration. Unset is the dark state and stays silent; a token that is SET but fails its shape is a
  // misconfiguration and is reported (once). This route reads no founder id.
  const token = readNamedBearerSecret("LEGAL_ACCEPTANCE_VERIFY_TOKEN");
  const badConfig: string[] = [];
  if (token !== null && !TOKEN_RE.test(token)) badConfig.push("LEGAL_ACCEPTANCE_VERIFY_TOKEN");
  if (badConfig.length > 0) reportBadConfig(badConfig);
  if (token === null || !TOKEN_RE.test(token)) return unavailable();

  // 2. Token, before any lookup of any kind.
  if (!bearerMatches(req.headers.get("authorization"), token)) return respond(401, { error: "Unauthorized" });

  // 3. Shape: the same predicate as the database CHECK and the RPC.
  const { key } = await ctx.params;
  if (!KEY_RE.test(key)) return respond(400, { error: "Bad request" });

  // 4. The key must be in the registry; the registry hash is the one `ok_to_flag` is judged against. Only a missing file is
  // 404; an unreadable or malformed registry is reported and answered 503 (after 401 and 400: nothing leaks unauthenticated).
  let registryHash: string;
  try {
    registryHash = getLegalText(key).textHash;
  } catch (err) {
    if (err instanceof LegalTextError && err.code === "unknown_key") return respond(404, { error: "Not found" });
    reportLegalOp("storeFailed", err, { tags: { stage: "registry" }, extra: { key, step: "registry" } });
    return unavailable();
  }

  // 5. The aggregate.
  try {
    const service = createServiceClient() as unknown as LegalRpcClient;
    const { total, by_hash } = await hashCounts(service, { key });
    return respond(200, {
      key,
      registry_hash: registryHash,
      total,
      by_hash,
      ok_to_flag: by_hash.every((r) => r.text_hash === registryHash),
    });
  } catch (err) {
    // 54000 is the RPC's own "more distinct hashes than the cap" refusal: an operator condition (investigate the rows), not a
    // missing migration. The response stays the same generic 503; only the report carries the static reason.
    const tooManyHashes = err instanceof LegalServiceError && err.code === "54000";
    reportLegalOp("storeFailed", err, {
      tags: { stage: "counts" },
      extra: { key, step: "counts", ...(tooManyHashes ? { reason: "too_many_hashes" } : {}) },
    });
    // An answer that is not a documented shape is a bad gateway; a failed or thrown call is unavailable. Never a 200.
    return err instanceof LegalServiceError && err.code === "bad_payload" ? respond(502, { error: "Bad gateway" }) : unavailable();
  }
}
