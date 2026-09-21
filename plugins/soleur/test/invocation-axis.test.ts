import { describe, test, expect } from "bun:test";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { discoverSkills, parseComponent, getComponentName } from "./helpers";

// Guard 1 of #8290 (ADR-236): the invocation axis.
//
// A skill whose frontmatter sets `disable-model-invocation: true` is USER-invoked: its
// description leaves the model's always-loaded skill listing, and the Skill tool refuses it
// with a tool_use_error telling the model to ask the user to type the slash command
// (measured on Claude Code 2.1.278, ADR-236). So no surface the model reads may direct the
// agent to invoke one. A model-read surface may NAME a user-invoked skill only at a reviewed
// (file, skill) pair in ACKS below, for a non-model reason.
//
// Keep-pins for skills that must stay model-invocable live in components.test.ts
// (MUST_STAY_INVOCABLE). The description-budget filter lives there too.

const REPO_ROOT = resolve(import.meta.dir, "../../..");

// Exact-set pin. Members are DERIVED from frontmatter below; this literal only makes a 13th
// flip a reviewed edit. A 13th flip moves four sites together: this pin, ACKS, ADR-236's
// list, and SKILL_DESCRIPTION_WORD_BUDGET in components.test.ts (lowered by that skill's
// description word count).
const EXPECTED_USER_INVOKED = [
  "admin-ip-refresh",
  "cf-token-scope",
  "cron-delete",
  "cron-list",
  "flag-create",
  "flag-delete",
  "flag-set-role",
  "provision-cloudflare",
  "provision-doppler",
  "provision-github",
  "provision-hetzner",
  "user-set-role",
];

type AckReason = "doc-mention" | "operator-handoff";

// One row per (file, skill) pair a model-read surface names a user-invoked skill at.
// `doc-mention`: the line describes or cross-references, it does not direct invocation.
// `operator-handoff`: the prose itself hands the command to a human to type.
// Growing this table is a reviewed decision: the prose at the site must read as its reason.
const ACKS: Record<string, AckReason> = {
  "knowledge-base/engineering/operations/runbooks/admin-ip-drift.md|admin-ip-refresh": "operator-handoff",
  "knowledge-base/engineering/operations/runbooks/tenant-provisioning.md|provision-cloudflare": "operator-handoff",
  "knowledge-base/engineering/operations/runbooks/tenant-provisioning.md|provision-doppler": "operator-handoff",
  "knowledge-base/engineering/operations/runbooks/tenant-provisioning.md|provision-github": "operator-handoff",
  "knowledge-base/engineering/operations/runbooks/tenant-provisioning.md|provision-hetzner": "operator-handoff",
  "knowledge-base/engineering/operations/runbooks/vector-redeliver.md|admin-ip-refresh": "doc-mention",
  "plugins/soleur/commands/go.md|admin-ip-refresh": "operator-handoff",
  "plugins/soleur/commands/go.md|cf-token-scope": "operator-handoff",
  "plugins/soleur/commands/go.md|cron-delete": "operator-handoff",
  "plugins/soleur/commands/go.md|cron-list": "operator-handoff",
  "plugins/soleur/commands/go.md|flag-create": "operator-handoff",
  "plugins/soleur/commands/go.md|flag-delete": "operator-handoff",
  "plugins/soleur/commands/go.md|flag-set-role": "operator-handoff",
  "plugins/soleur/commands/go.md|provision-cloudflare": "operator-handoff",
  "plugins/soleur/commands/go.md|provision-doppler": "operator-handoff",
  "plugins/soleur/commands/go.md|provision-github": "operator-handoff",
  "plugins/soleur/commands/go.md|provision-hetzner": "operator-handoff",
  "plugins/soleur/commands/go.md|user-set-role": "operator-handoff",
  "plugins/soleur/skills/flag-bootstrap/SETUP.md|flag-create": "operator-handoff",
  "plugins/soleur/skills/flag-bootstrap/SETUP.md|flag-set-role": "operator-handoff",
  "plugins/soleur/skills/flag-bootstrap/SETUP.md|user-set-role": "operator-handoff",
  "plugins/soleur/skills/flag-list/SKILL.md|flag-create": "operator-handoff",
  "plugins/soleur/skills/flag-list/SKILL.md|flag-delete": "operator-handoff",
  "plugins/soleur/skills/flag-list/SKILL.md|flag-set-role": "operator-handoff",
  "plugins/soleur/skills/operator-bootstrap/SKILL.md|provision-hetzner": "doc-mention",
  "plugins/soleur/skills/schedule/SKILL.md|cron-delete": "operator-handoff",
  "plugins/soleur/skills/schedule/SKILL.md|cron-list": "operator-handoff",
  "plugins/soleur/skills/trigger-cron/SKILL.md|cron-delete": "operator-handoff",
  "plugins/soleur/skills/trigger-cron/SKILL.md|cron-list": "operator-handoff",
};

