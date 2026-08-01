// Soak-Gated Follow-Through Enrollment Gate — verifies plugins/soleur/skills/ship/SKILL.md
// Phase 5.5 contains the canonical gate that blocks PR-ready when a PR/plan declares a
// post-deploy soak close-criterion for a tracker that is NOT enrolled in the
// follow-through sweeper.
//
// The gate is documentation an LLM agent reads at /ship time; this test is the only
// safety net against drift between the gate's bash and the followthrough convention.
//
// Why this gate exists: 2026-06-29 shipped two soak-gated closures in PROSE with no
// sweeper enrollment (PR #5675/#5689, PR #5671/#5673) — Phase 7 Step 3.5's ⏳-only scan
// never fired and the trackers were left to rot on human memory.
//
// Test harness: bun:test (matches sibling tests in plugins/soleur/test/*.ts).

import { describe, test, expect, beforeAll } from "bun:test";
import { resolve } from "path";
import { readFileSync, existsSync, statSync } from "fs";
import { spawnSync } from "child_process";

// plugins/soleur/test/ → ../../.. is the worktree (repo) root
const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SHIP_SKILL = resolve(REPO_ROOT, "plugins/soleur/skills/ship/SKILL.md");
const CONVENTION = resolve(
  REPO_ROOT,
  "knowledge-base/engineering/operations/runbooks/followthrough-convention.md",
);
const HOOK = resolve(REPO_ROOT, ".claude/hooks/ship-soak-followthrough-gate.sh");
const SETTINGS = resolve(REPO_ROOT, ".claude/settings.json");
const PLAN_SKILL = resolve(REPO_ROOT, "plugins/soleur/skills/plan/SKILL.md");

// The soak scan lives in a real script that OWNS the regex and every strip
// stage, so both consumers (this hook and ship/SKILL.md) invoke it rather than
// re-declaring it. That is why there is no byte-identity parity test here any
// more: with one copy, drift is unrepresentable rather than merely asserted.
// (`2026-07-17-a-copy-adapted-gate-drifted-in-the-half-i-did-not-parity-pin.md`
// — "Prefer removing the second copy over pinning it.")
const SCAN = resolve(REPO_ROOT, "scripts/ship-soak-signal-gate.sh");
const FIX = resolve(REPO_ROOT, "plugins/soleur/test/fixtures/ship-soak-signal-gate");

const GATE_HEADING = "### Soak-Gated Follow-Through Enrollment Gate";
const NEXT_HEADING = "## Phase 6.4";

let ship = "";
let gateSection = "";
let convention = "";

beforeAll(() => {
  ship = readFileSync(SHIP_SKILL, "utf8");
  convention = readFileSync(CONVENTION, "utf8");
  const start = ship.indexOf(GATE_HEADING);
  const end = ship.indexOf(NEXT_HEADING, start);
  gateSection = start >= 0 && end > start ? ship.slice(start, end) : "";
});

describe("Soak-Gated Follow-Through Enrollment Gate — presence & shape", () => {
  test("the gate section exists in ship Phase 5.5, before Phase 6.4", () => {
    expect(ship.indexOf(GATE_HEADING)).toBeGreaterThan(0);
    expect(ship.indexOf(NEXT_HEADING)).toBeGreaterThan(ship.indexOf(GATE_HEADING));
  });

  // Anchored on the INVOCATION, not on prose. The previous form asserted that
  // the section contained the lowercase words "soak", "post-deploy", "adopting"
  // and "accepted" — every one of which appears in the section's own explanatory
  // comments, so the assertion could not distinguish a working gate from a
  // paragraph describing one. `cq-assert-anchor-not-bare-token`.
  test("delegates the scan to the shipped script rather than re-declaring a regex", () => {
    expect(gateSection).toContain("ship-soak-signal-gate.sh");
    expect(gateSection).toContain("SOAK-SIGNAL");
  });

  test("extracts trackers via Ref/Tracks/Closes/Fixes and checks enrollment triad", () => {
    expect(gateSection).toMatch(/Ref\|Tracks\|Closes\|Fixes/);
    // Enrollment = follow-through label + directive + on-disk script.
    expect(gateSection).toContain("follow-through");
    expect(gateSection).toContain("soleur:followthrough");
    expect(gateSection).toContain("scripts/followthroughs/");
    expect(gateSection).toMatch(/earliest=/);
  });

  test("is fail-closed: SKIP only on no soak signal; OPEN unenrolled tracker triggers", () => {
    expect(gateSection).toMatch(/SKIP/);
    expect(gateSection).toContain("UNENROLLED");
    // Closed trackers must be exempt (no soak enrollment needed once closed).
    expect(gateSection).toMatch(/OPEN/);
  });

  test("offers the 3-option remediation incl. scaffold-from-stub and override", () => {
    expect(gateSection).toContain("followthrough-stub-template.sh");
    expect(gateSection).toContain("gate-override: soak-followthrough-enrollment");
    expect(gateSection.toLowerCase()).toContain("headless");
  });

  test("cites the followthrough convention as the substrate", () => {
    expect(gateSection).toContain("followthrough-convention.md");
  });
});

