// PR-I (#4078) — Two-probe template authorization predicate.
//
// Sits at `send/route.ts` AFTER `isGranted` and BEFORE the tier switch
// (plan §Phase 4 §4). Returns a discriminated `PredicateResult`:
//
//   - `first_send`  → no existing row. Caller MUST call
//                     `authorize_template` RPC and proceed to write
//                     `action_sends` in the same Supabase transaction
//                     (first-send-IS-authorization pattern).
//   - `authorized`  → active row with bounds in range; proceed.
//   - `denied`      → returns one of `template_revoked` /
//                     `template_expired` / `template_quota_exhausted`.
//
// Fail-closed: any DB exception inside the SELECT throws
// `PredicateException`. The route layer catches as 500 + Sentry
// (`kind:template_predicate_timeout`). The fail-closed posture is
// intentional — fail-OPEN against the authorization is a regulatory
// hazard (Art. 7(3) "informed" consent fails if the predicate silently
// admits a stale-state Send).
//
// Auto-revoke side effect: on expired or quota-exhausted detection,
// fire `revoke_template_authorization(template_hash, 'expired' |
// 'quota_exhausted')` fire-and-forget. Failure is logged via pino but
// does NOT mask the denial — the UI stays honest on the next read.
//
// Inline `DenyReason` type (plan §Phase 4 §1 + Simplicity review — no
// separate `deny-reason.ts`).

import type { SupabaseClient } from "@supabase/supabase-js";

import { warnSilentFallback } from "@/server/observability";
import type { ActionClassTier } from "@/server/scope-grants/action-class-map";

export type DenyReason =
  | "no_scope_grant"
  | "template_unauthorized"
  | "template_quota_exhausted"
  | "template_expired"
  | "template_revoked";

/**
 * Exhaustive predicate: does the given tier require a per-template
 * authorization row to be present (or first-send-IS-authorized) before
 * the send route admits the request?
 *
 * v1: only `draft_one_click` carries template-level authorization.
 * `auto` and `auto_with_digest` are rejected at the route's tier switch
 * (founder-initiated send is not the producer path for these);
 * `approve_every_time` gates on its own typed-confirm primitive and does
 * NOT carry a template_authorizations row in v1.
 *
 * The compile-time `_exhaustive: never` rail FORCES future tier additions
 * to declare their template-auth stance — a hypothetical 5th tier would
 * fail tsc here, surfacing the design decision before it can silently
 * bypass the gate. Surfaced by PR-I multi-agent review (architecture-
 * strategist P2 tier-exhaustiveness gap).
 */
export function tierRequiresTemplateAuth(tier: ActionClassTier): boolean {
  switch (tier) {
    case "draft_one_click":
      return true;
    case "auto":
    case "auto_with_digest":
    case "approve_every_time":
      return false;
    default: {
      const _exhaustive: never = tier;
      void _exhaustive;
      return false;
    }
  }
}

export type PredicateResult =
  | { status: "authorized"; rowId: string; sendsUsed: number }
  | { status: "first_send"; grantId: string }
  | {
      status: "denied";
      reason: Exclude<DenyReason, "no_scope_grant" | "template_unauthorized">;
    };

/**
 * Thrown when the predicate's SELECT or count fails. The route layer
 * catches this as 500 + Sentry capture (kind:template_predicate_timeout).
 * NEVER caught silently — fail-closed against the authorization.
 */
export class PredicateException extends Error {
  readonly cause?: unknown;
  constructor(cause: unknown) {
    super("isTemplateAuthorized: DB error");
    this.name = "PredicateException";
    this.cause = cause;
  }
}

interface TemplateAuthRow {
  id: string;
  expires_at: string;
  max_sends: number;
  revoked_at: string | null;
}

export async function isTemplateAuthorized(
  client: SupabaseClient,
  founderId: string,
  templateHash: string,
  grantId: string,
): Promise<PredicateResult> {
  // Unconditional parallel fetch: the most-recent template_authorizations
  // row (regardless of revoked/expired state) + the count of action_sends
  // sharing this (user_id, template_hash). NO fallback path — plan v2
  // explicitly cut the v1 conditional double-query.
  const [rowResult, countResult] = await Promise.all([
    client
      .from("template_authorizations")
      .select("id, expires_at, max_sends, revoked_at")
      .eq("founder_id", founderId)
      .eq("template_hash", templateHash)
      .order("authorized_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
    client
      .from("action_sends")
      .select("id", { count: "exact", head: true })
      .eq("user_id", founderId)
      .eq("template_hash", templateHash),
  ]);

  if (rowResult.error) {
    throw new PredicateException(rowResult.error);
  }
  if (countResult.error) {
    throw new PredicateException(countResult.error);
  }

  const row = rowResult.data as TemplateAuthRow | null;
  const sendsUsed = countResult.count ?? 0;

  // No row → first send. Caller writes the authorization in the same
  // transaction as action_sends.
  if (row === null) {
    return { status: "first_send", grantId };
  }

  // Already revoked → deny without auto-revoke (row state is final).
  if (row.revoked_at !== null) {
    return { status: "denied", reason: "template_revoked" };
  }

  // Compute bounds-in-range flags from the as-fetched row.
  const expired = new Date(row.expires_at).getTime() <= Date.now();
  const quotaExhausted = sendsUsed >= row.max_sends;

  if (expired) {
    void autoRevoke(client, templateHash, "expired");
    return { status: "denied", reason: "template_expired" };
  }

  if (quotaExhausted) {
    void autoRevoke(client, templateHash, "quota_exhausted");
    return { status: "denied", reason: "template_quota_exhausted" };
  }

  return { status: "authorized", rowId: row.id, sendsUsed };
}

/**
 * Fire-and-forget revoke for expired/quota-exhausted rows. Failure does
 * NOT mask the denial — the UI stays honest on the next read.
 *
 * NOT marked async to the caller: returns void Promise; caller uses
 * `void autoRevoke(...)` so the response path is not awaited.
 */
async function autoRevoke(
  client: SupabaseClient,
  templateHash: string,
  reason: "expired" | "quota_exhausted",
): Promise<void> {
  try {
    const { error } = await client.rpc("revoke_template_authorization", {
      p_template_hash: templateHash,
      p_reason: reason,
    });
    if (error) {
      // Best-effort: the denial was already returned to the founder.
      // Surface to pino + Sentry-warn so an alert can fire if auto-
      // revoke fails systematically. The next scope-grants page read
      // will trigger another auto-revoke attempt.
      warnSilentFallback(error, {
        feature: "template-authorizations",
        op: "auto_revoke",
        message: "auto-revoke RPC returned error",
        extra: { reason },
      });
    }
  } catch (err) {
    warnSilentFallback(err, {
      feature: "template-authorizations",
      op: "auto_revoke",
      message: "auto-revoke RPC threw",
      extra: { reason },
    });
  }
}
