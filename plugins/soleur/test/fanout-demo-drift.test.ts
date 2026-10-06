// Drift guard for the homepage "one brief reaches the departments" section (#9577).
//
// Guard 1 (data, vocabulary, render, anchor): the built homepage renders exactly the
// four rows plugins/soleur/docs/_data/fanoutDemo.js declares; every status key exists
// in the product's STATUS_LABELS (parsed as TEXT from apps/web-platform/lib/types.ts, so
// the docs build never imports apps/); every department key exists in agents.js; and
// the link resolves to exactly one id="departments".
// Guard 2 (copy): the section carries both caption lines and none of the forbidden
// claims on any text-bearing surface. The forbidden list lives HERE; lifting a term
// needs a CPO-signed edit citing #9578, #9620 and the deferral #9661.
//
// Build pattern: mirrors seo-aeo-drift-guard.test.ts (temp output dir, offline loaders).

import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { resolve, join } from "path";
import { readFileSync, mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import {
  decodeEntities,
  plainText,
  tagsOf,
  visibleText,
} from "./lib/visible-text";
import * as fanoutModule from "../docs/_data/fanoutDemo.js";
import {
  STATUS_LABELS as LOCAL_STATUS_LABELS,
  validateFanout,
  validateFrame,
} from "../docs/scripts/fanout-validate.mjs";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const TYPES_TS = resolve(REPO_ROOT, "apps/web-platform/lib/types.ts");
const STYLE_CSS = resolve(REPO_ROOT, "plugins/soleur/docs/css/style.css");
const FANOUT_DATA_JS = resolve(REPO_ROOT, "plugins/soleur/docs/_data/fanoutDemo.js");

let tmpSite: string;
let HOME: string;

beforeAll(() => {
  tmpSite = mkdtempSync(join(tmpdir(), "fanout-demo-drift-"));
  const proc = Bun.spawnSync(["npx", "@11ty/eleventy", `--output=${tmpSite}`], {
    cwd: REPO_ROOT,
    stdout: "inherit",
    stderr: "inherit",
    env: { ...process.env, SOLEUR_DOCS_OFFLINE: "1" },
  });
  if (proc.exitCode !== 0) {
    throw new Error(
      `Eleventy build failed in test setup (exit ${proc.exitCode}). Run 'npx @11ty/eleventy' from the repo root to reproduce.`,
    );
  }
  HOME = readFileSync(join(tmpSite, "index.html"), "utf8");
}, 90_000);

afterAll(() => {
  if (tmpSite) rmSync(tmpSite, { recursive: true, force: true });
});

// -- helpers ---------------------------------------------------------------

// The product's status vocabulary, read as text. Throws on fewer than four keys so a
// stale regex (or a refactor of STATUS_LABELS) reads RED instead of vacuously green.
export function statusLabelKeys(typesText: string): string[] {
  const block = typesText.match(/export const STATUS_LABELS\b[^=]*=\s*\{([\s\S]*?)\}/);
  const keys = block
    ? [...block[1].matchAll(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:/gm)].map((m) => m[1])
    : [];
  if (keys.length < 4) {
    throw new Error(
      `Expected at least four keys in STATUS_LABELS from apps/web-platform/lib/types.ts, found ${keys.length}. ` +
        "The product status vocabulary moved or was renamed; update this guard's parser and the fanout demo's local status constant together.",
    );
  }
  return keys;
}

// The section of the homepage this feature owns: the <section> holding the figure, found by
// section-depth so a nested <section> cannot hide the rest of it from every guard.
function fanoutSection(html: string): string {
  const start = html.indexOf('<section class="landing-section fanout-section"');
  if (start === -1) throw new Error("fanout section not found in the built homepage");
  const re = /<(\/?)section\b[^>]*>/g;
  re.lastIndex = start;
  let depth = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html))) {
    depth += m[1] ? -1 : 1;
    if (depth === 0) return html.slice(start, m.index + m[0].length);
  }
  throw new Error("fanout section is not terminated in the built homepage");
}

