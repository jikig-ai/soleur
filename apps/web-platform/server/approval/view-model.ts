/**
 * Verified read model of a stored approval row for the Owner-facing surfaces (#4672): the away-user landing page and the
 * inbox row. The stored `canonical_action` is re-hashed and compared with the row's bound `action_sha256` before it is
 * rendered, so what an Owner reads is provably the object that `consume_approval` will compare (P6). A row whose text was
 * scrubbed (retention) or whose hash does not match yields `{ kind: "removed" }` / `{ kind: "unverifiable" }`: the
 * caller shows no Approve button for either.
 *
 * Server-only (renders with `./render`). Never imports the decide path.
 */

import { CANONICAL_VERSION, computeActionHash, type CanonicalAction } from "./canonical";
import { renderApprovalView, type ApprovalView } from "./render";
import { isApprovalRequiredTool } from "./tools";

export interface StoredApprovalRow {
  id: string;
  workspace_id: string;
  conversation_id: string;
  tool_name: string;
  action_sha256: string;
  status: "pending" | "approved" | "rejected" | "expired" | "consumed";
  expires_at: string;
  created_at: string;
  decided_at: string | null;
  decided_by: string | null;
  consumed_at: string | null;
  canonical_action: unknown;
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
