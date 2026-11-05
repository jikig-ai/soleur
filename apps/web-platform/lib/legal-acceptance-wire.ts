// Client-safe wire types for the founder legal-acceptance web card (#12011 PR-C, ADR-319). No server imports: the card,
// the dialog and the routes all share these shapes, and the card is a client component.

export const LEGAL_CHOICES = ["accept", "decline", "request_changes"] as const;
export type LegalChoiceWire = (typeof LEGAL_CHOICES)[number];

/** Same cap the database CHECK enforces on `requested_edit`. */
export const REQUEST_CHANGES_MAX = 1000;

/** Derived, never stored: see `deriveLegalCardState` in `lib/approval-card-state.ts`. */
export const LEGAL_CARD_STATES = ["pending", "accepted", "declined", "changes_requested", "replaced", "expired"] as const;
export type LegalCardStateWire = (typeof LEGAL_CARD_STATES)[number];

/**
 * POST /api/legal-acceptance/[key]/reauth with {step:"send", resend?: boolean}.
 * `ok:true` is returned for a known AND an unknown address (the auth service answers them differently; the route must not).
 */
export type LegalReauthSendResult =
  | { ok: true; state: "sent" }
  | { ok: false; reason: "rate_limited" | "already_recorded" | "replaced" | "unavailable" };

/** POST /api/legal-acceptance/[key]/reauth with {step:"verify", code}. */
export type LegalReauthVerifyResult =
  | { ok: true }
  | { ok: false; reason: "wrong_code" | "locked" | "expired" | "replaced" | "code_stale" | "unavailable" };

/**
 * POST /api/legal-acceptance/[key]/decide with {choice, textHash, note?}. `textHash` is the hash the page showed; the
 * route compares it with the registry entry and never accepts text. `code_expired` and `expired` and `replaced` mean
 * nothing was recorded.
 */
export type LegalDecideOutcome = "recorded" | "already_recorded" | "replaced" | "expired" | "code_expired";
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
  return o === "recorded" || o === "already_recorded" || o === "replaced" || o === "expired" || o === "code_expired";
}
