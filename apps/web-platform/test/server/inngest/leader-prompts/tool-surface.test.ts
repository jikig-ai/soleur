/**
 * Tool surface allowlist sentinel (PR-B #4379 AC8 + ADR-042 I3).
 *
 * Asserts:
 *   - No raw `new Octokit(` or `probeOctokit(` calls anywhere in the
 *     leader-prompts directory or the Inngest function file. All Octokit
 *     access MUST route through `createGitHubAppClient(installationId,
 *     founderId)` (per PR-A I2 — inherited).
 *   - Each class's tools array is a strict subset of the documented
 *     per-class allowlist in ADR-042.
 */

import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";
import { globSync } from "fast-glob";

import {
  LEADER_PROMPTS,
  type LeaderActionClass,
} from "@/server/inngest/leader-prompts";

const REPO_ROOT = path.join(__dirname, "../../../..");

const SCAN_TARGETS = [
  "server/inngest/leader-prompts/**/*.ts",
  "server/inngest/functions/agent-on-spawn-requested.ts",
];

/** ADR-042-documented per-class tool allowlist. */
const ALLOWED_TOOLS: Record<LeaderActionClass, readonly string[]> = {
  "engineering.pr_review_pending": [
    "createPullRequestReviewComment",
    "createComment",
  ],
  "engineering.ci_failed": ["createComment"],
  "triage.p0p1_issue": ["addLabels", "createComment"],
  "security.cve_alert": [
    "createBranch",
    "createBlob",
    "createCommit",
    "createPullRequest",
    "createComment",
  ],
  "knowledge.kb_drift": ["createBranch", "createBlob", "createCommit"],
};

describe("tool surface — AC8 sentinels", () => {
  it("no leader-prompts file imports `new Octokit(` or `probeOctokit(`", () => {
    const files = SCAN_TARGETS.flatMap((g) =>
      globSync(g, { cwd: REPO_ROOT, absolute: true }),
    );
    expect(files.length).toBeGreaterThan(0); // sanity — globs resolve

    const violations: string[] = [];
    for (const file of files) {
      const src = readFileSync(file, "utf8");
      // Strip line and block comments before scanning so the PR-A
      // I2 documentation comment ("NEVER probeOctokit ... or raw new
      // Octokit(...)") does not trigger a false positive. We're hunting
      // executable code, not prose about the prohibition.
      const stripped = src
        .replace(/\/\*[\s\S]*?\*\//g, "") // block comments
        .replace(/^\s*\/\/.*$/gm, "");    // line comments
      if (/\bnew\s+Octokit\s*\(/.test(stripped)) {
        violations.push(`${file}: new Octokit(...)`);
      }
      if (/\bprobeOctokit\s*\(/.test(stripped)) {
        violations.push(`${file}: probeOctokit(...)`);
      }
    }
    expect(violations).toEqual([]);
  });

  for (const cls of Object.keys(ALLOWED_TOOLS) as LeaderActionClass[]) {
    it(`${cls} — tools array is a strict subset of the ADR-042 allowlist`, () => {
      const m = LEADER_PROMPTS[cls];
      const actual = m.tools.map((t) => t.name).sort();
      const expected = [...ALLOWED_TOOLS[cls]].sort();
      // Every actual tool MUST be in the allowed list. Extras fail.
      for (const name of actual) {
        expect(expected).toContain(name);
      }
      // Every allowed tool SHOULD be in the actual list (sanity — no
      // class advertises an allowlist its module silently drops). Equal
      // sets are the canonical shape.
      expect(actual).toEqual(expected);
    });
  }
});
