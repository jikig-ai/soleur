// PR-H (#3244) — Text-redaction allowlist for third-party-ingested
// content rendered in Today cards. Distinct threat model from the
// pino/Sentry log-payload redaction in `server/sensitive-keys.ts` +
// `server/sentry-scrub.ts` (which scrubs LLM-output and log paths).
//
// This module's `redactGithubSourcedText` is applied:
//   - INSERT-time inside the github-on-event Inngest dispatcher
//     (Phase 4 — `server/inngest/functions/github-on-event.ts`).
//   - Render-time inside `<TodayCard>` (Phase 6) — load-bearing
//     Art. 14 minimization gate per plan TR6 amendment.
//
// Belt-and-suspenders: INSERT-time keeps the audit row body
// redacted-equivalent; render-time is the final Art. 14 gate.
// If you must drop one, drop INSERT-time. NEVER drop render-time.
//
// PII shapes follow the three invariants from learning
// `2026-04-17-pii-regex-scrubber-three-invariants`:
//   1. Max-input bound (DoS-resistant).
//   2. Alphabet-aware UUID match (no /g+.test() gate that gets
//      stateful across calls).
//   3. No /g+.test() — every regex used here is single-shot or
//      paired with explicit lastIndex reset semantics via .replace().

export type RedactionSource = "pr_title" | "issue_body" | "cve_description";

export interface RedactionOptions {
  source?: RedactionSource;
}

// Hard cap: any input above this is truncated, then redacted.
// PR/issue titles top out around 256 chars per GitHub API; bodies
// at 65k chars. CVE descriptions are bounded by GHSA's 8k cap. The
// 64k bound keeps regex back-tracking bounded while admitting every
// realistic third-party body shape.
const MAX_INPUT_LEN = 64_000;
const TRUNCATION_MARKER = "[…]";

// Email — anchored on a word boundary; rejects empty local-part and
// missing TLD. Conservative; the goal is "is there an @ that looks
// like an address?" not full RFC 5322.
const EMAIL_RE = /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,24}\b/g;

// E.164-ish phone number: + optional, 7–15 digits with separators.
// Anchored to non-digit boundaries to avoid eating versioned strings
// like "1.2.3-rc.4".
const PHONE_RE = /(?<![\d])\+?\d{1,3}[-.\s]?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}(?![\d])/g;

// UUID v1-v5 — alphabet-aware (hex only), version-nibble in [1-8].
// 8-4-4-4-12 hex with version + variant bits. Per learning, no /g+.test()
// gate is used; .replace() with /g is reset per call via String.prototype.replace.
const UUID_RE = /\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\b/g;

