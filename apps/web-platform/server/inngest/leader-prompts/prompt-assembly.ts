// Prompt-assembly PII-scrub helpers for the Anthropic-SDK leader loop
// (PR-B #4379 AC16). Two composable passes:
//
//   1. sanitizePromptString: control-char + U+2028 + U+2029 strip.
//      Per learning 2026-05-06-new-prompt-injection-site-needs-sanitization-parity.md:
//      any new prompt-injection site MUST apply this contract. The
//      canonical local impl lives at server/soleur-go-runner.ts:1009-1013
//      (sanitizePromptString) with a 256-char cap for identifier-shaped
//      fields; PR-B's PR-diff content is long-form so this version omits
//      the cap. Same regex contract otherwise. Newline (0x0a) and tab
//      (0x09) are PRESERVED.
//
//   2. scrubEmails: replace any email-shaped match with `<email-redacted>`
//      EXCEPT the operator's own email if present on a redact-allowlist.
//      PR diffs and issue bodies regularly contain third-party PII.
//      PA-22 (g) enumerates this scrub.
//
//   3. assemblePromptText: composition: sanitize, then scrub. Order
//      matters: scrub-first would let `attacker\x00@evil.example` slip
//      past the email regex because the control char breaks the local
//      part match.
//
// Per cq-regex-unicode-separators-escape-only: regex literals reference
// U+2028 + U+2029 via escape sequences only (NEVER literal — the literal
// chars are JS line terminators and cannot appear inside a regex source).

// eslint-disable-next-line no-control-regex
const STRIP_REGEX = /[\x00-\x08\x0b-\x1f\x7f\u2028\u2029]/g;

const EMAIL_REGEX = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g;

export function sanitizePromptString(v: unknown): string {
  if (v === null || v === undefined) return "";
  return String(v).replace(STRIP_REGEX, "");
}

export function scrubEmails(
  text: string,
  allowlistEmail: string | null,
): string {
  const allowlistLower = allowlistEmail?.toLowerCase() ?? null;
  return text.replace(EMAIL_REGEX, (match) => {
    if (allowlistLower !== null && match.toLowerCase() === allowlistLower) {
      return match;
    }
    return "<email-redacted>";
  });
}

export function assemblePromptText(
  raw: unknown,
  allowlistEmail: string | null,
): string {
  return scrubEmails(sanitizePromptString(raw), allowlistEmail);
}
