import { describe, test, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { EXACT_LITERAL_SAFE_COMMANDS } from "../server/safe-bash";

/**
 * AC5↔AC6 coupling guard (Slice C, #6121 / ADR-093).
 *
 * The security invariant this locks: a read-only `worktree-manager.sh
 * (list|ls)` command is auto-approved on the Concierge server ONLY when its
 * emitted string is an EXACT member of `EXACT_LITERAL_SAFE_COMMANDS`
 * (Slice B's exact-equality carve-out — it deliberately does NOT loosen the
 * `$`/`{`/`}` `SHELL_METACHAR_DENYLIST`). So the set of `${CLAUDE_PLUGIN_ROOT}`
 * `list`/`ls` forms a migrated skill actually EMITS (AC6, the SKILL.md side)
 * and the set of forms the carve-out ADMITS (AC5, the safe-bash side) must
 * stay in lockstep.
 *
 * Without this guard the two drift silently: a future edit that emits a
 * `list`/`ls` in a shape NOT in the carve-out (a different fallback anchor, a
 * renamed script path) does not error — it just degrades from auto-approve to
 * the review gate on the CLI and, worse, is denied on the autonomous server
 * surface. That is invisible until a user hits it. This test makes such drift
 * fail loudly at CI time instead.
 *
 * Drift-guard hygiene (learnings #4): this is a DIRECTORY WALK over the live
 * SKILL.md tree, never a hardcoded file list — a new skill that emits a
 * `list`/`ls` is covered automatically. The `>= 1` vacuity floor catches a
 * broken walk/regex (which would otherwise pass the membership assertion
 * vacuously). It is deliberately NOT pinned to today's exact count (4 — the
 * git-worktree `list` sites at SKILL.md:72,124,217,299) so that legitimately
 * removing a `list` site does not false-fail the guard.
 */

const REPO_ROOT = resolve(__dirname, "../../..");
const SKILLS_ROOT = resolve(REPO_ROOT, "plugins/soleur/skills");

// Matches the deployed-form read-only verb emission that MUST be a carve-out
// member. Scoped to the ONLY read-only verb family in scope (git-worktree
// list|ls) — YAGNI: extend the alternation only when a second read-only verb
// actually appears in a migrated skill.
const LIST_EMISSION =
  /bash \$\{CLAUDE_PLUGIN_ROOT:-[^}]+\}\/skills\/git-worktree\/scripts\/worktree-manager\.sh (?:list|ls)\b/g;

function walkMarkdown(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = resolve(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...walkMarkdown(full));
    } else if (entry.isFile() && entry.name.endsWith(".md")) {
      out.push(full);
    }
  }
  return out;
}

function collectListEmissions(): string[] {
  const emissions: string[] = [];
  for (const file of walkMarkdown(SKILLS_ROOT)) {
    const src = readFileSync(file, "utf8");
    for (const match of src.matchAll(LIST_EMISSION)) {
      emissions.push(match[0]);
    }
  }
  return emissions;
}

describe("plugin-root list/ls carve-out coupling (AC5↔AC6, #6121)", () => {
  const emissions = collectListEmissions();

  test("every migrated list/ls emission is a member of EXACT_LITERAL_SAFE_COMMANDS", () => {
    for (const cmd of emissions) {
      expect(
        EXACT_LITERAL_SAFE_COMMANDS.has(cmd),
        `Emitted read-only command is NOT carved out (would degrade to the review gate on CLI and be DENIED on the autonomous server): ${cmd}`,
      ).toBe(true);
    }
  });

  test("vacuity guard: the walk found at least one list/ls emission", () => {
    // Current inventory = 4 (git-worktree/SKILL.md:72,124,217,299). A broken
    // walk or regex yields 0 here, which would make the membership assertion
    // above pass vacuously.
    expect(emissions.length).toBeGreaterThanOrEqual(1);
  });
});
