#!/usr/bin/env bun
/**
 * Generate the Cursor CLI skill and agent stubs from the canonical tree.
 *
 *   bun plugins/soleur/scripts/sync-cursor-name-map.ts
 *   bun plugins/soleur/scripts/sync-cursor-name-map.ts --check
 *
 * `--check` reprints nothing but `cursor-name-map ok` when the committed tree
 * matches a fresh walk. A drift, a missing stub, an extra stub, or two sources
 * that share one output name exits non-zero and names the path. There is no
 * second checker.
 */

import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "fs";
import { dirname, join, resolve } from "path";
import { parse as parseYaml } from "yaml";

const HEADER =
  "On Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to call those tools, stop. Slice 1 does not run hooks, does not classify the session as cursor, and does not block a commit.";

const HELP_DEVIN_SENTENCE = "Detect the active harness as Devin";
const BARE_SKILLS = new Set(["go", "sync"]);
const MODEL_DISABLED = new Set(["plan", "help", "review"]);
const STEM = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export function cursorSkillName(folder: string): string {
  if (BARE_SKILLS.has(folder)) return folder;
  return `soleur-${folder}`;
}

export function cursorSkillSlash(folder: string): string {
  return `/${cursorSkillName(folder)}`;
}

export function cursorAgentName(relUnderAgents: string): string {
  const stem = relUnderAgents.replace(/\.md$/i, "").replaceAll("/", "-");
  return `soleur-${stem}`;
}

export function cursorAgentSlash(relUnderAgents: string): string {
  return `/${cursorAgentName(relUnderAgents)}`;
}

/** YAML double-quoted scalar. A colon in `soleur:finance:cfo` stays inside the quotes. */
export function yamlQuote(value: string): string {
  const escaped = value
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\n/g, "\\n")
    .replace(/\r/g, "\\r")
    .replace(/\t/g, "\\t")
    .replace(/[\u0000-\u001f\u007f\u2028\u2029]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`);
  return `"${escaped}"`;
}

type BuiltMap = {
  files: Map<string, string>;
  problems: string[];
};

function skillTarget(folder: string): string {
  if (folder === "go" || folder === "sync" || folder === "help") return `commands/${folder}.md`;
  return `skills/${folder}/SKILL.md`;
}

function readFrontmatter(
  abs: string,
  source: string,
  problems: string[],
): { description: string | null; disableModel: boolean } {
  const raw = readFileSync(abs, "utf8");
  const match = raw.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!match) return { description: null, disableModel: false };
  let parsed: unknown;
  try {
    parsed = parseYaml(match[1]);
  } catch (err) {
    problems.push(`frontmatter parse failed: ${source}: ${err instanceof Error ? err.message : String(err)}`);
    return { description: null, disableModel: false };
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    return { description: null, disableModel: false };
  }
  const record = parsed as Record<string, unknown>;
  const disableModel = record["disable-model-invocation"] === true;
  const value = record.description;
  if (value === undefined || value === null || value === "") return { description: null, disableModel };
  if (typeof value !== "string") {
    problems.push(`description is not a string: ${source}`);
    return { description: null, disableModel: false };
  }
  return { description: value, disableModel };
}

function renderStub(name: string, description: string | null, disable: boolean, target: string): string {
  const lines = ["---", `name: ${name}`];
  if (description !== null) lines.push(`description: ${yamlQuote(description)}`);
  if (disable) lines.push("disable-model-invocation: true");
  lines.push("---", "", HEADER, "", `Read \`${target}\`, relative to the plugin root.`, "");
  return lines.join("\n");
}

function claim(owners: Map<string, string[]>, key: string, source: string): void {
  const list = owners.get(key) ?? [];
  list.push(source);
  owners.set(key, list);
}

function walkAgents(dir: string, prefix: string, out: string[]): void {
  const entries = readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
  for (const ent of entries) {
    const rel = prefix ? `${prefix}/${ent.name}` : ent.name;
    if (ent.isDirectory()) walkAgents(join(dir, ent.name), rel, out);
    else if (ent.isFile() && ent.name.endsWith(".md")) out.push(rel);
  }
}