describe("followthrough-convention.md — Soak trigger shape is documented", () => {
  test("the mapping table has a Soak row referencing a Sentry-rate exemplar", () => {
    expect(convention).toMatch(/\*\*Soak\*\*/);
    expect(convention).toContain("post-deploy");
    expect(convention).toMatch(/reconcile-ff-only-sentry-4977\.sh|ac8-founder-ambiguous-soak/);
  });
});

describe("referenced artifacts exist on disk", () => {
  test("the stub template the gate scaffolds from exists", () => {
    expect(
      existsSync(resolve(REPO_ROOT, "plugins/soleur/skills/ship/references/followthrough-stub-template.sh")),
    ).toBe(true);
  });
});

describe("PreToolUse hook — ship-soak-followthrough-gate.sh (mechanical twin)", () => {
  test("the hook exists and is executable", () => {
    expect(existsSync(HOOK)).toBe(true);
    // owner-executable bit set (0o100)
    expect(statSync(HOOK).mode & 0o100).toBeTruthy();
  });

  test("is registered as a PreToolUse Bash hook in settings.json", () => {
    const settings = readFileSync(SETTINGS, "utf8");
    expect(settings).toContain("ship-soak-followthrough-gate.sh");
    // valid JSON
    expect(() => JSON.parse(settings)).not.toThrow();
  });

  test("matches gh pr ready / gh pr merge --auto", () => {
    const hook = readFileSync(HOOK, "utf8");
    expect(hook).toMatch(/gh\\s\+pr\\s\+\(ready\|merge/);
  });

  // AC17 — single ownership. Exactly one executable surface declares SOAK_RE,
  // and it is the scan script. Scoped to executable paths on purpose:
  // knowledge-base/** is excluded because plans quote regexes as DATA (this
  // change's own plan carries two column-0 `SOAK_RE=` lines inside fences).
  test("exactly one executable surface declares SOAK_RE, and it is the scan script", () => {
    const res = spawnSync(
      "git",
      ["grep", "-lE", "^[[:space:]]*SOAK_RE=", "--", "*.sh", "plugins/**", ".claude/**"],
      { cwd: REPO_ROOT, encoding: "utf8" },
    );
    const owners = res.stdout.split("\n").filter((l) => l.trim() !== "");
    expect(owners).toEqual(["scripts/ship-soak-signal-gate.sh"]);
  });

  test("fails closed on the condition, fails open on infra errors + override", () => {
    const hook = readFileSync(HOOK, "utf8");
    expect(hook).toContain("UNENROLLED");
    expect(hook).toContain("gate-override: soak-followthrough-enrollment");
    expect(hook).toContain("SOLEUR_SKIP_SOAK_FOLLOWTHROUGH_GATE");
    // closed trackers exempt
    expect(hook).toMatch(/state.*OPEN.*\|\| continue|OPEN.*\]\] \|\| continue/);
  });
});

