import { describe, test, expect } from "bun:test";
import { readFileSync } from "fs";
import { resolve } from "path";

/**
 * Guards the ordering established by #7352 / ADR-183: the full `test-all.sh`
 * battery is the LAST LOCAL fail-fast checkpoint at `/ship` Phase 4, and the
 * `/work` Phase 2 exit runs only the shards the diff touches.
 *
 * Two properties are asserted, and neither is a bare-token grep — a search for
 * "test-all.sh" in either SKILL.md hits a dozen Sharp Edges and can never fail.
 *
 *   1. Ceiling: ship Phase 4 stays UNSHARDED. A future speed-PR that shards it
 *      silently deletes the only gate the registered `apps/web-platform/infra/`
 *      suites have (no required CI context runs that shard — verified against
 *      ruleset 14145388, whose contexts contain no infra job). The mutation this
 *      is built to catch is SHARDING the command, not deleting it; deletion is
 *      the easy mutation and the wrong threat.
 *
 *   2. OD1 fail-safe: the four PROJECT-AGNOSTIC prescriptions in work/SKILL.md
 *      ship to self-hosted plugin users whose repos have neither ruleset 14145388
 *      nor `scripts/test-all.sh`. They carry a conditional, and its DEFAULT under
 *      uncertainty must be the full battery. Asserting that the word "conditional"
 *      appears would be vacuous; what is asserted is the POLARITY, so a mutation
 *      that flips the default to the relaxed branch reds.
 */

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SHIP_SKILL = resolve(REPO_ROOT, "plugins/soleur/skills/ship/SKILL.md");
const WORK_SKILL = resolve(REPO_ROOT, "plugins/soleur/skills/work/SKILL.md");

/**
 * Slice `[startHeading, nextHeadingPrefix)` out of a markdown document.
 *
 * Explicitly bounded and `-1`-guarded on BOTH ends: an unguarded `indexOf` that
 * returns -1 turns `slice(-1)` into the document's last character, against which
 * every `.not.toMatch()` passes vacuously. A retitle of either heading is a hard
 * failure here rather than a silently-empty region.
 */
function sliceSection(src: string, startHeading: string, nextHeadingPrefix: string): string {
  const start = src.indexOf(startHeading);
  if (start === -1) {
    throw new Error(`anchor not found: ${JSON.stringify(startHeading)} — retitled?`);
  }
  const rest = src.slice(start + startHeading.length);
  const end = rest.indexOf(nextHeadingPrefix);
  if (end === -1) {
    throw new Error(`terminator not found after ${JSON.stringify(startHeading)}`);
  }
  return rest.slice(0, end);
}

/**
 * Literals are named constants so a failure message states the missing clause
 * rather than dumping the whole SKILL.md (485 KB) into the runner log.
 */
const INFRA_REASON = "no required status check runs that shard";
const CONDITIONAL_CLAUSE =
  "when the project has no CI-enforced full-suite gate on the merge branch, the full battery stays at implementation exit";
const FAILSAFE_CLAUSE =
  "if you cannot determine whether such a gate exists, treat it as ABSENT and run the full battery";
const INVERTED_DEFAULT = "treat it as PRESENT and run the touched-file suites";

/** The shard names `scripts/test-all.sh` accepts besides the default `all`. */
const SHARDS = ["webplat", "bun", "scripts", "infra"] as const;

describe("full suite is the merge gate, not the implementation-exit gate", () => {
  test("ship Phase 4 prescribes an UNSHARDED test-all.sh run", () => {
    const src = readFileSync(SHIP_SKILL, "utf8");
    const phase4 = sliceSection(src, "## Phase 4: Run Tests", "\n## Phase ");

    // Anchor on the INVOCATION SHAPE inside a fenced block, at line start —
    // a comment line cannot produce this, and prose mentioning the script cannot
    // either. `TEST_GROUP=all` is accepted because it IS the unsharded run;
    // the property is unshardedness, not the absence of a token.
    const invocations = [...phase4.matchAll(/^(?:TEST_GROUP=(\w+) )?bash scripts\/test-all\.sh(.*)$/gm)];
    expect(invocations.length).toBeGreaterThan(0);

    for (const [line, envShard, trailingArgs] of invocations) {
      if (envShard !== undefined) {
        expect(
          envShard,
          `ship Phase 4 must run the FULL battery; found sharded invocation: ${line.trim()}`,
        ).toBe("all");
      }
      // A positional shard argument (`bash scripts/test-all.sh webplat`) is the
      // other way to shard it, and the one a speed-PR reaches for first.
      const positional = trailingArgs.trim().split(/\s+/)[0] ?? "";
      expect(
        SHARDS as readonly string[],
        `ship Phase 4 must run the FULL battery; found positional shard: ${line.trim()}`,
      ).not.toContain(positional);
    }
  });

  test("ship Phase 4 states it is the sole local gate for apps/web-platform/infra/", () => {
    const src = readFileSync(SHIP_SKILL, "utf8");
    const phase4 = sliceSection(src, "## Phase 4: Run Tests", "\n## Phase ");

    // The REASON the ceiling exists must travel with it. Without this sentence a
    // future optimiser reads an unexplained `TEST_GROUP=all` and shards it.
    expect(
      phase4.includes(INFRA_REASON),
      `ship Phase 4 must state WHY it stays unsharded: ${INFRA_REASON}`,
    ).toBe(true);
  });
});

describe("OD1 — the project-agnostic relaxation fails safe", () => {
  const FALLBACK_ANCHOR = "Full-suite fallback (projects with no CI-enforced full-suite gate)";

  test("work/SKILL.md defines the fallback once, with the conditional stated", () => {
    const src = readFileSync(WORK_SKILL, "utf8");
    expect(src.includes(FALLBACK_ANCHOR), `work/SKILL.md is missing the anchor: ${FALLBACK_ANCHOR}`).toBe(true);
    expect(
      src.includes(CONDITIONAL_CLAUSE),
      `work/SKILL.md is missing the C1 conditional: ${CONDITIONAL_CLAUSE}`,
    ).toBe(true);
  });

  test("the fallback's DEFAULT under uncertainty is the full battery", () => {
    const src = readFileSync(WORK_SKILL, "utf8");

    // THE polarity assertion. Mutating "absent" -> "present", or "the full
    // battery" -> "the touched-file suites", reds this. An assertion that merely
    // found the word "conditional" would survive both mutations, which is why
    // this pins the implication direction instead.
    expect(
      src.includes(FAILSAFE_CLAUSE),
      `work/SKILL.md is missing the fail-safe default: ${FAILSAFE_CLAUSE}`,
    ).toBe(true);

    // The relaxation must never be reachable by default. Named negative: the
    // inverted default is the exact sentence a future edit would produce.
    expect(
      src.includes(INVERTED_DEFAULT),
      `work/SKILL.md inverts the fail-safe default: ${INVERTED_DEFAULT}`,
    ).toBe(false);
  });

  test("all four project-agnostic prescriptions point at the fallback", () => {
    const src = readFileSync(WORK_SKILL, "utf8");

    // These four lines ship verbatim to self-hosted plugin users. Each must carry
    // the pointer; a count, not a boolean, so relaxing a fifth site without a
    // pointer is visible. Anchored on the pointer's full clause — a bare
    // "fallback" would match unrelated prose.
    const POINTER = "see **Full-suite fallback**";
    const pointers = [...src.matchAll(/see \*\*Full-suite fallback\*\*/g)];
    expect(
      pointers.length,
      `expected the four project-agnostic sites to cite ${POINTER}`,
    ).toBeGreaterThanOrEqual(4);
  });
});
