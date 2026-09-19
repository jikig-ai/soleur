import { describe, test, expect } from "bun:test";
import { readFileSync } from "fs";
import { resolve } from "path";

/**
 * Guards the ordering established by #7352 / ADR-183 and re-specified by
 * #8322: `/ship` Phase 4 runs `test-all.sh --affected` by default (and
 * `--full` only on the operator's explicit `/ship --full`), and the `/work`
 * Phase 2 exit runs the same affected gate — never a bare, mode-less
 * `test-all.sh` invocation.
 *
 * Three properties, none of them a bare-token grep — a search for "test-all.sh"
 * in either SKILL.md hits a dozen Sharp Edges and can never fail.
 *
 *   1. CEILING — ship Phase 4 stays unsharded, every battery invocation carries
 *      an explicit mode flag (`--affected` or `--full`), AND its prescription
 *      is not demoted to conditional. Review of the first draft found the
 *      original regex recognised exactly one invocation spelling: `env …`,
 *      `TMPDIR=… `, an indented line, and `TEST_GROUP=$(…)` all evaded it while
 *      a retained `TEST_GROUP=all` line kept the assertion satisfied. Two of
 *      those are this repo's own documented idioms (`work/SKILL.md` prescribes
 *      `setsid nohup env TMPDIR=/var/tmp bash -c …`), so a future author
 *      sharding for speed would have evaded it BY DEFAULT. It is now a denylist
 *      over every fenced invocation line, not an allowlist over one parse —
 *      and since #8322 the flag itself is the pin: a bare `test-all.sh` whose
 *      mode silently defaults is as much a demotion as a shard.
 *
 *   2. FLOOR — `/work` §9 actually prescribes the affected gate. The first
 *      draft asserted the ceiling and the fallback prose and nothing about the
 *      change's own thesis: reverting §9 to an unconditional `TEST_GROUP=all`
 *      left the suite fully green.
 *
 *   3. OD1 FAIL-SAFE — the project-agnostic prescriptions ship to self-hosted
 *      users whose repos have neither ruleset 14145388 nor `scripts/test-all.sh`.
 *      Each site must carry the conditional ON ITS OWN LINE. A cardinality check
 *      ("at least four pointers somewhere") is satisfied by four pointers in one
 *      place while a real site carries none — verified as a live mutation.
 *
 * This file is enrolled in `preflight-check10-suite-integrity.test.sh`'s SUITES
 * manifest. That is load-bearing: `bun test` exits 0 for a file whose tests are
 * all `test.skip`, and this suite is auto-discovered, so deleting it removes the
 * guard AND every trace of it. A floor written inside this file could not close
 * that — the floor would itself be skippable.
 */

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SHIP_SKILL = resolve(REPO_ROOT, "plugins/soleur/skills/ship/SKILL.md");
const WORK_SKILL = resolve(REPO_ROOT, "plugins/soleur/skills/work/SKILL.md");
const WORK_REFS = [
  resolve(REPO_ROOT, "plugins/soleur/skills/work/references/work-agent-teams.md"),
  resolve(REPO_ROOT, "plugins/soleur/skills/work/references/work-subagent-fanout.md"),
];

/** Shard names `scripts/test-all.sh` accepts besides the unsharded default `all`. */
const SHARDS = ["webplat", "bun", "scripts", "infra"] as const;

const FALLBACK_ANCHOR = "Full-suite fallback (projects with no CI-enforced full-suite gate)";
const POINTER = "**Full-suite fallback**";
const INFRA_REASON = "no required status check runs that shard";
const SHIP_PRESCRIPTION = "Then run the project's test gate.";
const CONDITIONAL_CLAUSE =
  "when the project has no CI-enforced full-suite gate on the merge branch, the full battery stays at implementation exit";
const FAILSAFE_CLAUSE =
  "if you cannot determine that such a gate exists AND blocks merge, treat it as ABSENT and run the full battery";

/**
 * Slice `[startHeading, nextHeadingPrefix)`. Both ends throw on a miss: an
 * unguarded `indexOf` returning -1 turns `slice(-1)` into the document's last
 * character, against which every assertion passes vacuously.
 *
 * `nextHeadingPrefix` must be the SPECIFIC expected terminator. An earlier draft
 * used a generic `"\n## Phase "`, which does not throw when the intended
 * terminator is retitled — it silently extends the region to the following
 * heading, and a literal planted in the swallowed section satisfies the slice's
 * assertions (verified as a live mutation).
 */