function figureOf(section: string): string {
  const m = section.match(/<figure class="fanout-figure"[\s\S]*?<\/figure>/);
  if (!m) throw new Error("fanout figure not found in the fanout section");
  return m[0];
}

function rowsOf(section: string): string[] {
  return [...section.matchAll(/<li class="fanout-row"[\s\S]*?<\/li>/g)].map((m) => m[0]);
}

// Every attribute value except class: data-*, aria-*, alt, title and href can all carry text
// a reader, a screen reader, a scraper or a summariser sees, so none is exempt by name.
function attributeText(html: string): string[] {
  const out: string[] = [];
  for (const { raw } of tagsOf(html)) {
    for (const m of raw.matchAll(/\b([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)')/g)) {
      if (m[1].toLowerCase() === "class") continue;
      out.push(decodeEntities(m[2] ?? m[3] ?? ""));
    }
  }
  return out;
}

function stripCssComments(css: string): string {
  return css.replace(/\/\*[\s\S]*?\*\//g, "");
}

function collapse(s: string): string {
  return s.replace(/\s+/g, " ").trim();
}

// Case-insensitive, word-bounded, with common inflections (installs, plugins, terminals);
// CLI is the one case-sensitive term. "installation" is deliberately not a hit.
const FORBIDDEN_TERMS = [
  "hosted", "web app", "dashboard", "install", "terminal", "plugin", "Claude", "Anthropic",
  "your check", "your checks", "your standard", "your bar", "your definition of done",
  "acceptance check", "acceptance criteria", "you define", "checks you set", "margin check",
  "automatically", "verified", "verify", "verifies", "verification",
];
const FORBIDDEN: { term: string; re: RegExp }[] = [
  ...FORBIDDEN_TERMS.map((term) => ({
    term,
    re: new RegExp(`\\b${term.replace(/ /g, "\\s+")}(?:s|es|ed|ing)?\\b`, "i"),
  })),
  { term: "CLI", re: /\bCLI\b/ },
];

function forbiddenHits(text: string): string[] {
  return FORBIDDEN.filter(({ re }) => re.test(text)).map(({ term }) => term);
}

// Brace-depth scan: returns each block that starts with `header`, plus its depth.
function blocksOf(css: string, header: string): { body: string; depth: number }[] {
  const out: { body: string; depth: number }[] = [];
  let depth = 0;
  for (let i = 0; i < css.length; i++) {
    if (css.startsWith(header, i)) {
      const open = css.indexOf("{", i);
      let d = 1;
      let j = open + 1;
      while (j < css.length && d > 0) {
        if (css[j] === "{") d++;
        else if (css[j] === "}") d--;
        j++;
      }
      out.push({ body: css.slice(open + 1, j - 1), depth });
    }
    if (css[i] === "{") depth++;
    else if (css[i] === "}") depth--;
  }
  return out;
}

// -- the validator (in-memory, synthesized fixtures) ------------------------

describe("validateFanout (the one chokepoint the build and this suite share)", () => {
  const DEPTS = ["legal", "marketing", "finance", "engineering"];
  const row = (department: string, status: string, line = "Sample line.") => ({ department, status, line });
  const good = () => [
    row("legal", "completed"),
    row("marketing", "completed"),
    row("finance", "waiting_for_user"),
    row("engineering", "failed"),
  ];

  test("accepts a compliant set", () => {
    expect(() => validateFanout(good(), DEPTS, LOCAL_STATUS_LABELS)).not.toThrow();
  });

  test("accepts a different fictional set with the same keys", () => {
    const other = [
      row("marketing", "completed", "A different sample line."),
      row("legal", "failed", "Another."),
      row("engineering", "waiting_for_user", "More."),
      row("finance", "completed", "Last."),
    ];
    expect(() => validateFanout(other, DEPTS, LOCAL_STATUS_LABELS)).not.toThrow();
  });

  test("rejects a status key outside the closed constant, naming the row and key", () => {
    const rows = good();
    rows[2] = row("finance", "bogus_status");
    expect(() => validateFanout(rows, DEPTS, LOCAL_STATUS_LABELS)).toThrow(/row 3.*status.*bogus_status/s);
  });

  test("the status map is a real parameter: a key only a custom map has is accepted, and defaults to the local constant", () => {
    const rows = good();
    rows[0] = row("legal", "custom_only");
    expect(() => validateFanout(rows, DEPTS, LOCAL_STATUS_LABELS)).toThrow(/custom_only/);
    expect(() => validateFanout(rows, DEPTS, { ...LOCAL_STATUS_LABELS, custom_only: "Custom" })).not.toThrow();
    expect(() => validateFanout(good(), DEPTS)).not.toThrow();
    expect(() => validateFanout(rows, DEPTS)).toThrow(/custom_only/);
  });

  test("rejects five rows and three rows", () => {
    expect(() => validateFanout([...good(), row("legal", "completed")], DEPTS, LOCAL_STATUS_LABELS)).toThrow(
      /exactly four rows.*5/s,
    );
    expect(() => validateFanout(good().slice(0, 3), DEPTS, LOCAL_STATUS_LABELS)).toThrow(/exactly four rows.*3/s);
  });

  test("rejects a department key agents.js does not have", () => {
    const rows = good();
    rows[1] = row("astrology", "completed");
    expect(() => validateFanout(rows, DEPTS, LOCAL_STATUS_LABELS)).toThrow(/row 2.*department.*astrology/s);
  });

  test("rejects a missing field and a blank line", () => {
    const rows: any[] = good();
    rows[0] = { department: "legal", status: "completed" };
    expect(() => validateFanout(rows, DEPTS, LOCAL_STATUS_LABELS)).toThrow(/row 1.*line/s);
    const blank = good();
    blank[0].line = "   ";
    expect(() => validateFanout(blank, DEPTS, LOCAL_STATUS_LABELS)).toThrow(/row 1.*line/s);
  });

  test("rejects the same department twice", () => {
    const rows = good();
    rows[1] = row("legal", "completed");
    expect(() => validateFanout(rows, DEPTS, LOCAL_STATUS_LABELS)).toThrow(/row 2.*legal.*twice/s);
  });
});

describe("validateFrame (the disclosure text must fail the build when it goes missing)", () => {
  const frame = (): any => ({ ...(fanoutModule.default as () => any)() });

  test("accepts the shipped frame", () => {
    expect(() => validateFrame(frame())).not.toThrow();
  });

  test("rejects an emptied or renamed caption, a third caption line, and a blank heading", () => {
    const empty = frame();
    empty.captionLines = [];
    expect(() => validateFrame(empty)).toThrow(/captionLines/);
    const renamed = frame();
    delete renamed.captionLines;
    renamed.captions = ["a", "b"];
    expect(() => validateFrame(renamed)).toThrow(/captionLines/);
    const third = frame();
    third.captionLines = [...third.captionLines, "Soleur guarantees every launch is compliant."];
    expect(() => validateFrame(third)).toThrow(/captionLines/);
    const blank = frame();
    blank.heading = "  ";
    expect(() => validateFrame(blank)).toThrow(/heading/);
  });

  test("rejects a figure name or first caption that drops 'Illustrative example'", () => {
    const fig = frame();
    fig.figureName = "One founder brief and four departments";
    expect(() => validateFrame(fig)).toThrow(/figureName/);
    const cap = frame();
    cap.captionLines = ["Sample data.", cap.captionLines[1]];
    expect(() => validateFrame(cap)).toThrow(/caption/);
  });
});

// -- vocabulary: keys in the data file exist in the product ------------------

describe("status vocabulary parity with apps/web-platform/lib/types.ts", () => {
  const types = readFileSync(TYPES_TS, "utf8");

  test("the parser reads RED on a text with no STATUS_LABELS (its own dispatch)", () => {
    expect(() => statusLabelKeys("export const OTHER = { a: 1 } as const;")).toThrow(/STATUS_LABELS/);
  });

  test("the local closed constant and every key the data file uses are product keys", () => {
    const product = statusLabelKeys(types);
    for (const key of Object.keys(LOCAL_STATUS_LABELS)) expect(product).toContain(key);
    const data = (fanoutModule.default as () => any)();
    for (const r of data.rows) expect(product).toContain(r.status);
  });
});

// -- the data file ----------------------------------------------------------

describe("_data/fanoutDemo.js", () => {
  test("is default-export-only (a second named export makes Eleventy skip the function)", () => {
    expect(Object.keys(fanoutModule)).toEqual(["default"]);
    expect(typeof fanoutModule.default).toBe("function");
  });

  test("the default function calls both validators (the build-time throw is wired, not just exported)", () => {
    const src = readFileSync(FANOUT_DATA_JS, "utf8")
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/^\s*\/\/.*$/gm, "");
    expect(src).toMatch(/validateFanout\(\s*ROWS\b/);
    expect(src).toMatch(/validateFrame\(\s*frame\s*\)/);
    expect(src.indexOf("validateFrame(")).toBeLessThan(src.indexOf("return {"));
  });

  test("declares the four approved rows in order, with display names from agents.js", () => {
    const data = (fanoutModule.default as () => any)();
    expect(data.rows.map((r: any) => [r.department, r.name, r.status, r.label])).toEqual([
      ["legal", "Legal", "completed", "Done"],
      ["marketing", "Marketing", "completed", "Done"],
      ["finance", "Finance", "waiting_for_user", "Waiting on you"],
      ["engineering", "Engineering", "failed", "Stopped"],
    ]);
  });
});

// -- the built page ----------------------------------------------------------

describe("built homepage: the section", () => {
  test("instrument: the section is found exactly once and carries four rows and real text", () => {
    expect(HOME.match(/class="fanout-figure"/g)?.length).toBe(1);
    const section = fanoutSection(HOME);
    expect(rowsOf(section).length).toBe(4);
    expect(plainText(section).length).toBeGreaterThan(300);
  });

  test("instrument: the section extractor is depth-aware (a nested <section> does not end it early)", () => {
    const fixture =
      '<section class="landing-section fanout-section"><section>inner</section>TAIL</section><p>after</p>';
    expect(fanoutSection(fixture)).toContain("TAIL");
    expect(fanoutSection(fixture)).not.toContain("after");
  });

  test("sits after the positioning section and before the quote block", () => {
    const at = (needle: string) => HOME.indexOf(needle);
    expect(at("This Is the Way")).toBeGreaterThan(-1);
    expect(at('class="landing-section fanout-section"')).toBeGreaterThan(at("This Is the Way"));
    expect(at('class="landing-quote"')).toBeGreaterThan(at('class="landing-section fanout-section"'));
  });

  test("renders exactly the data file's rows, in order, with the approved copy", () => {
    const data = (fanoutModule.default as () => any)();
    const rows = rowsOf(fanoutSection(HOME));
    expect(rows.length).toBe(data.rows.length);
    rows.forEach((html, i) => {
      const text = collapse(plainText(html));
      expect(text).toContain(data.rows[i].name);
      expect(text).toContain(data.rows[i].label);
      expect(text).toContain(data.rows[i].line);
    });
    rows.forEach((html, i) => {
      expect(html.match(/<li class="fanout-row"[^>]*>/)![0]).toContain(`data-status="${data.rows[i].status}"`);
    });
    const finance = collapse(plainText(rows[2]));
    expect(finance).toContain(
      "Needs your answer: set the add-on price from the sample cost figures, or hold it until costs are clearer?",
    );
    const engineering = collapse(plainText(rows[3]));
    expect(engineering).toContain("Reminders change held back. A test did not pass. You decide what happens next.");
  });

  test("label, tag, heading, brief card, link and both caption lines carry the approved wording", () => {
    const section = fanoutSection(HOME);
    const text = collapse(plainText(section));
    expect(text.toLowerCase()).toContain("how a brief reaches the departments");
    expect(text).toContain("Example: one brief reaches the departments it concerns, and you keep the final say.");
    expect(text).toContain("Founder brief");
    expect(text).toContain(
      "A small software company is adding shared reminders to its app. Launch it to current customers as a paid add-on.",
    );
    expect(text).toContain("See every department below");
    const figure = figureOf(section);
    expect(collapse(plainText(figure))).toContain("Illustrative example · sample data");
    const cap = figure.match(/<figcaption[\s\S]*?<\/figcaption>/)?.[0] ?? "";
    const paragraphs = [...cap.matchAll(/<p\b[^>]*>([\s\S]*?)<\/p>/g)].map((m) => collapse(plainText(m[1])));
    expect(paragraphs).toEqual([
      "Illustrative example with sample data. Not a live run, a product screenshot or a customer result.",
      "Agent output is a draft for you to review and approve. Soleur does not guarantee that any test or review will catch every problem.",
    ]);
    expect(collapse(plainText(cap))).toBe(paragraphs.join(" "));
  });

  test("the figure's accessible name starts with 'Illustrative example'", () => {
    const figureTag = figureOf(fanoutSection(HOME)).match(/^<figure[^>]*>/)![0];
    const label = figureTag.match(/aria-label="([^"]*)"/)?.[1] ?? "";
    expect(decodeEntities(label).startsWith("Illustrative example")).toBe(true);
  });

  test("rows read 'Department: Status. Line.' to a screen reader (department, hidden colon, glyph hidden, then label and line)", () => {
    const section = fanoutSection(HOME);
    const data = (fanoutModule.default as () => any)();
    expect(section).toContain('<ul class="fanout-rows" role="list">');
    rowsOf(section).forEach((r, i) => {
      expect(r).toMatch(/<span class="fanout-colon sr-only">:<\/span>/);
      expect(r).toMatch(/<span class="fanout-glyph" aria-hidden="true">/);
      const at = (needle: string) => r.indexOf(needle);
      expect(at(data.rows[i].name)).toBeGreaterThan(-1);
      expect(at("fanout-colon")).toBeGreaterThan(at(data.rows[i].name));
      expect(at(data.rows[i].label)).toBeGreaterThan(at("fanout-colon"));
      expect(at(data.rows[i].line)).toBeGreaterThan(at(data.rows[i].label));
    });
    expect(section).not.toMatch(/<figure[^>]*role="list"/);
  });
});

describe("built homepage: anchor, scroll margin, reduced motion", () => {
  test("exactly one id=\"departments\", on the Your AI Organization section, and the link resolves to it", () => {
    expect(HOME.match(/\bid="departments"/g)?.length).toBe(1);
    const owner = HOME.match(/<section[^>]*\bid="departments"[^>]*>([\s\S]*?)<\/section>/);
    expect(owner).not.toBeNull();
    expect(owner![1]).toContain("Your AI Organization");
    const link = fanoutSection(HOME).match(/<a [^>]*href="#departments"[^>]*>/);
    expect(link).not.toBeNull();
  });

  const css = stripCssComments(readFileSync(STYLE_CSS, "utf8"));

  test("style.css gives #departments the fixed-header scroll margin", () => {
    expect(css).toMatch(
      /#departments\s*\{[^}]*scroll-margin-top:\s*calc\(var\(--header-h\)\s*\+\s*var\(--space-4\)\)/,
    );
  });

  test("scroll-behavior: auto sits inside a top-level, unlayered reduced-motion block", () => {
    const blocks = blocksOf(css, "@media (prefers-reduced-motion: reduce)");
    const top = blocks.filter((b) => b.depth === 0);
    expect(top.length).toBeGreaterThan(0);
    expect(top.some((b) => /html\s*\{[^}]*scroll-behavior:\s*auto/.test(b.body))).toBe(true);
  });
});

describe("style.css: the status hooks and generated text", () => {
  const css = stripCssComments(readFileSync(STYLE_CSS, "utf8"));

  test("every status key the validator allows has a glyph rule keyed on data-status", () => {
    for (const key of Object.keys(LOCAL_STATUS_LABELS)) {
      expect(css).toMatch(new RegExp(`\\.fanout-row\\[data-status="${key}"\\]\\s+\\.fanout-glyph::before`));
    }
  });

  test("instrument: comment stripping removes a commented-out rule", () => {
    expect(stripCssComments('/* #departments { scroll-margin-top: 1px } */ a{}')).not.toContain("scroll-margin-top");
  });

  test("generated content in .fanout-* rules carries no forbidden claim", () => {
    const rules = [...css.matchAll(/([^{}]*fanout[^{}]*)\{([^{}]*)\}/g)];
    const contents = rules.flatMap((r) => [...r[2].matchAll(/content:\s*"([^"]*)"/g)].map((m) => m[1]));
    expect(contents.length).toBeGreaterThanOrEqual(4);
    for (const c of contents) expect(forbiddenHits(c)).toEqual([]);
  });
});

describe("built homepage: copy guardrails", () => {
  test("instrument: the forbidden list is populated and non-hits pass", () => {
    expect(FORBIDDEN.length).toBe(FORBIDDEN_TERMS.length + 1);
    expect(FORBIDDEN_TERMS.length).toBe(23);
    for (const term of FORBIDDEN_TERMS) expect(forbiddenHits(`a ${term} b`)).toContain(term);
    expect(forbiddenHits("Installs plugins in your terminals, dashboards, verifies it")).toEqual(
      expect.arrayContaining(["install", "plugin", "terminal", "dashboard", "verifies"]),
    );
    expect(forbiddenHits("click Client ghosted installation")).toEqual([]);
    expect(forbiddenHits("your check will run in the Terminal, hosted by Claude")).toEqual(
      expect.arrayContaining(["your check", "terminal", "hosted", "Claude"]),
    );
    expect(forbiddenHits("the cli")).toEqual([]);
    expect(forbiddenHits("the CLI")).toEqual(["CLI"]);
  });

  test("no forbidden claim on any text-bearing surface (visible text, attributes, data file strings)", () => {
    const section = fanoutSection(HOME);
    const data = JSON.stringify((fanoutModule.default as () => unknown)());
    const surfaces = [plainText(section), ...attributeText(section), data];
    for (const s of surfaces) expect(forbiddenHits(s)).toEqual([]);
  });

  test("'guarantee' appears only in the caption disclosure", () => {
    const section = fanoutSection(HOME);
    const total = (collapse(plainText(section)) + " " + attributeText(section).join(" ")).match(/guarantee/gi)?.length ?? 0;
    const cap = figureOf(section).match(/<figcaption[\s\S]*?<\/figcaption>/)?.[0] ?? "";
    expect(total).toBeGreaterThan(0);
    expect(total).toBe(collapse(plainText(cap)).match(/guarantee/gi)?.length ?? 0);
  });

  test("no numerals in the section's text or attribute values", () => {
    const section = fanoutSection(HOME);
    const text = [plainText(section), ...attributeText(section)].join(" ");
    expect(text).not.toMatch(/\d/);
  });

  test("no button, form, script, plausible markup or JSON-LD inside the section", () => {
    const section = fanoutSection(HOME);
    expect(section).not.toMatch(/<(button|form|script|input|select|textarea)\b/i);
    expect(section).not.toMatch(/<(img|picture|svg|iframe|video|audio|object|embed|canvas)\b/i);
    expect(section).not.toMatch(/\son[a-z]+\s*=/i);
    expect(section).not.toMatch(/\b(?:tabindex\s*=|role\s*=\s*["']button)/i);
    const hrefs = [...section.matchAll(/<a\b[^>]*\bhref\s*=\s*"([^"]*)"/gi)].map((m) => m[1]);
    expect(hrefs).toEqual(["#departments"]);
    expect(section.toLowerCase()).not.toContain("plausible");
    expect(section).not.toContain("application/ld+json");
    expect(section).not.toMatch(/\{\{|\{%/);
    // visibleText of the section is the surface the guards read; confirm it is non-empty.
    expect(visibleText(section).length).toBeGreaterThan(300);
  });
});
