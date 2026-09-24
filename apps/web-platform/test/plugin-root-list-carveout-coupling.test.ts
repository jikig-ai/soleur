import { describe, test, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { EXACT_LITERAL_SAFE_COMMANDS, TRAILING_SAFE_REDIRECT } from "../server/safe-bash";
import { SOLEUR_PLUGIN_PATH_DEFAULT } from "../server/plugin-path";

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
 * Scope (deliberate, YAGNI; re-scoped by #7453 / ADR-179 A19): the guard covers every
 * `${CLAUDE_PLUGIN_ROOT…}` rendering of `worktree-manager.sh list|ls` — the modifier
 * group is `[^}]*`, so the bare token and any default-arm form are both EXTRACTED and
 * then decided by membership. Each emission is checked twice: as written, and as the
 * SDK loader substitutes it with the deployed root. A script *rename* still yields
 * zero matches for that site; the exact count below turns that into a red rather than
 * a silently unguarded site.
 *
 * Drift-guard hygiene (learnings #4): this is a DIRECTORY WALK over the live
 * SKILL.md tree, never a hardcoded file list — a new skill that emits a
 * `list`/`ls` is covered automatically. The count is pinned EXACTLY at 4 (the four
 * git-worktree `list` sites), so a broken walk/regex, a lost site, or a site that
 * drifted out of the regex's reach all go red. Removing a `list` site legitimately
 * means editing that number — a reviewed diff.
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
//  - `"?` on both sides of the root and after the script — quote-tolerant, so a
//    misquoted emission (`"${…}"/skills/…`) is EXTRACTED and fails membership.
//  - `\s+` before the verb — whitespace-tolerant for the same reason.
const LIST_EMISSION =
  /(?:bash\s+)?"?\$\{CLAUDE_PLUGIN_ROOT[^}]*\}"?\/skills\/git-worktree\/scripts\/worktree-manager\.sh"?\s+(?:list|ls)\b[^\n`|;&)>]*/g;

const TOKEN = "${CLAUDE_PLUGIN_ROOT}";

/** Mirror safe-bash stage 0: strip one trailing safe stderr redirect, then trim. */
function normalise(emission: string): string {
  return emission.replace(TRAILING_SAFE_REDIRECT, "").trim();
}

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

  test("every list/ls emission, raw AND as the loader renders it, is a member of EXACT_LITERAL_SAFE_COMMANDS", () => {
    for (const cmd of emissions) {
      const raw = normalise(cmd);
      const rendered = raw.replaceAll(TOKEN, SOLEUR_PLUGIN_PATH_DEFAULT);
      expect(
        EXACT_LITERAL_SAFE_COMMANDS.has(raw) && EXACT_LITERAL_SAFE_COMMANDS.has(rendered),
        `Emitted read-only command is NOT carved out (raw member: ${EXACT_LITERAL_SAFE_COMMANDS.has(raw)}, rendered member: ${EXACT_LITERAL_SAFE_COMMANDS.has(rendered)}) — it degrades to the review-gate prompt: ${cmd}`,
      ).toBe(true);
    }
  });

  test("exact count: the walk found the four git-worktree list sites", () => {
    // Pinned, not a floor: a broken walk/regex (0), a lost site, or one that drifted
    // out of reach all change this number.
    expect(emissions.length).toBe(4);
  });

  test("normalisation: a trailing safe redirect is stripped before membership (must-pass)", () => {
    const cmd = `bash "${TOKEN}/skills/git-worktree/scripts/worktree-manager.sh" list 2>/dev/null`;
    expect(EXACT_LITERAL_SAFE_COMMANDS.has(normalise(cmd))).toBe(true);
  });

  test("drift control: a misquoted or default-armed emission is EXTRACTED and is a non-member", () => {
    const DEF = ":-"; // assembled so this file never spells the rejected form as a literal
    const drifted = [
      `bash "${TOKEN}"/skills/git-worktree/scripts/worktree-manager.sh list`,
      `bash \${CLAUDE_PLUGIN_ROOT${DEF}./plugins/soleur}/skills/git-worktree/scripts/worktree-manager.sh list`,
      `bash "${TOKEN}/skills/git-worktree/scripts/worktree-manager.sh" list --json`,
    ];
    for (const d of drifted) {
      const got = [...d.matchAll(LIST_EMISSION)].map((m) => normalise(m[0]));
      expect(got).toHaveLength(1);
      expect(EXACT_LITERAL_SAFE_COMMANDS.has(got[0])).toBe(false);
    }
  });
});
