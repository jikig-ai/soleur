// Strip C0 control characters, DEL, and Unicode line/paragraph separators
// before strings reach structured logs. U+2028 and U+2029 are especially
// important: JSON loggers pass them through, but many log viewers and
// JavaScript consumers treat them as line terminators — re-enabling log
// injection through a "sanitized" goal.
//
// `server/pdf-linearize.ts` has a private copy that replaces with "?"
// (intentional, keeps qpdf stderr readable). Do not fold it into this helper.

export function sanitizeForLog(s: string, maxLen = 500): string {
  return s.replace(/[\x00-\x1f\x7f\u2028\u2029]/g, "").slice(0, maxLen);
}
