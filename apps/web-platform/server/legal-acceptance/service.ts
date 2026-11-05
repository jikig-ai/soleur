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
import { REQUEST_CHANGES_MAX } from "@/lib/legal-acceptance-wire";
import { isCurrent, type LegalTextEntry } from "./canonical";
import { reportLegalOp } from "@/server/approval/ops";

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

async function call(client: LegalRpcClient, fn: string, args: Record<string, unknown>): Promise<Record<string, unknown>> {
  let res: LegalRpcResult;
  try {
    res = await client.rpc(fn, args);
  } catch {
    throw new LegalServiceError(fn, "rpc_threw");
  }
  if (res.error) throw new LegalServiceError(fn, res.error.code);
  if (!isObj(res.data) || typeof res.data.outcome !== "string") throw new LegalServiceError(fn, "bad_payload");
  return res.data;
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
    if (!choice || typeof out.decided_at !== "string") throw new LegalServiceError(fn, "bad_payload");
    return { outcome: "recorded", choice, decidedAt: out.decided_at, reauthAt: typeof out.reauth_at === "string" ? out.reauth_at : null };
  }
  if (o === "already_recorded") return { outcome: "already_recorded", choice: asChoice(out.choice) };
  return { outcome: o };
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
}

/** Why a decision was not recorded; a closed set, safe as a Sentry tag. */
export type DecideRejectReason = "hash_mismatch" | "text_expired" | "replaced" | "expired" | "code_expired" | "no_intent" | "rate_limited" | "db_error";

/**
 * Validate the choice/note pair. Returns the note to send (trimmed for request_changes, null otherwise) or null when
 * the pair is malformed. The database CHECK counts characters of the UNTRIMMED value, so the cap is applied to what the
 * client sent.
 */
export function normaliseNote(choice: LegalChoiceWire, note: unknown): { ok: true; note: string | null } | { ok: false } {
  if (choice === "request_changes") {
    if (typeof note !== "string" || note.length > REQUEST_CHANGES_MAX) return { ok: false };
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
      reject("no_intent", err);
      return { kind: "forbidden" };
    }
    throw err;
  }

  if (rec.outcome === "recorded") {
    reportLegalOp("accepted", null, { userId: a.userId, extra: { key: a.entry.key, choice: rec.choice, version: a.entry.version } });
    return { kind: "result", result: { outcome: "recorded", choice: rec.choice, decidedAt: rec.decidedAt, reauthAt: rec.reauthAt } };
  }
  if (rec.outcome === "already_recorded") {
    return { kind: "result", result: { outcome: "already_recorded", ...(rec.choice ? { choice: rec.choice } : {}) } };
  }
  reject(rec.outcome);
  return { kind: "result", result: { outcome: rec.outcome } };
}
