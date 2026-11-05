/**
 * Typed wrappers over the migration-184 RPCs (#12011 PR-C, ADR-319). Every call is an RPC; there is no table access.
 *
 * Which client may call what (the database enforces it; this file only keeps the call sites honest):
 *  - `issue_legal_reauth`, `claim_legal_reauth_attempt`, `mark_legal_reauth_verified`: SERVICE client only.
 *  - `record_legal_acceptance`: USER-context client only. The actor is `auth.uid()`; the service client has none and the
 *    RPC refuses it. The wrappers take two differently named clients so a swap is a type-visible mistake.
 *
 * Errors: an RPC failure throws `LegalServiceError` with a STATIC message (never database text, which can echo row
 * content) and the SQLSTATE in `code`. A payload that is not one of the documented outcomes throws `bad_payload`:
 * an unknown outcome is never treated as success.
 */

import type { LegalChoiceWire, LegalDecideResult } from "@/lib/legal-acceptance-wire";
import { codePointLength, REQUEST_CHANGES_MAX } from "@/lib/legal-acceptance-wire";
import { isCurrent, type LegalTextEntry } from "./canonical";
import { reportLegalOp } from "@/server/approval/ops";
import { createChildLogger } from "@/server/logger";

const log = createChildLogger("legal-acceptance");

export interface LegalRpcResult {
  data: unknown;
  error: { message: string; code?: string } | null;
}
/** The slice of a Supabase client these wrappers use. */
export interface LegalRpcClient {
  rpc(fn: string, args?: Record<string, unknown>): PromiseLike<LegalRpcResult>;
}

export class LegalServiceError extends Error {
  readonly fn: string;
  readonly code?: string;
  constructor(fn: string, code?: string) {
    super(`legal acceptance rpc failed: ${fn}`);
    this.name = "LegalServiceError";
    this.fn = fn;
    this.code = code;
  }
}

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

/** SQLSTATE of a serialization failure: the transaction rolled back whole, so one retry is safe for every RPC here. */
const SERIALIZATION_FAILURE = "40001";

async function callOnce(client: LegalRpcClient, fn: string, args: Record<string, unknown>): Promise<LegalRpcResult> {
  try {
    return await client.rpc(fn, args);
  } catch {
    throw new LegalServiceError(fn, "rpc_threw");
  }
}

/** One RPC with the shared serialization-failure retry. Returns the raw `data`; every wrapper validates its own shape. */
async function rpcData(client: LegalRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  let res = await callOnce(client, fn, args);
  if (res.error?.code === SERIALIZATION_FAILURE) res = await callOnce(client, fn, args);
  if (res.error) throw new LegalServiceError(fn, res.error.code);
  return res.data;
}

async function call(client: LegalRpcClient, fn: string, args: Record<string, unknown>): Promise<Record<string, unknown>> {
  const data = await rpcData(client, fn, args);
  if (!isObj(data) || typeof data.outcome !== "string") throw new LegalServiceError(fn, "bad_payload");
  return data;
}

function oneOf<T extends string>(fn: string, out: Record<string, unknown>, allowed: readonly T[]): T {
  if (!(allowed as readonly string[]).includes(out.outcome as string)) throw new LegalServiceError(fn, "bad_payload");
  return out.outcome as T;
}

// ── issue_legal_reauth (service) ─────────────────────────────────────────────────────────────────────────────────

export type IssueResult =
  | { outcome: "issued"; reused: boolean; eventId: string; expiresAt: string }
  | { outcome: "already_recorded"; choice?: LegalChoiceWire }
  | { outcome: "rate_limited" };

export async function issueIntent(
  service: LegalRpcClient,
  a: { userId: string; entry: LegalTextEntry; sessionId: string; resend?: boolean },
): Promise<IssueResult> {
  const fn = "issue_legal_reauth";
  const out = await call(service, fn, {
    p_user_id: a.userId,
    p_key: a.entry.key,
    p_text_hash: a.entry.textHash,
    p_version: a.entry.version,
    p_session_id: a.sessionId,
    p_resend: a.resend === true,
  });
  const o = oneOf(fn, out, ["issued", "already_recorded", "rate_limited"] as const);
  if (o === "issued") {
    if (typeof out.event_id !== "string" || typeof out.expires_at !== "string") throw new LegalServiceError(fn, "bad_payload");
    return { outcome: "issued", reused: out.reused === true, eventId: out.event_id, expiresAt: out.expires_at };
  }
  if (o === "already_recorded") return { outcome: "already_recorded", choice: asChoice(out.choice) };
  return { outcome: "rate_limited" };
}

