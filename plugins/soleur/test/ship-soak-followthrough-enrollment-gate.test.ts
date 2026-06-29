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
import { readFileSync, existsSync } from "fs";

// plugins/soleur/test/ → ../../.. is the worktree (repo) root
const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SHIP_SKILL = resolve(REPO_ROOT, "plugins/soleur/skills/ship/SKILL.md");
const CONVENTION = resolve(
  REPO_ROOT,
  "knowledge-base/engineering/operations/runbooks/followthrough-convention.md",
);

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

  test("declares the soak-signal detection regex with the load-bearing alternatives", () => {
    expect(gateSection).toContain("SOAK_RE=");
    // The prose-soak phrases that Phase 7 Step 3.5's ⏳ scan misses.
    for (const token of ["soak", "post-deploy", "adopting", "accepted"]) {
      expect(gateSection.toLowerCase()).toContain(token);
    }
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
