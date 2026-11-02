import { describe, test, expect } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { PLUGIN_ROOT } from "./helpers";

// purpose-template.test.ts -- WikiSkill Phase 2 (#10550), CTO ruling T7.
//
// PROPERTY: the PURPOSE.md template is the SINGLE source for the provenance file's headings and fixed
// attribution text, so the server renderer (compound-promote-create, Phase 3) fills a closed set of
// slots and keeps no second copy of the headings.
//
// ASSEMBLY: one chokepoint, `skills/skill-creator/templates/purpose.md`. Members that must flow through
// it: the six fixed headings, the closed slot set, the fixed CC BY 4.0 attribution text (CLO,
// 2026-10-26; never model text). The SKILL.md side ("links ./PURPOSE.md exactly once") is asserted
// in the Phase 3 render tests, not here: this file asserts the PURPOSE.md side carries no link of
// its own, so the single link in SKILL.md is the only one.
//
// ANCHOR: the template lives in the plugin tree and is reviewed with the skill; the attribution
// literal below is pinned here independently of the template, so editing one without the other is a
// red test and a visible two-file diff.

const TEMPLATE_REL = "skills/skill-creator/templates/purpose.md";
const TEMPLATE_PATH = resolve(PLUGIN_ROOT, TEMPLATE_REL);

/** The closed slot set. The renderer may fill exactly these and nothing else. */
export const PURPOSE_TEMPLATE_SLOTS = [
  "SKILL_NAME",
  "ORIGIN",
  "PATTERNS_ADDRESSED",
  "NEAREST_SKILL",
  "PATCH_REJECTION_REASON",
  "MERGE_RETIRE_CANDIDATES",
  "EVOLUTION_HISTORY",
] as const;

/** The six fixed headings, in order. */
export const PURPOSE_TEMPLATE_HEADINGS = [
  "Origin",
  "Patterns addressed",
  "Nearest existing skill and why not patched",
  "Merge and retire candidates",
  "Evolution history",
  "Attribution",
] as const;

/** Fixed server text, verbatim from the CLO review of 2026-10-26. Never model text. */
export const PURPOSE_ATTRIBUTION =
  "Provenance and attribution: the prompt and structure text behind this skill's creation is adapted from the paper WikiSkill (Google Research), arXiv:2608.27454, licensed under CC BY 4.0 (<https://creativecommons.org/licenses/by/4.0/>). The authors are credited on the source page at <https://arxiv.org/abs/2608.27454>. Changes made: the text was adapted to this repository's learnings corpus and rendered by an automated proposer; no endorsement by the authors or Google Research is implied.";

function readTemplate(): string {
  // A missing template must FAIL these tests, never skip them.
  expect(existsSync(TEMPLATE_PATH), `${TEMPLATE_REL} must exist`).toBe(true);
  return readFileSync(TEMPLATE_PATH, "utf8");
}

/** Remove fenced code blocks so a heading or slot quoted inside an example is not counted. */
function stripFences(text: string): string {
  return text.replace(/^```[\s\S]*?^```[^\n]*\n?/gm, "");
}

describe("PURPOSE.md template", () => {
  test("exists, is non-empty and ends with a newline", () => {
    const t = readTemplate();
    expect(t.trim().length).toBeGreaterThan(0);
    expect(t.endsWith("\n")).toBe(true);
  });

  test("carries exactly the six fixed ## headings, in order", () => {
    const body = stripFences(readTemplate());
    const headings = body
      .split("\n")
      .filter((l) => l.startsWith("## "))
      .map((l) => l.slice(3).trim());
    expect(headings).toEqual([...PURPOSE_TEMPLATE_HEADINGS]);
  });

  test("has one H1 that carries the name slot, before any ## heading", () => {
    const body = stripFences(readTemplate());
    const lines = body.split("\n");
    const h1 = lines.filter((l) => /^# /.test(l));
    expect(h1).toHaveLength(1);
    expect(h1[0]).toContain("{{SKILL_NAME}}");
    expect(lines.indexOf(h1[0])).toBeLessThan(lines.findIndex((l) => l.startsWith("## ")));
  });

  test("uses exactly the closed slot set -- no unknown slot, no missing slot, no half-open braces", () => {
    const body = readTemplate();
    const found = [...body.matchAll(/\{\{([^{}]*)\}\}/g)].map((m) => m[1]);
    expect(new Set(found)).toEqual(new Set(PURPOSE_TEMPLATE_SLOTS));
    // A brace pair the slot regex does not capture (nested, unterminated) is a defect, not a slot.
    const leftovers = body.replace(/\{\{[A-Z_]+\}\}/g, "");
    expect(leftovers).not.toMatch(/\{\{|\}\}/);
  });

  test("every slot sits on its own line under its own heading (one slot per body line, no inline slots)", () => {
    const body = readTemplate();
    for (const slot of PURPOSE_TEMPLATE_SLOTS) {
      if (slot === "SKILL_NAME") continue;
      const own = body.split("\n").filter((l) => l.trim() === `{{${slot}}}`);
      expect(own, `slot ${slot} must occupy a whole line`).toHaveLength(1);
    }
  });

  test("the fixed attribution text is present verbatim and is NOT a slot", () => {
    const body = readTemplate();
    expect(body).toContain(PURPOSE_ATTRIBUTION);
    expect(body).not.toMatch(/\{\{ATTRIBUTION\}\}/);
    // The three facts the CLO required, asserted independently of the literal above.
    expect(body).toContain("arXiv:2608.27454");
    expect(body).toContain("CC BY 4.0");
    expect(body).toContain("no endorsement by the authors or Google Research is implied");
  });

  test("the attribution sits under the Attribution heading, which is the last section", () => {
    const body = readTemplate();
    const idx = body.indexOf("## Attribution");
    expect(idx).toBeGreaterThan(-1);
    const tail = body.slice(idx);
    expect(tail).toContain(PURPOSE_ATTRIBUTION);
    expect(body.indexOf(PURPOSE_ATTRIBUTION)).toBeGreaterThan(idx);
  });

  test("carries no markdown link, backtick, fence, [id:] token or rule-id token (Phase 3 compatible; lint-safe)", () => {
    const body = readTemplate();
    expect(body).not.toMatch(/\]\(/); // no inline link: the only PURPOSE link lives in SKILL.md, once
    expect(body).not.toContain("`");
    expect(body).not.toContain("[id:");
    expect(body).not.toMatch(/\b(hr|wg|cq|rf|pdr|cm)-[a-z]/);
    expect(body).not.toMatch(/\b(scripts|references|assets)\//);
    expect(body).not.toContain("soleur:");
    expect(body).not.toMatch(/(^|\s)\/[a-z][a-z-]+(\s|$)/m); // no leading /command form (invocation-axis census)
    expect(body).not.toContain("skills/");
  });

  test("contains no frontmatter (PURPOSE.md is not a component and must not be parsed as one)", () => {
    expect(readTemplate().startsWith("---")).toBe(false);
  });

  test("harness: the slot check can fail -- a template with an extra slot is detected", () => {
    const mutated = readTemplate().replace("{{EVOLUTION_HISTORY}}", "{{EVOLUTION_HISTORY}}\n\n{{EXTRA_SLOT}}");
    expect(mutated).not.toBe(readTemplate());
    const found = new Set([...mutated.matchAll(/\{\{([^{}]*)\}\}/g)].map((m) => m[1]));
    expect(found).not.toEqual(new Set(PURPOSE_TEMPLATE_SLOTS));
  });
});
