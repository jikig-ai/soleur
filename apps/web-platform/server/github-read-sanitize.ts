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
 * Pass 1 (cap-independent, done ONCE): strip invisible format characters from every string leaf and redact `title`/`body` per
 * field. Redaction runs per string field and NEVER over stringified JSON: its phone/UUID/IPv4 patterns would corrupt numeric ids,
 * timestamps and URLs. Non-string leaves (numbers, booleans, null) are untouched.
 */
function prepareStrings(value: unknown, key: string, redact: boolean): unknown {
  if (typeof value === "string") {
    const out = stripFormatChars(value);
    const source = REDACTED_KEYS[key];
    return redact && source ? redactGithubSourcedText(out, { source }) : out;
  }
  if (Array.isArray(value)) return value.map((v) => prepareStrings(v, key, redact));
  if (value !== null && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) out[k] = prepareStrings(v, k, redact);
    return out;
  }
  return value;
}

/** Pass 2 (cheap, repeatable): cut every string leaf to its cap. */
function capStrings(value: unknown, key: string, bodyCap: number): unknown {
  if (typeof value === "string") return capChars(value, BODY_KEYS.has(key) ? bodyCap : OTHER_FIELD_CAP);
  if (Array.isArray(value)) return value.map((v) => capStrings(v, key, bodyCap));
  if (value !== null && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) out[k] = capStrings(v, k, bodyCap);
    return out;
  }
  return value;
}

type ListShape = { summary?: unknown; has_more?: unknown; pull_requests: unknown[] };

function isListShape(value: unknown): value is ListShape {
  return value !== null && typeof value === "object" && !Array.isArray(value) && Array.isArray((value as ListShape).pull_requests);
}

/**
 * Harden one tool response: strip + redact once, then cap per field, then hold the JSON length under `RESPONSE_BUDGET_CHARS` by
 * halving the body cap (down to 64 characters) and, as the last resort, dropping trailing rows. The list tool keeps its own shape
 * (`summary` says how many rows were kept, `has_more` stays as GitHub reported, plus `truncated`/`note` beside them); a bare array is wrapped as
 * `{ truncated, note, items }`. The result stringifies to at most the budget plus a small marker.
 */
export function hardenReadResult(value: unknown, opts: { redact: boolean }): unknown {
  const size = (v: unknown): number => JSON.stringify(v)?.length ?? 0;
  const prepared = prepareStrings(value, "", opts.redact);
  let bodyCap = BODY_FIELD_CAP;
  let out = capStrings(prepared, "", bodyCap);
  while (size(out) > RESPONSE_BUDGET_CHARS && bodyCap > 64) {
    bodyCap = Math.max(64, Math.floor(bodyCap / 2));
    out = capStrings(prepared, "", bodyCap);
  }
  if (size(out) <= RESPONSE_BUDGET_CHARS) return out;

  const rows: unknown[] | null = Array.isArray(out) ? out : isListShape(out) ? out.pull_requests : null;
  if (rows === null || rows.length === 0) return out;
  const rebuild = (keep: number): unknown => {
    const kept = rows.slice(0, keep);
    const dropped = kept.length < rows.length;
    const note = dropped
      ? `response exceeded the size budget; showing ${kept.length} of ${rows.length} items. Call again with a smaller per_page.`
      : undefined;
    if (isListShape(out)) {
      // `has_more` stays what GitHub reported (it answers "are there more PRs on GitHub"); `truncated` answers "did we cut rows".
      return {
        ...out,
        ...(dropped ? { summary: `${out.summary ?? ""}; ${kept.length} of ${rows.length} shown (response size budget)` } : {}),
        truncated: dropped,
        ...(note ? { note } : {}),
        pull_requests: kept,
      };
    }
    return { truncated: dropped, ...(note ? { note } : {}), items: kept };
  };
  let keep = rows.length;
  let trimmed = rebuild(keep);
  while (keep > 1 && size(trimmed) > RESPONSE_BUDGET_CHARS) {
    keep = Math.max(1, Math.floor(keep * (RESPONSE_BUDGET_CHARS / size(trimmed)) * 0.9));
    trimmed = rebuild(keep);
  }
  return trimmed;
}
