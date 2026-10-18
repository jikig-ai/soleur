#!/usr/bin/env bun
/**
 * Generate the OpenCode adapter tree from the canonical tree.
 *
 *   bun plugins/soleur/scripts/sync-opencode-adapter.ts
 *   bun plugins/soleur/scripts/sync-opencode-adapter.ts --check
 *
 * OpenCode registers skills straight from the canonical tree through the `skills` config
 * key (measurement §2.0), so — unlike Cursor — **no skill tree is generated**. Only
 * agents and commands need a generated front door, because:
 *
 *   - agents are discovered from a path, register as `mode: primary` unless
 *     `mode: subagent` is emitted, and ignore frontmatter `name:` (§3.0). A primary
 *     agent is unreachable from the Task tool, so the field is the whole gate.
 *   - commands register from `commands/<name>.md` by filename stem and take
 *     `$ARGUMENTS` (§4.0).
 *
 * `--check` prints nothing but `opencode-adapter ok` when the committed tree matches a
 * fresh walk; a drift, a missing stub, a stale extra, or a canonical agent with no stub
 * exits 1 and names the path. There is no second checker.
 *
 * **Paths naming this checkout are emitted as `__SOLEUR_PLUGIN_ROOT__`, never absolute.**
 * The tree is committed, so an absolute path would be wrong on every other machine and
 * would make `--check` machine-dependent. `scripts/install-opencode-adapter.ts`
 * resolves the token at install time.
 */

import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "fs";
import { dirname, join, relative, resolve } from "path";
import { parse as parseYaml } from "yaml";
import { pathToAgentId } from "../lib/agent-registry";

/** Directory this generator owns, relative to the plugin root. */
export const ADAPTER_DIR = "opencode";

/** Stands in for the plugin checkout in every emitted path. Resolved by the installer. */
export const PLUGIN_ROOT_TOKEN = "__SOLEUR_PLUGIN_ROOT__";

const PLUGIN_ROOT = resolve(dirname(import.meta.filename), "..");

export interface CanonicalAgent {
  /** Repo-relative canonical path, e.g. `agents/engineering/cto.md`. */
  path: string;
  /** Canonical registry id, e.g. `soleur:engineering:cto`. */
  id: string;
  description: string;
}

function frontmatter(path: string): Record<string, unknown> {
  const raw = readFileSync(path, "utf-8");
  const match = raw.match(/^---\n([\s\S]*?)\n---\n?/);
  if (!match) return {};
  return (parseYaml(match[1]) ?? {}) as Record<string, unknown>;
}

function frontmatterString(path: string, key: string): string {
  const value = frontmatter(path)[key];
  return typeof value === "string" ? value : "";
}

