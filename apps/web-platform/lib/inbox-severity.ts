// Shared severity + merge contract for the unified inbox (feat-severity-ranked-inbox
// #6007). The SINGLE source of truth consumed by:
//   (a) GET /api/inbox (server route),
//   (b) the inbox_list agent tool (agent-native parity AP-004),
//   (c) the nav badge (must run the SAME clock/severity logic — a naive
//       status='new' count would drift).
//
// PURE + client-safe: no server imports (no supabase, no pino). The DB fetch
// lives in server/inbox-sources.ts; this module only ranks already-fetched rows.
//
// Load-bearing invariant (operator "pin all, calm the visuals" decision,
// 2026-07-04): EVERY non-archived statutory email row is `action_required`,
// pinned first, and EXEMPT from the NEEDS YOU cap — regardless of clock or
// acknowledgment status (acknowledgment is workflow state, not legal
// resolution; it never demotes). Severity NEVER derives from a deadline, so a
// cosmetic near/far-deadline chip can never move a statutory item out of NEEDS
// YOU or below the pin.

import type { EmailTriageItem } from "@/components/inbox/email-triage-row";
import type { ApprovalWireStatus } from "@/lib/approval-wire";
import type { LegalCardStateWire } from "@/lib/legal-acceptance-wire";
import { isUuid } from "@/lib/is-uuid";

export type InboxItemSeverity = "action_required" | "attention" | "info";

/** Native sources (mig 122 CHECK, widened by mig 180 for #4672). `autopilot_run` ships with #4674. */
export type InboxItemSource = "task_completed" | "system" | "approval_required";

/**
 * Render-time facts about the approval request behind an `approval_required` row, attached by GET /api/inbox from an
 * Owner-RLS read (the stored `title` is static and content-free by design; the row text and the expiry chip come from the
 * request itself). Absent on every other source and whenever the enrichment read failed: the row then renders its static
 * title and no chip.
 */
export interface InboxApprovalInfo {
  status: ApprovalWireStatus;
  expiresAt: string;
}

/** A native inbox_item row (subset the surface + merge consume). */
export interface InboxItemRowData {
  id: string;
  severity: InboxItemSeverity;
  source: InboxItemSource;
  title: string;
  source_ref: Record<string, string> | null;
  status: "unread" | "read" | "archived";
  created_at: string;
  read_at: string | null;
  acted_at: string | null;
  archived_at: string | null;
  /** #4672 — present only on enriched `approval_required` rows. */
  approval?: InboxApprovalInfo;
}

/**
 * The states a founder legal-text row can be in. `replaced` is not one of them: a row is always derived for the registry's
 * CURRENT hash, so a text that changed with no answer yet is simply `pending` again for the new version.
 */
export type LegalInboxState = Exclude<LegalCardStateWire, "replaced">;

/**
 * One founder legal-text row as derived by the server (`server/legal-acceptance/inbox-rows.ts`). Only these facts reach the
 * client: no text hash, no note, no timestamp, no account id. `validUntil` is the registry's public `valid_until` (for the
 * "Open until" chip), `version` is the registry's ISO date.
 */
export interface LegalInboxRowData {
  key: string;
  label: string;
  version: string;
  validUntil: string | null;
  state: LegalInboxState;
  severity: InboxItemSeverity;
  outstanding: boolean;
}

/** The unified, ordered row the route returns and the surface renders. */
export type MergedInboxItem =
  | {
      kind: "email";
      id: string;
      severity: InboxItemSeverity;
      /** email-statutory only — pinned first + exempt from the NEEDS YOU cap. */
      pinned: boolean;
      /** action_required and not yet resolved — drives the nav badge count. */
      outstanding: boolean;
      email: EmailTriageItem;
    }
  | {
      kind: "inbox";
      id: string;
      severity: InboxItemSeverity;
      pinned: false;
      outstanding: boolean;
      inbox: InboxItemRowData;
    }
  | {
      /** The founder's legal text (Ref #12197): derived at request time, never stored, never archivable. `id` is the registry key. */
      kind: "legal";
      id: string;
      severity: InboxItemSeverity;
      pinned: false;
      /** Only a `pending` text is outstanding; every other state, `expired` included, is FYI. */
      outstanding: boolean;
      legal: Omit<LegalInboxRowData, "severity" | "outstanding">;
    };

/** Visible NEEDS YOU cap (banner-blindness guard). Pinned statutory is exempt. */
export const NEEDS_YOU_CAP = 20;

const SEVERITY_RANK: Record<InboxItemSeverity, number> = {
  action_required: 0,
  attention: 1,
  info: 2,
};

export function severityRank(sev: InboxItemSeverity): number {
  return SEVERITY_RANK[sev];
}

/** An email row is statutory iff it carries a statutory_class. */
export function isStatutoryEmail(row: EmailTriageItem): boolean {
  return row.statutory_class !== null;
}

/**
 * Per-source severity — the product's precision rule (tested, not code-buried).
 * Email: statutory → action_required (ALWAYS, clock/status-independent), else
 * info. Native inbox rows carry their own severity.
 */
export function deriveEmailSeverity(row: EmailTriageItem): InboxItemSeverity {
  return isStatutoryEmail(row) ? "action_required" : "info";
}

