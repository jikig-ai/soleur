// scripts/live-verify/redact.ts
//
// Leakage-safety boundary for the live-verification harness (#5452, FR4).
// The harness drives the DEPLOYED app under a REAL synthetic-prod session and
// captures WS frames / DOM / network / console. Those artifacts can contain the
// synthetic principal's live credentials, so EVERYTHING is scrubbed here before
// it is surfaced in a PR/log; raw captures are never persisted.
//
// Design follows the three PII-scrubber invariants
// (knowledge-base/project/learnings/security-issues/2026-04-17-pii-regex-scrubber-three-invariants.md):
//   1. ReDoS-safe: every pattern is a single linear pass with one bounded
//      character class after its anchor — no adjacent unbounded `+` groups
//      around a `\.` anchor, so adversarial input cannot backtrack.
//   2. Structural matching: secrets are matched by WHERE they live (URL query
//      param, header, cookie, JSON key) plus the generic JWT shape — never a
//      version-specific token regex that misses a sibling shape.
//   3. No stateful `/g` + `.test()`: only `.replace()` is used, so there is no
//      `lastIndex` carry-over footgun.

const PLACEHOLDER = "[REDACTED]";

// Order matters: location-anchored rules run first (they preserve the
// surrounding structure), then the generic JWT/email sweeps catch anything that
// escaped a location rule.
const EMAIL_LOCAL = /[A-Za-z0-9._%+-]/;
const EMAIL_DOMAIN = /[A-Za-z0-9.-]+\.[A-Za-z]{2,}/y;

/**
 * Replace email addresses, with EXACTLY the matches of the original regex
 * `/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g`, in linear time.
 *
 * That regex rescans to the end of a long local-part-shaped run from every start
 * position when no `@` follows (quadratic: 100k characters took ~23 s). Its local
 * part must end at the first `@` after its start, so a match is determined by an
 * `@`: the local part is the run of local characters immediately before it
 * (clipped at the end of the previous match), and the domain is the same sticky
 * pattern the regex used. A lookbehind variant of the regex was linear but NOT
 * equivalent: it left the second of two back-to-back addresses unredacted
 * (`a@b.com+c@d.org`). `redact.test.ts` fuzzes this function against the original.
 */
function redactEmails(input: string): string {
  let out = "";
  let pos = 0; // end of the previous match: no local part may reach back past it
  let at = input.indexOf("@", pos);
  while (at !== -1) {
    let start = at;
    while (start > pos && EMAIL_LOCAL.test(input[start - 1])) start--;
    let end = -1;
    if (start < at) {
      EMAIL_DOMAIN.lastIndex = at + 1;
      if (EMAIL_DOMAIN.test(input)) end = EMAIL_DOMAIN.lastIndex;
    }
    if (end !== -1) {
      out += input.slice(pos, start) + PLACEHOLDER_EMAIL;
      pos = end;
      at = input.indexOf("@", pos);
    } else {
      at = input.indexOf("@", at + 1);
    }
  }
  return out + input.slice(pos);
}

const PLACEHOLDER_EMAIL = "[REDACTED_EMAIL]";

type Rule = [RegExp, string] | ((input: string) => string);

