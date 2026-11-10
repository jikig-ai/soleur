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
 * Ops fired by the expiry cron are registered here too so the uniqueness check covers the whole family.
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
  /** The expiry cron's `sweep_approvals()` call failed; the next 5-minute tick retries. */
  sweepFailed: {
    op: "approval-sweep-failed",
    message: "Approval expiry cron: the sweep_approvals call failed; the next tick retries",
    level: "error",
  },
  /** A pending cap was reached (5 per conversation, 20 per workspace): nothing was saved, the gate denies with static text. */
  capReached: {
    op: "approval-cap-reached",
    message: "Approval gate: too many requests are already waiting for the Owner; the new request was not saved",
    level: "warn",
  },
  /** The model's arguments cannot be approved as given (missing/invalid/uncovered field). Low volume. */
  invalidInput: {
    op: "approval-invalid-input",
    message: "Approval gate: the arguments cannot be approved as given; the action was denied",
    level: "warn",
  },
  /** The approval was consumed (spent) but the session had already ended, so the action was denied. */
  consumedAborted: {
    op: "approval-consumed-aborted",
    message: "Approval gate: the approval was spent but the session ended before the action ran",
    level: "warn",
  },
  /** Status reads failed during a wait; ONE event per wait with the count (not one per poll). */
  waitReadFailed: {
    op: "approval-wait-read-failed",
    message: "Approval gate: status reads failed while waiting for the Owner",
    level: "warn",
  },
  /** The requester's role could not be read; the card falls back to the read-only member view. */
  viewerRoleFailed: {
    op: "approval-viewer-role-failed",
    message: "Approval gate: the viewer role could not be read; the card shows the read-only view",
    level: "warn",
  },
  /** The requester label (who raised the request) could not be read; the card shows no requester line. Ids only, never the address. */
  requesterLabelFailed: {
    op: "approval-requester-label-failed",
    message: "Approval card: the requester label could not be read; the card shows no requester line",
    level: "warn",
  },
  /** The `approval-queue` flag read threw; the flag is treated as OFF. Debounced to one report per 10 minutes per process (flag.ts). */
  flagReadFailed: {
    op: "approval-flag-read-failed",
    message: "Approval gate: the approval-queue flag could not be read; the flag was treated as off",
    level: "warn",
  },
  /**
   * An execution grant was refused at a tool handler (the approval flow ran in the session but the handler could not
   * match what the Owner approved): the action was NOT performed. `extra.reason` is one of GRANT_REFUSED_REASONS and
   * `extra.tool` is the tool; the approval id is not known to the handler. Low volume (a refusal is an abnormal path).
   */
  grantRefused: {
    op: "approval-grant-refused",
    message: "Approval gate: a tool handler refused to run because the execution grant did not match; the action was not performed",
    level: "warn",
  },
  /**
   * The keyed-hash secret (SENTRY_USERID_PEPPER) is unset or empty: no approval can be hashed, so EVERY gated call denies.
   * Error level, own op, so one alert covers a mis-deployed container without sharing a group with other gate failures.
   */
  keyUnavailable: {
    op: "approval-key-unavailable",
    message: "Approval gate: the approval hash key is unavailable (SENTRY_USERID_PEPPER unset or empty); gated actions are denied",
    level: "error",
  },
  /**
   * The gate's no-git read of the workspace HEAD (`readWorkspaceHeadSha`) refused for a `github_push_branch` card (ADR-309 9b):
   * no card was created and the gate denies. `tags.reason` / `extra.reason` is the reader's closed `WorkspaceHeadReason`, never
   * the Error, a path or file content. The gate's `approval-bind-failed` report still fires after it.
   */
  headReadFailed: {
    op: "approval-head-read-failed",
    message: "Approval gate: the workspace HEAD could not be read safely for the push; no approval card was created",
    level: "error",
  },
  /** Fired by the expiry cron (15 minutes pending): issue-alerts registers THIS op only. */
  gateUnanswered: {
    op: "gate_unanswered",
    message: "Approval gate unanswered: a request has been pending for more than 15 minutes",
    level: "warn",
  },
} as const satisfies Record<string, ApprovalOp>;

export type ApprovalOpKey = keyof typeof APPROVAL_OPS;

