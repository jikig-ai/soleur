// Edge cases for plugins/soleur/test/lib/visible-text.ts, the scanner the
// docs drift guards read built pages through. Each row pins a failure the
// review of #9579 found or a property the guards depend on.

import { describe, test, expect } from "bun:test";
import { decodeEntities, openAncestors, plainText, sentencesOf, tagsOf, visibleText, withoutInert } from "./lib/visible-text";

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

  // One row per block-level family: a boundary missing from any of them lets a
  // plan sentence in one item borrow a self-host marker from its neighbour.
  test.each([
    ["li", "<ul><li>Pay with your Claude Pro plan</li><li>Self-hosted is free</li></ul>"],
    ["td", "<table><tr><td>Pay with your Claude Pro plan</td><td>Self-hosted is free</td></tr></table>"],
    ["th", "<table><tr><th>Pay with your Claude Pro plan</th><th>Self-hosted is free</th></tr></table>"],
    ["dt/dd", "<dl><dt>Pay with your Claude Pro plan</dt><dd>Self-hosted is free</dd></dl>"],
    ["summary", "<details><summary>Pay with your Claude Pro plan</summary><p>Self-hosted is free</p></details>"],
    ["br", "<p>Pay with your Claude Pro plan<br>Self-hosted is free</p>"],
    ["figcaption", "<figure><figcaption>Pay with your Claude Pro plan</figcaption><p>Self-hosted is free</p></figure>"],
  ])("a %s boundary separates neighbouring sentences", (_name, html) => {
    expect(sentencesOf(visibleText(html))).toEqual(["Pay with your Claude Pro plan", "Self-hosted is free"]);
  });

  test("inline tags are not boundaries", () => {
    expect(sentencesOf(visibleText("<p>Hosted uses your <cite>Claude plan</cite>.</p>"))).toEqual([
      "Hosted uses your Claude plan.",
    ]);
    expect(sentencesOf(visibleText("<p>Hosted <button>uses</button> your <label>Claude plan</label>.</p>"))).toEqual([
      "Hosted uses your Claude plan.",
    ]);
  });

  test("every named entity decodes to its character", () => {
    const table: Record<string, string> = {
      amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", rsquo: "\u2019", lsquo: "\u2018", ldquo: "\u201c",
      rdquo: "\u201d", mdash: "\u2014", ndash: "\u2013", hellip: "\u2026", rarr: "\u2192", ensp: " ", emsp: " ",
      thinsp: " ",
    };
    for (const [name, ch] of Object.entries(table)) {
      expect(decodeEntities(`a&${name};b`).replace(/\s/g, " "), `&${name};`).toBe(`a${ch}b`.replace(/\s/g, " "));
    }
    expect(decodeEntities("a&nbsp;b").replace(/\s/g, " ")).toBe("a b");
  });

  test("characters a browser renders as nothing do not split a word", () => {
    const soft = String.fromCharCode(0xad);
    const zw = String.fromCharCode(0x200b);
    expect(plainText(`<p>pri&shy;vate pri&#173;vate pri${soft}vate pri${zw}vate pri&zwj;vate pri&zwnj;vate</p>`)).toBe(
      "private private private private private private",
    );
  });

  test("space-class entities become spaces so a phrase still matches", () => {
    expect(plainText("<p>Claude&ensp;plan Claude&thinsp;plan Claude&emsp;plan</p>")).toBe(
      "Claude plan Claude plan Claude plan",
    );
  });

  test("the sentence split does not cut at e.g., i.e., vs. or etc.", () => {
    expect(sentencesOf("Self-hosted uses a plan, e.g. hosted ones too. Next one.")).toEqual([
      "Self-hosted uses a plan, e.g. hosted ones too.",
      "Next one.",
    ]);
    expect(sentencesOf("A vs. B differ. Done.")).toEqual(["A vs. B differ.", "Done."]);
    expect(sentencesOf("Pro, i.e. paid. Free.")).toEqual(["Pro, i.e. paid.", "Free."]);
  });

  test("tagsOf honours quoted > and skips comments and script bodies", () => {
    const html = '<a title="a>b" href="/x">t</a><!-- <b> --><script>if (a < b) {}</script><img alt="x">';
    expect(tagsOf(html).map((t) => t.raw)).toEqual(['<a title="a>b" href="/x">', "</a>", "<script>", "</script>", '<img alt="x">']);
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
