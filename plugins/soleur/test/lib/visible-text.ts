// Visible text of a built HTML document, without a tag-strip regex.
//
// The docs drift guards read built pages, so they need the text a visitor sees
// and the sentence boundaries a visitor perceives. A single-pass `/<[^>]+>/g`
// replace is the js/incomplete-multi-character-sanitization pattern CodeQL
// flags in this repo, so tags are removed by a character scan instead.
//
// Boundaries: every block-level tag (inline ones such as <cite>, <button> and
// <label> are NOT boundaries) emits BOUNDARY, so a heading without a
// final period never merges with the paragraph below it. Source newlines are
// ordinary whitespace (hard-wrapped prose is one sentence), never a boundary.
//
// Not a general HTML parser: it is exercised against this site's own Eleventy
// output, and plugins/soleur/test/visible-text.test.ts pins the edge cases.

export const BOUNDARY = "\u0001";

const BLOCK_TAGS = new Set([
  "address", "article", "aside", "blockquote", "br", "dd",
  "details", "div", "dl", "dt", "figcaption", "figure", "footer", "form",
  "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "li", "main",
  "nav", "ol", "p", "section", "summary", "table", "td", "th", "tr", "ul",
]);

const ENTITIES: Record<string, string> = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ",
  rsquo: "’", lsquo: "‘", ldquo: "“", rdquo: "”", mdash: "—",
  ndash: "–", hellip: "…", rarr: "→",
  ensp: " ", emsp: " ", thinsp: " ", hairsp: " ", numsp: " ", puncsp: " ",
  NonBreakingSpace: " ", shy: "", zwj: "", zwnj: "", ZeroWidthSpace: "",
};

// Characters a browser renders as nothing: every Unicode format character
// (soft hyphen, zero-width space and joiners, LRM/RLM, word joiner, BOM) plus the
// combining grapheme joiner and the Mongolian vowel separator. Built with a
// property escape and char codes, so no invisible character sits in this source.
const INVISIBLE_RE = new RegExp("[\\p{Cf}" + String.fromCharCode(0x34f, 0x180e) + "]", "gu");

// The one place every text arm normalises: visible text, attributes, JSON-LD
// strings and llms.txt all reach `sentencesOf`, so a hidden character cannot split
// a word in one arm and not another.
export function stripInvisible(s: string): string {
  return s.replace(INVISIBLE_RE, "");
}

