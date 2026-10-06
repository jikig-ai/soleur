// Visible text of a built HTML document, without a tag-strip regex.
//
// The docs drift guards read built pages, so they need the text a visitor sees
// and the sentence boundaries a visitor perceives. A single-pass `/<[^>]+>/g`
// replace is the js/incomplete-multi-character-sanitization pattern CodeQL
// flags in this repo, so tags are removed by a character scan instead.
//
// Boundaries: every block-level tag emits BOUNDARY, so a heading without a
// final period never merges with the paragraph below it. Source newlines are
// ordinary whitespace (hard-wrapped prose is one sentence), never a boundary.
//
// Not a general HTML parser: it is exercised against this site's own Eleventy
// output, and plugins/soleur/test/visible-text.test.ts pins the edge cases.

export const BOUNDARY = "\u0001";

const BLOCK_TAGS = new Set([
  "address", "article", "aside", "blockquote", "br", "button", "cite", "dd",
  "details", "div", "dl", "dt", "figcaption", "figure", "footer", "form",
  "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "label", "li", "main",
  "nav", "ol", "p", "section", "summary", "table", "td", "th", "tr", "ul",
]);

const ENTITIES: Record<string, string> = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ",
  rsquo: "’", lsquo: "‘", ldquo: "“", rdquo: "”", mdash: "—",
  ndash: "–", hellip: "…", rarr: "→",
};

// One pass: `&amp;lt;` becomes the literal text `&lt;`, never `<`.
export function decodeEntities(s: string): string {
  return s.replace(
    /&(?:#(\d+)|#[xX]([0-9a-fA-F]+)|([a-zA-Z]+));/g,
    (whole, dec?: string, hex?: string, name?: string) => {
      if (name !== undefined) return ENTITIES[name] ?? whole;
      const code = dec !== undefined ? parseInt(dec, 10) : parseInt(hex as string, 16);
      return Number.isInteger(code) && code >= 0 && code <= 0x10ffff
        ? String.fromCodePoint(code)
        : whole;
    },
  );
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

export function sentencesOf(text: string): string[] {
  return text
    .split(new RegExp(`${BOUNDARY}+|(?<=[.!?])\\s+`))
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
