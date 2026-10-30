// WikiSkill Phase 2 (#10550) -- ONE synthetic plugin tree for the create arm's integration suites (the persist suite
// and the handler suite both clone a throwaway git repository that holds it).
//
// What it writes, through the caller's `put` (so the suite decides where, and what else the repository holds):
//   - the 17 fixture skills of test/fixtures/compound-promote-create/skills.json, EXCEPT `plan`;
//   - the REAL `plan` skill (it carries the canonical Grok block the renderer reads) and the REAL PURPOSE template;
//   - 40 filler skills so the population clears the description counter's floor;
//   - 30 agent files and 50 Cursor stubs, the collision populations the arm fails closed on;
//   - the cap file, `total + headroom` words, with a history comment line.
// It writes NOTHING under README paths or the promotion log: those differ per suite.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { parse as parseYaml } from "yaml";
import type { SkillRecord } from "@/server/compound-promote-create";

const REPO_ROOT = join(__dirname, "..", "..", "..", "..");
const FIX = join(__dirname, "..", "fixtures", "compound-promote-create");

export const FIXTURE_SKILLS: SkillRecord[] = JSON.parse(readFileSync(join(FIX, "skills.json"), "utf8")) as SkillRecord[];

export const skillMd = (name: string, description: string, off = false): string =>
  ["---", `name: ${name}`, `description: ${JSON.stringify(description)}`, ...(off ? ["disable-model-invocation: true"] : []), "---", "", `# ${name}`, ""].join("\n");

export interface SyntheticTree {
  /** Every skill record written (the ranking population the proposals are checked against). */
  records: SkillRecord[];
  /** Model-visible description words (what the budget counter totals). */
  total: number;
}

export function buildSyntheticPluginTree(put: (rel: string, text: string) => void, opts: { headroom?: number } = {}): SyntheticTree {
  const realPlan = readFileSync(join(REPO_ROOT, "plugins/soleur/skills/plan/SKILL.md"), "utf8");
  const planFm = /^---\n([\s\S]*?)\n---\n?/.exec(realPlan)?.[1] ?? "";
  const planMeta = parseYaml(planFm) as Record<string, unknown>;
  const records: SkillRecord[] = FIXTURE_SKILLS.filter((s) => s.name !== "plan");
  for (const s of records) put(`plugins/soleur/skills/${s.name}/SKILL.md`, skillMd(s.name, s.description, s.disableModelInvocation));
  put("plugins/soleur/skills/plan/SKILL.md", realPlan);
  records.push({ name: "plan", description: String(planMeta.description ?? ""), disableModelInvocation: planMeta["disable-model-invocation"] === true });
  for (let i = 0; i < 40; i++) {
    const name = `filler-topic-${i}`;
    const description = `This skill should be used when handling the unrelated filler topic number ${i} in a synthetic fixture tree.`;
    put(`plugins/soleur/skills/${name}/SKILL.md`, skillMd(name, description));
    records.push({ name, description, disableModelInvocation: false });
  }
  put("plugins/soleur/skills/skill-creator/templates/purpose.md", readFileSync(join(REPO_ROOT, "plugins/soleur/skills/skill-creator/templates/purpose.md"), "utf8"));
  for (let i = 0; i < 30; i++) put(`plugins/soleur/agents/engineering/synthetic-agent-${i}.md`, "---\nname: x\n---\n");
  for (let i = 0; i < 50; i++) put(`plugins/soleur/cursor/skills/soleur-stub-${i}/SKILL.md`, "stub\n");
  const total = records.filter((r) => !r.disableModelInvocation).reduce((n, r) => n + r.description.split(/\s+/).filter(Boolean).length, 0);
  put("plugins/soleur/test/components.test.ts", `// history: 1 -> 2\nconst SKILL_DESCRIPTION_WORD_BUDGET = ${total + (opts.headroom ?? 40)};\n`);
  return { records, total };
}
