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
 * - The generated blog/tombstone items live in `dynamic "item" { ... }`, which
 *   the `item {` splitter does not match — they are pinned separately by the
 *   shape-arm assertions (and by validate-blog-links.sh's parity check) and
 *   enumerated for guards via `extractLocalMap` + `expandPrefixShapes` below.
 * - No escaped `\"` inside a tf string precedes a `#`/`//` on the same line
 *   (none exist today; one would mis-toggle the quote state).
 * - Duplicate `source_url` keys THROW (#8364): `Map.set` last-wins would let a
 *   wrong duplicate ordered before the correct item mask it silently.
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
  /** 0-based position among parsed `item {` blocks — used to name both
   *  occurrences in the duplicate-source_url error. */
  blockIndex: number;
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
  const blocks = stripTfComments(tf).split(/\bitem\s*\{/).slice(1);
  for (const [index, block] of blocks.entries()) {
    const src = block.match(/source_url\s*=\s*"([^"]+)"/)?.[1];
    const tgt = block.match(/target_url\s*=\s*"([^"]+)"/)?.[1];
    if (!src) continue;
    if (pairs.has(src)) {
      throw new Error(
        `duplicate source_url "${src}" in redirect items #${pairs.get(src)!.blockIndex + 1} and #${index + 1} — last-wins masking would hide one (#8364)`,
      );
    }
    pairs.set(src, {
      block,
      blockIndex: index,
      target: tgt ?? "<missing target_url>",
    });
  }
  return pairs;
}

/**
 * Extract a `"key" = "value"` map literal from a `locals {}` block —
 * e.g. `local.blog_redirect_pairs` or `local.tombstone_redirect_pairs`.
 * Region-scoped: only entries between `<name> = {` and its matching close
 * brace are read, so a quoted key elsewhere in the file cannot leak in.
 * Throws when the map is absent — a renamed local must fail loudly, not read
 * as an empty coverage set.
 */
export function extractLocalMap(
  tf: string,
  localName: string,
): Map<string, string> {
  const stripped = stripTfComments(tf);
  const open = stripped.match(new RegExp(`\\b${localName}\\s*=\\s*\\{`));
  if (!open || open.index === undefined) {
    throw new Error(`local.${localName} map not found in tf source`);
  }
  let depth = 0;
  let end = -1;
  for (let i = open.index + open[0].length - 1; i < stripped.length; i++) {
    if (stripped[i] === "{") depth++;
    else if (stripped[i] === "}") {
      depth--;
      if (depth === 0) {
        end = i;
        break;
      }
    }
  }
  if (end === -1) {
    throw new Error(`local.${localName} map has no closing brace`);
  }
  const body = stripped.slice(open.index + open[0].length, end);
  const map = new Map<string, string>();
  for (const m of body.matchAll(/"([^"]+)"\s*=\s*"([^"]+)"/g)) {
    if (map.has(m[1])) {
      throw new Error(
        `duplicate key "${m[1]}" in local.${localName} — a stale duplicate masks the live entry (#8364)`,
      );
    }
    map.set(m[1], m[2]);
  }
  return map;
}

/**
 * The 3-arm source expansion every redirect pair gets in
 * `local.redirect_items` (Bulk Redirects match http.request.full_uri
 * EXACTLY): directory URL, explicit index.html, bare no-slash form.
 * `pathPrefix` is a host-less path like `blog/<date-slug>` or
 * `pages/articles.html`.
 */
export function expandPrefixShapes(
  pathPrefix: string,
  target: string,
): { source: string; target: string }[] {
  const p = pathPrefix.replace(/^\/+|\/+$/g, "");
  return [
    { source: `soleur.ai/${p}/`, target },
    { source: `soleur.ai/${p}/index.html`, target },
    { source: `soleur.ai/${p}`, target },
  ];
}

/**
 * The full declared redirect source set: literal `item {}` source_urls +
 * `local.blog_redirect_pairs` expansion + `local.tombstone_redirect_pairs`
 * expansion. Throws on ANY duplicate source_url across sets — a generated
 * item colliding with a literal item produces two edge entries whose
 * precedence Cloudflare does not document (#8364, same last-wins masking
 * class as the in-list duplicate throw above).
 */
export function allDeclaredSources(tf: string): Map<string, string> {
  const out = new Map<string, string>();
  const add = (origin: string, src: string, target: string) => {
    if (out.has(src)) {
      throw new Error(
        `duplicate source_url "${src}" from ${origin} — collides with an earlier declaration (#8364)`,
      );
    }
    out.set(src, target);
  };
  for (const [src, item] of bulkRedirectPairs(tf)) {
    add("explicit item", src, item.target);
  }
  for (const [dateSlug, canonical] of extractLocalMap(
    tf,
    "blog_redirect_pairs",
  )) {
    for (const s of expandPrefixShapes(
      `blog/${dateSlug}`,
      `https://soleur.ai/blog/${canonical}/`,
    )) {
      add(`blog_redirect_pairs[${dateSlug}]`, s.source, s.target);
    }
  }
  for (const [prefix, target] of extractLocalMap(
    tf,
    "tombstone_redirect_pairs",
  )) {
    for (const s of expandPrefixShapes(prefix, target)) {
      add(`tombstone_redirect_pairs[${prefix}]`, s.source, s.target);
    }
  }
  return out;
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
