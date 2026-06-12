// Unit tests for the markdown -> Slack mrkdwn converter.
// Run with: node --test scripts/md-to-mrkdwn.test.mjs
//
// Slack "mrkdwn" is NOT GitHub-flavored Markdown. The converter rewrites the
// GFM subset that appears in changelogs into mrkdwn (single-asterisk bold,
// underscore italic, single-tilde strike, <url|label> links, no headings/
// tables/images) AND keeps untrusted input injection-inert (every author-typed
// <!channel>/<@U..>/<url|label> escaped so it can never fire a mass-ping or
// mint a disguised link). See the GFM->mrkdwn mapping table in
// plugins/soleur/skills/ship/references/ci-workflow-authoring.md.
import { test } from "node:test";
import assert from "node:assert/strict";
import { toSlackMrkdwn, truncateMrkdwn, parseMaxArg } from "./md-to-mrkdwn.mjs";

// --- Mapping-table rows -----------------------------------------------------

test("bold ** and __ -> single asterisk", () => {
  assert.equal(toSlackMrkdwn("a **bold** b"), "a *bold* b");
  assert.equal(toSlackMrkdwn("a __bold__ b"), "a *bold* b");
});

test("italic * and _ -> single underscore", () => {
  assert.equal(toSlackMrkdwn("a *it* b"), "a _it_ b");
  assert.equal(toSlackMrkdwn("a _it_ b"), "a _it_ b");
});

test("strikethrough ~~ -> single tilde", () => {
  assert.equal(toSlackMrkdwn("a ~~gone~~ b"), "a ~gone~ b");
});

test("bold-italic ***x*** -> *_x_* (no literal asterisks leak)", () => {
  assert.equal(toSlackMrkdwn("***hi***"), "*_hi_*");
  assert.equal(toSlackMrkdwn("a ***wow*** b"), "a *_wow_* b");
  // plain bold and the nested case still convert correctly
  assert.equal(toSlackMrkdwn("**bold**"), "*bold*");
  assert.equal(toSlackMrkdwn("**_x_**"), "*_x_*");
});

test("inline link [text](url) -> <url|text>", () => {
  assert.equal(toSlackMrkdwn("see [docs](https://x.io)"), "see <https://x.io|docs>");
});

test("reference link resolved and definition line consumed", () => {
  const out = toSlackMrkdwn("see [docs][d] now\n\n[d]: https://x.io");
  assert.equal(out.includes("<https://x.io|docs>"), true);
  // the orphan definition line is consumed, not emitted literally
  assert.equal(out.includes("[d]:"), false);
});

test("autolink <https://x> -> bare unwrapped url", () => {
  assert.equal(toSlackMrkdwn("at <https://x.io> end"), "at https://x.io end");
});

test("bare url in prose left unwrapped", () => {
  assert.equal(toSlackMrkdwn("go https://x.io/a?b=1 now"), "go https://x.io/a?b=1 now");
});

test("image ![alt](url) -> <url|alt> (degrade to link)", () => {
  assert.equal(toSlackMrkdwn("![logo](https://x.io/l.png)"), "<https://x.io/l.png|logo>");
});

test("ATX headings -> bold line", () => {
  assert.equal(toSlackMrkdwn("# Title"), "*Title*");
  assert.equal(toSlackMrkdwn("###### Small"), "*Small*");
});

test("setext H1 (=== underline) -> bold line", () => {
  assert.equal(toSlackMrkdwn("Title\n==="), "*Title*");
});

test("setext H2 (--- underline) -> bold line", () => {
  assert.equal(toSlackMrkdwn("Heading\n---\nbody"), "*Heading*\nbody");
});

test("--- after a bullet list stays a thematic break (bullet not bolded)", () => {
  // guard: a `---` separator following a list item must NOT be read as a
  // setext-H2 underline that bolds the bullet
  assert.equal(toSlackMrkdwn("- Fixed Y\n---\n- Added Z"), "• Fixed Y\n\n• Added Z");
});

test("bullets -*+ -> Slack bullet", () => {
  assert.equal(toSlackMrkdwn("- one\n* two\n+ three"), "• one\n• two\n• three");
});

test("ordered list preserved", () => {
  assert.equal(toSlackMrkdwn("1. first\n2. second"), "1. first\n2. second");
});

