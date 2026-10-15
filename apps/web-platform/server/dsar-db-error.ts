/**
 * Diagnostic text for a failed Supabase read in the DSAR export.
 *
 * supabase-js returns `{ data, error, status, statusText }`. When the response
 * body is not JSON (for example a plain-text body from a proxy or gateway),
 * postgrest-js sets `error = { message: body }` and nothing else:
 * no `code`, no `hint`. The HTTP status is the only other evidence, and it
 * lives on the result object, which the read sites used to discard. A bare
 * `workspace_engine_settings read failed: Project not specified` (seen in a
 * nightly run) therefore could not be classified.
 *
 * Fields included: `message`, HTTP `status` (100-599) and `statusText`, and
 * `code` when it is a 5-character SQLSTATE or a `PGRST` code. `details` and
 * `hint` are excluded on purpose: PostgREST and Postgres can embed row values in both
 * (the repo's own rule, see `sqlStateFromError` in lib/postgres-errors.ts and
 * the comments in server/observability.ts), and this text reaches logs and
 * error reports on a regulated surface. `message` can still echo a filter
 * operand, exactly as the bare `error.message` it replaces did; the log and
 * Sentry sinks redact email addresses downstream. The `code` shape check is
 * wider than `sqlStateFromError` (5 characters) because PostgREST codes such
 * as PGRST116 are longer, and narrower than "any short token" so a hostile
 * body cannot ride out in the `code` slot.
 *
 * Why not `sanitizeForLog` (lib/log-sanitize.ts): it strips only C0, DEL and
 * U+2028/2029 and truncates by UTF-16 unit. This text also meets format
 * characters (bidi overrides, zero-width) and lone surrogates from a hostile
 * gateway body, so `clean` turns every run of whitespace and Unicode "Other"
 * category characters into one space, and truncates by code point.
 *
 * Bounded work: the input is cut to a small multiple of the cap BEFORE the
 * regexes run, because a gateway body can be megabytes (a mixed word-and-space
 * body measured about 100 ms per MB unbounded, which blocks the worker loop). A
 * body that opens with more than that much whitespace or control text reads as
 * `(no message)`.
 *
 * A cut can split an email address, and the sinks' redaction needs a whole one,
 * so a truncated text drops a trailing token that contains `@`.
 *
 * When nothing beyond the message is known the result is the message alone, so
 * assertions on the existing `<table> read failed: <message>` text still match.
 */

interface DbErrorLike {
  message?: string;
  code?: string;
}

const MAX_MESSAGE_CHARS = 300;
const MAX_FIELD_CHARS = 120;
// Pre-bound on raw input length, as a multiple of the output cap.
const INPUT_BOUND_FACTOR = 4;
// A 5-character SQLSTATE or a PostgREST `PGRST<digits>` code.
const CODE_SHAPE_RE = /^(?:[0-9A-Z]{5}|PGRST[0-9]{3})$/;

function clean(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  const bound = max * INPUT_BOUND_FACTOR;
  const cutByBound = value.length > bound;
  // A cut inside a surrogate pair leaves a lone surrogate, which \p{C} matches.
  const prefix = cutByBound ? value.slice(0, bound) : value;
  const collapsed = prefix.replace(/[\s\p{C}]+/gu, " ").trim();
  const points = Array.from(collapsed);
  if (!cutByBound && points.length <= max) return collapsed;
  const cut = points.slice(0, max).join("").replace(/\S*@\S*$/, "").trimEnd();
  return cut ? `${cut}...` : "";
}

export function describeDbError(
  error: DbErrorLike,
  status?: number,
  statusText?: string,
): string {
  const message = clean(error.message, MAX_MESSAGE_CHARS) || "(no message)";

  const parts: string[] = [];
  if (typeof status === "number" && Number.isInteger(status) && status >= 100 && status <= 599) {
    const text = clean(statusText, MAX_FIELD_CHARS);
    parts.push(text ? `status=${status} ${text}` : `status=${status}`);
  }
  if (typeof error.code === "string" && CODE_SHAPE_RE.test(error.code)) {
    parts.push(`code=${error.code}`);
  }

  return parts.length > 0 ? `${message} [${parts.join(" ")}]` : message;
}
