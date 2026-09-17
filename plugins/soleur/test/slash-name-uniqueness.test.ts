import { describe, test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { collidingNames, normalizeSkillRoot, PLUGIN_ROOT } from "./helpers";

// Fixtures are SYNTHESIZED, never captured (cq-test-fixtures-synthesized-only).
// Names here are deliberately not real component names so a rename in the live
// tree cannot silently change what these cases assert.
const inv = (name: string) => ({ name, userInvocable: true });
const hidden = (name: string) => ({ name, userInvocable: false });

describe("collidingNames — command-vs-skill (clause b)", () => {
  test("a user-invocable skill sharing a command stem is flagged", () => {
    const r = collidingNames({
      commandNames: ["alpha-cmd", "beta-cmd"],
      skillRoots: [{ root: "./skills", skills: [inv("alpha-cmd"), inv("gamma")] }],
    });
    expect(r.commandCollisions).toEqual(["alpha-cmd"]);
  });

  // The fix itself. If this ever flags, `user-invocable: false` has stopped
  // exempting a skill and the three shims are back in the menu.
  test("a NON-user-invocable skill sharing a command stem is NOT flagged", () => {
    const r = collidingNames({
      commandNames: ["alpha-cmd", "beta-cmd"],
      skillRoots: [{ root: "./skills", skills: [hidden("alpha-cmd"), inv("gamma")] }],
    });
    expect(r.commandCollisions).toEqual([]);
  });

  test("both directions at once: hidden exempt, visible flagged", () => {
    const r = collidingNames({
      commandNames: ["alpha-cmd", "beta-cmd"],
      skillRoots: [{ root: "./skills", skills: [hidden("alpha-cmd"), inv("beta-cmd")] }],
    });
    expect(r.commandCollisions).toEqual(["beta-cmd"]);
  });
});

describe("collidingNames — skills-vs-skills across roots (clause a)", () => {
  test("one name contributed by two distinct roots is flagged", () => {
    const r = collidingNames({
      commandNames: [],
      skillRoots: [
        { root: "./skills", skills: [inv("shared-name")] },
        { root: "./vendor/skills", skills: [inv("shared-name")] },
      ],
    });
    expect(r.duplicateSkillNames).toEqual(["shared-name"]);
  });

  // Two spellings of ONE directory are one root. Without this, every manifest
  // that names its default root explicitly would report itself as a collision.
  test("a manifest path duplicating ./skills is NOT flagged", () => {
    const r = collidingNames({
      commandNames: [],
      skillRoots: [
        { root: "./skills", skills: [inv("shared-name")] },
        { root: "skills", skills: [inv("shared-name")] },
        { root: "skills/", skills: [inv("shared-name")] },
      ],
    });
    expect(r.duplicateSkillNames).toEqual([]);
  });

  // Clause (a) is about menu rows, which a hidden skill does not produce for
  // the USER — but two roots resolving one name is a loader ambiguity for every
  // harness, so it is flagged regardless of user-invocable.
  test("cross-root duplication is flagged even when both are hidden", () => {
    const r = collidingNames({
      commandNames: [],
      skillRoots: [
        { root: "./skills", skills: [hidden("shared-name")] },
        { root: "./vendor/skills", skills: [hidden("shared-name")] },
      ],
    });
    expect(r.duplicateSkillNames).toEqual(["shared-name"]);
  });
});

describe("collidingNames — degenerate inputs", () => {
  test("an empty skills array flags nothing and does not throw", () => {
    const r = collidingNames({ commandNames: ["alpha-cmd"], skillRoots: [] });
    expect(r.commandCollisions).toEqual([]);
    expect(r.duplicateSkillNames).toEqual([]);
  });

  test("a root with no skills flags nothing", () => {
    const r = collidingNames({
      commandNames: ["alpha-cmd"],
      skillRoots: [{ root: "./skills", skills: [] }],
    });
    expect(r.commandCollisions).toEqual([]);
    expect(r.duplicateSkillNames).toEqual([]);
  });
});

describe("normalizeSkillRoot", () => {
  test("strips a leading ./ and trailing slashes", () => {
    expect(normalizeSkillRoot("./devin/skills")).toBe("devin/skills");
    expect(normalizeSkillRoot("skills/")).toBe("skills");
    expect(normalizeSkillRoot("./skills//")).toBe("skills");
    expect(normalizeSkillRoot("skills")).toBe("skills");
  });
});

// ---------------------------------------------------------------------------
// Cross-file guard presence (mutation row M8)
//
// The live-tree assertions run in components.test.ts. Deleting that describe
// block there would remove every live clause while this file stayed green, so
// the deletion is detected from OUTSIDE the file it deletes from. Anchored on
// the describe() call, not a bare word, so prose mentioning the block elsewhere
// cannot satisfy it (cq-assert-anchor-not-bare-token).
// ---------------------------------------------------------------------------
describe("guard presence", () => {
  test("components.test.ts still declares the live slash-name uniqueness block", () => {
    const src = readFileSync(resolve(PLUGIN_ROOT, "test/components.test.ts"), "utf-8");
    expect(src).toMatch(/describe\(\s*["']plugin slash-name uniqueness["']/);
  });
});
