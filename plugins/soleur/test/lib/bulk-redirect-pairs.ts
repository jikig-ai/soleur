/**
 * Shared parser for the `item { value { redirect { source_url = ...
 * target_url = ... } } }` blocks in
 * `apps/web-platform/infra/seo-bulk-redirects.tf`.
 *
 * Used by seo-aeo-drift-guard.test.ts (Guard 2) and
 * marketing-content-drift.test.ts (Test 4). Single copy so a provider-v5
 * syntax flip (`item {}` blocks -> `items = [...]` attributes, warned about in
 * the tf header) needs one fix, not two coordinated edits.
 *
 * PARSER ASSUMPTIONS (mirrors terraform-target-parity.test.ts's convention):
 * - Comments are stripped before parsing: the tf file's own header embeds a
 *   literal `item { value { redirect { ... } } }` inside a # comment, which a
 *   naive `split("item {")` treats as a phantom block spanning into the first
 *   real item. `source_url`/`target_url` also appear in comments.
 * - Each `item {` block carries exactly one `source_url` and one
 *   `target_url`; the first match inside a block wins.
 * - The generated blog items live in `dynamic "item" { ... }`, which the
 *   `item {` splitter does not match — they are pinned separately by the
 *   shape-arm assertions (and by validate-blog-links.sh's parity check).
 * - No escaped `\"` inside a tf string precedes a `#`/`//` on the same line
 *   (none exist today; one would mis-toggle the quote state).
 * - Duplicate `source_url` keys resolve last-wins via `Map.set` — a wrong
 *   duplicate ordered before the correct item would mask it (acceptable
 *   residual; the pairs floor still applies).
 */

/** Strip `#` and `//` comments, respecting double-quoted strings per line. */
export function stripTfComments(tf: string): string {
  return tf
    .split("\n")
    .map((line) => {
      let inQuote = false;
      for (let i = 0; i < line.length; i++) {
        const ch = line[i];
        if (ch === '"') inQuote = !inQuote;
        if (!inQuote && ch === "#") return line.slice(0, i);
        if (!inQuote && ch === "/" && line[i + 1] === "/") {
          return line.slice(0, i);
        }
      }
      return line;
    })
    .join("\n");
}

export type RedirectItem = {
  /** The raw text of the item's block — lets callers pin flags (status_code,
   *  include_subdomains, preserve_query_string) on the SAME item they pin the
   *  pair on, not just file-wide. */
  block: string;
  target: string;
};

/**
 * Parse every `item { ... }` block into a source_url -> RedirectItem map.
 * A block with a source_url but no target_url maps to
 * `<missing target_url>` so a dropped attribute fails a pairing assertion
 * instead of silently absenting the key.
 */
export function bulkRedirectPairs(tf: string): Map<string, RedirectItem> {
  const pairs = new Map<string, RedirectItem>();
  for (const block of stripTfComments(tf).split(/\bitem\s*\{/).slice(1)) {
    const src = block.match(/source_url\s*=\s*"([^"]+)"/)?.[1];
    const tgt = block.match(/target_url\s*=\s*"([^"]+)"/)?.[1];
    if (src) pairs.set(src, { block, target: tgt ?? "<missing target_url>" });
  }
  return pairs;
}

const EDGE_301_FLAGS = [
  /status_code\s*=\s*301\b/,
  /include_subdomains\s*=\s*"enabled"/,
  /preserve_query_string\s*=\s*"enabled"/,
];

/**
 * The edge-301 flags a redirect item must carry (order-agnostic — a benign
 * attribute reorder is not a defect). Returns the missing flag patterns so a
 * caller can name exactly what drifted.
 */
export function missingEdge301Flags(block: string): string[] {
  return EDGE_301_FLAGS.filter((flag) => !flag.test(block)).map(
    (flag) => flag.source,
  );
}
