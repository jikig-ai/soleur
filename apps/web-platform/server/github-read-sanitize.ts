/**
 * Pure text hardening for the Command Center GitHub read tools (#12469).
 *
 * GitHub-sourced text (PR titles, bodies, comments, branch names, labels, CI run names) reaches an agent that may have open
 * web egress. These helpers shape what the cc read tools return: invisible format characters are stripped, every string is
 * cut to a character cap, and the whole response is held to a size budget. They are DATA MINIMISATION and size hygiene, not
 * an anti-exfiltration control: the controls are the entitlement, the public-repo gate, the untrusted-content framing and the
 * read-only scope.
 *
 * Nothing here imports the GitHub API, the SDK or the logger, so it is cheap to load and trivial to test.
 */

import { redactGithubSourcedText } from "@/lib/safety/redaction-allowlist";

/** Marker appended where a field was cut. */
export const TRUNCATION_SUFFIX = "…[truncated]";

/** Total character budget of one tool response (JSON length). */
export const RESPONSE_BUDGET_CHARS = 64_000;
/** Cap of the free-text fields that legitimately run long (issue/PR/comment `body`). */
export const BODY_FIELD_CAP = 4_096;
/** Cap of every other string field (titles, refs, logins, labels, run names, URLs). */
export const OTHER_FIELD_CAP = 512;

// Unicode "format" characters (tag characters, bidi controls, zero-width joiners, BOM, soft hyphen): invisible to a human
// reader and a known channel for hiding instructions in text. Written as an ESCAPE (`\p{Cf}`), never as literal characters.
const FORMAT_CHARS_RE = /\p{Cf}/gu;

/** Strip invisible Unicode format characters. */
export function stripFormatChars(value: string): string {
  return value.replace(FORMAT_CHARS_RE, "");
}

/** Cut `value` to `max` CODE POINTS (characters, not UTF-16 units), marking the cut. */
export function capChars(value: string, max: number): string {
  if (value.length <= max) return value; // <= max UTF-16 units implies <= max code points
  const points = Array.from(value);
  return points.length <= max ? value : `${points.slice(0, max).join("")}${TRUNCATION_SUFFIX}`;
}

/** String keys whose value is long-form text: they get the larger cap and the redaction pass. */
const BODY_KEYS = new Set(["body"]);
const REDACTED_KEYS: Record<string, "pr_title" | "issue_body"> = { title: "pr_title", body: "issue_body" };

/**
 * Deep-map every string leaf of `value`: strip format characters, redact `title`/`body` per field when `redact` is set, then
 * cap. Redaction runs per string field and NEVER over stringified JSON: its phone/UUID/IPv4 patterns would corrupt numeric ids,
 * timestamps and URLs. Non-string leaves (numbers, booleans, null) are untouched.
 */
function mapStrings(value: unknown, key: string, redact: boolean, bodyCap: number): unknown {
  if (typeof value === "string") {
    let out = stripFormatChars(value);
    const source = REDACTED_KEYS[key];
    if (redact && source) out = redactGithubSourcedText(out, { source });
    return capChars(out, BODY_KEYS.has(key) ? bodyCap : OTHER_FIELD_CAP);
  }
  if (Array.isArray(value)) return value.map((v) => mapStrings(v, key, redact, bodyCap));
  if (value !== null && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) out[k] = mapStrings(v, k, redact, bodyCap);
    return out;
  }
  return value;
}

/** The array a response carries its rows in: the value itself, or its `pull_requests` member. */
function rowsOf(value: unknown): unknown[] | null {
  if (Array.isArray(value)) return value;
  const rows = (value as { pull_requests?: unknown } | null)?.pull_requests;
  return Array.isArray(rows) ? rows : null;
}

function withRows(value: unknown, rows: unknown[]): unknown {
  return Array.isArray(value) ? rows : { ...(value as Record<string, unknown>), pull_requests: rows };
}

/**
 * Harden one tool response: per-field strip + redact + cap, then hold the JSON length under `RESPONSE_BUDGET_CHARS` by
 * halving the body cap (down to 64 characters) and, as the last resort, dropping trailing rows with an explicit marker.
 * The result is always a value that stringifies to at most the budget plus the small marker object.
 */
export function hardenReadResult(value: unknown, opts: { redact: boolean }): unknown {
  const size = (v: unknown): number => JSON.stringify(v)?.length ?? 0;
  let bodyCap = BODY_FIELD_CAP;
  let out = mapStrings(value, "", opts.redact, bodyCap);
  while (size(out) > RESPONSE_BUDGET_CHARS && bodyCap > 64) {
    bodyCap = Math.max(64, Math.floor(bodyCap / 2));
    out = mapStrings(value, "", opts.redact, bodyCap);
  }
  if (size(out) <= RESPONSE_BUDGET_CHARS) return out;
  const rows = rowsOf(out);
  if (rows === null || rows.length === 0) return out;
  let keep = rows.length;
  let trimmed = withRows(out, rows.slice(0, keep));
  while (keep > 1 && size(trimmed) > RESPONSE_BUDGET_CHARS) {
    keep = Math.max(1, Math.floor(keep * (RESPONSE_BUDGET_CHARS / size(trimmed)) * 0.9));
    trimmed = withRows(out, rows.slice(0, keep));
  }
  return {
    truncated: true,
    note: `response exceeded the size budget; showing ${keep} of ${rows.length} items. Ask for fewer items (a smaller per_page).`,
    result: trimmed,
  };
}
