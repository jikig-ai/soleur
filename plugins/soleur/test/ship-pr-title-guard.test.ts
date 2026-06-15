// PR-title guard — verifies plugins/soleur/skills/ship/SKILL.md Phase 6 keeps the
// HARD GATE that blocks `gh pr ready` / auto-merge while the PR title is still the
// `WIP: <branch>` draft default produced by worktree-manager.sh draft-pr.
//
// The squash-merge commit subject = PR title, so an un-updated WIP title lands a
// `WIP: feat-… (#N)` commit in permanent history (the #5371/PR #5373 regression).
// The guard is documentation an LLM agent executes at /ship time; this test is the
// only safety net against the guard being silently dropped in a future SKILL.md edit.
//
// Test harness: bun:test (matches sibling tests in plugins/soleur/test/*.ts).

import { describe, test, expect, beforeAll } from "bun:test";
import { resolve } from "path";
import { readFileSync } from "fs";

// plugins/soleur/test/ → ../../.. is the worktree (repo) root
const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SHIP_SKILL = resolve(REPO_ROOT, "plugins/soleur/skills/ship/SKILL.md");

let skill: string;
beforeAll(() => {
  skill = readFileSync(SHIP_SKILL, "utf8");
});

describe("ship Phase 6 PR-title guard", () => {
  test("the guard section is present", () => {
    expect(skill).toContain("PR-title guard (HARD GATE");
  });

  test("the guard greps the live title for the WIP draft prefix and fails closed", () => {
    // The detection pattern must anchor on the start of the title, case-insensitively.
    expect(skill).toContain("grep -qiE '^WIP:'");
    // Fail-closed: a still-WIP title must abort, not warn-and-continue.
    expect(skill).toMatch(/title_guard[\s\S]*?exit 1/);
  });

  test("the guard fetches the live PR title (not the local commit subject)", () => {
    expect(skill).toContain("gh pr view PR_NUMBER --json title --jq .title");
  });

  test("the guard runs BEFORE the `gh pr ready` step so it gates ready/merge", () => {
    const guardIdx = skill.indexOf("PR-title guard (HARD GATE");
    const readyIdx = skill.indexOf("gh pr ready PR_NUMBER");
    expect(guardIdx).toBeGreaterThan(-1);
    expect(readyIdx).toBeGreaterThan(-1);
    expect(guardIdx).toBeLessThan(readyIdx);
  });

  test("Phase 6 states that --title is mandatory alongside --body", () => {
    expect(skill).toContain("`--title` is mandatory");
  });
});
