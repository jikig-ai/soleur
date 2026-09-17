import { describe, test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  collidingNames,
  normalizeSkillRoot,
  unackedDuplicates,
  PLUGIN_ROOT,
} from "./helpers";

// WHY THIS FILE EXISTS (design review recommended deleting it; partially declined).
//
// The reviewer's argument is right for clause (b): the live tree pins it, because
// clause (b) was RED on the unmodified tree naming go/help/sync and is green only
// because the `user-invocable: false` exemption works. If `isUserInvocable` broke,
// the live assertion reds. A fixture adds nothing there.
//
// It does NOT hold for clause (a). On the live tree the only cross-root duplicates
// are `go`, `help` and `sync`, and all three are ACKED — so the live assertion
// filters them out and compares [] to [], which is exactly the vacuity the review
// skill warns about ("the live corpus is clean, so the corpus assertion proves
// nothing"). The positive direction of clause (a) — that it FLAGS a duplicate — is
// unreachable on this tree by construction.
//
// Mutation row M6 proved it, and M6 was reverted. The repo's own rule is that a
// guard's non-vacuity claim is worth its evidence, and that evidence must be a
// COMMITTED harness rather than a comment asserting "mutation-proven". These
// fixtures are that harness. They can be deleted when #8236 removes the ack,
// because clause (a) then fires on the live tree unaided.
//
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

// Axes a review found unfixtured. Each row below closes a mutation that left the
// suite BYTE-IDENTICAL green, and each was invisible to the original battery
// because the battery perturbed the implementation while the gap was in the
// fixture SET — no mutation of the code can reach a shape no fixture instantiates.
describe("collidingNames — axes that had no coverage", () => {
  // Every clause-(b) fixture had exactly ONE root, so `roots.flatMap(...)` was
  // decorative: narrowing it to `roots.slice(0, 1)` changed nothing.
  test("a collision in the SECOND root is still flagged", () => {
    const r = collidingNames({
      commandNames: ["alpha-cmd"],
      skillRoots: [
        { root: "./skills", skills: [inv("gamma")] },
        { root: "./vendor/skills", skills: [inv("alpha-cmd")] },
      ],
    });
    expect(r.commandCollisions).toEqual(["alpha-cmd"]);
  });

  // DIRECTION. Every other clause-(b) fixture asserts must-flag, so a matcher
  // made MORE aggressive (exact match -> startsWith) passed everything. An
  // over-reporting matcher is a false RED blocking a legitimate skill name.
  test("a skill whose name merely EXTENDS a command stem is NOT flagged", () => {
    const r = collidingNames({
      commandNames: ["alpha-cmd"],
      skillRoots: [{ root: "./skills", skills: [inv("alpha-cmd-extra")] }],
    });
    expect(r.commandCollisions).toEqual([]);
  });

  // No fixture asserted a two-element result, so ordering was unobservable and
  // `.sort()` -> `.reverse()` survived.
  test("multiple collisions are reported sorted, not in encounter order", () => {
    // Encounter order is deliberately ALREADY sorted: with zeta-first input a
    // `.reverse()` coincidentally produces the sorted answer and the assertion
    // passes for the wrong reason. Measured — the first version of this fixture
    // did exactly that and the mutation survived.
    const r = collidingNames({
      commandNames: ["alpha-cmd", "zeta-cmd"],
      skillRoots: [{ root: "./skills", skills: [inv("alpha-cmd"), inv("zeta-cmd")] }],
    });
    expect(r.commandCollisions).toEqual(["alpha-cmd", "zeta-cmd"]);
  });

  test("cross-root duplicates are reported sorted", () => {
    const r = collidingNames({
      commandNames: [],
      skillRoots: [
        { root: "./skills", skills: [inv("alpha"), inv("zeta")] },
        { root: "./vendor/skills", skills: [inv("alpha"), inv("zeta")] },
      ],
    });
    expect(r.duplicateSkillNames).toEqual(["alpha", "zeta"]);
  });
});

// The ack's APPLICATION, not just the set it reads. Neutering the inline filter
// to `() => false` made clause (a) incapable of reporting anything for any
// manifest, and the only assertion covering the ack inspected its MEMBERSHIP,
// which that mutation leaves untouched.
describe("unackedDuplicates — the ack filter itself", () => {
  test("acked names are removed and unacked names survive", () => {
    expect(unackedDuplicates(["x", "y"], new Set(["x"]))).toEqual(["y"]);
  });

  test("an empty ack removes nothing", () => {
    expect(unackedDuplicates(["x", "y"], new Set())).toEqual(["x", "y"]);
  });

  test("a filter that dropped everything would fail here", () => {
    expect(unackedDuplicates(["unacked-name"], new Set(["go", "help", "sync"]))).toEqual([
      "unacked-name",
    ]);
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
// the deletion is detected from OUTSIDE the file it deletes from.
//
// CORRECTED 2026-09-17. The previous version claimed it was "anchored on the
// describe() call, not a bare word, so prose mentioning the block elsewhere
// cannot satisfy it". That was FALSE and was measured: commenting the whole
// block out with `s/^/\/\/ /` leaves `// describe("plugin slash-name
// uniqueness", () => {` in the file, which satisfies the regex exactly — the
// suite reported 1329 pass / 0 fail with every live clause gone. Anchoring on
// call syntax rather than a bare token is necessary and not sufficient when the
// haystack still contains comments; cq-assert-anchor-not-bare-token is about the
// anchor's SHAPE, and the remaining gap was the SEARCH SPACE.
//
// The haystack is now comment-stripped before matching, and the assertion counts
// executable occurrences so a decoy in prose cannot stand in for the real block.
// ---------------------------------------------------------------------------
describe("guard presence", () => {
  test("components.test.ts still declares the live slash-name uniqueness block", () => {
    const raw = readFileSync(resolve(PLUGIN_ROOT, "test/components.test.ts"), "utf-8");
    const executable = raw
      .split("\n")
      .filter((line) => !/^\s*(\/\/|\*|\/\*)/.test(line))
      .join("\n");
    const hits = executable.match(/describe\(\s*["']plugin slash-name uniqueness["']/g) ?? [];
    expect(
      hits.length,
      "components.test.ts must declare exactly one EXECUTABLE `describe(\"plugin " +
        "slash-name uniqueness\")` block. Zero means the live clauses were deleted " +
        "or commented out; more than one means a decoy could satisfy this guard.",
    ).toBe(1);
  });
});