// ── claim_legal_reauth_attempt (service) ─────────────────────────────────────────────────────────────────────────

export type ClaimResult =
  | { outcome: "allowed"; eventId: string; attempts: number }
  | { outcome: "locked" | "code_stale" | "expired" | "replaced" | "not_found" };

export async function claimAttempt(
  service: LegalRpcClient,
  a: { userId: string; entry: LegalTextEntry; sessionId: string },
): Promise<ClaimResult> {
  const fn = "claim_legal_reauth_attempt";
  const out = await call(service, fn, {
    p_user_id: a.userId,
    p_key: a.entry.key,
    p_text_hash: a.entry.textHash,
    p_session_id: a.sessionId,
  });
  const o = oneOf(fn, out, ["allowed", "locked", "code_stale", "expired", "replaced", "not_found"] as const);
  if (o !== "allowed") return { outcome: o };
  if (typeof out.event_id !== "string") throw new LegalServiceError(fn, "bad_payload");
  return { outcome: "allowed", eventId: out.event_id, attempts: typeof out.attempts === "number" ? out.attempts : 0 };
}

// ── mark_legal_reauth_verified (service) ─────────────────────────────────────────────────────────────────────────

export type MarkResult = "verified" | "not_claimed" | "expired" | "replaced" | "not_found";

export async function markVerified(
  service: LegalRpcClient,
  a: { userId: string; eventId: string; entry: LegalTextEntry; sessionId: string },
): Promise<MarkResult> {
  const fn = "mark_legal_reauth_verified";
  const out = await call(service, fn, {
    p_user_id: a.userId,
    p_event_id: a.eventId,
    p_key: a.entry.key,
    p_text_hash: a.entry.textHash,
    p_session_id: a.sessionId,
  });
  return oneOf(fn, out, ["verified", "not_claimed", "expired", "replaced", "not_found"] as const);
}

// ── record_legal_acceptance (USER client) ────────────────────────────────────────────────────────────────────────

export type RecordResult =
  | { outcome: "recorded"; choice: LegalChoiceWire; decidedAt: string; reauthAt: string | null }
  | { outcome: "already_recorded"; choice?: LegalChoiceWire }
  | { outcome: "replaced" | "expired" | "code_expired" };

function asChoice(v: unknown): LegalChoiceWire | undefined {
  return v === "accept" || v === "decline" || v === "request_changes" ? v : undefined;
}

export async function recordAcceptance(
  userClient: LegalRpcClient,
  a: { key: string; textHash: string; choice: LegalChoiceWire; note: string | null },
): Promise<RecordResult> {
  const fn = "record_legal_acceptance";
  const out = await call(userClient, fn, {
    p_key: a.key,
    p_text_hash: a.textHash,
    p_choice: a.choice,
    p_requested_edit: a.note,
  });
  const o = oneOf(fn, out, ["recorded", "already_recorded", "replaced", "expired", "code_expired"] as const);
  if (o === "recorded") {
    const choice = asChoice(out.choice);
    // The reply must be about the text that was sent: a different hash is never treated as a recorded decision.
    if (!choice || typeof out.decided_at !== "string" || out.text_hash !== a.textHash) throw new LegalServiceError(fn, "bad_payload");
    return { outcome: "recorded", choice, decidedAt: out.decided_at, reauthAt: typeof out.reauth_at === "string" ? out.reauth_at : null };
  }
  if (o === "already_recorded") return { outcome: "already_recorded", choice: asChoice(out.choice) };
  return { outcome: o };
}

// ── verify_legal_acceptance (service; read-only) ─────────────────────────────────────────────────────────────────

export type VerifyStatus = "none" | "accepted" | "declined" | "changes_requested" | "invalid";
export const VERIFY_STATUSES: readonly VerifyStatus[] = ["none", "accepted", "declined", "changes_requested", "invalid"];

/** The four fields the check endpoint may return. The note (`requested_edit`) is not here and never will be. */
export interface VerifyResult {
  status: VerifyStatus;
  text_hash: string;
  decided_at: string | null;
  row_ok: boolean | null;
}

/**
 * A UTC ISO timestamp as Postgres renders a timestamptz in JSON: date, `T`, time, optional fraction, then `Z` or a zero
 * offset. The same pattern as WA_TS_RE in the shell gate (hold-gate-eval.sh), so the two layers cannot disagree about which
 * forms count: `Date.parse` alone accepts many more (RFC 2822 dates, "2026", other offsets, a missing time) and rejects some
 * of these (V8 refuses `+00` and, on some versions, `+0000`), so it is not used. The calendar fields are checked by hand.
 */
