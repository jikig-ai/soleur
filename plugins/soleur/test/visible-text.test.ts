// Edge cases for plugins/soleur/test/lib/visible-text.ts, the scanner the
// docs drift guards read built pages through. Each row pins a failure the
// review of #9579 found or a property the guards depend on.

import { describe, test, expect } from "bun:test";
import { decodeEntities, plainText, sentencesOf, visibleText, withoutInert } from "./lib/visible-text";

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

  test("withoutInert drops comments, template and noscript bodies and keeps the rest", () => {
    const html = "<p>a</p><!-- <p>hidden</p> --><TEMPLATE><p>t</p></TEMPLATE><noscript><p>n</p></noscript><p>b</p>";
    expect(withoutInert(html)).toBe("<p>a</p><p>b</p>");
    expect(withoutInert("<p>x</p><!-- never closed")).toBe("<p>x</p>");
  });
});