export function buildCursorNameMap(pluginRoot: string): BuiltMap {
  const files = new Map<string, string>();
  const problems: string[] = [];
  const nameOwners = new Map<string, string[]>();
  const pathOwners = new Map<string, string[]>();

  const skillsDir = join(pluginRoot, "skills");
  if (!existsSync(skillsDir)) {
    problems.push("MISSING: skills");
  } else {
    const folders = readdirSync(skillsDir, { withFileTypes: true })
      .filter((ent) => ent.isDirectory())
      .map((ent) => ent.name)
      .sort();
    for (const folder of folders) {
      const source = `skills/${folder}/SKILL.md`;
      const abs = join(skillsDir, folder, "SKILL.md");
      if (!existsSync(abs)) continue;
      if (!STEM.test(folder)) {
        problems.push(`skill folder is not a cursor name stem: ${source}`);
        continue;
      }
      const name = cursorSkillName(folder);
      const rel = `cursor/skills/${name}/SKILL.md`;
      const meta = readFrontmatter(abs, source, problems);
      const body = renderStub(
        name,
        meta.description,
        MODEL_DISABLED.has(folder) || meta.disableModel,
        skillTarget(folder),
      );
      if (folder === "help" && body.includes(HELP_DEVIN_SENTENCE)) {
        problems.push(`help stub contains the Devin harness sentence: ${rel}`);
      }
      claim(nameOwners, name, source);
      claim(pathOwners, rel, source);
      if (!files.has(rel)) files.set(rel, body);
    }
  }

  const agentsDir = join(pluginRoot, "agents");
  if (!existsSync(agentsDir)) {
    problems.push("MISSING: agents");
  } else {
    const rels: string[] = [];
    walkAgents(agentsDir, "", rels);
    for (const relUnder of rels) {
      const source = `agents/${relUnder}`;
      const stem = relUnder.replace(/\.md$/i, "").replaceAll("/", "-");
      if (!STEM.test(stem)) {
        problems.push(`agent path is not a cursor name stem: ${source}`);
        continue;
      }
      const name = cursorAgentName(relUnder);
      const rel = `cursor/agents/${name}.md`;
      const meta = readFrontmatter(join(agentsDir, relUnder), source, problems);
      const body = renderStub(name, meta.description, meta.disableModel, source);
      const afterFrontmatter = body.split("\n---\n").slice(1).join("\n---\n");
      if (afterFrontmatter.includes("spawn_subagent") || afterFrontmatter.includes("GROK_STUB_SPAWN_RULE")) {
        problems.push(`agent stub names a Grok spawn rule: ${rel}`);
      }
      claim(nameOwners, name, source);
      claim(pathOwners, rel, source);
      if (!files.has(rel)) files.set(rel, body);
    }
  }

  for (const [rel, sources] of pathOwners) {
    if (sources.length > 1) problems.push(`${rel} maps from ${sources.join(" and ")}`);
  }
  for (const [name, sources] of nameOwners) {
    if (sources.length < 2) continue;
    const outputPaths = new Set<string>();
    for (const source of sources) {
      for (const [rel, owners] of pathOwners) {
        if (owners.includes(source)) outputPaths.add(rel);
      }
    }
    // One file claimed twice is already reported above. This row is the case
    // where a skill and an agent render the same slash name as two files.
    if (outputPaths.size > 1) problems.push(`${name} maps from ${sources.join(" and ")}`);
  }

  return { files, problems };
}

function listGenerated(pluginRoot: string): string[] {
  const out: string[] = [];
  const skillsRoot = join(pluginRoot, "cursor/skills");
  if (existsSync(skillsRoot)) {
    for (const ent of readdirSync(skillsRoot, { withFileTypes: true })) {
      const relDir = `cursor/skills/${ent.name}`;
      if (!ent.isDirectory()) {
        out.push(relDir);
        continue;
      }
      for (const child of readdirSync(join(skillsRoot, ent.name))) out.push(`${relDir}/${child}`);
    }
  }
  const agentsRoot = join(pluginRoot, "cursor/agents");
  if (existsSync(agentsRoot)) {
    for (const ent of readdirSync(agentsRoot, { withFileTypes: true })) out.push(`cursor/agents/${ent.name}`);
  }
  return out;
}

function diskProblems(pluginRoot: string, files: Map<string, string>): string[] {
  const problems: string[] = [];
  for (const [rel, body] of files) {
    const abs = join(pluginRoot, rel);
    if (!existsSync(abs)) {
      problems.push(`MISSING: ${rel}`);
      continue;
    }
    if (readFileSync(abs, "utf8") !== body) problems.push(`DRIFT: ${rel}`);
  }
  for (const rel of listGenerated(pluginRoot)) {
    if (!files.has(rel)) problems.push(`EXTRA: ${rel}`);
  }
  const helpAbs = join(pluginRoot, "cursor/skills/soleur-help/SKILL.md");
  if (existsSync(helpAbs) && readFileSync(helpAbs, "utf8").includes(HELP_DEVIN_SENTENCE)) {
    problems.push("help stub contains the Devin harness sentence: cursor/skills/soleur-help/SKILL.md");
  }
  return problems;
}

export function cursorNameMapProblems(pluginRoot: string): string[] {
  const built = buildCursorNameMap(pluginRoot);
  return [...built.problems, ...diskProblems(pluginRoot, built.files)];
}

export function writeCursorNameMap(pluginRoot: string): string[] {
  const built = buildCursorNameMap(pluginRoot);
  if (built.problems.length > 0) return built.problems;
  const extras = listGenerated(pluginRoot).filter((rel) => !built.files.has(rel));
  const dirExtras = extras.filter((rel) => {
    try {
      return statSync(join(pluginRoot, rel)).isDirectory();
    } catch {
      return false;
    }
  });
  if (dirExtras.length > 0) return dirExtras.map((rel) => `EXTRA: ${rel}`);
  for (const [rel, body] of built.files) {
    const abs = join(pluginRoot, rel);
    mkdirSync(dirname(abs), { recursive: true });
    writeFileSync(abs, body);
  }
  for (const rel of extras) {
    const abs = join(pluginRoot, rel);
    rmSync(abs, { force: true });
    const parent = dirname(abs);
    if (parent.includes("/cursor/skills/") && existsSync(parent) && readdirSync(parent).length === 0) {
      rmSync(parent, { recursive: true });
    }
  }
  return [];
}

function main(): void {
  const argv = process.argv.slice(2);
  let check = false;
  let rootArg: string | undefined;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--check") {
      check = true;
      continue;
    }
    if (arg === "--root") {
      rootArg = argv[i + 1];
      if (!rootArg || rootArg.startsWith("--")) {
        console.error("missing --root path");
        process.exit(1);
      }
      i++;
      continue;
    }
    console.error(`unknown argument: ${arg}`);
    process.exit(1);
  }

  const pluginRoot = rootArg ? resolve(rootArg) : resolve(import.meta.dir, "..");
  if (!check) {
    const wrote = writeCursorNameMap(pluginRoot);
    if (wrote.length > 0) {
      for (const problem of wrote) console.error(problem);
      process.exit(1);
    }
  }
  const problems = cursorNameMapProblems(pluginRoot);
  if (problems.length > 0) {
    for (const problem of problems) console.error(problem);
    process.exit(1);
  }
  console.log("cursor-name-map ok");
}

if (import.meta.main) main();