const UTC_ISO_RE = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.\d+)?(Z|\+00(:?00)?)$/;
function isTimestamp(v: unknown): v is string {
  if (typeof v !== "string") return false;
  const m = UTC_ISO_RE.exec(v);
  if (!m) return false;
  const [year, month, day, hour, minute, second] = m.slice(1, 7).map(Number);
  if (month < 1 || month > 12 || day < 1 || hour > 23 || minute > 59 || second > 59) return false;
  const daysInMonth = new Date(Date.UTC(year, month, 0)).getUTCDate(); // day 0 of the next month = last day of this one
  return day <= daysInMonth;
}

/**
 * The status of one founder's decision on one text. This RPC answers `{status, text_hash, decided_at, row_ok}` with NO
 * `outcome` key, so it has its own strict validation instead of loosening `call()` (an unknown outcome is never success).
 * Anything that does not match the documented shapes throws `bad_payload`:
 *  - `none`: no row, so `decided_at` and `row_ok` are both null;
 *  - `accepted | declined | changes_requested`: `row_ok` is exactly true and `decided_at` is a timestamp;
 *  - `invalid`: the checksum failed, `row_ok` is exactly false (it is never collapsed into `none`);
 *  - `text_hash` equals the hash that was asked about. Extra keys are dropped: the result is rebuilt from four fields.
 */
export async function verifyAcceptance(
  service: LegalRpcClient,
  a: { founderId: string; key: string; textHash: string },
): Promise<VerifyResult> {
  const fn = "verify_legal_acceptance";
  const out = await rpcData(service, fn, { p_founder_id: a.founderId, p_key: a.key, p_text_hash: a.textHash });
  if (!isObj(out)) throw new LegalServiceError(fn, "bad_payload");
  const status = out.status;
  if (typeof status !== "string" || !(VERIFY_STATUSES as readonly string[]).includes(status)) throw new LegalServiceError(fn, "bad_payload");
  if (out.text_hash !== a.textHash) throw new LegalServiceError(fn, "bad_payload");
  const bad = () => new LegalServiceError(fn, "bad_payload");
  if (status === "none") {
    if (out.decided_at !== null || out.row_ok !== null) throw bad();
    return { status, text_hash: a.textHash, decided_at: null, row_ok: null };
  }
  if (!isTimestamp(out.decided_at)) throw bad();
  if (status === "invalid") {
    if (out.row_ok !== false) throw bad();
    return { status, text_hash: a.textHash, decided_at: out.decided_at, row_ok: false };
  }
  if (out.row_ok !== true) throw bad();
  return { status: status as VerifyStatus, text_hash: a.textHash, decided_at: out.decided_at, row_ok: true };
}

// ── ack_legal_acceptance / legal_acceptance_ack_state (service) ──────────────────────────────────────────────────

/**
 * A decision row that has no acknowledgement this many seconds after it was written is reported as `row_without_event`.
 * The grace covers the normal gap between the commit and the ack (the response, the flush and the ack run right after
 * it, bounded by ACK_FLUSH_TIMEOUT_MS), so a write that is still in progress is not mistaken for a gap. Inclusive: a row
 * exactly this old is reported.
 */
export const ROW_WITHOUT_EVENT_GRACE_SECONDS = 120;

/** The statuses the check endpoint can emit. Declared once; the route is typed against it and the tests assert it. */
export const VERIFY_ENDPOINT_STATUSES = [200, 400, 401, 404, 502, 503] as const;
export type VerifyEndpointStatus = (typeof VERIFY_ENDPOINT_STATUSES)[number];

export type AckResult = "acked" | "not_found";

/** Mark one decision row as reported (the `accepted` event was flushed). Idempotent in the database. */
export async function ackAcceptance(
  service: LegalRpcClient,
  a: { founderId: string; key: string; textHash: string },
): Promise<AckResult> {
  const fn = "ack_legal_acceptance";
  const out = await call(service, fn, { p_founder_id: a.founderId, p_key: a.key, p_text_hash: a.textHash });
  return oneOf(fn, out, ["acked", "not_found"] as const);
}

export type AckStateResult = { outcome: "none" } | { outcome: "row"; acked: boolean; age_seconds: number };

/** Whether the decision row was acknowledged and how old it is (database clock). Read-only. */
export async function ackState(
  service: LegalRpcClient,
  a: { founderId: string; key: string; textHash: string },
): Promise<AckStateResult> {
  const fn = "legal_acceptance_ack_state";
  const out = await call(service, fn, { p_founder_id: a.founderId, p_key: a.key, p_text_hash: a.textHash });
  const o = oneOf(fn, out, ["none", "row"] as const);
  if (o === "none") return { outcome: "none" };
  const age = out.age_seconds;
  if (typeof out.acked !== "boolean" || typeof age !== "number" || !Number.isInteger(age) || age < 0) {
    throw new LegalServiceError(fn, "bad_payload");
  }
  return { outcome: "row", acked: out.acked, age_seconds: age };
}