/** The `extra.reason` values of the `approval-grant-refused` op (a closed set: the alert and the tests pin it). */
export const GRANT_REFUSED_REASONS = ["grant_missing", "workspace_changed", "commit_mismatch", "commit_unavailable", "grant_error"] as const;
export type GrantRefusedReason = (typeof GRANT_REFUSED_REASONS)[number];

export interface ApprovalOpContext {
  approvalId?: string;
  toolName?: string;
  conversationId?: string;
  workspaceId?: string;
  userId?: string;
  /** Extra low-cardinality Sentry TAGS (searchable), merged after `approval_id`. Static enum values only, never user content. */
  tags?: Record<string, string>;
  extra?: Record<string, unknown>;
  /** `reportLegalOp` only: sets the severity of ONE report (default: the op's own level). Ignored by `reportApprovalOp`. */
  level?: "error" | "warn";
}

/**
 * What a thrown value contributes to the event: a short code (`err.code`, else the class name), the failing RPC (`fn`) and
 * the class name. Never the message or the stack (database text can echo row content).
 */
function describeError(err: unknown): { code?: string; fn?: string; errName?: string } {
  if (err === null || err === undefined) return {};
  if (typeof err !== "object") return { errName: typeof err };
  const e = err as { code?: unknown; fn?: unknown; name?: unknown };
  return {
    ...(typeof e.code === "string" && e.code ? { code: e.code } : {}),
    ...(typeof e.fn === "string" && e.fn ? { fn: e.fn } : {}),
    ...(typeof e.name === "string" && e.name ? { errName: e.name } : {}),
  };
}

/**
 * Report one approval op. `err` is the caught error or null for a condition with no error object. The Error object is
 * NEVER handed to the Sentry helper: with an Error the pino mirror (logger.error) captures it first, without the
 * `feature`/`op` tags, and one Sentry group would hold untagged events no alert can route. The op's static message is the
 * Sentry message and the thrown value contributes only `{code, fn, errName}` in `extra`.
 */
export function reportApprovalOp(key: ApprovalOpKey, err: unknown, ctx: ApprovalOpContext = {}): void {
  const def: ApprovalOp = APPROVAL_OPS[key];
  const options = {
    feature: FEATURE,
    op: def.op,
    message: def.message,
    tags: ctx.approvalId || ctx.tags ? { ...(ctx.approvalId ? { approval_id: ctx.approvalId } : {}), ...ctx.tags } : undefined,
    extra: {
      ...(ctx.toolName ? { tool: ctx.toolName } : {}),
      ...(ctx.conversationId ? { conversationId: ctx.conversationId } : {}),
      ...(ctx.workspaceId ? { workspaceId: ctx.workspaceId } : {}),
      ...(ctx.userId ? { userId: ctx.userId } : {}),
      ...describeError(err),
      ...ctx.extra,
    },
  };
  try {
    if (def.level === "error") reportSilentFallback(null, options);
    else warnSilentFallback(null, options);
  } catch {
    // Observability must never turn a deny into a throw.
  }
}

/**
 * Founder legal acceptance ops (#12011, ADR-319). A separate registry and helper, NOT members of APPROVAL_OPS: the Sentry
 * alert rules match `feature=legal-acceptance` plus the op, while every gate op keeps `feature=approval-queue` (the gate's
 * alert and its contract tests iterate APPROVAL_OPS). Same rules as above: one static message per op, no database text,
 * the thrown value contributes only `{code, fn, errName}`, and never the note, the code, the address or the text.
 */