// The referrer population: what the model reads or is dispatched with. Every entry is a
// `:(glob)` pathspec — plain pathspecs do not recurse `**` (measured: runbooks 0 vs 79), and
// git has no `{a,b}` brace expansion, so each alternative is its own entry. Each carries a
// NAMED floor, set well under today's count and never derived from the population it guards:
// a glob that silently matches nothing fails here instead of passing over zero files.
const SCAN_GLOBS: { spec: string; min: number; why: string }[] = [
  // G1 — always loaded.
  { spec: "AGENTS.md", min: 1, why: "always-loaded index" },
  { spec: "AGENTS.rules.md", min: 1, why: "always-loaded rule corpus" },
  // G2 — what the plugin ships and the model reads.
  { spec: ":(glob)plugins/soleur/skills/**/*.md", min: 150, why: "skill bodies and references" },
  { spec: ":(glob)plugins/soleur/agents/**/*.md", min: 40, why: "agent prompts" },
  { spec: ":(glob)plugins/soleur/commands/*.md", min: 3, why: "entry commands" },
  { spec: ":(glob)plugins/soleur/devin/**/*.md", min: 2, why: "Devin mirrors and instructions" },
  { spec: ":(glob)plugins/soleur/codex/**/*.md", min: 2, why: "Codex mirrors and instructions" },
  { spec: ":(glob)plugins/soleur/hooks/**", min: 5, why: "shipped SessionStart injectors" },
  { spec: ":(glob)plugins/soleur/lib/**/*.ts", min: 6, why: "harness routing text" },
  // G3 — model-dispatch prompts.
  { spec: ":(glob)apps/web-platform/server/inngest/**/*.ts", min: 40, why: "cron agent prompts" },
  { spec: ":(glob).github/workflows/*.yml", min: 40, why: "claude-code-action prompts" },
  { spec: ":(glob).claude/hooks/**", min: 50, why: "hook-injected context" },
  // G4 — agent-read runbooks.
  { spec: ":(glob)knowledge-base/engineering/operations/runbooks/**/*.md", min: 40, why: "runbooks" },
];

// The same population written out a second time, as literals. The conservation check below
// compares the scanner's file count against `git ls-files` over THIS list: if both sides read
// SCAN_GLOBS, narrowing a glob would move both and stay green.
const CONSERVATION_PATHSPECS = [
  "AGENTS.md",
  "AGENTS.rules.md",
  ":(glob)plugins/soleur/skills/**/*.md",
  ":(glob)plugins/soleur/agents/**/*.md",
  ":(glob)plugins/soleur/commands/*.md",
  ":(glob)plugins/soleur/devin/**/*.md",
  ":(glob)plugins/soleur/codex/**/*.md",
  ":(glob)plugins/soleur/hooks/**",
  ":(glob)plugins/soleur/lib/**/*.ts",
  ":(glob)apps/web-platform/server/inngest/**/*.ts",
  ":(glob).github/workflows/*.yml",
  ":(glob).claude/hooks/**",
  ":(glob)knowledge-base/engineering/operations/runbooks/**/*.md",
];

// Deliberately outside the assembly (ADR-236):
//  - commands/help.md: a human-read listing (ADR-226 §4); it marks user-invoked skills by rule.
//  - ADRs, docs/, README.md: record or document, they do not instruct.
//  - apps/web-platform/** outside server/inngest/: web user turns reach skills only through
//    the POSTAMBLE constant in server/prompt-injection-wrap.ts. Migration 054's error text names
//    a user-invoked skill for a human; applied migrations are immutable.
//  - scripts/**, plugins/soleur/scripts/**: human-facing output.
const EXCLUDED_FILES = new Set(["plugins/soleur/commands/help.md"]);

