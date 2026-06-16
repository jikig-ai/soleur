import { describe, expect, test } from "bun:test";
import { readFileSync } from "fs";
import { resolve } from "path";

// FIX 2 (plan Phase 4, AC3 doc-contract proxy) — the `/soleur:sync` command body
// MUST carry an explicit `--headless` execution contract:
//   - commits KB scaffolding LOCALLY,
//   - if it would push, uses the worktree→PR workflow — NEVER a raw `git push`
//     to the checked-out protected default branch,
//   - on GH013 / "! [remote rejected]" / push-rule rejection surfaces a clear,
//     actionable DEGRADED status (committed-locally, could-not-open-PR), not a
//     hard error,
//   - auto-skips the interactive AskUserQuestion gates (they cannot be answered
//     in headless mode).
//
// This is a DOC-CONTRACT drift guard: it proves the prose carries the contract,
// not the LLM agent's runtime push behavior. It FAILS on pre-feature main (RED).

// Test dir is plugins/soleur/test → repo root is three levels up.
const REPO_ROOT = resolve(import.meta.dir, "../../..");
const read = (rel: string) => readFileSync(resolve(REPO_ROOT, rel), "utf-8");

const sync = read("plugins/soleur/commands/sync.md");

// Extract the headless contract block so assertions are scoped to it, not the
// whole file (which already says "git push" in unrelated rule-prune prose).
function headlessSection(): string {
  const start = sync.search(/##+\s+Headless/i);
  expect(start).toBeGreaterThan(-1); // the headless contract block exists
  const rest = sync.slice(start);
  const end = rest.slice(3).search(/\n##\s+/);
  return end === -1 ? rest : rest.slice(0, end + 3);
}

describe("sync.md — headless execution contract (FIX 2)", () => {
  test("a dedicated --headless contract section exists", () => {
    const section = headlessSection();
    expect(section).toContain("--headless");
  });

  test("headless commits locally and uses worktree→PR, never a raw push to the default branch", () => {
    const section = headlessSection().toLowerCase();
    expect(section).toMatch(/commit[s]?\s+(kb\s+|knowledge-base\s+)?(scaffolding\s+)?local/);
    expect(section).toMatch(/worktree|open a pr|pull request/);
    // Must explicitly forbid the raw push to the protected default branch.
    expect(section).toMatch(/must not|never|do not/);
    expect(section).toMatch(/git push|protected|default branch/);
  });

  test("GH013 / remote-rejected push is handled as a degraded status, not a hard error", () => {
    const section = headlessSection();
    expect(section).toMatch(/GH013|remote rejected|branch protection|push-rule|push rule/i);
    expect(section.toLowerCase()).toMatch(/degraded|committed locally|could not open a pr|actionable/);
  });

  test("interactive AskUserQuestion gates auto-skip in headless mode", () => {
    const section = headlessSection();
    expect(section).toMatch(/AskUserQuestion/);
    expect(section.toLowerCase()).toMatch(/auto-skip|skip|do not pause|auto-proceed|never pause/);
  });
});