test("task list -> bullet + checkbox glyph", () => {
  assert.equal(toSlackMrkdwn("- [ ] todo"), "• ☐ todo");
  assert.equal(toSlackMrkdwn("- [x] done"), "• ☑ done");
  assert.equal(toSlackMrkdwn("- [X] done"), "• ☑ done");
});

test("blockquote preserved", () => {
  assert.equal(toSlackMrkdwn("> quoted"), "> quoted");
});

test("thematic break -> blank line", () => {
  assert.equal(toSlackMrkdwn("a\n\n---\n\nb"), "a\n\n\n\nb");
});

test("GFM pipe table -> wrapped in code fence (monospace degrade)", () => {
  const out = toSlackMrkdwn("| A | B |\n| - | - |\n| 1 | 2 |");
  assert.equal(out.startsWith("```"), true);
  assert.equal(out.trimEnd().endsWith("```"), true);
  assert.equal(out.includes("| A | B |"), true);
});

// --- Code regions: escape-only, NEVER convert, NEVER verbatim (P1-B) --------

test("fenced code: GFM markers inside are NOT converted (literal)", () => {
  const out = toSlackMrkdwn("```js\nconst x = '**not bold**';\nconst y = [a](b);\n```");
  assert.equal(out.includes("**not bold**"), true, "** must stay literal inside a fence");
  assert.equal(out.includes("[a](b)"), true, "link syntax must stay literal inside a fence");
  // info string stripped, fence normalized to ```
  assert.equal(out.startsWith("```"), true);
});

test("fenced code: <!channel> inside a fence is ESCAPED, not verbatim (P1-B)", () => {
  const out = toSlackMrkdwn("```\nping <!channel> here\n```");
  assert.equal(out.includes("&lt;!channel&gt;"), true);
  assert.equal(out.includes("<!channel>"), false, "Slack renders mentions inside backticks — must escape");
});

test("inline code: markers inside NOT converted", () => {
  assert.equal(toSlackMrkdwn("call `**x**` here"), "call `**x**` here");
});

test("inline code: <@U123> inside is escaped, never a live mention", () => {
  const out = toSlackMrkdwn("id `<@U123>` x");
  assert.equal(out.includes("`&lt;@U123&gt;`"), true);
  assert.equal(out.includes("<@U123>"), false);
});

test("unclosed fence runs to EOF as code and is escaped", () => {
  const out = toSlackMrkdwn("```\nraw <!here>\nmore");
  assert.equal(out.includes("&lt;!here&gt;"), true);
  assert.equal(out.includes("<!here>"), false);
});

// --- Injection safety: raw mentions/links typed in prose stay inert --------

test("raw <!channel> in prose -> escaped inert", () => {
  const out = toSlackMrkdwn("ping <!channel> now");
  assert.equal(out.includes("&lt;!channel&gt;"), true);
  assert.equal(out.includes("<!channel>"), false);
});

test("raw disguised link <https://evil|Bank> in prose -> escaped inert", () => {
  const out = toSlackMrkdwn("click <https://evil.test|Bank> here");
  // the | makes it not a valid autolink -> whole thing escaped, never <url|label>
  assert.equal(out.includes("&lt;https://evil.test|Bank&gt;"), true);
  assert.equal(/<https?:[^|>]*\|/.test(out), false, "must not mint a disguised link from raw input");
});

test("nested emphasis **_x_** -> *_x_*", () => {
  assert.equal(toSlackMrkdwn("**_x_**"), "*_x_*");
});

test("mention inside emphasis stays escaped (P1-C)", () => {
  assert.equal(toSlackMrkdwn("**<!channel>**"), "*&lt;!channel&gt;*");
  assert.equal(toSlackMrkdwn("_<@U1>_"), "_&lt;@U1&gt;_");
});

// --- Minted-link smuggling (P1-A) -------------------------------------------

test("smuggled mention in link label is escaped", () => {
  const out = toSlackMrkdwn("[<!channel>](https://x.io)");
  assert.equal(out, "<https://x.io|&lt;!channel&gt;>");
  assert.equal(out.includes("<!channel"), false);
});

