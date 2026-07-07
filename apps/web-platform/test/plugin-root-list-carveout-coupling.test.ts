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
 * `list`/`ls` of THIS script in a shape NOT in the carve-out — a different
 * fallback anchor (`../../plugins/soleur`, bare `plugins/soleur`), a missing
 * `bash ` prefix, or a trailing argument (`list --json`, `list --porcelain`) —
 * does not error; it just degrades from a no-prompt safe-bash auto-approve to
 * the review-gate prompt (on the CLI, and on the autonomous server before
 * first-run consent; post-consent the autonomous-bypass still auto-approves it
 * — the carve-out is never a hard deny). That is invisible until a user hits it.
 * This test makes such drift fail loudly at CI time instead. Note: the
 * `${CLAUDE_PLUGIN_ROOT}` path migration — NOT this carve-out — is what
 * guarantees the trusted DEPLOYED script runs; the carve-out governs only the
 * approval prompt, so drift is UX friction, never untrusted-code execution.
 *
 * Scope (deliberate, YAGNI): the guard covers the `${CLAUDE_PLUGIN_ROOT:-…}`
 * default-expansion form of `worktree-manager.sh list|ls` only. A script
 * *rename* or a var-expansion form without the `:-` default yields zero matches
 * for that site (the site becomes unguarded) — both are larger changes that
 * warrant their own review; extend the regex when a second read-only verb or
 * script actually appears in a migrated skill.
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

// Matches every shape a `worktree-manager.sh list|ls` emission can take, so the
// membership check (not the regex) decides carve-out conformance. Scoped to the
// ONLY read-only verb family in scope (git-worktree list|ls) — YAGNI: extend the
// alternation only when a second read-only verb appears in a migrated skill.
//
//  - `(?:bash )?` — the `bash ` prefix is OPTIONAL. The carve-out members carry
//    it, but a migrated skill can also emit the no-`bash`/env-prefixed direct-exec
//    form (this diff already uses that shape for the `feature` verb). Matching it
//    too means a future no-`bash` `list` is EXTRACTED and fails membership (→ RED)
//    instead of silently escaping the guard.
//  - trailing `[^\n`|;&)>]*` — captures ANY argument tail up to a command
//    boundary (newline, backtick, pipe, `;`, `&`, `)`, redirect). Load-bearing:
//    without it a drifted `… list --json` would match only the `… list` prefix
//    (a member) and pass GREEN while the real command is a non-member. Capturing
//    the tail makes the drifted string a non-member → RED.
// The match is `.trim()`-ed before the membership check to mirror safe-bash's
// `candidate.trim()`, so a benign trailing space is not a false failure.
const LIST_EMISSION =
  /(?:bash )?\$\{CLAUDE_PLUGIN_ROOT:-[^}]+\}\/skills\/git-worktree\/scripts\/worktree-manager\.sh (?:list|ls)\b[^\n`|;&)>]*/g;

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
      emissions.push(match[0].trim());
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
        `Emitted read-only command is NOT carved out (degrades from a no-prompt auto-approve to the review-gate prompt on the CLI / pre-consent server): ${cmd}`,
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
