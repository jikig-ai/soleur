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
 * Fields included: `message` (whitespace-collapsed, stripped of control and
 * separator characters, truncated), HTTP `status` and `statusText`, `code`,
 * `hint`. `details` is excluded on purpose: PostgREST can echo row values in
 * it, and this text reaches logs and error reports on a regulated surface.
 * When nothing beyond the message is known the result is the message alone, so
 * assertions on the existing `<table> read failed: <message>` text still match.
 */

export interface DbErrorLike {
  message?: string;
  code?: string;
  hint?: string;
}

const MAX_MESSAGE_CHARS = 300;
const MAX_FIELD_CHARS = 120;

function clean(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  const collapsed = value
    .replace(/\s+/g, " ")
    .replace(/\p{C}/gu, "")
    .trim();
  return collapsed.length > max ? `${collapsed.slice(0, max)}...` : collapsed;
}

export function describeDbError(
  error: DbErrorLike,
  status?: number,
  statusText?: string,
): string {
  const message = clean(error.message, MAX_MESSAGE_CHARS) || "(no message)";

  const parts: string[] = [];
  if (typeof status === "number" && status > 0) {
    const text = clean(statusText, MAX_FIELD_CHARS);
    parts.push(text ? `status=${status} ${text}` : `status=${status}`);
  }
  const code = clean(error.code, MAX_FIELD_CHARS);
  if (code) parts.push(`code=${code}`);
  const hint = clean(error.hint, MAX_FIELD_CHARS);
  if (hint) parts.push(`hint=${hint}`);

  return parts.length > 0 ? `${message} [${parts.join(" ")}]` : message;
}