test("pipe in link url is neutralized (does not re-open grammar)", () => {
  const out = toSlackMrkdwn("[Click](https://x.io|<!channel>)");
  assert.equal(out.includes("<!channel>"), false, "no live mention");
  // exactly one raw | (the <url|label> delimiter), url-side | encoded
  assert.equal((out.match(/\|/g) || []).length, 1);
});

test("pipe in link label is stripped (single delimiter pipe only)", () => {
  const out = toSlackMrkdwn("[a|b](https://x.io)");
  assert.equal((out.match(/\|/g) || []).length, 1);
  assert.equal(out.startsWith("<https://x.io|"), true);
});

test("> in link url is escaped", () => {
  const out = toSlackMrkdwn("[a](https://x.io>y)");
  assert.equal(out.includes("&gt;"), true);
  assert.equal(out, "<https://x.io&gt;y|a>");
});

test("degenerate links do not emit broken <|> grammar", () => {
  // empty label, valid url -> bare url
  assert.equal(toSlackMrkdwn("[](https://x.io)"), "https://x.io");
  // empty url -> degrade to escaped literal, no <|x>
  const out = toSlackMrkdwn("[x]()");
  assert.equal(out.includes("<|"), false);
  assert.equal(out.includes("<>"), false);
});

test("non-http(s)/mailto link scheme is NOT minted (no javascript: links)", () => {
  const out = toSlackMrkdwn("[x](javascript:alert(1))");
  assert.equal(out.includes("<javascript:"), false);
});

