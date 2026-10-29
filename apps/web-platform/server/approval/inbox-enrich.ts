/**
 * Enrich `approval_required` inbox rows for GET /api/inbox (#4672, wireframe 06).
 *
 * The stored inbox_item title is static and content-free on purpose (ADR-085: it is also what push and email derive from).
 * The in-product row, behind sign-in, names the action in full, so this reads the approval requests the rows point at on the
 * CALLER's RLS client (Owner-only select) and rebuilds the row text from the stored canonical action, re-verified against
 * the bound hash like the landing page. A failed or empty read leaves the row on its static title: never a wrong row.
 *
 * Never used for the inbox_list agent tool: the agent reads the static titles only.
 */

import type { InboxItemRowData } from "@/lib/inbox-severity";
import { reportApprovalOp } from "./ops";
import { renderApprovalInboxTitle, type ApprovalInboxState } from "./render";
import { readStoredApproval, type StoredApprovalRow } from "./view-model";

interface RlsClient {
  from(table: string): {
    select(cols: string): { in(col: string, vals: string[]): PromiseLike<{ data: unknown; error: unknown }> };
  };
}

const COLUMNS = "id, workspace_id, conversation_id, tool_name, action_sha256, status, expires_at, created_at, decided_at, decided_by, consumed_at, revoked_at, canonical_action";

function stateOf(r: StoredApprovalRow): ApprovalInboxState {
  if (r.status === "expired") return r.decided_at ? "expired_after_approval" : "expired";
  return r.status;
}

export async function enrichApprovalInboxRows(client: RlsClient, rows: InboxItemRowData[]): Promise<InboxItemRowData[]> {
  const ids = [
    ...new Set(
      rows
        .filter((r) => r.source === "approval_required")
        .map((r) => r.source_ref?.approvalId)
        .filter((v): v is string => typeof v === "string"),
    ),
  ];
  if (ids.length === 0) return rows;
  let byId = new Map<string, StoredApprovalRow>();
  try {
    const { data, error } = await client.from("approval_request").select(COLUMNS).in("id", ids);
    if (error) throw error;
    byId = new Map((Array.isArray(data) ? (data as StoredApprovalRow[]) : []).map((a) => [a.id, a]));
  } catch (err) {
    reportApprovalOp("inboxEnrichFailed", err, {});
    return rows;
  }
  return rows.map((r) => {
    if (r.source !== "approval_required") return r;
    const a = r.source_ref?.approvalId ? byId.get(r.source_ref.approvalId) : undefined;
    if (!a) return r;
    const read = readStoredApproval(a);
    const title = read.kind === "ok" ? renderApprovalInboxTitle(read.action, stateOf(a), r.title) : r.title;
    return { ...r, title, approval: { status: a.status, expiresAt: a.expires_at } };
  });
}
