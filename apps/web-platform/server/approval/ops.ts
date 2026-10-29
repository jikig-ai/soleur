/**
 * Observability for the approval gate (#4672): the Sentry fault ops and the `SOLEUR_APPROVAL_*` log markers.
 *
 * Two channels, on purpose:
 *  - Sentry carries only FAULTS and degraded conditions an operator must see. Every op has its OWN static message
 *    (never a shared default, never tool input or database text), tagged with `approval_id`, so one Sentry group is
 *    one condition. `approval_id` is a row UUID, not personal data; it is the one tag that lets an operator walk from
 *    an event to the row (the same id is in every marker).
 *  - Better Stack carries the lifecycle as `SOLEUR_APPROVAL_*` markers (information, not faults). The app
 *    container source ships a pino line only at level >= 40 (`app_container_warn_filter` in infra/vector.toml), so a
 *    marker is logged at WARN: it is the level that reaches the aggregator, not a severity claim. Markers carry ids and
 *    the tool name only, never action text (the Vector user-content key drop is a backstop, not the control).
 *
 * The ops registry is the single place a message string lives; a test fails when two ops share an op name or a message.
 * Ops fired by the expiry cron (a later unit) are registered here too so the uniqueness check covers the whole family.
 */

import { createChildLogger } from "../logger";
import { reportSilentFallback, warnSilentFallback } from "../observability";

const log = createChildLogger("approval");

const FEATURE = "approval-queue";

export interface ApprovalOp {
  readonly op: string;
  readonly message: string;
  readonly level: "error" | "warn";
}

export const APPROVAL_OPS = {
  /** `create_approval_request` (or the canonical/hash step before it) failed: the gate denies. */
  createFailed: {
    op: "approval-create-failed",
    message: "Approval gate: could not create the approval request; the action was denied",
    level: "error",
  },
  /** Anything unexpected inside the approval flow (a throw, an unknown outcome): the gate denies. */
  gateFailed: {
    op: "approval-gate-failed",
    message: "Approval gate: unexpected failure inside the approval flow; the action was denied",
    level: "error",
  },
  /** The server-derived fields (reply recipient, repository, HEAD) could not be resolved: nothing to bind, deny. */
  bindFailed: {
    op: "approval-bind-failed",
    message: "Approval gate: the server-derived fields could not be resolved; the action was denied",
    level: "error",
  },
  /** The agent stopped waiting (5 minutes) and the request is still pending. Routine; the row stays pending. */
  waitTimeout: {
    op: "approval-wait-timeout",
    message: "Approval gate: the agent stopped waiting while the request was still pending",
    level: "warn",
  },
  /** The request expired (observed by a waiting gate, or swept by the cron). */
  expired: {
    op: "approval-expired",
    message: "Approval gate: the request expired before it was consumed",
    level: "warn",
  },
  /** `consume_approval` did not return `consumed: true` (changed input, replay, expiry, wrong conversation). */
  consumeRejected: {
    op: "approval-consume-rejected",
    message: "Approval gate: the approval could not be consumed for this call; the action was denied",
    level: "warn",
  },
  /** The agent asked again for an action that already has earlier requests (request count 2 or more). */
  reproposed: {
    op: "approval-reproposed",
    message: "Approval gate: the agent proposed the same action again",
    level: "warn",
  },
  /** The card or the notification could not be delivered; the inbox row remains the fallback surface. */
  notifyFailed: {
    op: "approval-notify-failed",
    message: "Approval gate: the approval card or notification could not be delivered",
    level: "warn",
  },
  /** A decision could not be recorded (RPC error on the decide path). */
  decideFailed: {
    op: "approval-decide-failed",
    message: "Approval gate: the decision could not be recorded",
    level: "error",
  },
  /** Re-sending live approval cards on session attach failed. */
  reattachFailed: {
    op: "approval-reattach-failed",
    message: "Approval gate: live approval cards could not be re-sent on session attach",
    level: "warn",
  },
  /** The away-user landing page could not read the row (RLS read error, not a missing row). */
  landingReadFailed: {
    op: "approval-landing-read-failed",
    message: "Approval gate: the landing page could not read the approval request",
    level: "error",
  },
  /** GET /api/inbox could not read the approval requests behind the inbox rows; the rows keep their static title. */
  inboxEnrichFailed: {
    op: "approval-inbox-enrich-failed",
    message: "Approval gate: the inbox could not read the approval requests behind its rows",
    level: "warn",
  },
  /** Reserved for the expiry cron (15 minutes pending): alert-reference registers THIS op only. */
  gateUnanswered: {
    op: "gate_unanswered",
    message: "Approval gate unanswered: a request has been pending for more than 15 minutes",
    level: "warn",
  },
} as const satisfies Record<string, ApprovalOp>;

export type ApprovalOpKey = keyof typeof APPROVAL_OPS;

export interface ApprovalOpContext {
  approvalId?: string;
  toolName?: string;
  conversationId?: string;
  workspaceId?: string;
  userId?: string;
  extra?: Record<string, unknown>;
}

/**
 * Report one approval op. `err` is the caught error (its message is static for `ApprovalServiceError`) or null for a
 * condition with no error object, in which case the op's static message is the Sentry message.
 */
export function reportApprovalOp(key: ApprovalOpKey, err: unknown, ctx: ApprovalOpContext = {}): void {
  const def: ApprovalOp = APPROVAL_OPS[key];
  const options = {
    feature: FEATURE,
    op: def.op,
    message: def.message,
    tags: ctx.approvalId ? { approval_id: ctx.approvalId } : undefined,
    extra: {
      ...(ctx.toolName ? { tool: ctx.toolName } : {}),
      ...(ctx.conversationId ? { conversationId: ctx.conversationId } : {}),
      ...(ctx.workspaceId ? { workspaceId: ctx.workspaceId } : {}),
      ...(ctx.userId ? { userId: ctx.userId } : {}),
      ...ctx.extra,
    },
  };
  try {
    if (def.level === "error") reportSilentFallback(err ?? null, options);
    else warnSilentFallback(err ?? null, options);
  } catch {
    // Observability must never turn a deny into a throw.
  }
}

export const APPROVAL_MARKERS = [
  "SOLEUR_APPROVAL_REQUESTED",
  "SOLEUR_APPROVAL_DECIDED",
  "SOLEUR_APPROVAL_CONSUMED",
  "SOLEUR_APPROVAL_EXPIRED",
  "SOLEUR_APPROVAL_SWEEP",
] as const;
export type ApprovalMarker = (typeof APPROVAL_MARKERS)[number];

/**
 * Log one lifecycle marker. The message is `<MARKER> key=value ...` so one grep reconstructs the lifecycle. Values are
 * ids, enums and counts; never action text. Logged at warn so the line reaches Better Stack (see the file header).
 */
export function logApprovalMarker(marker: ApprovalMarker, fields: Record<string, string | number | boolean | null | undefined>): void {
  const pairs = Object.entries(fields)
    .filter(([, v]) => v !== undefined && v !== null)
    .map(([k, v]) => `${k}=${String(v)}`)
    .join(" ");
  log.warn({ sec: true, marker, ...fields }, pairs ? `${marker} ${pairs}` : marker);
}