// ---------------------------------------------------------------------------
// The behavioural suite. Everything above this line reads Markdown and asserts
// on its shape; only the block below actually EXECUTES the matcher. That gap is
// why #7056 and #7087 both shipped: the old suite was 14 green tests over prose,
// none of which could have caught a regex that fires on the word "soak" inside
// a negation or inside a filename.
//
// Fixtures are fed on stdin, one per run, and are synthesized plan-shaped prose
// (`cq-test-fixtures-synthesized-only`) — the real #7034/#7072 plans are used
// read-only in the retroactive check and are never copied in here.
// ---------------------------------------------------------------------------
/**
 * Run the SHIPPED scan script against a fixture; returns true iff it signalled.
 *
 * The exit contract is three-valued and this helper pins all three: 0 = signal,
 * 1 = clean no-signal, >=2 = harness fault. Asserting `status === 1` exactly
 * (rather than "non-zero") is load-bearing — a script that crashes on every
 * input would otherwise read as a gate that correctly stays quiet.
 */
function signals(fixture: string): boolean {
  const res = spawnSync("bash", [SCAN], {
    input: readFileSync(resolve(FIX, fixture)),
    encoding: "utf8",
  });
  expect(res.stderr).toBe("");
  if (res.status === 0) {
    expect(res.stdout).toContain("SOAK-SIGNAL: yes");
    return true;
  }
  expect(res.status).toBe(1);
  expect(res.stdout.trim()).toBe("");
  return false;
}

