// Shared draft-action-card insert (#4579). One write choke point for all three
// producers: the KB-drift ingest route, github-on-event, and cfo-on-payment-failed.
//
// IMPORT BOUNDARY: this module is reachable from the Inngest/WS server bundle
// (github-on-event / cfo-on-payment-failed) as well as the Next API route. Import
// the Supabase client ONLY from `@/lib/supabase/tenant` (Next-free) — never
// `@/lib/supabase/server`, which transitively pulls `next/headers` into the
// esbuild bundle (see learning 2026-04-18-server-bundle-transitive-next-headers-leak).
// `@/server/observability` is already imported by github-on-event in the same
// bundle, so reportSilentFallback is bundle-safe here.
//
// CROSS-TENANT (single-user-incident threshold): workspace_id is PINNED to the
// founder's solo workspace (workspaces.id = founderId, ADR-038 N2) — NOT
// resolveCurrentWorkspaceId, which returns the session-SELECTED workspace and
// would let a multi-membership operator cross-post into a team queue (RLS passes
// by membership, so RLS is NOT the guard — the solo-pin is). Verified against
// prd 2026-05-29: is_workspace_member(founderId, founderId) = true for the
// operator founder. A future caller that genuinely needs a non-solo workspace
// must add an explicit override param — never re-introduce selection semantics
// for an identity-attributed write.

import { randomUUID } from "node:crypto";
import { getFreshTenantClient } from "@/lib/supabase/tenant";
import { reportSilentFallback } from "@/server/observability";
import { PG_UNIQUE_VIOLATION } from "@/lib/postgres-errors";
import { MESSAGE_STATUS_DRAFT, type MessageSource } from "@/lib/messages/tiers";
import { redactGithubSourcedText } from "@/lib/safety/redaction-allowlist";

export interface DraftCardInput {
  /** Founder identity. Also the solo workspace id (ADR-038 N2). */
  founderId: string;
  source: MessageSource;
  /** Free-form per producer ("knowledge", "cfo", computed github domain). */
  owning_domain: string;
  /** RAW preview — redacted inside the helper (FR5 single choke point). */
  draft_preview: string;
  tier: string;
  urgency: string;
  trust_tier: string;
  /**
   * MUST be a structured/hashed value, never raw upstream text — it is NOT
   * redacted and is surfaced verbatim by the Today read + send routes. Absent
   * for cfo (its rows do not dedup).
   */
  source_ref?: string;
  /**
   * Caller-set action class. NOT pre-validated here — a caller passing
   * `payment.*`/`legal.*`/`auth.*` hits messages_action_class_not_locked (23514),
   * surfaced loudly (not swallowed as dedup).
   */
  action_class?: string;
}

export type DraftCardResult = { status: "inserted" | "deduped"; id?: string };

/**
 * Insert a draft action card into `messages` via the RLS-enforced tenant client.
 * Maps the partial-unique dedup index conflict (23505) to an idempotent skip;
 * every other error (including CHECK violations, 23514) is mirrored to
 * Sentry/Better Stack and re-thrown for the caller to handle.
 */
export async function insertDraftCard(
  input: DraftCardInput,
): Promise<DraftCardResult> {
  const tenant = await getFreshTenantClient(input.founderId); // role=authenticated, sub=founderId
  const workspace_id = input.founderId; // solo-pin (ADR-038 N2)
  const id = randomUUID();

  const { error } = await tenant.from("messages").insert({
    id,
    user_id: input.founderId,
    workspace_id,
    template_id: "default_legacy", // Decision A — ack-only card; matches messages_template_id_check
    status: MESSAGE_STATUS_DRAFT,
    source: input.source,
    source_ref: input.source_ref ?? null,
    owning_domain: input.owning_domain,
    draft_preview: redactGithubSourcedText(input.draft_preview), // FR5
    tier: input.tier,
    urgency: input.urgency,
    trust_tier: input.trust_tier,
    ...(input.action_class ? { action_class: input.action_class } : {}),
  });

  if (error) {
    if (error.code === PG_UNIQUE_VIOLATION) {
      return { status: "deduped" };
    }
    reportSilentFallback(error, {
      feature: "insert-draft-card",
      op: "persist",
      message: `insertDraftCard(${input.source}) failed: ${error.message}`,
      extra: {
        founderId: input.founderId,
        workspace_id,
        source_ref: input.source_ref,
        code: error.code,
      },
    });
    throw new Error(`insertDraftCard failed (${error.code}): ${error.message}`);
  }

  return { status: "inserted", id };
}
