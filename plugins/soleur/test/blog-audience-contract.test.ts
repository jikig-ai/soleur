// #8774 — blog posts target the non-technical solo founder.
//
// Guard 1 pins the cross-file heading contract: content-writer resolves a blog
// post's register through the brand guide's `## Channel Notes > ### Blog` note,
// so that heading must exist exactly once, inside Channel Notes, and no routing
// line may send the blog back to the technical register. It pins headings and
// one routing phrase only — never the note's wording.
//
// Guard 2 pins blog-jargon-scan.sh: exit 1 with every hit iff a scanned line
// (frontmatter title/seoTitle/description incl. folded values, and the body
// outside JSON-LD blocks, link targets stripped) carries a backtick, a --flag,
// or a visible #NN; exit 0 otherwise; exit 2 on a usage error or an unreadable
// path. BLOG_SCAN_SCRIPT points the suite at a
// copy for mutation runs; the tracked script is never edited in place.
import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { resolve, join } from "path";
import { spawnSync } from "child_process";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "fs";
import { tmpdir } from "os";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const BRAND_GUIDE = resolve(REPO_ROOT, "knowledge-base/marketing/brand-guide.md");
const VISION = resolve(REPO_ROOT, "knowledge-base/overview/vision.md");
const CONTENT_WRITER = resolve(
  REPO_ROOT,
  "plugins/soleur/skills/content-writer/SKILL.md",
);
const SCAN_SCRIPT =
  process.env.BLOG_SCAN_SCRIPT ??
  resolve(REPO_ROOT, "plugins/soleur/skills/content-writer/scripts/blog-jargon-scan.sh");

// ---------------------------------------------------------------------------
// Guard 1 validators — pure functions over a string.
// ---------------------------------------------------------------------------

/** `## Channel Notes` up to the next level-2 heading or end of file; "" if absent. */
function channelNotesSlice(guide: string): string {
  const m = /^## Channel Notes$/m.exec(guide);
  if (!m) return "";
  const rest = guide.slice(m.index);
  const next = /^## (?!Channel Notes$)/m.exec(rest.slice(1));
  return next ? rest.slice(0, next.index + 1) : rest;
}

