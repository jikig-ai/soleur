// #9545 PR2 — types and pure helpers for the egress audit view (client-safe: no server imports).

/** The decision filter as the URL and the chips spell it. `blocked` is the stored `denied`. */
export type DecisionFilter = "all" | "allowed" | "blocked" | "other";

export const DECISION_FILTERS: readonly DecisionFilter[] = ["all", "allowed", "blocked", "other"];

/** An unknown or repeated `?decision=` value falls back to `all`; it is never a 400. */
export function parseDecisionFilter(raw: string | string[] | undefined): DecisionFilter {
  const v = Array.isArray(raw) ? raw[0] : raw;
  return (DECISION_FILTERS as readonly string[]).includes(v ?? "") ? (v as DecisionFilter) : "all";
}

/** The RPC's `p_decision` for a filter (`null` = every outcome). */
export function toRpcDecision(filter: DecisionFilter): "allowed" | "denied" | "other" | null {
  if (filter === "all") return null;
  return filter === "blocked" ? "denied" : filter;
}

export type StoredDecision = "allowed" | "denied" | "other";
export type Outcome = "Allowed" | "Blocked" | "Other";

export function outcomeOf(decision: string): Outcome {
  if (decision === "denied") return "Blocked";
  if (decision === "allowed") return "Allowed";
  return "Other";
}

/** The RPC's jsonb, as `get_egress_audit_summary` returns it (migration 177). */
export interface EgressAuditPayload {
  window: { start: string; end: string };
  truncated: boolean;
  summary: {
    request_count_min: number | null;
    blocked_request_count_min: number | null;
    last_request_at: string | null;
  };
  rows: { host: string; decision: string; request_count: number; last_seen: string }[];
  overflow: { decision: string; request_count: number; last_seen: string }[];
}

/** Whether the `egress-audit-collection` flag is on for the workspace's org; `"unknown"` = not determinable. */
export type CollectionState = true | false | "unknown";

/** What the page loader hands the view. An error is a value, never an empty log. */
export type EgressAuditResult =
  | {
      kind: "ready";
      data: EgressAuditPayload;
      collection: CollectionState;
      /** null = the read failed or returned null (unknown), which the view treats as unavailable for the empties. */
      webAccess: boolean | null;
      workspaceName: string | null;
    }
  | { kind: "forbidden" }
  | { kind: "unbound" }
  | { kind: "unavailable" };

/**
 * What the Scope Grants card needs: the last recorded request and the collection state. `workspaceId` is the
 * workspace the loader read them for; the page compares it with its own active workspace and discards both on a
 * mismatch. The toggle never receives it.
 */
export type EgressCardState = {
  lastRequestAt: string | null;
  collection: CollectionState;
  workspaceId: string | null;
};

/** Host rows the page asks the RPC for; the view's truncation copy quotes the same number. */
export const PAGE_LIMIT = 200;

/** The destination page, linked from the card and from the filter chips. */
export const EGRESS_AUDIT_PATH = "/dashboard/settings/scope-grants/egress-audit";

/**
 * Every in-body denial the RPC raises (membership, revoked token) starts with this text, so the loader can
 * tell it from the engine's own "permission denied for function" (same SQLSTATE 42501, a lost grant).
 */
export const RPC_DENIAL_PREFIX = "egress audit: ";

const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const isCount = (v: unknown): v is number => typeof v === "number" && Number.isSafeInteger(v) && v >= 0;
const isTimestamp = (v: unknown): v is string => typeof v === "string" && Number.isFinite(Date.parse(v));

const isRow = (v: unknown): boolean =>
  isRecord(v) && typeof v.host === "string" && typeof v.decision === "string" && isCount(v.request_count) && isTimestamp(v.last_seen);
// An unknown stored decision is tolerated here (any string): the view maps it to "Other".
const isOverflowRow = (v: unknown): boolean =>
  isRecord(v) && typeof v.decision === "string" && isCount(v.request_count) && isTimestamp(v.last_seen);

/**
 * Structural check at the trust boundary, per element: a malformed body (or one bad row) is an error, never an
 * empty or partial log, and nothing downstream can throw on a field the type promised.
 */
export function isEgressAuditPayload(v: unknown): v is EgressAuditPayload {
  if (!isRecord(v)) return false;
  const { window: w, truncated, summary: s, rows, overflow } = v;
  if (!isRecord(w) || typeof w.start !== "string" || typeof w.end !== "string") return false;
  if (typeof truncated !== "boolean") return false;
  if (!isRecord(s) || !("last_request_at" in s)) return false;
  if (s.request_count_min !== null && !isCount(s.request_count_min)) return false;
  if (s.blocked_request_count_min !== null && !isCount(s.blocked_request_count_min)) return false;
  if (s.last_request_at !== null && !isTimestamp(s.last_request_at)) return false;
  return Array.isArray(rows) && rows.every(isRow) && Array.isArray(overflow) && overflow.every(isOverflowRow);
}

/** "at least 4,812": every count is a minimum (best-effort capture). */
export function formatAtLeast(n: number): string {
  return `at least ${n.toLocaleString("en-US")}`;
}

/** Long-form relative time ("4 minutes ago"), clamped at zero so a clock skew never reads "in the future". */
export function formatAgo(iso: string, now: number = Date.now()): string {
  const then = new Date(iso).getTime();
  if (!Number.isFinite(then)) return "at an unknown time";
  const ms = Math.max(0, now - then);
  const mins = Math.floor(ms / 60_000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins} minute${mins === 1 ? "" : "s"} ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs} hour${hrs === 1 ? "" : "s"} ago`;
  const days = Math.floor(hrs / 24);
  if (days === 1) return "yesterday";
  return `${days} days ago`;
}
