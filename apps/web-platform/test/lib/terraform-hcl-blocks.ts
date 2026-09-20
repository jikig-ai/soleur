// Shared source-text extraction helpers for the infra/*.tf pin suites
// (seo-rulesets-noindex.test.ts, seo-config-rules.test.ts,
// seo-page-redirects-ruleset.test.ts).
//
// There is no HCL parser in the toolchain, so these helpers brace-count raw
// source text — the technique established by seo-rulesets-noindex.test.ts and
// duplicated in seo-config-rules.test.ts before being lifted here (#8364,
// guard gap 3). Two assumptions the counting relies on:
//
//   - `{`/`}` inside quoted strings are BALANCED (true for the host-set
//     literals `{"a" "b"}` inside Cloudflare filter expressions).
//   - Callers that must survive a commented-out `rules { }` block strip HCL
//     comments BEFORE extracting (see stripHclComments in
//     seo-config-rules.test.ts) — brace counting cannot see comments, and a
//     stray `{` inside a comment desyncs the depth count.

/**
 * Extract the body of a `resource "cloudflare_ruleset" "<name>" { ... }` block
 * by brace-counting from the resource declaration. Returns the substring
 * between the opening `{` and its matching `}` (exclusive). Throws if the
 * resource is absent so a deleted-resource regression fails loudly rather than
 * silently passing on an empty string.
 */
export function extractResourceBody(src: string, name: string): string {
  const marker = `resource "cloudflare_ruleset" "${name}"`;
  const start = src.indexOf(marker);
  if (start === -1) {
    throw new Error(`resource "cloudflare_ruleset" "${name}" not found`);
  }
  const openBrace = src.indexOf("{", start);
  if (openBrace === -1) {
    throw new Error(`opening brace for resource "${name}" not found`);
  }
  let depth = 0;
  for (let i = openBrace; i < src.length; i++) {
    const ch = src[i];
    if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) return src.slice(openBrace + 1, i);
    }
  }
  throw new Error(`unbalanced braces in resource "${name}"`);
}

/**
 * Return EVERY `rules { ... }` block body within a resource body, brace-counted
 * so nested `action_parameters { ... }` / `from_value { ... }` / `target_url
 * { ... }` blocks are captured in full. Anchors on `rules\s*\{` (the block
 * opener) rather than the bare word "rules", which also appears in
 * `provider = cloudflare.rulesets` — matching `rules\s*{` prevents a comment
 * with a stray `{` before the first real rules block from desyncing the brace
 * count and binding the wrong rule.
 */
export function extractRuleBlocks(resourceBody: string): string[] {
  const opener = /\brules\s*\{/g;
  const blocks: string[] = [];
  let m: RegExpExecArray | null;
  while ((m = opener.exec(resourceBody)) !== null) {
    const openBrace = resourceBody.indexOf("{", m.index);
    let depth = 0;
    let end = -1;
    for (let i = openBrace; i < resourceBody.length; i++) {
      const ch = resourceBody[i];
      if (ch === "{") depth++;
      else if (ch === "}") {
        depth--;
        if (depth === 0) {
          end = i;
          break;
        }
      }
    }
    if (end === -1) break;
    blocks.push(resourceBody.slice(openBrace + 1, end));
    opener.lastIndex = end + 1;
  }
  return blocks;
}