function blogHeadingProblems(guide: string): string[] {
  const problems: string[] = [];
  const total = guide.match(/^### Blog$/gm)?.length ?? 0;
  if (total !== 1) {
    problems.push(`brand-guide.md must contain exactly one "### Blog" heading (found ${total})`);
  }
  const slice = channelNotesSlice(guide);
  if (!slice.startsWith("## Channel Notes\n")) {
    problems.push('brand-guide.md has no "## Channel Notes" section');
  }
  const inside = slice.match(/^### Blog$/gm)?.length ?? 0;
  if (inside !== 1) {
    problems.push(
      `"### Blog" must sit inside "## Channel Notes" in brand-guide.md (found ${inside} there)`,
    );
  }
  return problems;
}

function routingPhraseLines(text: string): string[] {
  return text.split("\n").filter((l) => /technical blog/i.test(l));
}

function audienceBullets(skill: string): string[] {
  return skill.split("\n").filter((l) => l.startsWith("- `--audience"));
}

function audienceBulletProblems(skill: string): string[] {
  const bullets = audienceBullets(skill);
  if (bullets.length !== 1) {
    return [`content-writer SKILL.md must have exactly one "- \`--audience" bullet (found ${bullets.length})`];
  }
  const problems: string[] = [];
  if (!bullets[0].includes("## Channel Notes > ### Blog")) {
    problems.push('the content-writer --audience bullet must name "## Channel Notes > ### Blog"');
  }
  if (bullets[0].includes("blog → technical")) {
    problems.push('the content-writer --audience bullet still carries the unconditional "blog → technical" default');
  }
  return problems;
}

const GOOD_GUIDE = [
  "# Brand",
  "## Voice",
  "Some voice.",
  "## Channel Notes",
  "### Discord",
  "- d",
  "### Blog",
  "- b",
  "### Website / Landing Page",
  "- w",
  "",
].join("\n");

describe("Guard 1 — validators (synthesized fixtures)", () => {
  test("must-PASS: ### Blog between two other Channel Notes subsections", () => {
    expect(blogHeadingProblems(GOOD_GUIDE)).toEqual([]);
  });

  test("RED: renamed heading (### Blog Posts only)", () => {
    const g = GOOD_GUIDE.replace("### Blog\n", "### Blog Posts\n");
    expect(blogHeadingProblems(g).length).toBeGreaterThan(0);
  });

  test("RED: a second ### Blog heading", () => {
    const g = GOOD_GUIDE.replace("### Website", "### Blog\n- again\n### Website");
    expect(blogHeadingProblems(g).length).toBeGreaterThan(0);
  });

  test("RED: ### Blog outside Channel Notes (whole-file count still 1)", () => {
    const g = GOOD_GUIDE.replace("### Blog\n- b\n", "").replace(
      "## Voice\n",
      "## Voice\n### Blog\n- b\n",
    );
    expect(g.match(/^### Blog$/gm)?.length).toBe(1);
    expect(blogHeadingProblems(g).length).toBeGreaterThan(0);
  });

  test("RED: ### Blog under a later ## section, not Channel Notes", () => {
    const g = GOOD_GUIDE.replace("### Blog\n- b\n", "") + "## Archive\n### Blog\n- b\n";
    expect(g.match(/^### Blog$/gm)?.length).toBe(1);
    expect(blogHeadingProblems(g).length).toBeGreaterThan(0);
  });

  test("RED: ### Blog both in ## Voice and in ## Channel Notes", () => {
    const g = GOOD_GUIDE.replace("## Voice\n", "## Voice\n### Blog\n- v\n");
    expect(channelNotesSlice(g).match(/^### Blog$/gm)?.length).toBe(1);
    expect(blogHeadingProblems(g).length).toBeGreaterThan(0);
  });

  test("RED: no ## Channel Notes heading at all", () => {
    const g = GOOD_GUIDE.replace("## Channel Notes\n", "");
    expect(blogHeadingProblems(g).length).toBeGreaterThan(0);
  });

  test("routing phrase detector flags the old channel wording", () => {
    expect(routingPhraseLines("| HN, GitHub, Discord, technical blog posts |")).toHaveLength(1);
    expect(routingPhraseLines("| HN, GitHub, Discord, docs |")).toHaveLength(0);
  });

  test("audience bullet: zero or two matching lines is RED", () => {
    expect(audienceBulletProblems("no bullet here").length).toBeGreaterThan(0);
    const two =
      "- `--audience` uses ## Channel Notes > ### Blog\n- `--audience` uses ## Channel Notes > ### Blog";
    expect(audienceBulletProblems(two).length).toBeGreaterThan(0);
  });

  test("audience bullet: old default, or old + new text, is RED", () => {
    expect(
      audienceBulletProblems("- `--audience` (blog → technical, landing page → general)").length,
    ).toBeGreaterThan(0);
    expect(
      audienceBulletProblems(
        "- `--audience` ## Channel Notes > ### Blog, else (blog → technical)",
      ).length,
    ).toBeGreaterThan(0);
    expect(audienceBulletProblems("- `--audience` ## Channel Notes > ### Blog")).toEqual([]);
  });
});

describe("Guard 1 — real files", () => {
  test("brand-guide.md: exactly one ### Blog, inside ## Channel Notes (edit brand-guide.md > ## Channel Notes)", () => {
    const guide = readFileSync(BRAND_GUIDE, "utf8");
    const slice = channelNotesSlice(guide);
    expect(slice.startsWith("## Channel Notes\n")).toBe(true);
    expect(/^### Discord$/m.test(slice)).toBe(true);
    expect(blogHeadingProblems(guide)).toEqual([]);
  });

  test("brand-guide.md: the line above ### Blog names this test", () => {
    const lines = readFileSync(BRAND_GUIDE, "utf8").split("\n");
    const i = lines.indexOf("### Blog");
    expect(i).toBeGreaterThan(0);
    expect(lines[i - 1]).toContain("plugins/soleur/test/blog-audience-contract.test.ts");
  });

  test("brand-guide.md and vision.md: no 'technical blog' routing line", () => {
    expect(routingPhraseLines(readFileSync(BRAND_GUIDE, "utf8"))).toEqual([]);
    expect(routingPhraseLines(readFileSync(VISION, "utf8"))).toEqual([]);
  });

  test("content-writer SKILL.md: the --audience bullet resolves blogs through the Blog note", () => {
    expect(audienceBulletProblems(readFileSync(CONTENT_WRITER, "utf8"))).toEqual([]);
  });

  test("the Phase 2.4 trigger label is in the Blog note and gated on in content-writer SKILL.md", () => {
    const label = "**Jargon limits.**";
    const blog = channelNotesSlice(readFileSync(BRAND_GUIDE, "utf8")).split(/^### Blog$/m)[1] ?? "";
    const blogNote = blog.split(/^### /m)[0];
    expect(blogNote).toContain(label);
    expect(readFileSync(CONTENT_WRITER, "utf8")).toContain("contains the literal label `" + label + "`");
  });

  test("content-writer SKILL.md invokes the scan by path and never pastes the draft into a heredoc", () => {
    const skill = readFileSync(CONTENT_WRITER, "utf8");
    expect(skill).toContain('bash "${CLAUDE_PLUGIN_ROOT}/skills/content-writer/scripts/blog-jargon-scan.sh"');
    const phase = skill.split(/^## Phase 2\.4: /m)[1]?.split(/^## /m)[0] ?? "";
    expect(phase).toContain("with the **Write** tool");
    // Any heredoc, whatever its delimiter: a draft line equal to it ends the heredoc early.
    expect(phase).not.toContain("<<");
  });

  test("brand-guide.md register lines: the blog is General, not Technical", () => {
    const lines = readFileSync(BRAND_GUIDE, "utf8").split("\n");
    const tech = lines.filter((l) => l.startsWith("**Technical register**"));
    const general = lines.filter((l) => l.startsWith("**General register**"));
    expect(tech).toHaveLength(1);
    expect(general).toHaveLength(1);
    expect(tech[0]).not.toMatch(/\bblog\b/i);
    expect(general[0]).toMatch(/\bblog\b/i);
  });
});

// ---------------------------------------------------------------------------
// Guard 2 — blog-jargon-scan.sh
// ---------------------------------------------------------------------------

const RED_FIXTURE = [
  "---", //                                          1
  'title: "Fixing the --limit bug"', //              2  hit: --flag
  'seoTitle: "Why #77 matters"', //                  3  hit: #NN
  "description: >-", //                              4
  "  About #42 and more", //                         5  hit: folded value
  "---", //                                          6
  "", //                                             7
  "Run `next` to see it.", //                        8  hit: backtick
  "Plain prose line.", //                            9
  "Use --force now.", //                             10 hit: --flag
  "See the issue (#1423) for more.", //              11 hit: #NN after (
  "Try it (--dry-run) today.", //                    12 hit: --flag after (
  '<script type="application/ld+json">', //         13
  '{"a": "#99"}', //                                 14 skipped: JSON-LD
  "</script>", //                                    15
  "After the schema, run `ls`.", //                  16 hit: body after JSON-LD
  '<script type="application/ld+json">{"b": 1}</script>', // 17 one-line JSON-LD
  "Then use <code>go</code> here.", //               18 hit: <code> after a one-line block
  "And <pre>npx x</pre> too.", //                    19 hit: <pre>
  "",
].join("\n");

const PASS_FIXTURE = [
  "---",
  'title: "A plain title"',
  "description: >-",
  "  A plain folded description",
  'ref: "#123"',
  'ogImage: "og--x.png"',
  "---",
  "",
  "Prose with a dash -- like this &#8212; and an entity.",
  "Read [the fix](https://github.com/o/r/pull/8536) or [tips](#10-tips), or https://example.com/#12 bare.",
  "See [wiki](https://en.wikipedia.org/wiki/Foo_(bar)#12), v2#12, foo#42 and ##12.",
  "## A heading",
  "---",
  "",
  '<script type="application/ld+json">',
  '{"answer": "#123 and `code`"}',
  "</script>",
  "",
  "After the schema, plain words, a <codex> word and <b>bold</b>.",
  "",
].join("\n");

let dir = "";
const fixturePath = (name: string) => join(dir, name);

function scan(...args: string[]) {
  const r = spawnSync("bash", [SCAN_SCRIPT, ...args], { encoding: "utf8" });
  expect(r.error).toBeUndefined();
  return r;
}

function hitLines(stdout: string): number[] {
  return stdout
    .split("\n")
    .filter((l) => l.length > 0)
    .map((l) => Number(l.split(":")[0]));
}

beforeAll(() => {
  dir = mkdtempSync(join(tmpdir(), "blog-scan-"));
  writeFileSync(fixturePath("red.md"), RED_FIXTURE);
  writeFileSync(fixturePath("pass.md"), PASS_FIXTURE);
});

afterAll(() => {
  if (dir) rmSync(dir, { recursive: true, force: true });
});

describe("Guard 2 — blog-jargon-scan.sh", () => {
  test("instrument: the scan script exists", () => {
    expect(existsSync(SCAN_SCRIPT)).toBe(true);
  });

  test("RED fixture: exit 1 and exactly lines 2, 3, 5, 8, 10, 11, 12, 16, 18, 19", () => {
    const r = scan(fixturePath("red.md"));
    expect(r.status).toBe(1);
    expect(hitLines(r.stdout)).toEqual([2, 3, 5, 8, 10, 11, 12, 16, 18, 19]);
    expect(r.stdout.split("\n")).toContain("8: Run `next` to see it.");
  });

  test("must-PASS fixture: exit 0, nothing printed", () => {
    const r = scan(fixturePath("pass.md"));
    expect(r.stdout).toBe("");
    expect(r.status).toBe(0);
  });

  test("no argument: exit 2 with usage on stderr", () => {
    const r = scan();
    expect(r.status).toBe(2);
    expect(r.stderr).toMatch(/^usage: blog-jargon-scan\.sh/);
  });

  test("missing file: exit 2 with usage on stderr", () => {
    const r = scan(fixturePath("does-not-exist.md"));
    expect(r.status).toBe(2);
    expect(r.stderr).toMatch(/^usage: blog-jargon-scan\.sh/);
  });

  test("directory argument: exit 2 with usage on stderr", () => {
    const r = scan(dir);
    expect(r.status).toBe(2);
    expect(r.stderr).toMatch(/^usage: blog-jargon-scan\.sh/);
  });
});
