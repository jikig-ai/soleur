// PR-H (#4077) — Single write boundary for action_sends.
//
// Bounded-context per Arch F1 + hr-write-boundary-sentinel-sweep-all-write-sites.
// Every producer that records a send (the dashboard Send route in PR-H;
// the digest emitter in PR-I; future template-authorization writers)
// MUST funnel through this helper. tsc + the action-class-typed-literals
// lint together prove the literal-union is honored at the call site;
// THIS function honors the WORM/RLS invariants at the DB boundary.

import { createHash } from "node:crypto";
import * as Sentry from "@sentry/nextjs";

import type { SupabaseClient } from "@supabase/supabase-js";

import type {
  ActionClass,
  ActionClassTier,
} from "@/server/scope-grants/action-class-map";
import type { ActiveGrant } from "@/server/scope-grants/is-granted";
import { reportSilentFallback } from "@/server/observability";
import { getTemplateHash } from "@/server/templates/template-registry";
import type { TemplateId } from "@/server/templates/template-registry";

export interface WriteActionSendArgs {
  supabase: SupabaseClient;
  founderId: string;
  message: {
    id: string;
    action_class: ActionClass;
    draft_preview: string | null;
    // PR-I (#4078): drives `getTemplateHash` via the shared registry at
    // `@/server/templates/template-registry`. Producers SELECT this
    // column when reading `messages`; the field is NOT NULL at the DB
    // layer (mig 053 Part A backfills to 'default_legacy'). Null /
    // undefined here is treated by the registry as a fall-through to
    // `default_legacy` + a `warnSilentFallback` emit — a producer-side
    // bug, but does not block the WORM write.
    template_id?: TemplateId | string | null;
  };
  grant: ActiveGrant;
  tier: ActionClassTier;
  // approve_every_time tier requires the typed-confirm signature.
  confirmedTyped?: boolean;
  typedValue?: string;
  // The recipient identifier the founder is sending to. Hashed before
  // persistence — the raw value is never written.
  recipientIdentifier: string;
  // The exact body that will be sent. PR-H stubs the outbound effect
  // (no producer integration yet); the body is still hashed so PR-I
  // wire-ups don't change the table-write contract.
  bodyContent: string;
}

export interface ActionSendRecord {
  id: string;
}

function sha256(s: string): string {
  return createHash("sha256").update(s).digest("hex");
}

// Canonical-JSON serialization for the approval signature so that a
// payload containing `||` substrings can't collide with another via
// naive string concatenation (Sharp Edges §"Approval signature ||
// ambiguity"). Keys are sorted to remove ordering ambiguity from the
// signed surface.
//
// GDPR Art. 5(2) accountability: the signature binds founder+message+
// what-was-sent (body hash, recipient hash, template hash, tier) +
// what-was-typed. A founder later disputing "I never approved THIS
// body to THIS recipient" can be answered by re-running the same
// canonical-JSON hash against the stored action_sends columns —
// mismatch proves the row was tampered with, match proves the signed
// surface matches the persisted row. `ts` is intentionally omitted so
// the signature is reproducible from the stored row (clicked_at gives
// the wall-clock anchor separately).
function approvalSignature(args: {
  founderId: string;
  messageId: string;
  typedValue: string;
  perSendBodyHash: string;
  recipientHash: string;
  templateHash: string;
  tier: ActionClassTier;
}): string {
  const ordered: Record<string, unknown> = {};
  for (const key of Object.keys(args).sort()) {
    ordered[key] = (args as Record<string, unknown>)[key];
  }
  return sha256(JSON.stringify(ordered));
}

/**
 * Writes a single action_sends row. Returns the inserted id on success.
 * Throws on failure — callers should catch + return 500 to the founder
 * + mirror to Sentry via reportSilentFallback.
 *
 * Per Phase 4.3 of the plan, callers MUST:
 *   1. Pre-validate origin + JWT.
 *   2. Re-call isGranted at click-time with the SAME cookie-scoped client.
 *   3. Reject 409 for approve_every_time when confirmedTyped is missing.
 *   4. Reject 400 for auto / auto_with_digest tiers (these are not
 *      founder-initiated paths).
 *
 * The function does not itself perform isGranted re-check — that lives
 * at the route layer so the 403/409/400 branching has direct response
 * control. write-action-send only writes.
 */
export async function writeActionSend(
  args: WriteActionSendArgs,
): Promise<ActionSendRecord> {
  const {
    supabase,
    founderId,
    message,
    grant,
    tier,
    confirmedTyped = false,
    typedValue,
    recipientIdentifier,
    bodyContent,
  } = args;

  // PR-I (#4078): the canonical template hash is derived from the
  // code-static template registry, not from a route-local concatenation
  // of (action_class, owning_domain, tier). The hash keys
  // `template_authorizations` (mig 053) so producers + consumers must
  // route through the same module. See ADR-035.
  const templateHash = getTemplateHash({ template_id: message.template_id });

  const perSendBodyHash = sha256(bodyContent);
  const recipientHash = sha256(recipientIdentifier);

  let approvalSig: string | null = null;
  if (tier === "approve_every_time") {
    if (!confirmedTyped || typedValue !== "SEND") {
      // The route layer should have caught this; defense-in-depth.
      throw new Error(
        "writeActionSend: approve_every_time tier requires confirmed_typed=true and typed_value='SEND'",
      );
    }
    approvalSig = approvalSignature({
      founderId,
      messageId: message.id,
      typedValue,
      perSendBodyHash,
      recipientHash,
      templateHash,
      tier,
    });
  }

  const { data, error } = await supabase
    .from("action_sends")
    .insert({
      user_id: founderId,
      message_id: message.id,
      action_class: message.action_class,
      tier_at_send: tier,
      template_hash: templateHash,
      per_send_body_sha256: perSendBodyHash,
      recipient_id_hash: recipientHash,
      confirmed_typed: confirmedTyped,
      approval_signature_sha256: approvalSig,
      grant_id: grant.id,
    })
    .select("id")
    .single();

  if (error) {
    reportSilentFallback(error, {
      feature: "action-sends",
      op: "write-action-send",
      message: "action_sends INSERT failed",
      extra: {
        userId: founderId,
        messageId: message.id,
        actionClass: message.action_class,
        tier,
      },
    });
    throw error;
  }

  Sentry.addBreadcrumb({
    category: "action-sends",
    message: "action_sends.recorded",
    level: "info",
    data: {
      action_class: message.action_class,
      tier,
      confirmed_typed: confirmedTyped,
    },
  });

  return { id: data!.id as string };
}
