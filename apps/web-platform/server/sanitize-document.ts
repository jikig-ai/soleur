/**
 * Single-source sanitizer for user-controlled body content destined for the
 * `<document>...</document>` system-prompt wrapper.
 *
 * Two passes, in order:
 *   1. Strip control chars (`\x00-\x1f`), DEL (`\x7f`), and U+2028/U+2029.
 *      Per `cq-regex-unicode-separators-escape-only` — line/paragraph
 *      separators are prompt-injection vectors AND character classes
 *      using literal U+2028/U+2029 are silently rewritten by some editors;
 *      always use escape forms (`\u2028\u2029`).
 *   2. Escape any closing-tag variant (`</document>`, `</Document>`,
 *      `</DOCUMENT>`, `</document >`, `< /document>`, …) to `<\/document>`
 *      so a poisoned body cannot break out of the wrapper. Case-insensitive
 *      + whitespace-tolerant per #3343.
 *
 * Centralized here so any future tightening (new variant, new escape
 * shape) lands in one place instead of six. Prior to this consolidation,
 * the same two-step pipeline lived inline at 6 sites across
 * `agent-runner.ts` and `soleur-go-runner.ts`; the case-variant gap (#3343)
 * was caused by the chained `replaceAll(...)` being case-sensitive at all
 * six places independently.
 */
// eslint-disable-next-line no-control-regex -- intentional: strip control chars + U+2028/U+2029
const CONTROL_CHAR_STRIP = /[\x00-\x1f\x7f\u2028\u2029]/g;
const DOCUMENT_CLOSE_TAG = /<\s*\/\s*document\s*>/gi;

export function sanitizeDocumentBody(text: string): string {
  return String(text).replace(CONTROL_CHAR_STRIP, "").replace(DOCUMENT_CLOSE_TAG, "<\\/document>");
}
