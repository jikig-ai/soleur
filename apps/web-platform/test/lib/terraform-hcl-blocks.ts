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
//     comments BEFORE extracting — stripHclComments is exported below for
//     exactly this. Brace counting cannot see comments: a `/* rules { … } *\/`
//     or `#`-commented rule otherwise still matches `rules\s*\{` and counts
//     toward the pin (demonstrated mutant in seo-config-rules.test.ts), and
//     a stray `{` inside a comment desyncs the depth count. EVERY consumer
//     of these extractors must pass stripped text; only read raw source when
//     the comment itself is the assertion target.

/**
 * Strip `#`, `//`, and `/* *\/` HCL comments while respecting double-quoted
 * strings (backslash escapes included); newlines are preserved so line
 * structure survives. Lifted from seo-config-rules.test.ts (#8364 review):
 * the pin suites' assertions are all regexes over extracted text, so a
 * commented-out `rules {}` block — or a `status_code = 301` inside a
 * comment — must never satisfy them.
 */
export function stripHclComments(src: string): string {
  let out = "";
  let inString = false;
  for (let i = 0; i < src.length; i++) {
    const ch = src[i];
    if (inString) {
      out += ch;
      if (ch === "\\") {
        // Preserve the escaped character verbatim; it cannot close the string.
        if (i + 1 < src.length) {
          out += src[i + 1];
          i++;
        }
      } else if (ch === '"') {
        inString = false;
      }
      continue;
    }
    if (ch === '"') {
      inString = true;
      out += ch;
      continue;
    }
    if (ch === "/" && src[i + 1] === "*") {
      // Block comment: skip to the closing delimiter, preserving newlines so
      // line structure is unchanged.
      i += 2;
      while (i < src.length && !(src[i] === "*" && src[i + 1] === "/")) {
        if (src[i] === "\n") out += "\n";
        i++;
      }
      i++; // land on the '/' of the closer; loop's i++ steps past it
      continue;
    }
    if (ch === "#" || (ch === "/" && src[i + 1] === "/")) {
      while (i < src.length && src[i] !== "\n") i++;
      out += "\n";
      continue;
    }
    out += ch;
  }
  return out;
}

/**
 * Escape every regex metacharacter so an interpolated literal matches itself.
 * Escaping only `.` leaves `\` unescaped, which lets the input alter the
 * pattern's meaning rather than being matched verbatim (CodeQL
 * js/incomplete-sanitization).
 */
export function escapeRegExp(literal: string): string {
  return literal.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Read a quoted attribute value (`name = "..."`) from a block, decoding
 * HCL's backslash escapes so a Cloudflare filter expression such as
 * `"(http.host in {\"soleur.ai\"})"` is compared in its logical form.
 * Returns the FIRST match — for `expression` that is the rule-level filter,
 * which always precedes `action_parameters.target_url.expression`.
 */
export function quotedAttr(block: string, name: string): string | null {
  // nosemgrep: javascript.lang.security.audit.detect-non-literal-regexp.detect-non-literal-regexp -- name is escaped via escapeRegExp; attribute identifiers are test-controlled constants
  const re = new RegExp(`\\b${escapeRegExp(name)}\\s*=\\s*"((?:[^"\\\\]|\\\\.)*)"`);
  const m = re.exec(block);
  if (!m) return null;
  return m[1].replace(/\\(.)/g, "$1");
}

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