// One pass: `&amp;lt;` becomes the literal text `&lt;`, never `<`.
export function decodeEntities(s: string): string {
  return s
    .replace(
    /&(?:#(\d+)|#[xX]([0-9a-fA-F]+)|([a-zA-Z]+));/g,
    (whole, dec?: string, hex?: string, name?: string) => {
      if (name !== undefined) return ENTITIES[name] ?? whole;
      const code = dec !== undefined ? parseInt(dec, 10) : parseInt(hex as string, 16);
      return Number.isInteger(code) && code >= 0 && code <= 0x10ffff
        ? String.fromCodePoint(code)
        : whole;
    },
    )
    .replace(INVISIBLE_RE, "");
}

// End index (exclusive) of the tag that starts at `start` (a `<`), or -1.
// Honours quoted attribute values so a `>` inside one does not end the tag;
// when a quote never closes, falls back to the first `>` so one stray quote
// cannot swallow the rest of the page.
function tagEnd(html: string, start: number): number {
  let quote = "";
  for (let j = start + 1; j < html.length; j++) {
    const c = html[j];
    if (quote) {
      if (c === quote) quote = "";
    } else if (c === '"' || c === "'") {
      quote = c;
    } else if (c === ">") {
      return j + 1;
    }
  }
  const first = html.indexOf(">", start + 1);
  return first === -1 ? -1 : first + 1;
}

export function visibleText(html: string): string {
  let out = "";
  let i = 0;
  while (i < html.length) {
    if (html[i] !== "<") {
      out += html[i++];
      continue;
    }
    if (html.startsWith("<!--", i)) {
      const end = html.indexOf("-->", i + 4);
      i = end === -1 ? html.length : end + 3;
      continue;
    }
    // A `<` that cannot start a tag (`x < 5`) is text.
    if (!/[A-Za-z/!]/.test(html[i + 1] ?? "")) {
      out += html[i++];
      continue;
    }
    const end = tagEnd(html, i);
    if (end === -1) {
      out += html[i++];
      continue;
    }
    const tag = html.slice(i + 1, end - 1);
    const name = (tag.match(/^\/?\s*([a-zA-Z][a-zA-Z0-9]*)/)?.[1] ?? "").toLowerCase();
    if (!tag.startsWith("/") && (name === "script" || name === "style")) {
      const close = new RegExp(`</${name}[^>]*>`, "gi");
      close.lastIndex = end;
      const m = close.exec(html);
      i = m ? m.index + m[0].length : html.length;
      out += BOUNDARY;
      continue;
    }
    if (BLOCK_TAGS.has(name)) out += BOUNDARY;
    i = end;
  }
  return decodeEntities(out);
}

// A sentence ends at [.!?] plus whitespace, unless the next word starts in lower
// case ("as Inc. reported", "approx. two seats") or the period closes e.g., i.e.
// or vs. Merging two sentences is the unsafe direction for a guard (a neighbour's
// "waitlist" would excuse a price), so the rule only declines to split where the
// continuation is lower case.
export function sentencesOf(text: string): string[] {
  return stripInvisible(text)
    .split(new RegExp(`${BOUNDARY}+|(?<!\\b(?:[eE]\\.g|[iI]\\.e|[vV]s)\\.)(?<=[.!?])\\s+(?=[^a-z\\s])`))
    .map((s) => s.replace(/\s+/g, " ").trim())
    .filter((s) => s.length > 0);
}

// The text of one fragment as a single normalised string.
export function plainText(html: string): string {
  return sentencesOf(visibleText(html)).join(" ");
}

// The document with parts a visitor never sees removed: comments, <template>
// and <noscript> bodies. Character scan, not a replace-regex sanitizer.
export function withoutInert(html: string): string {
  let out = "";
  let i = 0;
  const starts = /<!--|<template\b|<noscript\b/gi;
  while (i < html.length) {
    starts.lastIndex = i;
    const m = starts.exec(html);
    if (!m) {
      out += html.slice(i);
      break;
    }
    out += html.slice(i, m.index);
    const open = m[0].toLowerCase();
    if (open === "<!--") {
      const end = html.indexOf("-->", m.index + 4);
      i = end === -1 ? html.length : end + 3;
    } else {
      const name = open.slice(1);
      const close = new RegExp(`</${name}[^>]*>`, "gi");
      close.lastIndex = m.index;
      const c = close.exec(html);
      i = c ? c.index + c[0].length : html.length;
    }
  }
  return out;
}

// Every tag of the document in source order with its start index, comments and
// <script>/<style> bodies skipped, quoted attribute values honoured (a `>` inside
// one does not end the tag). Attribute scans and ancestor walks read this.
export function tagsOf(html: string): { raw: string; index: number }[] {
  const out: { raw: string; index: number }[] = [];
  let i = 0;
  while (i < html.length) {
    if (html[i] !== "<") {
      i++;
      continue;
    }
    if (html.startsWith("<!--", i)) {
      const end = html.indexOf("-->", i + 4);
      i = end === -1 ? html.length : end + 3;
      continue;
    }
    if (!/[A-Za-z/]/.test(html[i + 1] ?? "")) {
      i++;
      continue;
    }
    const end = tagEnd(html, i);
    if (end === -1) {
      i++;
      continue;
    }
    const raw = html.slice(i, end);
    out.push({ raw, index: i });
    const name = (raw.match(/^<\/?\s*([a-zA-Z][a-zA-Z0-9]*)/)?.[1] ?? "").toLowerCase();
    if (!raw.startsWith("</") && (name === "script" || name === "style")) {
      const close = new RegExp(`</${name}[^>]*>`, "gi");
      close.lastIndex = end;
      const m = close.exec(html);
      if (m) out.push({ raw: m[0], index: m.index });
      i = m ? m.index + m[0].length : html.length;
      continue;
    }
    i = end;
  }
  return out;
}

const VOID_TAGS = new Set([
  "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
  "source", "track", "wbr",
]);

// The opening tags still open at `target` (an index into `html`), outermost
// first: what a stylesheet or `hidden` attribute on an ancestor can hide.
export function openAncestors(html: string, target: number): string[] {
  const stack: { name: string; raw: string }[] = [];
  for (const { raw, index } of tagsOf(html)) {
    if (index >= target) break;
    const name = (raw.match(/^<\/?\s*([a-zA-Z][a-zA-Z0-9]*)/)?.[1] ?? "").toLowerCase();
    if (raw.startsWith("</")) {
      const at = stack.map((t) => t.name).lastIndexOf(name);
      if (at !== -1) stack.length = at;
    } else if (!VOID_TAGS.has(name)) {
      // `/>` does not close a non-void HTML element (`<div/>` is an open div, and an
      // unquoted `action=/x/>` ends in one), so only the void list decides.
      stack.push({ name, raw });
    }
  }
  return stack.map((t) => t.raw);
}
