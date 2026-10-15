/**
 * Diagnostic text for a failed Supabase read in the DSAR export.
 *
 * supabase-js returns `{ data, error, status, statusText }`. When the response
 * body is not JSON (a gateway or edge text body such as `Project not
 * specified`), postgrest-js sets `error = { message: body }` and nothing else:
 * no `code`, no `hint`. The HTTP status is the only other evidence, and it
 * lives on the result object, which the read sites used to discard. A bare
 * `workspace_engine_settings read failed: Project not specified` therefore
 * could not be told apart from a database error.
 *
 * Fields included: `message`, HTTP `status` and `statusText`, and `code` when
 * it has the shape of a SQLSTATE or PostgREST code. `details` and `hint` are
 * excluded on purpose: PostgREST and Postgres can embed row values in both
 * (the repo's own rule, see `sqlStateFromError` in lib/postgres-errors.ts and
 * the comments in server/observability.ts), and this text reaches logs and
 * error reports on a regulated surface. `message` can still echo a filter
 * operand, exactly as the bare `error.message` it replaces did; the log and
 * Sentry sinks redact email addresses downstream. The `code` shape check is
 * wider than `sqlStateFromError` (5 characters) because PostgREST codes such
 * as PGRST116 are longer.
 *
 * Why not `sanitizeForLog` (lib/log-sanitize.ts): it strips only C0, DEL and
 * U+2028/2029 and truncates by UTF-16 unit. This text also meets format
 * characters (bidi overrides, zero-width) and lone surrogates from a hostile
 * gateway body, so `clean` collapses whitespace, removes every Unicode "Other"
 * category character, and truncates by code point.
 *
 * Bounded work: the input is cut to a small multiple of the cap BEFORE the
 * regexes run, because a gateway body can be megabytes (measured ~170 ms per MB
 * for a whitespace-heavy body, which blocks the worker loop). A body that opens
 * with more than that much whitespace or control text reads as `(no message)`.
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
const CODE_SHAPE_RE = /^[A-Za-z0-9_]{1,16}$/;

function clean(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  const bound = max * INPUT_BOUND_FACTOR;
  // A cut inside a surrogate pair leaves a lone surrogate, which \p{C} removes.
  const prefix = value.length > bound ? value.slice(0, bound) : value;
  const collapsed = prefix
    .replace(/\s+/g, " ")
    .replace(/\p{C}/gu, "")
    .trim();
  const points = Array.from(collapsed);
  return points.length > max
    ? `${points.slice(0, max).join("")}...`
    : collapsed;
}

export function describeDbError(
  error: DbErrorLike,
  status?: number,
  statusText?: string,
): string {
  const message = clean(error.message, MAX_MESSAGE_CHARS) || "(no message)";

  const parts: string[] = [];
  if (typeof status === "number" && Number.isInteger(status) && status > 0) {
    const text = clean(statusText, MAX_FIELD_CHARS);
    parts.push(text ? `status=${status} ${text}` : `status=${status}`);
  }
  if (typeof error.code === "string" && CODE_SHAPE_RE.test(error.code)) {
    parts.push(`code=${error.code}`);
  }

  return parts.length > 0 ? `${message} [${parts.join(" ")}]` : message;
}