const RULES: Rule[] = [
  // GitHub tokens (#5487): the trigger-gate step runs `gh api` with GH_TOKEN.
  // These arms run FIRST: a generic-shape arm matching mid-body on a rotated
  // token's punctuation would shatter the gh*_ run and leak the tail.
  [/gh[pousr]_[A-Za-z0-9._~+/=-]{20,}/g, "[REDACTED_GH_TOKEN]"],
  [/github_pat_[A-Za-z0-9._~+/=-]{20,}/g, "[REDACTED_GH_TOKEN]"],
  // URL query secrets (incl. the Realtime WS connect URL: ?apikey=&access_token=)
  [
    /([?&](?:access_token|refresh_token|provider_token|apikey|token)=)[^&\s"'#]+/gi,
    `$1${PLACEHOLDER}`,
  ],
  // Authorization: Bearer <token>  (request headers in captured network frames)
  [/(authorization:\s*bearer\s+)[A-Za-z0-9._~+/=-]+/gi, `$1${PLACEHOLDER}`],
  // Supabase auth cookie: sb-<ref>-auth-token=<value>, including the chunked
  // form sb-<ref>-auth-token.0=, .1=, … that @supabase/ssr emits for large
  // sessions (without the `.N` allowance the chunked names escape — security
  // review P1).
  [/(sb-[a-z0-9-]+-auth-token(?:\.\d+)?=)[^;\s"']+/gi, `$1${PLACEHOLDER}`],
  // @supabase/ssr serialized session value: `base64-<base64url(JSON session)>`.
  // The blob embeds access_token + refresh_token + email but has NO JWT `.`
  // separators, so the generic JWT/email/cookie rules all miss it. Redact the
  // opaque value wholesale wherever it appears (cookie value, network frame,
  // DOM) — this is the structural shape the scrubber's threat model targets
  // (security review P1; default cookieEncoding="base64url").
  [/base64-[A-Za-z0-9_-]{40,}/g, "[REDACTED_SB_SESSION]"],
  // Supabase API keys, CURRENT format (#7969). The prd
  // SUPABASE_SERVICE_ROLE_KEY is `sb_secret_…` — opaque, not a JWT — so the
  // generic `eyJ…` rule below cannot see it. That is the highest-value
  // credential in the live-verify pipeline and it was the one format this
  // scrubber did not cover, on a PUBLIC repo whose Actions logs are
  // world-readable. `sb_publishable_…` is included because a mix-up that put
  // one in the service-role slot should still not be published.
  [/sb_secret_[A-Za-z0-9_-]{10,}/g, "[REDACTED_SB_SECRET]"],
  [/sb_publishable_[A-Za-z0-9_-]{10,}/g, "[REDACTED_SB_PUBLISHABLE]"],
  // Doppler tokens (#5487): the live-verify GHA job runs the harness under
  // `doppler run -c prd`, so a doppler CLI error could surface its token in
  // stderr — which the job tees to the run log and embeds in a Sentry crash-tail
  // event. These are prefix-shaped (no structural location in raw stderr), so a
  // shape match is the only option; the `dp.<class>.` prefix is stable across
  // service/personal/service-account/CLI/scim/audit token classes.
  [/dp\.(?:st|pt|sa|ct|scim|audit)\.[A-Za-z0-9._-]{10,}/g, "[REDACTED_DOPPLER]"],
  // JSON token keys: "access_token":"...", "refresh_token":"...", etc.
  [
    /(["'](?:access_token|refresh_token|provider_token)["']\s*:\s*")[^"]+/gi,
    `$1${PLACEHOLDER}`,
  ],
  // api_keys ciphertext columns (I-cannot-spend read in verifyPrincipal). The
  // gate never logs row data; this is the backstop should a row ever reach a
  // captured error, response body or console line. Two shapes: JSON
  // (`"encrypted_key":"…"`) and unquoted/`util.inspect`/query-string
  // (`encrypted_key: '…'`, `iv=…&`). The lookbehind keeps `iv` from matching
  // inside other identifiers (`div=`, `device_iv:`); the lookahead keeps the
  // rule idempotent on its own output.
  [
    /(["'](?:encrypted_key|iv|auth_tag)["']\s*:\s*")[^"]+/gi,
    `$1${PLACEHOLDER}`,
  ],
  [
    /((?<![A-Za-z0-9_])(?:encrypted_key|iv|auth_tag)["']?\s*[:=]\s*["']?)(?!\[REDACTED)[^\s"',&;)}\]]+/gi,
    `$1${PLACEHOLDER}`,
  ],
  // Generic JWT shape (3 base64url segments) — catches bare tokens in DOM/logs.
  [/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, "[REDACTED_JWT]"],
  // Email addresses: a linear scan, not a regex (see redactEmails).
  redactEmails,
];

/**
 * Redact secrets from a captured-artifact string by structural location.
 * Pure + idempotent on already-redacted input.
 */
export function redact(input: string): string {
  let out = input;
  for (const rule of RULES) {
    out = typeof rule === "function" ? rule(out) : out.replace(rule[0], rule[1]);
  }
  return out;
}
