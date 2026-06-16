// Outbound-email compliance validators (#5325, pilot slice).
//
// PURE validators only — no IO, fully unit-testable. The send chokepoint
// (`outbound.ts`) composes these BEFORE any Resend call. Every validator
// throws OutboundComplianceError (carrying a stable `code` for Sentry
// op-tagging) on failure — refuse-to-send is fail-loud, never silent.
//
// CLO conditions (brainstorm CLO C1–C5):
//   C1 postal-address footer · C2 opt-out line · C3 EU/UK Art. 14 disclosure
//   (6 discrete element predicates) · C4 FTC material-connection · C5 suppress
//   opt-outs (the send-time corollary — refuse-to-send if suppressed — lives in
//   outbound.ts because it needs a DB round-trip).
//
// C3 is MECHANICAL per-element presence, NOT semantic NLP: each cold send is
// human-approved, so the approver owns semantic correctness. These predicates
// only assert each required structured field is present + non-blank, closing
// the "approver forgot the postal address entirely" gap.
//
// recipient_hash determinism (deepen P0-2): a per-row/random salt would break
// cross-campaign suppression lookup and re-mail a suppressed contact (the exact
// incident this guards). Keyed HMAC with an app-wide pepper is deliberately
// linkable — that linkability IS the suppression-matching property.

import { createHmac } from "node:crypto";

export class OutboundComplianceError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.name = "OutboundComplianceError";
    this.code = code;
  }
}

export type Jurisdiction = "us" | "eu_uk" | "unknown";

export interface Art14Disclosure {
  identity?: string;
  purpose?: string;
  legalBasis?: string;
  dataSource?: string;
  retention?: string;
  rights?: string;
}

export interface OutboundComplianceRequest {
  to: string;
  from: string;
  subject: string;
  bodyText: string;
  replyTo?: string;
  jurisdiction: Jurisdiction;
  /** C1 — postal-address footer. */
  postalAddress?: string;
  /** C2 — opt-out line. */
  optOut?: string;
  /** C3 — EU/UK Art. 14 disclosure elements (required when jurisdiction resolves eu_uk). */
  art14?: Art14Disclosure;
  /** C4 — FTC material-connection disclosure (free-access pitch). */
  ftcDisclosure?: string;
}

function isBlank(v: unknown): boolean {
  return typeof v !== "string" || v.trim().length === 0;
}

/**
 * Default-to-EU/UK-strict (deepen plan + CLO): ONLY an explicit US signal
 * resolves to the lenient US path. Unknown / low-confidence / empty → eu_uk.
 */
export function resolveJurisdiction(input?: string | null): "us" | "eu_uk" {
  if (typeof input === "string" && input.trim().toLowerCase() === "us") {
    return "us";
  }
  return "eu_uk";
}

const ART14_ELEMENTS: Array<keyof Art14Disclosure> = [
  "identity",
  "purpose",
  "legalBasis",
  "dataSource",
  "retention",
  "rights",
];

/**
 * C1–C4 (+ C3's 6 Art. 14 predicates under EU/UK-strict). Throws on the first
 * absent/blank required element. C5 (suppression) is enforced in outbound.ts.
 */
export function validateComplianceConditions(req: OutboundComplianceRequest): void {
  // C1 — postal-address footer (CAN-SPAM + PECR).
  if (isBlank(req.postalAddress)) {
    throw new OutboundComplianceError(
      "c1_postal_address_missing",
      "C1: physical postal-address footer is required on every cold send.",
    );
  }

  // C2 — opt-out line.
  if (isBlank(req.optOut)) {
    throw new OutboundComplianceError(
      "c2_opt_out_missing",
      "C2: an opt-out line is required on every cold send.",
    );
  }

  // C4 — FTC material-connection disclosure (free-access pitch).
  if (isBlank(req.ftcDisclosure)) {
    throw new OutboundComplianceError(
      "c4_ftc_disclosure_missing",
      "C4: FTC material-connection disclosure is required.",
    );
  }

  // C3 — EU/UK Art. 14 disclosure (default-to-strict on unknown jurisdiction).
  const resolved = resolveJurisdiction(req.jurisdiction);
  if (resolved === "eu_uk") {
    const art14 = req.art14 ?? {};
    for (const el of ART14_ELEMENTS) {
      if (isBlank(art14[el])) {
        throw new OutboundComplianceError(
          `c3_art14_${el.toLowerCase()}_missing`,
          `C3: EU/UK Art. 14 disclosure element "${el}" is required (default-to-strict).`,
        );
      }
    }
  }
}

// Control chars (C0 + DEL), plus the Unicode line/paragraph separators that
// some parsers treat as newlines. Escape-only per cq-regex-unicode-separators-
// escape-only — never paste the literal separator into the pattern.
// eslint-disable-next-line no-control-regex
const HEADER_INJECTION_RE = /[\x00-\x1f\x7f\u2028\u2029]/;

