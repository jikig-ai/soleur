/**
 * Client-safe single source for the approval status and decide-outcome vocabularies (#4672). Pure leaf: no imports, so
 * `lib/types.ts`, the zod schemas, the landing page and the inbox types can all read it without crossing the
 * client/server import boundary. The server holds its own tuples (`APPROVAL_STATUSES` in server/approval/service.ts,
 * `DECIDE_OUTCOMES` in server/approval/decide.ts); test/approval/wire-parity.test.ts derives the expected sets from
 * those and fails when either side drifts.
 */

export const APPROVAL_WIRE_STATUSES = ["pending", "approved", "rejected", "expired", "consumed"] as const;
export type ApprovalWireStatus = (typeof APPROVAL_WIRE_STATUSES)[number];

export const APPROVAL_WIRE_DECIDE_OUTCOMES = [
  "decided",
  "unchanged",
  "already_decided",
  "conflict",
  "revoked",
  "expired",
  "closed",
] as const;
export type ApprovalDecideOutcomeWire = (typeof APPROVAL_WIRE_DECIDE_OUTCOMES)[number];

export function isApprovalWireStatus(v: unknown): v is ApprovalWireStatus {
  return typeof v === "string" && (APPROVAL_WIRE_STATUSES as readonly string[]).includes(v);
}

export function isApprovalDecideOutcomeWire(v: unknown): v is ApprovalDecideOutcomeWire {
  return typeof v === "string" && (APPROVAL_WIRE_DECIDE_OUTCOMES as readonly string[]).includes(v);
}