// API-key-shaped: long base64-url-safe runs prefixed by a known sentinel.
// Covered:
//   GitHub classic PAT  ghp_/gho_/ghu_/ghs_/ghr_<20+ base64url>
//   GitHub fine-grained github_pat_<22 alnum>_<59 alnum>
//   Stripe live/test    sk_live_/pk_live_/rk_live_/sk_test_/pk_test_/rk_test_
//   Anthropic           sk-ant-<20+>
//   OpenAI              sk-<32+>
//   AWS access key id   AKIA<16 upper-alnum>
//   AWS secret access   40-char base64url (matched only after AWS sentinel
//                       words to avoid mass false-positives on long b64 blobs)
//   Slack tokens        xoxb-/xoxa-/xoxp-/xoxr-/xoxs- followed by digits + dash
const API_KEY_RE =
  /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_-]{20,}\b|\bgithub_pat_[A-Za-z0-9]{22}_[A-Za-z0-9]{59,}\b|\b(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{16,}\b|\bsk-ant-[A-Za-z0-9_-]{20,}\b|\bsk-[A-Za-z0-9]{32,}\b|\bAKIA[0-9A-Z]{16}\b|\bxox[abprs]-[0-9]+-[0-9]+-[A-Za-z0-9-]+\b/g;

// AWS_SECRET_ACCESS_KEY shape — the 40-char base64url is too generic to
// match standalone (collides with arbitrary hashes). We anchor on the
// canonical "AWS_SECRET_ACCESS_KEY=..." or "aws_secret_access_key = ..."
// assignment shapes that show up in pasted env / config snippets. The
// replacement preserves the assignment key so downstream tooling can
// still parse the line.
const AWS_SECRET_ASSIGN_RE =
  /\b(aws[_-]?secret[_-]?access[_-]?key)\s*[:=]\s*['"]?[A-Za-z0-9/+=]{40}['"]?/gi;

// AWS / IPv4 — keep CVE descriptions usable when they reference public
// service IPs (rendered as "[ip]"); avoids accidental MAC-address strip.
const IPV4_RE = /\b(?:25[0-5]|2[0-4]\d|[01]?\d{1,2})(?:\.(?:25[0-5]|2[0-4]\d|[01]?\d{1,2})){3}\b/g;

// IPv6 — strict 8-group hex form OR the "::" compressed form with at
// least one hex group on either side. Conservative: rejects single "::"
// alone (would match too many MAC-address chunks) and rejects ambiguous
// fragments like ":::". Matches global unicast and ULA shapes; link-local
// fe80::/10 also matches under the same regex.
const IPV6_RE =
  /\b(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\b|\b(?:[0-9a-fA-F]{1,4}:){1,7}:(?:[0-9a-fA-F]{1,4}:){0,6}[0-9a-fA-F]{1,4}\b/g;

// JWT — three base64url segments. Coarse; matches any "header.payload.sig"
// shape with realistic minimum lengths.
const JWT_RE = /\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/g;

/**
 * Redact third-party-ingested text (GitHub PR titles, issue bodies,
 * CVE advisory descriptions) before persisting to `messages` and
 * before rendering in `<TodayCard>`.
 *
 * The redaction set is conservative — it strips obvious credentials
 * and PII (emails, phones, UUIDs, API keys, JWTs, IPv4 addresses).
 * Card body context is preserved; only the shapes that map to known
 * leak vectors are replaced with `[redacted-<kind>]` markers.
 *
 * INVARIANT: existing exports in this module (if any) MUST be
 * preserved. This is a new export co-located with future siblings.
 * Stripe/CFO render paths use no redaction primitive from this module
 * today — only the github-* and kb-drift sources route through here.
 */
export function redactGithubSourcedText(
  s: string,
  _opts: RedactionOptions = {},
): string {
  if (typeof s !== "string" || s.length === 0) return "";

  // Max-input bound: truncate before regex to keep back-tracking bounded.
  // The truncation marker is appended AFTER redaction so the marker
  // itself cannot be falsely matched by any redaction pattern.
  const truncated = s.length > MAX_INPUT_LEN;
  const head = truncated ? s.slice(0, MAX_INPUT_LEN) : s;

  // Order matters: structured tokens (keys, JWT, UUID) BEFORE numeric
  // shapes (phone, IPv4). UUID precedes PHONE because the UUID's
  // 12-digit tail (e.g. 446655440000) otherwise matches the phone
  // 3+3+4 grouping when un-separated. EMAIL early — the local-part
  // can contain dots and digits that overlap nothing else here.
  const out = head
    // AWS secret assignment first — its replacement keeps the key= prefix
    // so the subsequent generic redactors don't double-process the value.
    .replace(AWS_SECRET_ASSIGN_RE, "$1=[redacted-key]")
    .replace(API_KEY_RE, "[redacted-key]")
    .replace(JWT_RE, "[redacted-jwt]")
    .replace(EMAIL_RE, "[redacted-email]")
    .replace(UUID_RE, "[redacted-uuid]")
    .replace(PHONE_RE, "[redacted-phone]")
    // IPv6 BEFORE IPv4 so "::ffff:192.0.2.1" maps to a single [redacted-ip]
    // instead of leaving "::ffff:[redacted-ip]" behind.
    .replace(IPV6_RE, "[redacted-ip]")
    .replace(IPV4_RE, "[redacted-ip]");

  return truncated ? `${out}${TRUNCATION_MARKER}` : out;
}