// window-assembly: sliceSection — the window is asserted complete against ONE
// markdown section, delimited by its own start heading and the SPECIFIC heading
// that follows it (never a generic `## Phase ` prefix). Completeness is enforced
// at both ends by construction: each `indexOf` throws on -1, so a retitle of
// either delimiter fails loudly instead of silently truncating the window (start
// missing) or swallowing the following section into it (terminator missing). The
// enumeration this stands for is "every fenced test-all.sh invocation prescribed
// by this section" — widening the window would admit invocations from a section
// that is not the one under test, which is the defect a generic terminator caused
// and which review demonstrated as a live mutation.
function sliceSection(src: string, startHeading: string, nextHeading: string): string {
  const start = src.indexOf(startHeading);
  if (start === -1) throw new Error(`anchor not found: ${JSON.stringify(startHeading)} — retitled?`);
  const rest = src.slice(start + startHeading.length);
  const end = rest.indexOf(nextHeading);
  if (end === -1) throw new Error(`terminator not found: ${JSON.stringify(nextHeading)} — retitled?`);
  return rest.slice(0, end);
}

/** Body text of every fenced code block in `region`. */
function fencedBodies(region: string): string {
  const bodies: string[] = [];
  const fence = /```[a-zA-Z]*\n([\s\S]*?)```/g;
  let m: RegExpExecArray | null;
  while ((m = fence.exec(region)) !== null) bodies.push(m[1]);
  return bodies.join("\n");
}

/**
 * Every non-comment line inside a fenced block that invokes `test-all.sh`.
 * Deliberately spelling-agnostic: it matches the script path anywhere on the
 * line, so `env …`, `TMPDIR=… `, indentation and `bash -c '…'` wrappers are all
 * caught rather than parsed around.
 */