test("malformed / unbalanced links never leak unescaped <>|", () => {
  for (const input of ["[a[b](c)](d)", "[text](https://x.io with > inside", "[a)(b]"]) {
    const out = toSlackMrkdwn(input);
    assert.equal(/<(!|@|#|subteam\^)/.test(out), false, `no smuggled mention from: ${input}`);
  }
});

// --- Empty / whitespace bodies ----------------------------------------------

test("empty and whitespace-only bodies", () => {
  assert.equal(toSlackMrkdwn(""), "");
  // whitespace-only stays harmless (no throw, no injected sequences)
  assert.equal(/<(!|@|#|subteam\^)/.test(toSlackMrkdwn("   \n\t\n")), false);
});

// --- Keystone fail-closed output invariant (P1-C) ---------------------------

// The mention-prefix alphabet (! @ # subteam^) in the regex below is mirrored
// in plugins/soleur/test/reusable-release-idempotency.test.sh (T7 keystone
// glob) and ci-workflow-authoring.md's mapping table — keep all three in sync.
// The converter escapes EVERY `<` in text nodes, so this is a detection
// backstop, not the primary defense.
test("KEYSTONE: adversarial corpus -> output never contains <! <@ <# <subteam^", () => {
  const corpus = [
    "<!channel> <!here> <!everyone>",
    "<@U12345> and <@W99999>",
    "<#C0000|general>",
    "<!subteam^S123|team>",
    "<!here> <!everyone>",
    "***<!channel>***",
    "[<!channel>](https://x.io)",
    "[Click](https://x.io|<!channel>)",
    "**<!everyone>** and _<@U1>_",
    "```\n<!channel>\n```",
    "`<@U1>`",
    "<https://evil.test|Bank>",
    "> quote with <!channel>",
    "- bullet <@U1>",
    "# heading <!here>",
    "| <!channel> | <@U1> |\n| - | - |",
    "![<!channel>](https://x.io)",
  ];
  for (const input of corpus) {
    const out = toSlackMrkdwn(input);
    assert.equal(
      /<(!|@|#|subteam\^)/.test(out),
      false,
      `smuggled mention survived conversion of: ${JSON.stringify(input)} -> ${JSON.stringify(out)}`,
    );
  }
});

test("KEYSTONE: minted < coexists with escaped author < on the same line", () => {
  // a genuine link (minted `<url|`) AND a raw author-typed mention on one line:
  // every '<' in the output must be a minted link delimiter (followed by a URL
  // scheme), and the author mention must be escaped to &lt; — never a live one
  const out = toSlackMrkdwn("see [docs](https://x.io) and ping <!channel> now");
  assert.equal(out.includes("&lt;!channel&gt;"), true, "author mention must be escaped");
  assert.equal(out.includes("<https://x.io|docs>"), true, "genuine link must be minted");
  let mintedCount = 0;
  for (let i = 0; i < out.length; i++) {
    if (out[i] === "<") {
      assert.equal(/^<(https?:|mailto:)/.test(out.slice(i)), true, `stray < at ${i}: ${out}`);
      mintedCount += 1;
    }
  }
  assert.equal(mintedCount, 1, "exactly one minted link delimiter, no escaped-into-oblivion vacuity");
});

test("ReDoS guard: adversarial unterminated-[ input converts in well under 1s", () => {
  // The converter runs on untrusted changelog input; a long run of `[` used to
  // tail-scan to EOF at every position (O(n^2)). The MAX_INPUT cap + bounded
  // link char-classes must keep this fast. (performance-oracle P1.)
  const start = process.hrtime.bigint();
  const out = toSlackMrkdwn("[".repeat(65536) + "x".repeat(65536));
  const elapsedMs = Number(process.hrtime.bigint() - start) / 1e6;
  assert.equal(elapsedMs < 500, true, `conversion took ${elapsedMs.toFixed(1)}ms (expected < 500ms)`);
  assert.equal(/<(!|@|#|subteam\^)/.test(out), false);
});

// --- Structure-aware truncation ---------------------------------------------

test("truncateMrkdwn: short text returned unchanged", () => {
  assert.equal(truncateMrkdwn("hello", 100), "hello");
});

test("truncateMrkdwn: never leaves a half-open <url| link (space-free label)", () => {
  // A single-token (space-free) long link forces the word-boundary cut to land
  // mid-link, so the mid-link guard MUST fire. Split assertions so neither can
  // pass vacuously. (security-sentinel P2 / test-design P1.)
  const text = "intro <https://x.io/" + "a".repeat(60) + "|lbl>";
  const out = truncateMrkdwn(text, 30);
  assert.equal(/<https?:[^>]*$/.test(out), false, "no half-open <url| at the tail");
  assert.equal(out.endsWith("…"), true);
});

test("truncateMrkdwn: half-open guard fires when a closed link is re-cut at a label space", () => {
  // The link IS closed in the wider slice, but a multi-word label means the
  // word-boundary cut can re-open it between `|` and `>`. The post-boundary
  // re-trim must drop the whole link.
  const text = "intro text here <https://x.io|alpha beta> tail-no-spaces-xxxxxxxxxxxx";
  const out = truncateMrkdwn(text, 42);
  assert.equal(/<https?:[^>]*$/.test(out), false, "no dangling <url|partial-label");
  assert.equal(out.length <= 42, true, `result ${out.length} must not exceed max`);
});

test("truncateMrkdwn: result never exceeds max (suffix budget reserved)", () => {
  const text = "```\n" + "x".repeat(5000);
  const out = truncateMrkdwn(text, 3000);
  assert.equal(out.length <= 3000, true, `result ${out.length} must not exceed max`);
});

test("parseMaxArg: space form, equals form, absent, and malformed", () => {
  assert.equal(parseMaxArg(["node", "s.mjs", "--max", "3000"]), 3000);
  assert.equal(parseMaxArg(["node", "s.mjs", "--max=3000"]), 3000);
  assert.equal(parseMaxArg(["node", "s.mjs"]), 0);
  // Number() parses scientific notation correctly (the whole point of the fix:
  // parseInt("1e9") === 1 would silently destroy the body; Number("1e9") === 1e9)
  assert.equal(parseMaxArg(["node", "s.mjs", "--max", "1e9"]), 1e9);
  // genuinely malformed values must throw, never silently coerce
  assert.throws(() => parseMaxArg(["node", "s.mjs", "--max", "-5"]), RangeError);
  assert.throws(() => parseMaxArg(["node", "s.mjs", "--max", "abc"]), RangeError);
  assert.throws(() => parseMaxArg(["node", "s.mjs", "--max", "3.5"]), RangeError);
  assert.throws(() => parseMaxArg(["node", "s.mjs", "--max=0"]), RangeError);
});

test("truncateMrkdwn: closes an unbalanced code fence", () => {
  const text = "```\n" + "x".repeat(50) + "\nmore code here";
  const out = truncateMrkdwn(text, 20);
  const fences = (out.match(/```/g) || []).length;
  assert.equal(fences % 2, 0, "fence count must be balanced after truncation");
});
