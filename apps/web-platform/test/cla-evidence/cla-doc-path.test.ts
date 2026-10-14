// Guard 4 — the discriminant is singular, and the one place that cannot import
// it is pinned to it by this test.
//
// `cla-evidence.yml` carries `CLA_DOC_PATH` as a job-level `env:` literal. An
// earlier revision resolved it at run time by shelling out to this module's
// CLI and writing the answer to $GITHUB_ENV — an npm install and a new `exit 1`
// on the critical path of a REQUIRED check, inside a `pull_request_target` job,
// to compute a constant. A wrong literal is a code change either way; the only
// question is whether it is caught before merge or at run time. This catches it
// before merge, in the same shape as the Guard 1 allowlist pin.
import { describe, it, expect } from "vitest";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  INDIVIDUAL_CLA_DOC_PATH,
  CORPORATE_CLA_DOC_PATH,
} from "@/scripts/cla-evidence/cla-doc-path";

const repoRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
const WORKFLOW_REL = ".github/workflows/cla-evidence.yml";
const workflow = readFileSync(join(repoRoot, WORKFLOW_REL), "utf8");

/** The job-level `CLA_DOC_PATH:` assignment, as the workflow actually spells it. */
const declared = (): string | null => {
  const m = workflow.match(/^\s*CLA_DOC_PATH:\s*(?:["']?)([^"'\s#]+)(?:["']?)\s*$/m);
  return m ? m[1] : null;
};

describe("Guard 4 — cla-evidence.yml's CLA_DOC_PATH is pinned to the discriminant", () => {
  it("anti-vacuity: the text under test is the tracked workflow, not a fixture", () => {
    // Anchors that exist only in the real workflow. Without these, swapping the
    // read for an inline string would leave every assertion below still green.
    expect(workflow).toContain("pull_request_target");
    expect(workflow).toContain("Compute CLA doc hash at PR base SHA");
  });

  it("the workflow declares the path exactly once, at job level", () => {
    // More than one assignment means a step-level override the guard below
    // would not see — which is the drift this whole module exists to remove.
    expect(workflow.match(/^\s*CLA_DOC_PATH:/gm) ?? []).toHaveLength(1);
  });

  it("the declared literal IS INDIVIDUAL_CLA_DOC_PATH", () => {
    expect(declared()).toBe(INDIVIDUAL_CLA_DOC_PATH);
  });

  it("it is NOT the Corporate CLA — this workflow evidences the instrument an individual signs", () => {
    // The two paths differ by one word and decide which legal instrument a
    // permanently-archived evidence record attests to. Assert the negative
    // directly: "equals the individual path" is satisfied by the right answer
    // and would also be satisfied if both constants were accidentally unified.
    expect(declared()).not.toBe(CORPORATE_CLA_DOC_PATH);
    expect(INDIVIDUAL_CLA_DOC_PATH).not.toBe(CORPORATE_CLA_DOC_PATH);
  });

  it("no bare CLA-document literal survives anywhere else in the workflow", () => {
    // AC7. The literal may appear ONLY in the pinned assignment above; every
    // other site must go through ${CLA_DOC_PATH}.
    const hits = workflow.split("\n").filter((l) => l.includes(INDIVIDUAL_CLA_DOC_PATH));
    expect(hits).toHaveLength(1);
    expect(hits[0]).toMatch(/^\s*CLA_DOC_PATH:/);
  });
});
