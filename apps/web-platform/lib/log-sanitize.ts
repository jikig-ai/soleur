/**
 * Strip C0 control characters, DEL, and Unicode line/paragraph separators
 * before strings reach structured logs. U+2028 and U+2029 are especially
 * important: JSON loggers pass them through, but many log viewers and
 * JavaScript consumers treat them as line terminators — re-enabling log
 * injection through a "sanitized" log value.
 *
 * `server/pdf-linearize.ts` has a private copy that replaces stripped
 * characters with "?" (intentional — keeps qpdf stderr readable). Do not
 * fold it into this helper.
 *
 * @param value  String to sanitize.
 * @param maxLen Truncation cap, defaults to 500 to bound structured-log
 *               line size. Callers that already pre-cap upstream (e.g.,
 *               analytics-track's 200-char prop cap) are unaffected at
 *               the default; pass an explicit smaller cap when a call
 *               site wants tighter control (e.g., rejectCsrf uses 100).
 */
export function sanitizeForLog(value: string, maxLen = 500): string {
  return value.replace(/[\x00-\x1f\x7f\u2028\u2029]/g, "").slice(0, maxLen);
}
