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

/** Structural check at the trust boundary: a malformed body is an error, never an empty log. */
export function isEgressAuditPayload(v: unknown): v is EgressAuditPayload {
  if (typeof v !== "object" || v === null) return false;
  const p = v as Record<string, unknown>;
  const s = p.summary as Record<string, unknown> | null | undefined;
  return (
    Array.isArray(p.rows) &&
    Array.isArray(p.overflow) &&
    typeof p.truncated === "boolean" &&
    typeof s === "object" &&
    s !== null &&
    "last_request_at" in s
  );
}

/** "at least 4,812": every count is a minimum (best-effort capture). */
export function formatAtLeast(n: number): string {
  return `at least ${n.toLocaleString("en-US")}`;
}

/** Long-form relative time ("4 minutes ago"), clamped at zero so a clock skew never reads "in the future". */
export function formatAgo(iso: string, now: number = Date.now()): string {
  const ms = Math.max(0, now - new Date(iso).getTime());
  const mins = Math.floor(ms / 60_000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins} minute${mins === 1 ? "" : "s"} ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs} hour${hrs === 1 ? "" : "s"} ago`;
  const days = Math.floor(hrs / 24);
  if (days === 1) return "yesterday";
  return `${days} days ago`;
}

/** Absolute time for a `title` attribute. */
export function formatAbsolute(iso: string): string {
  return new Date(iso).toISOString().replace("T", " ").replace(/:\d{2}\.\d{3}Z$/, " UTC");
}