/** YAML-safe double-quoted scalar. Descriptions carry `:` and `;` and must not break the parser. */
function yamlQuote(value: string): string {
  const escaped = value
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\n/g, "\\n")
    .replace(/\r/g, "\\r")
    .replace(/\t/g, "\\t")
    .replace(/[\u0000-\u001f\u007f\u2028\u2029]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`);
  return `"${escaped}"`;
}

/** Walk `<root>/agents/**` and return entries sorted by canonical id (deterministic output). */
export function walkAgents(root: string): CanonicalAgent[] {
  const agentsDir = join(root, "agents");
  const found: CanonicalAgent[] = [];
  const visit = (dir: string): void => {
    for (const entry of readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const full = join(dir, entry.name);
      if (entry.isDirectory()) {
        visit(full);
        continue;
      }
      if (!entry.name.endsWith(".md")) continue;
      const repoRelative = `agents/${relative(agentsDir, full).split("\\").join("/")}`;
      found.push({
        path: repoRelative,
        id: pathToAgentId(repoRelative),
        description: frontmatterString(full, "description"),
      });
    }
  };
  visit(agentsDir);
  return found.sort((a, b) => a.id.localeCompare(b.id));
}

function walkCommands(root: string): string[] {
  const commandsDir = join(root, "commands");
  return readdirSync(commandsDir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith(".md"))
    .map((entry) => entry.name.replace(/\.md$/, ""))
    .sort();
}

function agentStub(agent: CanonicalAgent): string {
  return [
    "---",
    "mode: subagent",
    `description: ${yamlQuote(agent.description)}`,
    // No `model:` line, deliberately. Canonical agents carry Claude Code SKU aliases
    // (`sonnet`, `opus`) or the literal `inherit`; neither is an OpenCode `provider/model`
    // id, and measurement §3.1 shows an agent carrying `model: inherit` is dropped from
    // `GET /api/agent` entirely — the first draft emitted it and all 67 stubs were invisible.
    // Omitting the key is what actually expresses "inherits the session model".
    "---",
    "",
    `Stub for the canonical agent \`${agent.id}\`. OpenCode derives an agent's id from this`,
    "file's path, so the canonical `name:` frontmatter is deliberately not repeated here.",
    "",
    `Read and follow the canonical agent definition at \`${PLUGIN_ROOT_TOKEN}/${agent.path}\`,`,
    "then work as that agent.",
    "",
  ].join("\n");
}

function commandStub(name: string, description: string): string {
  const lines = ["---"];
  if (description !== "") lines.push(`description: ${yamlQuote(description)}`);
  lines.push(
    "---",
    "",
    `Run the canonical \`${name}\` command. Its full definition lives at`,
    `\`${PLUGIN_ROOT_TOKEN}/commands/${name}.md\`; read and follow it.`,
    "",
    "Arguments passed to this command are:",
    "",
    "$ARGUMENTS",
    "",
  );
  return lines.join("\n");
}

function configFragment(): string {
  return `${JSON.stringify(
    {
      skills: [`${PLUGIN_ROOT_TOKEN}/skills`],
      instructions: [`${PLUGIN_ROOT_TOKEN}/${ADAPTER_DIR}/INSTRUCTIONS.md`],
    },
    null,
    2,
  )}\n`;
}

function instructions(): string {
  return [
    "# Soleur on OpenCode — routing",
    "",
    "Generated by `scripts/sync-opencode-adapter.ts`. Do not edit by hand.",
    "",
    "## Skills",
    "",
    "Soleur skills register from the canonical tree through the `skills` config key, so this",
    "harness has no generated skill tree. A skill id is the **bare directory basename**",
    "(`plan`, `one-shot`, `work`): there is no `soleur:` namespace here (measurement §2.3).",
    "",
    "Canonical Soleur prose is written for Claude Code and says `soleur:<name>`. On this",
    "harness that prefix is dropped: invoke `soleur:plan` as `plan`. An agent-read document",
    "keeps the canonical form; an operator-typed or tool-invoked reference is bare.",
    "",
    "## Agents",
    "",
    "An agent id is derived from its file path, not from frontmatter `name:`, so",
    "`soleur:engineering:cto` is spawned as `engineering/cto` (measurement §3.0). Every",
    "Soleur agent is generated with `mode: subagent`; without that field an agent registers",
    "as primary and the Task tool cannot reach it.",
    "",
    "Spawn subagents through the **Task** tool.",
    "",
    "## Commands",
    "",
    "`/go`, `/help`, `/sync` and `/version` register from `opencode/commands/` and take their",
    "arguments as `$ARGUMENTS` (measurement §4.0).",
    "",
    "## Hooks and completion",
    "",
    "OpenCode exposes no Stop hook. The `session.idle` event is the stop-equivalent, and a",
    "plugin cannot defer or block a stop through it, so Soleur's completion marker is",
    "**advisory** on this harness: the structural checks in the invoked skill are the",
    "contract, and the marker is a report, not a gate.",
    "",
    "Compaction re-read **is** delivered here, unlike Codex and Devin: the plugin binds",
    "`experimental.session.compacting`, so the re-read directive fires on a compaction the",
    "same way the Claude Code Stop hook does.",
    "",
  ].join("\n");
}

/**
 * Every file this generator owns, keyed by plugin-root-relative path.
 * The map is the whole truth: `--check` compares the committed tree against it.
 */
export function expectedOpenCodeAdapter(root: string): Map<string, string> {
  const files = new Map<string, string>();
  for (const agent of walkAgents(root)) {
    // The stub path IS the id: `agents/engineering/cto.md` → `opencode/agents/engineering/cto.md`
    // → id `engineering/cto` (measurement §3.0). Renaming it silently changes the id.
    files.set(`${ADAPTER_DIR}/agents/${agent.path.slice("agents/".length)}`, agentStub(agent));
  }
  for (const name of walkCommands(root)) {
    const description = frontmatterString(join(root, "commands", `${name}.md`), "description");
    files.set(`${ADAPTER_DIR}/commands/${name}.md`, commandStub(name, description));
  }
  files.set(`${ADAPTER_DIR}/opencode.json`, configFragment());
  files.set(`${ADAPTER_DIR}/INSTRUCTIONS.md`, instructions());
  return files;
}

/** Committed files under `opencode/`, plugin-root-relative. */
function committedOpenCodeAdapter(root: string): string[] {
  const adapterDir = join(root, ADAPTER_DIR);
  const found: string[] = [];
  const visit = (dir: string): void => {
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
      const full = join(dir, entry.name);
      if (entry.isDirectory()) {
        visit(full);
        continue;
      }
      if (entry.name === ".gitkeep") continue;
      found.push(`${ADAPTER_DIR}/${relative(adapterDir, full).split("\\").join("/")}`);
    }
  };
  visit(adapterDir);
  return found.sort();
}

/** Drift between the committed tree and a fresh walk. Empty means clean. */
export function openCodeAdapterProblems(root: string): string[] {
  const expected = expectedOpenCodeAdapter(root);
  const problems: string[] = [];
  for (const [path, content] of expected) {
    const full = join(root, path);
    try {
      if (readFileSync(full, "utf-8") !== content) problems.push(`DRIFT: ${path}`);
    } catch {
      problems.push(`MISSING: ${path}`);
    }
  }
  for (const path of committedOpenCodeAdapter(root)) {
    if (!expected.has(path)) problems.push(`EXTRA: ${path}`);
  }
  return problems.sort();
}

/** Write the whole tree, then report the post-write check (which catches stale extras). */
export function writeOpenCodeAdapter(root: string): string[] {
  const expected = expectedOpenCodeAdapter(root);
  for (const [path, content] of expected) {
    const full = join(root, path);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, content);
  }
  // A file the generator no longer emits is not removed by writing; surface it so a stale
  // stub cannot sit in the tree looking supported.
  for (const path of committedOpenCodeAdapter(root)) {
    if (!expected.has(path)) rmSync(join(root, path), { force: true });
  }
  return openCodeAdapterProblems(root);
}

export function parseRoot(argv: readonly string[]): string {
  const index = argv.indexOf("--root");
  if (index === -1) return PLUGIN_ROOT;
  const value = argv[index + 1];
  if (value === undefined) throw new Error("--root requires a directory");
  return resolve(value);
}

function main(): void {
  const argv = process.argv.slice(2);
  const root = parseRoot(argv);
  const problems = argv.includes("--check") ? openCodeAdapterProblems(root) : writeOpenCodeAdapter(root);
  if (problems.length > 0) {
    for (const problem of problems) console.error(problem);
    process.exit(1);
  }
  if (argv.includes("--check")) console.log("opencode-adapter ok");
}

if (import.meta.main) main();
