// PR-I (#4078) — Template-authorization gate orchestration.
//
// Extracted from `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts`
// at multi-agent review (code-quality F3). The route was carrying ~105
// lines of inline orchestration mixing the predicate's 5s timeout race,
// pino denial logging, first-send RPC dispatch, and discriminated
// result handling. The route is now a thin orchestrator that calls
// `runTemplateGate` and branches on a 3-variant discriminated result.
//
// Posture is unchanged from the inline version:
//   - 5s `Promise.race` timeout around `isTemplateAuthorized`.
//   - Fail-closed: any predicate exception throws → caller maps to 500.
//   - first_send → call `authorize_template` RPC; on failure caller maps
//     to 500 (NOT fall-through to writeActionSend).
//   - denied → pino structured log; 403 response shape.
//   - authorized → no side effect; caller proceeds.
//
// Returns a discriminated result the caller pattern-matches on; the
// caller (route handler) constructs the actual NextResponse so the
// extraction does not bind the gate to Next.js's response API.

import type { SupabaseClient } from "@supabase/supabase-js";

import { reportSilentFallback } from "@/server/observability";
import logger from "@/server/logger";

import {
  isTemplateAuthorized,
  PredicateException,
  type DenyReason,
} from "./is-template-authorized";

// 5s ceiling on the template-authorization probe. Exceeding this hard
// timeout fails-closed with a `PredicateException` that the caller maps
// to 500 + Sentry capture (`kind:template_predicate_timeout`).
const PREDICATE_TIMEOUT_MS = 5_000;

export interface RunTemplateGateArgs {
  supabase: SupabaseClient;
  founderId: string;
  founderIdHash: string;
  templateHash: string;
  grantId: string;
  actionClass: string;
  messageId: string;
}

export type TemplateGateResult =
  | { kind: "allow" }
  | {
      kind: "deny";
      denyReason: Exclude<DenyReason, "no_scope_grant" | "template_unauthorized">;
    }
  | { kind: "predicate_error" }
  | { kind: "authorize_error" };

/**
 * Orchestrates the predicate + first-send-IS-authorization flow. Does
 * NOT touch the HTTP response — the caller maps the discriminated
 * result onto its framework's response API.
 *
 * Side effects:
 *   - On denial: emits a pino structured log
 *     `{template_hash, action_class, deny_reason, founder_id_hash}`.
 *     NO Sentry mirror on routine denials (Art. 7(3) — expected
 *     behavior, not silent fallback).
 *   - On predicate exception: emits `reportSilentFallback` with
 *     `kind:template_predicate_timeout`.
 *   - On first_send path: calls `authorize_template` RPC. On RPC
 *     failure emits `reportSilentFallback` with
 *     `kind:template_authorization_race` and returns `authorize_error`.
 *   - On `authorized` or `first_send` happy path: returns `allow`.
 */
export async function runTemplateGate(
  args: RunTemplateGateArgs,
): Promise<TemplateGateResult> {
  const {
    supabase,
    founderId,
    founderIdHash,
    templateHash,
    grantId,
    actionClass,
    messageId,
  } = args;

  let predicateResult;
  try {
    predicateResult = await Promise.race([
      isTemplateAuthorized(supabase, founderId, templateHash, grantId),
      new Promise<never>((_, reject) =>
        setTimeout(
          () => reject(new PredicateException("predicate timed out")),
          PREDICATE_TIMEOUT_MS,
        ),
      ),
    ]);
  } catch (err) {
    reportSilentFallback(err, {
      feature: "dashboard-send",
      op: "template-authorize",
      message: "isTemplateAuthorized threw (fail-closed)",
      extra: {
        userId: founderId,
        messageId,
        actionClass,
        kind: "template_predicate_timeout",
      },
    });
    return { kind: "predicate_error" };
  }

  if (predicateResult.status === "denied") {
    logger.info(
      {
        feature: "template-authorizations",
        op: "denied",
        template_hash: templateHash,
        action_class: actionClass,
        deny_reason: predicateResult.reason,
        founder_id_hash: founderIdHash,
      },
      "template-authorization denied",
    );
    return { kind: "deny", denyReason: predicateResult.reason };
  }

  if (predicateResult.status === "first_send") {
    const { error: authErr } = await supabase.rpc("authorize_template", {
      p_template_hash: templateHash,
      p_action_class: actionClass,
      p_grant_id: grantId,
    });
    if (authErr) {
      reportSilentFallback(authErr, {
        feature: "dashboard-send",
        op: "authorize-template",
        message: "authorize_template RPC failed (first-send path)",
        extra: {
          userId: founderId,
          messageId,
          actionClass,
          kind: "template_authorization_race",
        },
      });
      return { kind: "authorize_error" };
    }
  }

  // `authorized` path falls through unchanged.
  return { kind: "allow" };
}
