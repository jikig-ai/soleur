// Client-safe wire types for the founder legal-acceptance web card (#12011 PR-C, ADR-319). No server imports: the card,
// the dialog and the routes all share these shapes, and the card is a client component.

import { EMAIL_OTP_LENGTH } from "@/lib/auth/constants";

export const LEGAL_CHOICES = ["accept", "decline", "request_changes"] as const;
export type LegalChoiceWire = (typeof LEGAL_CHOICES)[number];

/** Same cap the database CHECK enforces on `requested_edit`. It counts characters (code points), not UTF-16 units. */
export const REQUEST_CHANGES_MAX = 1000;

/** Number of characters (code points) in a string: what the database CHECK counts. */
export function codePointLength(s: string): number {
  return Array.from(s).length;
}

/** The first `max` characters (code points) of a string. Never cuts a surrogate pair in half. */
export function truncateCodePoints(s: string, max: number): string {
  if (s.length <= max) return s;
  return Array.from(s).slice(0, max).join("");
}

/** The email-code length range, defined once. The lower bound is the auth service's code length; 8 is the dev upper bound. */
export const LEGAL_CODE_MIN_DIGITS = EMAIL_OTP_LENGTH;
export const LEGAL_CODE_MAX_DIGITS = 8;
const LEGAL_CODE_RE = new RegExp(`^\\d{${LEGAL_CODE_MIN_DIGITS},${LEGAL_CODE_MAX_DIGITS}}$`);
export function isLegalCode(v: string): boolean {
  return LEGAL_CODE_RE.test(v);
}

/** Derived, never stored: see `deriveLegalCardState` in `lib/approval-card-state.ts`. */
export const LEGAL_CARD_STATES = ["pending", "accepted", "declined", "changes_requested", "replaced", "expired"] as const;
export type LegalCardStateWire = (typeof LEGAL_CARD_STATES)[number];

export const LEGAL_SEND_REASONS = ["rate_limited", "already_recorded", "replaced", "unavailable"] as const;
export type LegalSendReason = (typeof LEGAL_SEND_REASONS)[number];

/**
 * POST /api/legal-acceptance/[key]/reauth with {step:"send", resend?: boolean}.
 * `ok:true` is returned for a known AND an unknown address (the auth service answers them differently; the route must not).
 */
export type LegalReauthSendResult = { ok: true; state: "sent" } | { ok: false; reason: LegalSendReason };

export const LEGAL_VERIFY_REASONS = ["wrong_code", "locked", "expired", "replaced", "code_stale", "unavailable"] as const;
export type LegalVerifyReason = (typeof LEGAL_VERIFY_REASONS)[number];

/** POST /api/legal-acceptance/[key]/reauth with {step:"verify", code}. */
export type LegalReauthVerifyResult = { ok: true } | { ok: false; reason: LegalVerifyReason };

export const LEGAL_DECIDE_OUTCOMES = ["recorded", "already_recorded", "replaced", "expired", "code_expired"] as const;

/**
 * POST /api/legal-acceptance/[key]/decide with {choice, textHash, note?}. `textHash` is the hash the page showed; the
 * route compares it with the registry entry and never accepts text. `code_expired` and `expired` and `replaced` mean
 * nothing was recorded. A refusal because the email code no longer counts answers HTTP 403 `{error:"reverify"}`.
 */
export type LegalDecideOutcome = (typeof LEGAL_DECIDE_OUTCOMES)[number];
export interface LegalDecideResult {
  outcome: LegalDecideOutcome;
  choice?: LegalChoiceWire;
  decidedAt?: string;
  /** When the email code was confirmed, for a recorded Yes. */
  reauthAt?: string | null;
}

export function isLegalChoice(v: unknown): v is LegalChoiceWire {
  return typeof v === "string" && (LEGAL_CHOICES as readonly string[]).includes(v);
}

export function isLegalDecideResult(v: unknown): v is LegalDecideResult {
  if (!v || typeof v !== "object") return false;
  const o = (v as { outcome?: unknown }).outcome;
  return typeof o === "string" && (LEGAL_DECIDE_OUTCOMES as readonly string[]).includes(o);
}

// ---- the founder's own stored rows (read by the legal pages through the user-context client) ---------------------------

export const LEGAL_ROW_COLUMNS = "key, text_hash, version, choice, requested_edit, reauth_at, created_at";

export interface LegalStoredRow {
  key: string;
  text_hash: string;
  version: string;
  choice: LegalChoiceWire;
  requested_edit: string | null;
  reauth_at: string | null;
  created_at: string;
}

/** Strict parse of a `legal_acceptance` select: one malformed row makes the whole read `null` (a loud failure, never a partial page). */
export function parseLegalRows(data: unknown): LegalStoredRow[] | null {
  if (!Array.isArray(data)) return null;
  const out: LegalStoredRow[] = [];
  for (const r of data as Record<string, unknown>[]) {
    if (
      !r ||
      typeof r.key !== "string" ||
      typeof r.text_hash !== "string" ||
      typeof r.version !== "string" ||
      !isLegalChoice(r.choice) ||
      typeof r.created_at !== "string" ||
      (r.requested_edit !== null && typeof r.requested_edit !== "string") ||
      (r.reauth_at !== null && typeof r.reauth_at !== "string")
    ) {
      return null;
    }
    out.push({
      key: r.key,
      text_hash: r.text_hash,
      version: r.version,
      choice: r.choice,
      requested_edit: r.requested_edit as string | null,
      reauth_at: r.reauth_at as string | null,
      created_at: r.created_at,
    });
  }
  return out;
}
