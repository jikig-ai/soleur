// Shared turn-summary insert (feat-reasoning-chat-boxes #5370). The single
// write choke point for the agent-emitted `turn_summary` chat row. Mirrors
// insert-draft-card.ts (#4579): tenant-scoped client + founder solo-pin.
//
// IMPORT BOUNDARY: reachable from the WS server bundle (cc-dispatcher). Import
// the Supabase client ONLY from `@/lib/supabase/tenant` (Next-free) — never
// `@/lib/supabase/server`, which pulls `next/headers` into the esbuild bundle
// (learning 2026-04-18-server-bundle-transitive-next-headers-leak).
//
// CROSS-TENANT (single-user-incident threshold): workspace_id is PINNED to the
// founder's solo workspace (workspaces.id = founderId, ADR-038 N2) — NOT
// resolveCurrentWorkspaceId. This is load-bearing for the
// `messages_workspace_member_insert` RLS gate (mig 059), which passes by
// is_workspace_member(workspace_id, auth.uid()); the solo-pin — not RLS — is
// the cross-tenant guard. user_id is set to founderId (NOT omitted like the
// draft-card branch) BECAUSE the DSAR Art-15(4) author-redaction
// (dsar-export.ts, keyed on user_id NOT role) must keep `content` un-redacted
// in the user's OWN export — a turn_summary is the user's own data.
//
// COLUMN CONTRACT (data-integrity P0-1): conversation_id + role + content
// satisfy messages_row_kind_chk (mig 082) "chat row" branch; workspace_id +
// template_id are NOT-NULL-undefaulted (mig 059/053); message_kind='turn_summary'
// + role='assistant' satisfy messages_message_kind_chk (mig 105). Omitting any
// of these throws 23502/23514 at the first prod write — invisible to mocks.
//
// REDACTION (data-integrity P2 — single write choke point): `content` is
// scrubbed with `formatAssistantText` HERE so any future caller gets host/sandbox
// path scrubbing for free. The cc-dispatcher emit path scrubs the SAME way before
// calling in, so the stored bytes equal the buffered-frame bytes (security M-1);
// re-scrubbing an already-scrubbed string is idempotent.

import { randomUUID } from "node:crypto";
import { getFreshTenantClient } from "@/lib/supabase/tenant";
import { reportSilentFallback } from "@/server/observability";
import { formatAssistantText } from "@/lib/format-assistant-text";

export interface TurnSummaryInput {
  /** Founder identity. Also the solo workspace id (ADR-038 N2) AND user_id. */
  founderId: string;
  /** Parent conversation — required by messages_row_kind_chk + DSAR guard. */
  conversationId: string;
  /** Plain-language summary. Scrubbed inside (FR5 single choke point). */
  content: string;
}

export type TurnSummaryResult = { status: "inserted"; id: string };

/**
 * Insert a `turn_summary` chat row via the RLS-enforced tenant client. Throws
 * (after mirroring to Sentry/Better Stack) on any DB error so the caller's
 * catch can decide; never swallows.
 */
export async function insertTurnSummary(
  input: TurnSummaryInput,
): Promise<TurnSummaryResult> {
  const tenant = await getFreshTenantClient(input.founderId); // role=authenticated, sub=founderId
  const workspace_id = input.founderId; // solo-pin (ADR-038 N2)
  const id = randomUUID();

  // FR5 choke point — scrub host/sandbox path prefixes. Idempotent: the emit
  // path already scrubbed, so this preserves byte-equality with the frame.
  const content = formatAssistantText(input.content, {
    reportFallthrough: (shape) =>
      reportSilentFallback(new Error("turn-summary fallthrough"), {
        feature: "insert-turn-summary",
        op: "reasoning-narration:summary-redaction-fallthrough",
        message: "suspected path leak survived scrub in turn_summary content",
        extra: { founderId: input.founderId, conversationId: input.conversationId, shape },
      }),
  });

  const { error } = await tenant.from("messages").insert({
    id,
    conversation_id: input.conversationId,
    workspace_id,
    template_id: "default_legacy", // mig 053 NOT NULL + ^[a-z][a-z0-9_]*$
    user_id: input.founderId, // Art-15(4): un-redacted in the user's own DSAR export
    role: "assistant", // mig 105 messages_message_kind_chk requires this
    content,
    message_kind: "turn_summary",
    leader_id: null,
  });

  if (error) {
    reportSilentFallback(error, {
      feature: "insert-turn-summary",
      op: "reasoning-narration:summary-insert-fail",
      message: `insertTurnSummary failed: ${error.message}`,
      extra: {
        founderId: input.founderId,
        conversationId: input.conversationId,
        workspace_id,
        code: error.code,
      },
    });
    throw new Error(`insertTurnSummary failed (${error.code}): ${error.message}`);
  }

  return { status: "inserted", id };
}
