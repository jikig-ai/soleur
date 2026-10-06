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
} from "../lib/fanout-validate.js";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const TYPES_TS = resolve(REPO_ROOT, "apps/web-platform/lib/types.ts");
const STYLE_CSS = resolve(REPO_ROOT, "plugins/soleur/docs/css/style.css");

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

// The section of the homepage this feature owns: the one <section> holding the figure.
function fanoutSection(html: string): string {
  const m = html.match(/<section class="landing-section fanout-section"[\s\S]*?<\/section>/);
  if (!m) throw new Error("fanout section not found in the built homepage");
  return m[0];
}

function figureOf(section: string): string {
  const m = section.match(/<figure class="fanout-figure"[\s\S]*?<\/figure>/);
  if (!m) throw new Error("fanout figure not found in the fanout section");
  return m[0];
}

function rowsOf(section: string): string[] {
  return [...section.matchAll(/<li class="fanout-row"[\s\S]*?<\/li>/g)].map((m) => m[0]);
}

// Attribute values that carry text a reader, a screen reader or a summariser can see.
function attributeText(html: string): string[] {
  const out: string[] = [];
  for (const { raw } of tagsOf(html)) {
    for (const m of raw.matchAll(/\b(?:alt|aria-label|aria-description|title)\s*=\s*(?:"([^"]*)"|'([^']*)')/gi)) {
      out.push(decodeEntities(m[1] ?? m[2] ?? ""));
    }
  }
  return out;
}

function collapse(s: string): string {
  return s.replace(/\s+/g, " ").trim();
}

// Case-insensitive, word-bounded; CLI is the one case-sensitive term.
const FORBIDDEN: { term: string; re: RegExp }[] = [
  ...[
    "hosted", "web app", "dashboard", "install", "terminal", "plugin", "Claude", "Anthropic",
    "your check", "your checks", "your standard", "your bar", "your definition of done",
    "acceptance check", "acceptance criteria", "you define", "checks you set", "margin check",
    "automatically", "verified",
  ].map((term) => ({ term, re: new RegExp(`\\b${term.replace(/ /g, "\\s+")}\\b`, "i") })),
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
  const row = (department: string, status: string, label: string, line = "Sample line.") => ({
    department,
    status,
    label,
    line,
  });
  const good = () => [
    row("legal", "completed", "Done"),
    row("marketing", "completed", "Done"),
    row("finance", "waiting_for_user", "Waiting on you"),
    row("engineering", "failed", "Stopped"),
  ];

  test("accepts a compliant set, including labels that differ from the product's", () => {
    expect(() => validateFanout(good(), DEPTS, LOCAL_STATUS_LABELS)).not.toThrow();
  });

  test("accepts a different fictional set with the same keys", () => {
    const other = [
      row("marketing", "completed", "Done", "A different sample line."),
      row("legal", "failed", "Stopped", "Another."),
      row("engineering", "waiting_for_user", "Waiting on you", "More."),
      row("finance", "completed", "Done", "Last."),
    ];
    expect(() => validateFanout(other, DEPTS, LOCAL_STATUS_LABELS)).not.toThrow();
  });

  test("rejects a status key outside the closed constant, naming the row and key", () => {
    const rows = good();
    rows[2] = row("finance", "bogus_status", "Waiting on you");
    expect(() => validateFanout(rows, DEPTS, LOCAL_STATUS_LABELS)).toThrow(/row 3.*status.*bogus_status/s);
  });

  test("rejects a label that does not match its key", () => {
    const rows = good();
    rows[3] = row("engineering", "failed", "Done");
    expect(() => validateFanout(rows, DEPTS, LOCAL_STATUS_LABELS)).toThrow(/row 4.*label.*failed/s);
  });

  test("rejects five rows and three rows", () => {
    expect(() =>
      validateFanout([...good(), row("legal", "completed", "Done")], DEPTS, LOCAL_STATUS_LABELS),
    ).toThrow(/exactly four rows.*5/s);
    expect(() => validateFanout(good().slice(0, 3), DEPTS, LOCAL_STATUS_LABELS)).toThrow(/exactly four rows.*3/s);
  });

  test("rejects a department key agents.js does not have", () => {
    const rows = good();
    rows[1] = row("astrology", "completed", "Done");
    expect(() => validateFanout(rows, DEPTS, LOCAL_STATUS_LABELS)).toThrow(/row 2.*department.*astrology/s);
  });

  test("rejects a missing field and a blank line", () => {
    const rows: any[] = good();
    rows[0] = { department: "legal", status: "completed", label: "Done" };
    expect(() => validateFanout(rows, DEPTS, LOCAL_STATUS_LABELS)).toThrow(/row 1.*line/s);
    const blank = good();
    blank[0].line = "   ";
    expect(() => validateFanout(blank, DEPTS, LOCAL_STATUS_LABELS)).toThrow(/row 1.*line/s);
  });

  test("rejects the same department twice", () => {
    const rows = good();
    rows[1] = row("legal", "completed", "Done");
    expect(() => validateFanout(rows, DEPTS, LOCAL_STATUS_LABELS)).toThrow(/row 2.*legal.*twice|duplicate/is);
  });
});

// -- vocabulary: keys in the data file exist in the product ------------------

describe("status vocabulary parity with apps/web-platform/lib/types.ts", () => {
  const types = readFileSync(TYPES_TS, "utf8");

  test("the parser finds at least four STATUS_LABELS keys", () => {
    expect(statusLabelKeys(types).length).toBeGreaterThanOrEqual(4);
  });

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
    expect(text).toContain("One brief reaches the departments it concerns. You keep the final say.");
    expect(text).toContain("Founder brief");
    expect(text).toContain(
      "Fernlight is adding shared reminders. Launch it to current customers as a paid add-on.",
    );
    expect(text).toContain("See every department below");
    const figure = figureOf(section);
    expect(collapse(plainText(figure))).toContain("Illustrative example · sample data");
    const cap = figure.match(/<figcaption[\s\S]*?<\/figcaption>/)?.[0] ?? "";
    expect(collapse(plainText(cap))).toContain(
      "Illustrative example with sample data. Not a live run or a customer result. Soleur pauses for your approval; it does not guarantee any check will pass.",
    );
  });

  test("the figure's accessible name starts with 'Illustrative example'", () => {
    const figureTag = figureOf(fanoutSection(HOME)).match(/^<figure[^>]*>/)![0];
    const label = figureTag.match(/aria-label="([^"]*)"/)?.[1] ?? "";
    expect(decodeEntities(label).startsWith("Illustrative example")).toBe(true);
  });

  test("rows read 'Department: Status. Line.' to a screen reader (hidden colon, aria-hidden glyph and connector)", () => {
    const section = fanoutSection(HOME);
    expect(section).toContain('<ul class="fanout-rows" role="list">');
    for (const r of rowsOf(section)) {
      expect(r).toMatch(/<span class="fanout-colon sr-only">:<\/span>/);
      expect(r).toMatch(/<span class="fanout-glyph" aria-hidden="true">/);
    }
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

  const css = readFileSync(STYLE_CSS, "utf8");

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

describe("built homepage: copy guardrails", () => {
  test("instrument: the forbidden list is populated and non-hits pass", () => {
    expect(FORBIDDEN.length).toBeGreaterThanOrEqual(20);
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
    expect(section.toLowerCase()).not.toContain("plausible");
    expect(section).not.toContain("application/ld+json");
    expect(section).not.toMatch(/\{\{|\{%/);
    // visibleText of the section is the surface the guards read; confirm it is non-empty.
    expect(visibleText(section).length).toBeGreaterThan(300);
  });
});