function invocationLines(region: string): string[] {
  return fencedBodies(region)
    .split("\n")
    .filter((l) => /scripts\/test-all\.sh/.test(l) && !/^\s*#/.test(l));
}

/**
 * Query-mode flags answer and exit without running a suite (`--capacity`,
 * `--print-suite-globs`). They are NOT battery invocations.
 *
 * WHY THIS EXISTS. #7545 added a fenced `bash scripts/test-all.sh --capacity`
 * probe to ship Phase 4. `shardTokensOn` finds no shard on it (its positional
 * regex cannot match a `-`-leading token), so the probe alone satisfied BOTH the
 * floor below and the unsharded check — meaning deleting the real
 * `TEST_GROUP=all` line would have left every CEILING assertion green while
 * Phase 4 prescribed an invocation that runs ZERO suites. The floor's own
 * failure message ("prescribes no test-all.sh invocation at all") would have
 * been false rather than triggered.
 */
// `--enumerate` (#7902) walks every registration and exits 0 having started NO suite — the same
// shape as `--capacity` (#7545), which is why that flag is here. Omitting it let a Phase 4
// invocation of `bash scripts/test-all.sh --enumerate all` satisfy every CEILING assertion AND the
// "at least one invocation actually RUNS the battery" floor while running nothing: measured 11
// pass / 0 fail. That is the defect this file memorializes, reintroduced by the PR that added the
// flag. Any future query-mode flag belongs here the moment it is added. `--print-affected-set`
// (#8322) prints the selection and runs nothing — same shape.
const QUERY_FLAGS = ["--capacity", "--print-suite-globs", "--enumerate", "--print-affected-set"] as const;
function isQueryInvocation(line: string): boolean {
  return QUERY_FLAGS.some((f) => line.includes(f));
}

/** The shard a line selects, if any — env-prefix or positional, any position. */
function shardTokensOn(line: string): string[] {
  const found: string[] = [];
  const env = line.match(/TEST_GROUP=([^\s"']+)/g) ?? [];
  for (const e of env) {
    const v = e.slice("TEST_GROUP=".length);
    if (v !== "all") found.push(v);
  }
  const positional = line.match(/scripts\/test-all\.sh\s+([A-Za-z]+)/);
  if (positional && (SHARDS as readonly string[]).includes(positional[1])) found.push(positional[1]);

  // #7936 — a THIRD way to select a subset, added by #7902: SCRIPTS_SHARD=k/N partitions
  // round-robin at the run_suite chokepoint, WITHIN a group. Neither branch above can see it:
  // the `/` and digits fail the positional `[A-Za-z]+`, and it is not a TEST_GROUP prefix. Left
  // unrecognised, `SCRIPTS_SHARD=1/3 TEST_GROUP=all bash scripts/test-all.sh` would satisfy every
  // CEILING assertion here while running a third of the battery — the merge gate reporting the
  // full suite pinned at /ship over a strict subset.
  //
  // Matched on the `_SHARD=` SUFFIX, not the one literal name. The selector this catches today is
  // SCRIPTS_SHARD; the point of the gate is to notice the NEXT one too, which by construction
  // nobody will remember to add here. A name-list would be wrong the moment a second partition
  // lands — the same reason `SHARDS` is compared against rather than restated.
  const shardEnv = line.match(/\b([A-Z][A-Z0-9_]*_SHARD)=([^\s"']+)/g) ?? [];
  for (const e of shardEnv) {
    const [name, value] = e.split("=");
    found.push(`${name}=${value}`);
  }
  return found;
}

/**
 * The battery-mode flags `scripts/test-all.sh` accepts (#8322). A bare
 * `test-all.sh` whose mode is implicit is a demotion — the same failure class
 * as sharding — so callers pin the mode explicitly.
 */
const MODE_FLAGS = ["--affected", "--full"] as const;
function modeFlagsOn(line: string): string[] {
  return MODE_FLAGS.filter((f) => new RegExp(`(^|\\s)${f.replace("-", "\\-")}(\\s|$|'|")`).test(line));
}

describe("CEILING — /ship Phase 4 runs the gate unsharded, with an explicit mode flag", () => {
  const shipPhase4 = () =>
    sliceSection(readFileSync(SHIP_SKILL, "utf8"), "## Phase 4: Run Tests", "\n## Phase 5: Final Checklist");

  test("Phase 4 prescribes at least one invocation that actually RUNS the battery", () => {
    const battery = invocationLines(shipPhase4()).filter((l) => !isQueryInvocation(l));
    expect(
      battery.length,
      "ship Phase 4 prescribes no battery-running test-all.sh invocation — a query-mode " +
        "flag (--capacity/--print-suite-globs) runs zero suites and cannot satisfy this",
    ).toBeGreaterThan(0);
  });

  test("every fenced test-all.sh invocation in Phase 4 is unsharded, in any spelling", () => {
    const lines = invocationLines(shipPhase4());
    expect(lines.length, "ship Phase 4 prescribes no test-all.sh invocation at all").toBeGreaterThan(0);

    for (const line of lines) {
      expect(
        shardTokensOn(line),
        `ship Phase 4 must not shard the gate; sharded invocation: ${line.trim()}`,
      ).toEqual([]);
    }
  });

  test("every battery-running invocation in Phase 4 carries an explicit mode flag (#8322)", () => {
    // A bare `test-all.sh` inherits the operator's ambient default — the same
    // demotion class as a shard, and the mutation this pins.
    const battery = invocationLines(shipPhase4()).filter((l) => !isQueryInvocation(l));
    expect(battery.length, "ship Phase 4 prescribes no battery-running invocation").toBeGreaterThan(0);
    for (const line of battery) {
      expect(
        modeFlagsOn(line),
        `ship Phase 4 invocation must name its mode (--affected or --full): ${line.trim()}`,
      ).not.toEqual([]);
    }
  });

  test("modeFlagsOn sees the mode flags, not the query flags", () => {
    // Both directions — a matcher that flagged nothing would pass the pin
    // above vacuously.
    expect(modeFlagsOn("bash scripts/test-all.sh --affected")).toEqual(["--affected"]);
    expect(modeFlagsOn("bash scripts/test-all.sh --full")).toEqual(["--full"]);
    expect(
      modeFlagsOn("bash scripts/test-all.sh --capacity"),
      "a query flag is not a mode flag",
    ).toEqual([]);
  });

  test("shardTokensOn sees a *_SHARD= selector, not only TEST_GROUP and positional (#7936)", () => {
    // Without this row the #7936 branch is deletable at full green: every real Phase 4 line is
    // unsharded, so nothing in the suite exercises the new detection. Both directions, because a
    // matcher that flags everything would also pass a one-directional check.
    expect(
      shardTokensOn("SCRIPTS_SHARD=1/3 TEST_GROUP=all bash scripts/test-all.sh"),
      "a *_SHARD= env selector must be reported as sharding, or the CEILING pin is satisfiable " +
        "by a run that executes a strict subset of the battery",
    ).not.toEqual([]);
    expect(
      shardTokensOn("FUTURE_SHARD=2/5 TEST_GROUP=all bash scripts/test-all.sh"),
      "the suffix match must catch a future partition selector, not just today's name",
    ).not.toEqual([]);
    expect(
      shardTokensOn("TEST_GROUP=all bash scripts/test-all.sh"),
      "an unsharded full-battery invocation must NOT be reported as sharded",
    ).toEqual([]);
  });

  test("Phase 4's prescription is imperative, not conditional", () => {
    // Guards the demotion mutation: leaving the fenced `TEST_GROUP=all` line
    // byte-identical while rewriting the prose above it to "skip this run if
    // /work Phase 2 already ran the shards" defeats every assertion that only
    // inspects commands.
    expect(
      shipPhase4().includes(SHIP_PRESCRIPTION),
      `ship Phase 4 must unconditionally prescribe the run: ${SHIP_PRESCRIPTION}`,
    ).toBe(true);
  });

  test("Phase 4 states WHY it stays unsharded", () => {
    // Without the reason a future optimiser reads an unexplained pin and shards it.
    expect(
      shipPhase4().includes(INFRA_REASON),
      `ship Phase 4 must state why the pin exists: ${INFRA_REASON}`,
    ).toBe(true);
  });
});

describe("FLOOR — /work Phase 2 exits on the affected gate, not the battery", () => {
  const workGate = () =>
    sliceSection(
      readFileSync(WORK_SKILL, "utf8"),
      "9. **Affected-Test Exit Gate (single pass, end of Phase 2)**",
      "\n### Phase 2.5:",
    );

  test("§9 prescribes the affected gate", () => {
    const affected = invocationLines(workGate()).filter((l) => modeFlagsOn(l).includes("--affected"));
    expect(
      affected.length,
      "work §9 no longer prescribes `test-all.sh --affected` — the reordering has been reverted",
    ).toBeGreaterThan(0);
  });

  test("§9 prescribes NO unsharded battery run — every invocation carries a mode flag or is a query", () => {
    for (const line of invocationLines(workGate())) {
      expect(
        shardTokensOn(line),
        `work §9 prescribes a sharded run as the exit gate: ${line.trim()}`,
      ).toEqual([]);
      if (!isQueryInvocation(line)) {
        expect(
          modeFlagsOn(line),
          `work §9 prescribes a bare, mode-less test-all.sh: ${line.trim()}`,
        ).not.toEqual([]);
        expect(
          modeFlagsOn(line),
          `work §9 prescribes --full at implementation exit — that is the pre-#8322 state: ${line.trim()}`,
        ).not.toEqual(["--full"]);
      }
    }
  });
});

describe("OD1 — the project-agnostic relaxation fails safe", () => {
  test("work/SKILL.md defines the fallback once, with the conditional stated", () => {
    const src = readFileSync(WORK_SKILL, "utf8");
    expect(src.includes(FALLBACK_ANCHOR), `missing anchor: ${FALLBACK_ANCHOR}`).toBe(true);
    expect(src.includes(CONDITIONAL_CLAUSE), `missing C1 conditional: ${CONDITIONAL_CLAUSE}`).toBe(true);
  });

  test("the default under uncertainty is the full battery, and covers ENFORCEMENT not just existence", () => {
    // The polarity assertion. An earlier draft scoped this to whether a gate
    // "exists"; a repo whose CI runs tests on PRs but whose branch protection is
    // server-side then answered YES at rung 1, could not establish enforcement at
    // rung 2, and fell through to the relaxed branch. The literal now names both.
    const src = readFileSync(WORK_SKILL, "utf8");
    expect(src.includes(FAILSAFE_CLAUSE), `missing fail-safe default: ${FAILSAFE_CLAUSE}`).toBe(true);
  });

  test("each rung of the detection ladder ends in an action", () => {
    // Rung 2 originally ended in a classification ("that is the uncertain case")
    // with no imperative, so an agent walking the ladder literally reached the end
    // with no branch taken and fell through to §9's shard prescription.
    const src = readFileSync(WORK_SKILL, "utf8");
    const ladder = sliceSection(src, FALLBACK_ANCHOR, "**Reading a `test-all.sh` run");
    const rungs = ladder.split("\n").filter((l) => /^\s+\d\.\s+\*\*/.test(l));
    expect(rungs.length, "expected a numbered detection ladder").toBeGreaterThanOrEqual(2);
    expect(
      ladder.includes("Each rung ends in an action"),
      "the ladder must state that every rung terminates in an action",
    ).toBe(true);
  });

  test("EVERY project-agnostic prescription carries the conditional on its own line", () => {
    // Per-site, not a count. A cardinality assertion (">= 4 pointers in the file")
    // passes when four pointers sit in one place and a real site carries none —
    // verified as a live mutation against the first draft.
    const sites: Array<[string, string]> = [
      [WORK_SKILL, "Place a final test-and-lint task at the end"],
      [WORK_SKILL, "Run the touched-file suites after changes"],
      [WORK_SKILL, "run the touched-file suites after each RED/GREEN/REFACTOR cycle"],
      [WORK_SKILL, "# Run the suites covering the touched files"],
      [WORK_REFS[0], "Run the touched-file suites to verify integration"],
      [WORK_REFS[1], "Run the touched-file suites to verify integration across all parallel work"],
    ];

    for (const [file, anchor] of sites) {
      const lines = readFileSync(file, "utf8").split("\n");
      const idx = lines.findIndex((l) => l.includes(anchor));
      expect(idx, `prescription site vanished (retitled?): ${anchor}`).toBeGreaterThanOrEqual(0);
      // The site plus its immediate continuation — a fenced comment carries the
      // pointer on the following line.
      const window = lines.slice(idx, idx + 3).join("\n");
      expect(
        window.includes(POINTER),
        `project-agnostic prescription lacks the fallback conditional: ${anchor}`,
      ).toBe(true);
    }
  });
});