/**
 * Deep link built from source_ref ids AT RENDER (never a stored URL). Returns
 * null when the target does not exist yet (a source whose child hasn't shipped)
 * or the ref is missing — the surface renders such a row non-navigating rather
 * than dead-ending on a 404.
 */
export function buildInboxDeepLink(
  source: string,
  sourceRef: Record<string, string> | null,
): string | null {
  switch (source) {
    case "task_completed": {
      const id = sourceRef?.conversationId;
      return id ? `/dashboard/chat/${id}` : null;
    }
    case "system": {
      // A system item may carry an explicit same-origin relative path; else it
      // lands on the dashboard. Reject protocol-relative `//host` (open-redirect
      // via router.push) — `startsWith("/")` alone would accept it.
      const path = sourceRef?.path;
      if (path && path.startsWith("/") && !path.startsWith("//")) return path;
      return "/dashboard";
    }
    case "approval_required": {
      // The id is interpolated into a path, so it must be exactly a UUID (never a free string from a stored ref).
      const id = sourceRef?.approvalId;
      return id && isUuid(id) ? `/dashboard/approvals/${id}` : null;
    }
    default:
      // autopilot_run's target is built by #4674.
      return null;
  }
}

function toMergedEmail(row: EmailTriageItem): MergedInboxItem {
  const statutory = isStatutoryEmail(row);
  const nonArchived = row.status !== "archived";
  return {
    kind: "email",
    id: row.id,
    severity: deriveEmailSeverity(row),
    // Pin every non-archived statutory row (clock/status-independent).
    pinned: statutory && nonArchived,
    // Statutory items are always outstanding until archived (ack never resolves).
    outstanding: statutory && nonArchived,
    email: row,
  };
}

function toMergedInbox(row: InboxItemRowData): MergedInboxItem {
  return {
    kind: "inbox",
    id: row.id,
    severity: row.severity,
    pinned: false,
    outstanding: row.severity === "action_required" && row.acted_at === null,
    inbox: row,
  };
}

function toMergedLegal(row: LegalInboxRowData): MergedInboxItem {
  return {
    kind: "legal",
    id: row.key,
    severity: row.severity,
    pinned: false,
    outstanding: row.outstanding,
    legal: { key: row.key, label: row.label, version: row.version, validUntil: row.validUntil, state: row.state },
  };
}

/** The ISO timestamp (or date) a row sorts by. A legal row has no event time; the registry's `version` is an ISO date. */
function sortIso(m: MergedInboxItem): string {
  switch (m.kind) {
    case "email":
      return m.email.received_at;
    case "inbox":
      return m.inbox.created_at;
    case "legal":
      return m.legal.version;
    default: {
      const _exhaustive: never = m;
      return _exhaustive;
    }
  }
}

function sortTime(m: MergedInboxItem): number {
  const t = Date.parse(sortIso(m));
  return Number.isNaN(t) ? 0 : t;
}

/**
 * Merge + rank both sources into ONE ordered list. Ordering (the load-bearing
 * contract): (1) non-archived statutory pinned first, uncapped; (2) severity
 * rank (action_required > attention > info); (3) recency DESC. A statutory clock
 * can never fall below the fold because a statutory item is never below the pin.
 * The caller renders in this order and never re-sorts.
 */
export function mergeAndRank(
  inboxRows: InboxItemRowData[],
  emailRows: EmailTriageItem[],
  legalRows: LegalInboxRowData[] = [],
): MergedInboxItem[] {
  const merged = [
    ...emailRows.map(toMergedEmail),
    ...inboxRows.map(toMergedInbox),
    ...legalRows.map(toMergedLegal),
  ];
  merged.sort((a, b) => {
    if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
    const rank = severityRank(a.severity) - severityRank(b.severity);
    if (rank !== 0) return rank;
    return sortTime(b) - sortTime(a); // recency DESC
  });
  return merged;
}

/** Outstanding action_required count for the nav badge (regardless of read). */
export function countOutstandingActionRequired(items: MergedInboxItem[]): number {
  return items.filter((m) => m.severity === "action_required" && m.outstanding)
    .length;
}

/**
 * Partition the merged list into the two UI groups and apply the visible
 * NEEDS YOU cap. Pinned (statutory) items are ALWAYS visible — only non-pinned
 * action_required rows overflow. Preserves the merged order within each group.
 */
export function partitionForDisplay(items: MergedInboxItem[]): {
  needsYouVisible: MergedInboxItem[];
  needsYouOverflow: number;
  goodToKnow: MergedInboxItem[];
} {
  const needsYou = items.filter((m) => m.severity === "action_required");
  const goodToKnow = items.filter((m) => m.severity !== "action_required");

  const pinned = needsYou.filter((m) => m.pinned);
  const unpinned = needsYou.filter((m) => !m.pinned);
  const room = Math.max(0, NEEDS_YOU_CAP - pinned.length);
  const unpinnedVisible = unpinned.slice(0, room);
  const needsYouOverflow = unpinned.length - unpinnedVisible.length;

  return {
    // Pinned first (already ordered by mergeAndRank), then visible unpinned.
    needsYouVisible: [...pinned, ...unpinnedVisible],
    needsYouOverflow,
    goodToKnow,
  };
}