// Pragmatic RFC-5322 addr-spec (the strict grammar is not worth its length for
// a refuse-to-send guard). Rejects spaces, control chars, and missing parts.
const ADDR_SPEC_RE = /^[^\s@<>",;]+@[^\s@<>",;]+\.[^\s@<>",;]+$/;

// Extracts the bare addr-spec from a "Display Name <addr@host>" or bare form.
export function extractAddrSpec(field: string): string {
  const angle = field.match(/<([^>]*)>/);
  return (angle ? angle[1]! : field).trim();
}

export interface EmailHeaderFields {
  to: string;
  from: string;
  subject: string;
  replyTo?: string;
}

/**
 * RFC-5322 header-field validator (deepen P0-4) — a DEDICATED guard, never the
 * display/prompt sanitizer. Rejects CR/LF/NUL/control/DEL/U+2028/U+2029 in any
 * header field (header injection), validates each address is a single
 * well-formed addr-spec, and caps the recipient count at one (cold 1:1).
 */
export function validateEmailHeaders(fields: EmailHeaderFields): void {
  const { to, from, subject, replyTo } = fields;

  for (const [name, value] of Object.entries({ to, from, subject, replyTo })) {
    if (value === undefined) continue;
    if (HEADER_INJECTION_RE.test(value)) {
      throw new OutboundComplianceError(
        "header_injection",
        `Header injection: control/separator character in "${name}".`,
      );
    }
  }

  // Cold 1:1 — exactly one recipient. A comma/semicolon means multi-recipient.
  if (/[,;]/.test(to)) {
    throw new OutboundComplianceError(
      "recipient_count",
      "Cold outreach is single-recipient (1:1); multiple recipients are not allowed.",
    );
  }

  for (const [name, value] of Object.entries({ to, from, replyTo })) {
    if (value === undefined) continue;
    const addr = extractAddrSpec(value);
    if (!ADDR_SPEC_RE.test(addr)) {
      throw new OutboundComplianceError(
        "invalid_address",
        `"${name}" is not a valid RFC-5322 address: ${addr}`,
      );
    }
  }
}

// Own-domain / internal — a prompt-injected agent could exfiltrate by mailing
// our own inboxes (deepen P0-3). Never send cold outreach to these.
const INTERNAL_DOMAINS = new Set(["jikigai.com", "soleur.ai", "outbound.soleur.ai"]);

// Role / bare local-parts — non-personal mailboxes; cold 1:1 outreach targets a
// named individual, never a role address.
const ROLE_LOCAL_PARTS = new Set([
  "postmaster",
  "abuse",
  "noreply",
  "no-reply",
  "hostmaster",
  "webmaster",
  "admin",
  "root",
  "mailer-daemon",
]);

/**
 * Recipient allow-list (deepen P0-3). Rejects internal/own-domain addresses
 * (exfiltration vector) and role/bare local-parts.
 */
export function assertRecipientAllowed(to: string): void {
  const addr = normalizeEmail(extractAddrSpec(to));
  const at = addr.lastIndexOf("@");
  if (at < 0) {
    throw new OutboundComplianceError("invalid_address", `Not a valid address: ${to}`);
  }
  const local = addr.slice(0, at);
  const domain = addr.slice(at + 1);

  if (INTERNAL_DOMAINS.has(domain)) {
    throw new OutboundComplianceError(
      "recipient_internal_domain",
      `Refusing to send cold outreach to an internal/own-domain address: ${domain}`,
    );
  }
  if (ROLE_LOCAL_PARTS.has(local)) {
    throw new OutboundComplianceError(
      "recipient_role_address",
      `Refusing to send cold outreach to a role/bare address: ${local}@…`,
    );
  }
}

/** Canonicalize for hashing + matching: lowercase + trim. */
export function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

/**
 * Deterministic keyed recipient hash (deepen P0-2):
 * HMAC-SHA-256(EMAIL_HASH_PEPPER, normalize(email)). Fails loud if the pepper
 * is unset — a silent unsalted/empty-key hash would change as soon as the
 * pepper lands, orphaning every prior suppression row.
 */
export function recipientHash(email: string): string {
  const pepper = process.env.EMAIL_HASH_PEPPER;
  if (!pepper) {
    throw new OutboundComplianceError(
      "pepper_unset",
      "EMAIL_HASH_PEPPER is unset — cannot compute a deterministic recipient hash.",
    );
  }
  // Canonicalize to the bare addr-spec FIRST, identically to
  // assertRecipientAllowed — otherwise suppressing `a@b.com` (bare) would not
  // match a send to `Name <a@b.com>` (display-name form), silently re-mailing
  // an opted-out contact (security review, #5325). email_reply hits this by
  // default since inbound `from` headers carry a display name.
  return createHmac("sha256", pepper)
    .update(normalizeEmail(extractAddrSpec(email)))
    .digest("hex");
}