// ── decide orchestration ─────────────────────────────────────────────────────────────────────────────────────────

export type DecideOutcome =
  | { kind: "result"; result: LegalDecideResult }
  /** 403: no live intent / email code required (SQLSTATE 42501). Nothing was recorded. */
  | { kind: "forbidden" }
  /** 429: too many new intents for this user and key in the last 15 minutes. Nothing was recorded. */
  | { kind: "rate_limited" };

export interface DecideDeps {
  service: LegalRpcClient;
  user: LegalRpcClient;
  now?: () => Date;
  /**
   * Flush pending Sentry events. `Sentry.flush` resolves true when the queue drained, which includes the case where there
   * is no transport or DSN (nothing was sent), so a true answer is not proof that Sentry received the event. A rejection or
   * throw is `store_failed` (stage ack); false or no answer within ACK_FLUSH_TIMEOUT_MS acknowledges nothing and logs one
   * warning line. Absent means "no flush is possible", so nothing is acknowledged.
   */
  flushEvents?: () => Promise<boolean>;
  /** Runs the post-response task. The default is a caught fire-and-forget promise; the route passes `after()`. */
  runOffPath?: (task: () => Promise<void>) => void;
}

/** The longest the ack task waits for the event flush. A flush that has not answered by then counts as not flushed (warn only). */
export const ACK_FLUSH_TIMEOUT_MS = 2000;

/** Caught fire-and-forget: the task's own failures are already reported inside it, so a rejection here is dropped. */
const fireAndForget = (task: () => Promise<void>): void => {
  void task().catch(() => {});
};

function raceFlush(flush: () => Promise<boolean>): Promise<boolean> {
  return new Promise<boolean>((resolve, reject) => {
    const timer = setTimeout(() => resolve(false), ACK_FLUSH_TIMEOUT_MS);
    (timer as { unref?: () => void }).unref?.();
    let p: Promise<boolean>;
    try {
      p = flush();
    } catch (err) {
      clearTimeout(timer);
      reject(err);
      return;
    }
    p.then(
      (v) => {
        clearTimeout(timer);
        resolve(v);
      },
      (err) => {
        clearTimeout(timer);
        reject(err);
      },
    );
  });
}

/** The one place an ack-path failure is reported: `store_failed`, stage `ack`, with the step that failed. */
function reportAckFailure(a: { userId: string; key: string }, err: unknown, step: string, extra: Record<string, unknown> = {}): void {
  reportLegalOp("storeFailed", err, { userId: a.userId, tags: { stage: "ack" }, extra: { key: a.key, step, ...extra } });
}

/**
 * Off the request path: wait (bounded) for the `accepted` event to be flushed and, ONLY when the flush answered true,
 * write the acknowledgement that the verify endpoint later looks for. Never throws. A flush that throws or rejects, and an
 * ack write that fails, are reported as `store_failed` (stage `ack`); a flush that answers false or does not answer within
 * ACK_FLUSH_TIMEOUT_MS writes one warning log line (key only, no Sentry event). All of them leave the row unacknowledged,
 * which the endpoint then surfaces as `row_without_event`.
 */
async function ackWhenFlushed(
  deps: DecideDeps & { flushEvents: () => Promise<boolean> },
  a: { userId: string; key: string; textHash: string },
): Promise<void> {
  let flushed: boolean;
  try {
    flushed = (await raceFlush(deps.flushEvents)) === true;
  } catch (err) {
    reportAckFailure(a, err, "flush");
    return;
  }
  if (!flushed) {
    // The only trace of a flush that was not confirmed: no user id, no hash, no note, and not a Sentry event.
    log.warn({ key: a.key }, "legal acceptance ack skipped: flush not confirmed");
    return;
  }
  try {
    const res = await ackAcceptance(deps.service, { founderId: a.userId, key: a.key, textHash: a.textHash });
    if (res !== "acked") reportAckFailure(a, null, "ack", { outcome: res });
  } catch (err) {
    reportAckFailure(a, err, "ack");
  }
}

/** Why a decision was not recorded; a closed set, safe as a Sentry tag. */
export type DecideRejectReason = "hash_mismatch" | "text_expired" | "replaced" | "expired" | "code_expired" | "denied_42501" | "rate_limited" | "db_error" | "unexpected";