export const LEGAL_OPS = {
  /** One event per RECORDED row (any choice; `extra.choice` says which). The liveness signal: a row the decide route did not acknowledge after flushing this event is `row_without_event`. */
  accepted: {
    op: "accepted",
    message: "Legal acceptance: a founder decision was recorded",
    level: "warn",
  },
  /** A decision was not recorded; `tags.reason` is one of DecideRejectReason (hash_mismatch, replaced, expired, denied_42501, db_error, unexpected, ...). */
  decideRejected: {
    op: "decide_rejected",
    message: "Legal acceptance: a founder decision was not recorded",
    level: "warn",
  },
  /** The email-code step failed for a reason other than a wrong code; `extra.errorClass` is the provider error class, never the address. */
  reauthFailed: {
    op: "reauth_failed",
    message: "Legal acceptance: the email code step failed at the auth service; nothing was recorded",
    level: "error",
  },
  /**
   * Reconciliation found a legal_acceptance row with no acknowledgement (reported by the verify endpoint, PR-D): the decide
   * route writes the ack only after the `accepted` event was flushed, so this proves the route did not acknowledge, not that
   * Sentry received or missed the event. Alert-only. `extra` carries `key`, the public `textHash`, `ageSeconds` and `status`.
   */
  rowWithoutEvent: {
    op: "row_without_event",
    message: "Legal acceptance: a legal acceptance row has no recorded acknowledgement",
    level: "error",
  },
  /**
   * A legal-acceptance page could not read the founder's decisions or the registry text (a read error, not "no rows"). Recorded, not paged.
   * `extra.read` names the read. The Inbox legal row (`read: legal_acceptance_inbox`, server/legal-acceptance/inbox-rows.ts) adds a static
   * `extra.step` saying where it stopped: gate | registry | read | shape | state. The registry step also carries `extra.key`.
   */
  pageReadFailed: {
    op: "page_read_failed",
    message: "Legal acceptance: the page could not read the founder's decisions or the legal text",
    level: "error",
  },
  /** A registered text has no declared card kind (LEGAL_TEXT_KIND), so the page renders nothing for it. Reported on every render, once the founder surface gate has passed; `tags.key` names the text. */
  kindUndeclared: {
    op: "kind_undeclared",
    message: "Legal acceptance: a registry text has no declared card kind",
    level: "warn",
  },
  /** The check endpoint read a row whose checksum no longer matches (status `invalid`). Recorded in Sentry; no paging rule yet (#12195). `extra` carries `key` and the public `textHash`. */
  recordInvalid: {
    op: "record_invalid",
    message: "Legal acceptance: a stored decision failed its integrity check",
    level: "error",
  },
  /**
   * A store call on the verify or ack path failed, threw or answered an unrecognised payload; `tags.stage` is one of
   * STORE_FAILED_STAGES: `verify` (the verify RPC), `ack_state` (the reconciliation RPC), `ack` (the decide path's flush or
   * ack write), `registry` (the legal text could not be read, or the committed text is malformed: bad_bytes, no_front_matter, bad_version, bad_valid_until; the on-call reads extra.code; the verify route's step 4 and the counts route's step 4, so both
   * routes emit it) or `config` (a token or founder id that is SET but malformed; once per route module, so a malformed
   * token yields one event from each of the verify and counts routes; names only the variable) or `counts` (the aggregate
   * read behind GET /api/internal/legal-acceptance/[key]/counts failed, threw, or answered an undocumented shape, including
   * migration 186 not applied; extra.code is the SQLSTATE and extra.reason is "too_many_hashes" when the RPC refused with
   * 54000; #12429). No paging rule yet (#12195).
   */
  storeFailed: {
    op: "store_failed",
    message: "Legal acceptance: a store call on the verify or acknowledge path failed",
    level: "error",
  },
} as const satisfies Record<string, ApprovalOp>;

export type LegalOpKey = keyof typeof LEGAL_OPS;

/** The closed set of `store_failed` `tags.stage` values; every storeFailed report carries exactly one (the contract test pins it). */
export const STORE_FAILED_STAGES = ["verify", "ack_state", "ack", "registry", "config", "counts"] as const;
export type StoreFailedStage = (typeof STORE_FAILED_STAGES)[number];

export function reportLegalOp(key: LegalOpKey, err: unknown, ctx: ApprovalOpContext = {}): void {
  const def: ApprovalOp = LEGAL_OPS[key];
  const level = ctx.level ?? def.level;
  const options = {
    feature: "legal-acceptance",
    op: def.op,
    message: def.message,
    tags: ctx.tags,
    extra: {
      ...(ctx.userId ? { userId: ctx.userId } : {}),
      ...describeError(err),
      ...ctx.extra,
    },
  };
  try {
    if (level === "error") reportSilentFallback(null, options);
    else warnSilentFallback(null, options);
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
