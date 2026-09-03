import { describe, expect, test } from "bun:test";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

/**
 * ADR-083 bounds the `model: fable` upgrade pin to a named gate set. That bound was
 * prose, and prose bounds move silently — PR #7796 first proposed a third gate and,
 * in the same diff, deleted the one numeric anchor ("2-gate") that another file
 * carried. This test makes the bound mechanical, mirroring
 * `workflow-model-pins.test.ts`'s `expect(total).toBe(12)` for the workflow surface
 * that ADR-083 explicitly says does NOT cover SKILL.md prose.
 *
 * Adding a gate is now a test edit, which is the point: it forces the ADR-083
 * admission rule (no existing line answers it; the actor cannot self-answer it; a
 * session-model spawn was tried and failed) to be argued rather than assumed.
 */
const SKILLS_DIR = join(import.meta.dir, "..", "skills");

/** The sanctioned ADR-083 consult gates. Changing this list is a model-policy change. */
const SANCTIONED = ["plan", "ship"].sort();

function skillsDeclaringFablePin(): string[] {
  const hits: string[] = [];
  for (const entry of readdirSync(SKILLS_DIR, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    let body: string;
    try {
      body = readFileSync(join(SKILLS_DIR, entry.name, "SKILL.md"), "utf8");
    } catch {
      continue; // not every skill dir has a SKILL.md
    }
    // Anchor on the CALL FORM, not the token. A bare /`model: fable`/ also matches
    // prose ABOUT the pin — `review/SKILL.md` explains why its consult is *not*
    // pinned, and that sentence quotes the pin. The first draft of this test used
    // the bare token and reported three gates where two exist, which is
    // `cq-assert-anchor-not-bare-token` reproduced inside the guard written to
    // enforce a model-policy bound. Both sanctioned gates spell the spawn
    // "Spawn a **Task** subagent with `model: fable`".
    if (/subagent with `model:\s*fable`/.test(body)) hits.push(entry.name);
  }
  return hits.sort();
}

describe("ADR-083 fable consult gates", () => {
  test("`model: fable` is pinned at exactly the sanctioned gates", () => {
    expect(skillsDeclaringFablePin()).toEqual(SANCTIONED);
  });

  test("the sanctioned set is non-empty and the probe actually matches something", () => {
    // Anti-vacuity: an equality assertion against a list is satisfied by a broken
    // matcher iff SANCTIONED is also empty. Pin that it is not.
    expect(SANCTIONED.length).toBeGreaterThan(0);
    expect(skillsDeclaringFablePin().length).toBe(SANCTIONED.length);
  });

  test("every sanctioned gate still cites ADR-083 next to its pin", () => {
    // A pin without its rationale is how the next reader concludes the tier is arbitrary.
    for (const skill of SANCTIONED) {
      const body = readFileSync(join(SKILLS_DIR, skill, "SKILL.md"), "utf8");
      expect(body).toContain("ADR-083");
    }
  });

  test("the review coverage consult is NOT pinned — it ships at the session model", () => {
    // ADR-083's admission rule lets a proposal that cannot demonstrate a session-model
    // deficit ship unpinned. This asserts the outcome of that rule, so a later edit
    // that quietly upgrades the spawn reds here rather than sliding in as prose.
    const body = readFileSync(join(SKILLS_DIR, "review", "SKILL.md"), "utf8");
    expect(body).toContain("Coverage consult (conditional, session model)");
    expect(body).not.toMatch(/subagent with `model:\s*fable`/);
  });
});