describe("ship soak-signal scan — behaviour (#7056, #7087)", () => {
  // AC3 — the #7056 required pair. This is the false positive that blocked a PR
  // on the plan's own sentence saying no soak was needed.
  test("a real soak declaration DOES signal", () => {
    expect(signals("real-soak-declaration.md")).toBe(true);
  });

  test("a plan declaring `not applicable` does NOT signal", () => {
    expect(signals("soak-disposition-not-applicable.md")).toBe(false);
  });

  // AC4 — the #7087 pair. The BARE form is the one that proves the structural
  // left-delimiter; the backticked form would also be caught by the code-span
  // strip, so passing only that one would leave the real fix unpinned.
  test("a backticked soak FILENAME does NOT signal", () => {
    expect(signals("soak-filename-backticked.md")).toBe(false);
  });

  test("a bare (un-backticked) soak FILENAME does NOT signal", () => {
    expect(signals("soak-filename-bare.md")).toBe(false);
  });

  // AC5 — the negation strip has to reach claims that fire through RETAINED
  // alternatives (`post-deploy soak`, `7-day soak`); no amount of noun-shaping
  // on the bare alternative can silence these.
  test("negated criteria (`No post-deploy soak`, `no 7-day soak`) do NOT signal", () => {
    expect(signals("negated-criterion-soak.md")).toBe(false);
  });

  // AC6 — the highest-value assertion in the set. The strip must remove a SPAN,
  // not a line: both of these carry a disposition AND a real criterion on one
  // line, and under a `grep -v` line drop both go silently dark. PR bodies are
  // not hard-wrapped, so mixed lines are the norm rather than the exception.
  test("a real criterion sharing a line with a disposition DOES signal", () => {
    expect(signals("negation-span-not-line.md")).toBe(true);
  });

  // AC7 — the <=3-token bound. `no P0 incidents during the 7-day soak` puts five
  // tokens between the negation and the noun, so the negation does not GOVERN
  // the soak and must not strip it. Widening the bound turns this RED.
  test("a negation too distant to govern the soak DOES signal", () => {
    expect(signals("negation-adjacent-real-soak.md")).toBe(true);
  });

  // AC8 — `Soak follow-through enrollment` is not only this gate's name, it is
  // the canonical heading real plans use to DECLARE enrollment. Stripping the
  // gate's own name (which the first draft of this fix proposed) deletes a true
  // positive; this fixture is what makes that mistake unshippable.
  test("the canonical enrollment heading DOES signal", () => {
    expect(signals("enrollment-heading-fires.md")).toBe(true);
  });

  // AC9 — fence handling, both halves.
  test("a soak claim inside a balanced fence does NOT signal", () => {
    expect(signals("fenced-claim-quiet.md")).toBe(false);
  });

  test("a soak claim after an UNBALANCED fence DOES signal (fail-closed)", () => {
    expect(signals("unbalanced-fence-real-soak.md")).toBe(true);
  });

  // AC10 / accepted residual: the inline-code strip cannot tell a quoted
  // filename from a quoted claim, and filenames are the far commoner case. This
  // fixture pins the residual as a KNOWN, named bypass rather than a surprise.
  test("a declaration written entirely inside a code span does NOT signal (known residual)", () => {
    expect(signals("backticked-declaration-known-bypass.md")).toBe(false);
  });

  // AC19 — binary-safe. `grep` is GNU grep in the hook but a ugrep wrapper with
  // `-I` on the agent's Bash path; without `-a` on every grep the two disagree
  // and the SKILL path goes silently dark on a corpus containing a NUL byte.
  test("a corpus containing a NUL byte still signals", () => {
    expect(signals("binary-corpus-real-soak.md")).toBe(true);
  });

  // AC11 — the exit contract has three values and each has a reader.
  test("an empty-signal corpus exits exactly 1 with no stdout", () => {
    const res = spawnSync("bash", [SCAN], { input: "nothing to see here\n", encoding: "utf8" });
    expect(res.status).toBe(1);
    expect(res.stdout.trim()).toBe("");
  });

  test("a harness fault exits 2, never 1", () => {
    // A PATH with no `awk` makes the fence-strip stage fail. That is a FAULT,
    // not a clean no-signal — collapsing the two would let a broken gate be
    // indistinguishable from a passing one, which is this whole change's theme.
    //
    // Two details are load-bearing and both were got wrong first:
    //  - `bash` is invoked by ABSOLUTE path, because naming it bare would make
    //    the stripped PATH unresolvable for the interpreter itself; the spawn
    //    would fail before the script ran and the test would pass while never
    //    exercising the fault arm.
    //  - PATH is pinned explicitly rather than relying on `env -i`, which still
    //    hands bash a default PATH that resolves awk perfectly well.
    // The input is a corpus that WOULD signal, so a fault cannot be confused
    // with a correct quiet verdict.
    const res = spawnSync("/usr/bin/env", ["-i", "PATH=/nonexistent", "/bin/bash", SCAN], {
      input: "the tracker closes after a 7-day post-deploy soak\n",
      encoding: "utf8",
    });
    expect(res.status).toBe(2);
  });

  // AC16 — diagnosability. A gate that says only "blocked" teaches the operator
  // to override it; it has to say WHAT it matched.
  test("a signal run emits the matched text alongside the marker", () => {
    const res = spawnSync("bash", [SCAN], {
      input: "The tracker closes after a 7-day post-deploy soak.\n",
      encoding: "utf8",
    });
    expect(res.status).toBe(0);
    expect(res.stdout).toContain("SOAK-SIGNAL: yes");
    expect(res.stdout).toContain("post-deploy soak");
  });

  // AC21 — retroactive application (`wg-when-fixing-a-workflow-gates-detection`):
  // the two REAL plans this gate wrongly blocked must now pass. Read-only; these
  // are deliberately not copied into fixtures/.
  test("the two real plans this gate wrongly blocked now pass", () => {
    for (const p of [
      "knowledge-base/project/plans/2026-07-28-chore-collapse-agents-change-class-sidecars-plan.md",
      "knowledge-base/project/plans/2026-07-29-chore-triage-seven-orphan-infra-suites-plan.md",
    ]) {
      const res = spawnSync("bash", [SCAN], {
        input: readFileSync(resolve(REPO_ROOT, p)),
        encoding: "utf8",
      });
      expect({ plan: p, status: res.status }).toEqual({ plan: p, status: 1 });
    }
  });
});

describe("plan Phase 2.9.1 — proactive soak-enrollment scaffold", () => {
  test("plan/SKILL.md prescribes Follow-Through Enrollment for soak-gated ACs", () => {
    const plan = readFileSync(PLAN_SKILL, "utf8");
    expect(plan).toContain("Soak Follow-Through Enrollment");
    expect(plan).toContain("scripts/followthroughs/");
    expect(plan).toContain("soleur:followthrough");
  });
});
