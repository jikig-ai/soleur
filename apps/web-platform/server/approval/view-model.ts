/**
 * Verified read model of a stored approval row for the Owner-facing surfaces (#4672): the away-user landing page and the
 * inbox row. The stored `canonical_action` is re-hashed and compared with the row's bound `action_sha256` before it is
 * rendered, so what an Owner reads is provably the object that `consume_approval` will compare (P6). A row whose text was
 * scrubbed (retention) or whose hash does not match yields `{ kind: "removed" }` / `{ kind: "unverifiable" }`: the
 * caller shows no Approve button for either.
 *
 * Server-only (renders with `./render`). Never imports the decide path.
 */

import type { ApprovalWireStatus } from "@/lib/approval-wire";
import { CANONICAL_VERSION, computeActionHash, type CanonicalAction } from "./canonical";
import { renderApprovalView, type ApprovalView } from "./render";
import { isApprovalRequiredTool } from "./tools";

export interface StoredApprovalRow {
  id: string;
  workspace_id: string;
  conversation_id: string;
  tool_name: string;
  action_sha256: string;
  status: ApprovalWireStatus;
  expires_at: string;
  created_at: string;
  decided_at: string | null;
  decided_by: string | null;
  consumed_at: string | null;
  /** Set once when an Owner took an approved, unconsumed request back (status `rejected`). */
  revoked_at: string | null;
  canonical_action: unknown;
}

/**
 * The row as the Owner landing page reads it: it also selects `requested_by_user_id` (#9601). The key is REQUIRED so a
 * `ROW_COLUMNS` that loses the column fails type-check; a runtime row without the key (`undefined`, an older select) gets NO
 * label (the page does not call the labeler), while an explicit `null` (an erased account) gets the labeler's fixed
 * fallback "a workspace member". `inbox-enrich.ts` stays on the base type.
 */
export interface StoredApprovalRowWithRequester extends StoredApprovalRow {
  requested_by_user_id: string | null;
}

export type ApprovalRead =
  | { kind: "ok"; action: CanonicalAction; view: ApprovalView }
  | { kind: "removed" }
  | { kind: "unverifiable" };

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

export function readStoredApproval(row: StoredApprovalRow): ApprovalRead {
  if (row.canonical_action === null || row.canonical_action === undefined) return { kind: "removed" };
  const c = row.canonical_action;
  if (!isObj(c) || c.v !== CANONICAL_VERSION || typeof c.tool !== "string" || !isApprovalRequiredTool(c.tool) || !isObj(c.fields)) {
    return { kind: "unverifiable" };
  }
  const action = c as unknown as CanonicalAction;
  try {
    const hash = computeActionHash({
      toolName: row.tool_name,
      workspaceId: row.workspace_id,
      conversationId: row.conversation_id,
      action,
    });
    if (hash !== row.action_sha256) return { kind: "unverifiable" };
    return { kind: "ok", action, view: renderApprovalView(action) };
  } catch {
    return { kind: "unverifiable" };
  }
}
