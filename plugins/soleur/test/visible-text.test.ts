// Edge cases for plugins/soleur/test/lib/visible-text.ts, the scanner the
// docs drift guards read built pages through. Each row pins a failure the
// review of #9579 found or a property the guards depend on.

import { describe, test, expect } from "bun:test";
import { decodeEntities, openAncestors, plainText, sentencesOf, stripInvisible, tagsOf, visibleText, withoutInert } from "./lib/visible-text";

describe("visible-text scanner", () => {
  test("a heading without a final period does not merge with the next block", () => {
    expect(sentencesOf(visibleText("<h2>Hosted</h2><p>Your Claude plan pays.</p>"))).toEqual([
      "Hosted",
      "Your Claude plan pays.",
    ]);
  });

  test("hard-wrapped source lines stay one sentence", () => {
    expect(sentencesOf(visibleText("<p>Hosted runs on your Claude\nplan today.</p>"))).toEqual([
      "Hosted runs on your Claude plan today.",
    ]);
  });

  test("a stray < in text does not swallow the page", () => {
    const got = sentencesOf(visibleText("<p>Use x < 5 and don't</p><p>Hosted is private.</p>"));
    expect(got).toEqual(["Use x < 5 and don't", "Hosted is private."]);
  });

  test("an unbalanced quote inside a tag does not swallow the page", () => {
    const got = sentencesOf(visibleText(`<p class="a>First.</p><p>Hosted is private.</p>`));
    expect(got.at(-1)).toBe("Hosted is private.");
  });

  test("a > inside a quoted attribute does not end the tag", () => {
    expect(plainText(`<a title="a>b" href="/x">link text</a>`)).toBe("link text");
  });

  test("script, style and comment bodies are skipped, uppercase tags are tags", () => {
    const html =
      "<P>Keep.</P><SCRIPT>var hosted = 'private';</SCRIPT><style>.x{}</style><!-- hosted private --><p>Also keep.</p>";
    expect(sentencesOf(visibleText(html))).toEqual(["Keep.", "Also keep."]);
  });

  test("entities decode once and never throw", () => {
    expect(decodeEntities("a&mdash;b&rsquo;s &#65; &#x42; &amp;lt;i&amp;gt;")).toBe("a—b’s A B &lt;i&gt;");
    expect(decodeEntities("&#99999999999; &#xFFFFFFFF; &unknownentity;")).toBe(
      "&#99999999999; &#xFFFFFFFF; &unknownentity;",
    );
  });

  test("positive control: a hosted sentence in a later block is still reachable", () => {
    const html = "<section><p>One.</p></section><section><p>Hosted runs on your Claude plan.</p></section>";
    expect(sentencesOf(visibleText(html)).some((s) => /Hosted runs on your Claude plan/.test(s))).toBe(true);
  });

  // One row per block-level tag, with BARE text on both sides (a neighbouring <p> is
  // itself a boundary and would hide a missing member). The list is written here,
  // not read from the scanner, so deleting a member from the scanner fails a row.
  const BLOCK = [
    "address", "article", "aside", "blockquote", "dd", "details", "div", "dl", "dt",
    "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6",
    "header", "li", "main", "nav", "ol", "p", "section", "summary", "table", "td",
    "th", "tr", "ul",
  ];
  test.each(BLOCK)("a <%s> boundary separates bare neighbouring text", (tag) => {
    expect(sentencesOf(visibleText(`Pay with your Claude Pro plan<${tag}>Self-hosted is free</${tag}>Next thing`))).toEqual([
      "Pay with your Claude Pro plan",
      "Self-hosted is free",
      "Next thing",
    ]);
  });

  test.each(["br", "hr"])("a void <%s> separates bare neighbouring text", (tag) => {
    expect(sentencesOf(visibleText(`Pay with your Claude Pro plan<${tag}>Self-hosted is free`))).toEqual([
      "Pay with your Claude Pro plan",
      "Self-hosted is free",
    ]);
  });

  test("inline tags are not boundaries", () => {
    expect(sentencesOf(visibleText("<p>Hosted uses your <cite>Claude plan</cite>.</p>"))).toEqual([
      "Hosted uses your Claude plan.",
    ]);
    expect(sentencesOf(visibleText("<p>Hosted <button>uses</button> your <label>Claude plan</label>.</p>"))).toEqual([
      "Hosted uses your Claude plan.",
    ]);
    for (const tag of ["a", "abbr", "b", "code", "em", "i", "mark", "small", "span", "strong", "sub", "sup", "time", "u"]) {
      expect(sentencesOf(visibleText(`Hosted <${tag}>uses</${tag}> your Claude plan`)), `<${tag}> is inline`).toEqual([
        "Hosted uses your Claude plan",
      ]);
    }
  });

  test("every named entity (visible and invisible) decodes to its character", () => {
    const table: Record<string, string> = {
      amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", rsquo: "\u2019", lsquo: "\u2018", ldquo: "\u201c",
      rdquo: "\u201d", mdash: "\u2014", ndash: "\u2013", hellip: "\u2026", rarr: "\u2192", ensp: " ", emsp: " ",
      thinsp: " ", hairsp: " ", numsp: " ", puncsp: " ", NonBreakingSpace: " ", shy: "", zwj: "", zwnj: "", ZeroWidthSpace: "",
    };
    for (const [name, ch] of Object.entries(table)) {
      expect(decodeEntities(`a&${name};b`).replace(/\s/g, " "), `&${name};`).toBe(`a${ch}b`.replace(/\s/g, " "));
    }
    expect(decodeEntities("a&nbsp;b").replace(/\s/g, " ")).toBe("a b");
  });

  // Every character in the strip set, spelled as a literal and as a numeric reference.
  // Built from char codes so no invisible character sits in this test's source.
  test.each([0xad, 0x200b, 0x200c, 0x200d, 0x200e, 0x200f, 0x2060, 0xfeff, 0x34f, 0x180e])(
    "U+%i does not split a word, as a literal, as a reference and in a sentence-only arm",
    (code) => {
      const ch = String.fromCharCode(code);
      expect(plainText(`<p>pri${ch}vate</p>`), "literal in markup").toBe("private");
      expect(plainText(`<p>pri&#${code};vate</p>`), "numeric reference in markup").toBe("private");
      expect(sentencesOf(`pri${ch}vate data`), "JSON-LD / llms.txt arm (sentencesOf only)").toEqual(["private data"]);
      expect(stripInvisible(`a${ch}b`)).toBe("ab");
    },
  );

  test("space-class entities become spaces so a phrase still matches", () => {
    expect(plainText("<p>Claude&ensp;plan Claude&thinsp;plan Claude&emsp;plan</p>")).toBe(
      "Claude plan Claude plan Claude plan",
    );
  });

  test("the sentence split keeps e.g., i.e. and vs. inside a sentence and cuts before a capital", () => {
    expect(sentencesOf("Self-hosted uses a plan, e.g. hosted ones too. Next one.")).toEqual([
      "Self-hosted uses a plan, e.g. hosted ones too.",
      "Next one.",
    ]);
    expect(sentencesOf("A vs. B differ. Done.")).toEqual(["A vs. B differ.", "Done."]);
    expect(sentencesOf("Pro, i.e. paid. Free.")).toEqual(["Pro, i.e. paid.", "Free."]);
    expect(sentencesOf("E.g. hosted ones. Free.")).toEqual(["E.g. hosted ones.", "Free."]);
  });

  test("a period before a lower-case word does not end the sentence; before a capital it does", () => {
    expect(sentencesOf("As Inc. reported, hosted is private. Done.")).toEqual(["As Inc. reported, hosted is private.", "Done."]);
    expect(sentencesOf("Plans, API, etc. Self-hosted is free.")).toEqual(["Plans, API, etc.", "Self-hosted is free."]);
    expect(sentencesOf("Hosted costs $49 per month, etc. Coming soon.")).toEqual(["Hosted costs $49 per month, etc.", "Coming soon."]);
  });

  test("tagsOf honours quoted > and skips comments and script bodies", () => {
    const html = '<a title="a>b" href="/x">t</a><!-- <b> --><script>if (a < b) {}</script><img alt="x">';
    expect(tagsOf(html).map((t) => t.raw)).toEqual(['<a title="a>b" href="/x">', "</a>", "<script>", "</script>", '<img alt="x">']);
  });

  test.each(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"])(
    "a void <%s> is never listed as an open ancestor",
    (tag) => {
      const html = `<section><${tag}><span id="t"></span></section>`;
      expect(openAncestors(html, html.indexOf('<span id="t">'))).toEqual(["<section>"]);
    },
  );

  test("`/>` does not close a non-void element, so an unquoted value ending in a slash cannot hide a hidden form", () => {
    const f = '<form hidden action=/x/><span id="t"></span></form>';
    expect(openAncestors(f, f.indexOf('<span id="t">'))).toEqual(["<form hidden action=/x/>"]);
    const d = '<div hidden/><span id="t"></span></div>';
    expect(openAncestors(d, d.indexOf('<span id="t">'))).toEqual(["<div hidden/>"]);
  });

  test("a closing tag with no opener is ignored; a closing tag pops everything opened inside it", () => {
    const stray = '<section></aside><span id="t"></span></section>';
    expect(openAncestors(stray, stray.indexOf('<span id="t">'))).toEqual(["<section>"]);
    const nested = '<section><div><p></section><span id="t"></span>';
    expect(openAncestors(nested, nested.indexOf('<span id="t">'))).toEqual([]);
  });

  test("openAncestors lists the still-open tags, outermost first, ignoring void and closed ones", () => {
    const html = '<section class="a"><form hidden><p>x</p><br><div style="display:none"><span id="t">y</span></div></form></section>';
    const at = html.indexOf('<span id="t">');
    expect(openAncestors(html, at)).toEqual(['<section class="a">', "<form hidden>", '<div style="display:none">']);
    expect(openAncestors(html, html.indexOf("<p>"))).toEqual(['<section class="a">', "<form hidden>"]);
  });

  test("withoutInert drops comments, template and noscript bodies and keeps the rest", () => {
    const html = "<p>a</p><!-- <p>hidden</p> --><TEMPLATE><p>t</p></TEMPLATE><noscript><p>n</p></noscript><p>b</p>";
    expect(withoutInert(html)).toBe("<p>a</p><p>b</p>");
    expect(withoutInert("<p>x</p><!-- never closed")).toBe("<p>x</p>");
  });
});