/**
 * Validate the choice/note pair. Returns the note to send (trimmed for request_changes, null otherwise) or null when
 * the pair is malformed. The trimmed value is what is sent, and the cap is applied to the UNTRIMMED length in code
 * points, the same unit the SQL CHECK counts (and the card's counter): trimmed is never longer than untrimmed, so
 * anything accepted here satisfies the CHECK.
 * A NUL (not storable in Postgres text) and a lone surrogate (not valid UTF-8) are refused.
 */
/** A UTF-16 surrogate with no partner (escapes only, so the pattern is unambiguous). */
const LONE_SURROGATE_RE = /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/;
const notStorable = (text: string): boolean => text.includes("\u0000") || LONE_SURROGATE_RE.test(text);

export function normaliseNote(choice: LegalChoiceWire, note: unknown): { ok: true; note: string | null } | { ok: false } {
  if (choice === "request_changes") {
    if (typeof note !== "string" || codePointLength(note) > REQUEST_CHANGES_MAX || notStorable(note)) return { ok: false };
    const trimmed = note.trim();
    return trimmed.length === 0 ? { ok: false } : { ok: true, note: trimmed };
  }
  return note === undefined || note === null ? { ok: true, note: null } : { ok: false };
}

/**
 * Record one founder decision. The registry entry is already resolved by the caller (the browser never supplies text).
 *
 * - `textHash` is the hash the page showed. A different one means the text moved on: `replaced`, nothing recorded.
 * - decline and request_changes have no email step, so the intent is opened here first (service client); accept relies
 *   on the intent and confirmation created by the reauth steps and never opens one itself.
 * - `record_legal_acceptance` runs on the USER-context client only.
 * - Every non-recorded outcome other than `already_recorded` (a benign second tab) is reported with a reason tag.
 */
export async function decideLegal(
  deps: DecideDeps,
  a: {
    userId: string;
    sessionId: string;
    entry: LegalTextEntry;
    choice: LegalChoiceWire;
    textHash: string;
    note: string | null;
  },
): Promise<DecideOutcome> {
  const now = deps.now?.() ?? new Date();
  const reject = (reason: DecideRejectReason, err: unknown = null): void =>
    reportLegalOp("decideRejected", err, { userId: a.userId, tags: { reason }, extra: { reason, key: a.entry.key, choice: a.choice } });

  if (a.textHash !== a.entry.textHash) {
    reject("hash_mismatch");
    return { kind: "result", result: { outcome: "replaced" } };
  }
  if (!isCurrent(a.entry, now)) {
    reject("text_expired");
    return { kind: "result", result: { outcome: "expired" } };
  }

  if (a.choice !== "accept") {
    const issued = await issueIntent(deps.service, { userId: a.userId, entry: a.entry, sessionId: a.sessionId });
    if (issued.outcome === "already_recorded") {
      return { kind: "result", result: { outcome: "already_recorded", ...(issued.choice ? { choice: issued.choice } : {}) } };
    }
    if (issued.outcome === "rate_limited") {
      reject("rate_limited");
      return { kind: "rate_limited" };
    }
  }

  let rec: RecordResult;
  try {
    rec = await recordAcceptance(deps.user, { key: a.entry.key, textHash: a.entry.textHash, choice: a.choice, note: a.note });
  } catch (err) {
    if (err instanceof LegalServiceError && err.code === "42501") {
      reject("denied_42501", err);
      return { kind: "forbidden" };
    }
    throw err;
  }

  if (rec.outcome === "recorded") {
    reportLegalOp("accepted", null, { userId: a.userId, extra: { key: a.entry.key, choice: rec.choice, version: a.entry.version } });
    // The ack runs after the response. Nothing from here on can reach the founder's result or `decideRejected`.
    const flushEvents = deps.flushEvents;
    if (flushEvents) {
      try {
        (deps.runOffPath ?? fireAndForget)(() =>
          ackWhenFlushed({ ...deps, flushEvents }, { userId: a.userId, key: a.entry.key, textHash: a.entry.textHash }),
        );
      } catch (err) {
        reportAckFailure({ userId: a.userId, key: a.entry.key }, err, "schedule");
      }
    }
    return { kind: "result", result: { outcome: "recorded", choice: rec.choice, decidedAt: rec.decidedAt, reauthAt: rec.reauthAt } };
  }
  if (rec.outcome === "already_recorded") {
    return { kind: "result", result: { outcome: "already_recorded", ...(rec.choice ? { choice: rec.choice } : {}) } };
  }
  reject(rec.outcome);
  return { kind: "result", result: { outcome: rec.outcome } };
}
