// Bulk-archive eligibility — the SINGLE predicate consumed by both sides of
// POST /api/inbox/bulk-archive (feat-inbox-bulk-archive, #9284):
//   (a) the UI (disabled-with-reason checkboxes, select-all filtering),
//   (b) the server handler (classifier that decides `guarded` vs `conflict`
//       and refuses to dispatch an RPC for an ineligible id).
//
// PURE + client-safe: no server imports. Mirrors `lib/inbox-severity.ts`'s
// contract. Two write paths depend on this staying in sync with the RPCs —
// `set_inbox_item_state` (mig 122: archive-guard on un-acted action_required)
// and `set_email_triage_status` (mig 111 + 145: new→acknowledged|archived,
// statutory pin). If either RPC's rules change, this module must move with it.

import type { MergedInboxItem } from "@/lib/inbox-severity";

export type ArchiveEligibilityReason =
  | "ok"
  | "statutory"
  | "needs_action"
  | "already_acknowledged"
  | "already_archived";

/** Copy keyed by reason — the disabled-checkbox affordance (CPO note:
 * a disabled control with no stated reason reads as a bug, not a boundary). */
export const REASON_COPY: Record<
  Exclude<ArchiveEligibilityReason, "ok">,
  string
> = {
  statutory: "Statutory — must stay visible",
  needs_action: "Awaiting your call",
  already_acknowledged: "Already acknowledged",
  already_archived: "Already archived",
};

export interface BulkItemRef {
  kind: "inbox" | "email";
  id: string;
}

export type BulkOutcome =
  | "archived"
  | "guarded"
  | "not_found"
  | "conflict"
  | "error";

/** The POST /api/inbox/bulk-archive response contract — shared client+server
 * so the wire shape can't drift. */
export interface BulkItemResult extends BulkItemRef {
  outcome: BulkOutcome;
  reason?: ArchiveEligibilityReason;
}

/** Selection-set key — one definition shared by the surface, the request
 * body, and results intersection. */
export function keyOf(item: BulkItemRef): string {
  return `${item.kind}:${item.id}`;
}

/** Inverse of keyOf — the wire format's ONLY parser lives next to its
 * serializer. `kind` never contains ":". */
export function unkey(key: string): BulkItemRef {
  const idx = key.indexOf(":");
  return {
    kind: key.slice(0, idx) as BulkItemRef["kind"],
    id: key.slice(idx + 1),
  };
}

/** Email rows (email_triage_items). Mirrors `set_email_triage_status`:
 * transitions only from `new`; statutory rows are never archivable (mig 145). */
export function emailRowEligibility(row: {
  status: string;
  statutory_class: string | null;
}): ArchiveEligibilityReason {
  if (row.status === "archived") return "already_archived";
  if (row.statutory_class !== null) return "statutory";
  // The CHECK constraint bounds status to new|acknowledged|archived — any
  // non-new, non-archived value can only be acknowledged.
  if (row.status !== "new") return "already_acknowledged";
  return "ok";
}

/** Inbox rows (inbox_item). Mirrors `set_inbox_item_state`: the archive-guard
 * rejects an un-acted action_required item. */
export function inboxRowEligibility(row: {
  severity: string;
  acted_at: string | null;
  status: string;
}): ArchiveEligibilityReason {
  if (row.status === "archived") return "already_archived";
  if (row.severity === "action_required" && row.acted_at === null) {
    return "needs_action";
  }
  return "ok";
}

/** Client-side adapter over the merged feed row. */
export function archiveEligibility(
  item: MergedInboxItem,
): ArchiveEligibilityReason {
  return item.kind === "email"
    ? emailRowEligibility(item.email)
    : inboxRowEligibility(item.inbox);
}