function lsFiles(specs: string[]): string[] {
  const out = execFileSync("git", ["ls-files", "--full-name", "--", ...specs], {
    cwd: REPO_ROOT,
    encoding: "utf-8",
    maxBuffer: 64 * 1024 * 1024,
  });
  return out.split("\n").filter(Boolean);
}

const USER_INVOKED = discoverSkills()
  .filter((p) => parseComponent(p).frontmatter["disable-model-invocation"] === true)
  .map((p) => getComponentName(p, "skill"))
  .sort();

type Hit = { file: string; line: number; skill: string; form: string };

function scan(): { examined: string[]; perGlob: Map<string, number>; hits: Hit[] } {
  const perGlob = new Map<string, number>();
  const seen = new Set<string>();
  for (const g of SCAN_GLOBS) {
    const files = lsFiles([g.spec]);
    perGlob.set(g.spec, files.length);
    for (const f of files) seen.add(f);
  }
  const examined = [...seen].sort();
  const hits: Hit[] = [];
  if (USER_INVOKED.length === 0) return { examined, perGlob, hits };
  const alt = USER_INVOKED.join("|");
  const re = new RegExp(`soleur:(${alt})(?![a-z0-9-])|skills/(${alt})/`, "g");
  const flippedDir = new RegExp(`^plugins/soleur/skills/(${alt})/`);
  for (const file of examined) {
    if (EXCLUDED_FILES.has(file)) continue;
    // Exempt by construction: a user-invoked skill's own directory, and another user-invoked
    // skill's directory. A user-invoked skill runs only after a human typed it, and it cannot
    // Skill-invoke a flipped sibling; its sibling routing lines are hand-offs (read once, #8290).
    if (flippedDir.test(file)) continue;
    const lines = readFileSync(resolve(REPO_ROOT, file), "utf-8").split("\n");
    lines.forEach((text, i) => {
      for (const m of text.matchAll(re)) {
        hits.push({ file, line: i + 1, skill: m[1] ?? m[2], form: m[0] });
      }
    });
  }
  return { examined, perGlob, hits };
}

describe("Invocation axis (ADR-236)", () => {
  const { examined, perGlob, hits } = scan();
  const hitKeys = new Set(hits.map((h) => `${h.file}|${h.skill}`));

  test("user-invoked skills are exactly the reviewed set (derived from frontmatter)", () => {
    expect(
      USER_INVOKED,
      "The set of skills carrying `disable-model-invocation: true` changed. A 13th flip must also " +
        "move ACKS, ADR-236's list and SKILL_DESCRIPTION_WORD_BUDGET in components.test.ts.",
    ).toEqual(EXPECTED_USER_INVOKED);
  });

  for (const g of SCAN_GLOBS) {
    test(`files examined >= ${g.min} for ${g.spec} (${g.why})`, () => {
      expect(perGlob.get(g.spec) ?? 0).toBeGreaterThanOrEqual(g.min);
    });
  }

  test("scanned file count equals git ls-files over the literal pathspec list", () => {
    expect(examined.length).toBe(new Set(lsFiles(CONSERVATION_PATHSPECS)).size);
  });

  test("no unacked referrer to a user-invoked skill", () => {
    const unacked = hits.filter((h) => !(`${h.file}|${h.skill}` in ACKS));
    const detail = unacked
      .map((h) => `  ${h.file}:${h.line} names ${h.skill} (as \`${h.form}\`)`)
      .join("\n");
    expect(
      unacked.length,
      `A model-read surface names a user-invoked skill:\n${detail}\n` +
        "The model cannot invoke these (the Skill tool refuses them). Either rewrite the line as an " +
        "explicit hand-off to a human who types `/soleur:<name>` and add an `operator-handoff` row " +
        "to ACKS, add a `doc-mention` row if the line only describes it, or keep the skill " +
        "model-invocable. See ADR-236.",
    ).toBe(0);
  });

  test("no stale ack (every ack row still has a hit)", () => {
    const stale = Object.keys(ACKS).filter((k) => !hitKeys.has(k));
    expect(stale, "ACKS rows with no remaining hit; delete them").toEqual([]);
  });

  test("ack rows equal the distinct (file, skill) referrer pairs", () => {
    console.log(`invocation-axis: ${hits.length} hit line(s), ${hitKeys.size} (file, skill) pair(s)`);
    expect(Object.keys(ACKS).length).toBe(hitKeys.size);
  });
});
