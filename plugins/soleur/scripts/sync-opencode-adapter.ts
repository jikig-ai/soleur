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

import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "fs";
import { dirname, join, relative, resolve } from "path";
import { parse as parseYaml } from "yaml";
import { pathToAgentId } from "../lib/agent-registry";

/** Directory this generator owns, relative to the plugin root. */
export const ADAPTER_DIR = "opencode";

/** Stands in for the plugin checkout in every emitted path. Resolved by the installer. */
export const PLUGIN_ROOT_TOKEN = "__SOLEUR_PLUGIN_ROOT__";

/**
 * Hand-written files inside `ADAPTER_DIR`. The generator asserts each one EXISTS but never
 * emits it, never drift-checks its bytes and never deletes it.
 *
 * `opencode/plugin.ts` is the reason this set exists: it carries the hook dispatch logic, which
 * has to be unit-tested by import — and a template string in this file cannot be imported. So
 * the module is source, the generated stubs around it are not, and the drift check must be able
 * to tell them apart without losing the "a committed tree is present" guarantee.
 */
export const ADAPTER_SOURCE_FILES: readonly string[] = [`${ADAPTER_DIR}/plugin.ts`];

function isAdapterSource(path: string): boolean {
  return ADAPTER_SOURCE_FILES.includes(path);
}

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
    "as primary and the `subagent` tool cannot reach it.",
    "",
    "Spawn subagents through the **`subagent`** tool, with the path-derived id and a",
    "complete prompt. Foreground waits for the result; `background: true` returns",
    "immediately and notifies the parent when the child finishes. Nesting depth is one.",
    "",
    "## Commands",
    "",
    "`/go`, `/help`, `/sync` and `/version` register from `opencode/commands/` and take their",
    "arguments as `$ARGUMENTS` (measurement §4.0).",
    "",
    "## Tools",
    "",
    "Canonical Soleur prose names Claude Code tools. This table is the translation, and the",
    "property it is held to is that **every** name Soleur's agent-read corpus uses has a row",
    "here (`test/harness-tool-map.test.ts`). The OpenCode side is the V2 built-in set",
    "(measurement §12.8); V1 called the shell tool `bash` and V2 calls it `shell`.",
    "",
    "| Soleur instruction | OpenCode execution |",
    "| --- | --- |",
    "| Read / Glob / Grep | `read`, `glob`, `grep` |",
    "| Write / Edit / MultiEdit | `write` for a new file, `edit` for a change (`replaceAll` replaces every match, which is all `MultiEdit` ever was); `patch` adds, moves or deletes several files in one call on the models that expose it |",
    "| Bash / Shell | `shell`. Set `workdir` instead of putting `cd` in the command, `timeout` in milliseconds, and `background: true` for a long-running process |",
    "| Skill `soleur:<name>` | The `skill` tool with the **bare** id: load `soleur:plan` as `plan`. The id must be in the advertised set, so a wrong one fails loudly instead of silently loading nothing |",
    "| Task / Agent / spawn_subagent | The `subagent` tool with the path-derived id (`engineering/cto`) |",
    "| AskUserQuestion | `question` — a real blocking prompt with a free-form answer always available |",
    "| TodoWrite / TodoRead | No `todo` tool exists. Track the steps in the skill's own Markdown, or in a scratch file in the project |",
    "| Monitor / AwaitShell / TaskOutput | `shell` with `background: true` returns immediately and notifies the session when the process finishes, retaining the full output in a managed file. There is no await/poll primitive and no background output reader; for a wait-until-event watch, run a bounded `shell` poll loop and keep progress visible |",
    "| WebSearch / WebFetch / ToolSearch | `websearch`, `webfetch`. No tool-search tool exists: the built-in set is advertised up front, so name the tool the step wants |",
    "| SendMessage / ListAgents | No equivalent. `subagent` starts a child and, in the background form, notifies on completion — there is no message-without-a-turn and no enumeration. Pass the returned `sessionID` to continue that same child |",
    "| TaskCreate / TaskGet / TaskList / TaskUpdate / TaskStop | No equivalent, and no inventory of running children exists. Track steps in the skill's own Markdown or a project file |",
    "| RemoteTrigger / PushNotification / ScheduleWakeup / CronCreate / CronDelete / CronList | No equivalent. Report the unsupported gate rather than simulating it — a scheduled or push-triggered step that silently does not fire is worse than one that refuses |",
    "| NotebookEdit | No equivalent; edit the file with `edit` |",
    "| Workflow scripts | Translate the orchestration into `subagent` calls; do not execute Claude tool calls as shell JavaScript |",
    "",
    "A gate with no OpenCode equivalent is stated as unsupported above, never silently",
    "skipped — the same posture the hook ledger takes. A step that cannot fire must say so.",
    "",
    "## Hooks and completion",
    "",
    "The plugin module `plugin.ts` (installed as `<configdir>/plugins/soleur-plugin.ts`) is the hook",
    "carrier. `.claude/hooks/opencode-dispositions.tsv` is its ledger: one row per canonical",
    "registration, every row carrying a disposition, so a gate with no equivalent here is",
    "**reported, never silently skipped**.",
    "",
    "OpenCode V2 has **no Stop hook**. Every hook surface communicates only by mutating the event",
    "object it is handed, and `ctx.event.subscribe` is a one-way iterator with no return channel,",
    "so no hook can defer a stop, force a continuation, or veto a completion. Soleur's completion",
    "marker is therefore **advisory** on this harness: a session that goes quiet is observed and",
    "nothing more. The structural checks inside the invoked skill are the contract, and the marker",
    "is a report, not a gate.",
    "",
    "The guards are real, and they reuse the canonical scripts unchanged. A shell call is handed to",
    "`browser-snapshot-credential-guard.sh` and `destructive-command-guard.sh` in the order",
    "`hooks.json` registers them, and the decision is written onto the permission event: a `deny`",
    "becomes `effect = \"deny\"` and a guard's `ask` becomes `effect = \"ask\"`, a real prompt. The tool",
    "then reports `permission.rejected` carrying the guard's reason, which the model reads. Neither",
    "value is downgraded — `deny` blocks, `ask` waits (measurement §12.2).",
    "",
    "The shell tool's wire name here is **`shell`**, not `bash`; the plugin maps both to Claude's",
    "`Bash` before handing the call to a guard (measurement §12.1). Code-mode `execute` calls carry",
    "JavaScript rather than a command and are not decided by the Bash guards — a limitation this",
    "harness shares with the guard scripts' own input contract.",
    "",
    "The post-compaction re-read **is** delivered, unlike Codex and Devin: the plugin binds",
    "`ctx.session.hook(\"compaction\")` and re-injects the rule corpus plus the re-read directive on",
    "the next request. What is not reproduced is `compaction-state.sh`'s transcript-bounded",
    "window bookkeeping, which counts `compact_boundary` records in a Claude Code transcript this",
    "harness has no equivalent of.",
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
  // A source file is not compared byte-for-byte, but its absence is a defect: a tree that
  // dropped its hook module would otherwise pass with every generated stub intact.
  for (const path of ADAPTER_SOURCE_FILES) {
    if (!existsSync(join(root, path))) problems.push(`MISSING-SOURCE: ${path}`);
  }
  for (const path of committedOpenCodeAdapter(root)) {
    if (!expected.has(path) && !isAdapterSource(path)) problems.push(`EXTRA: ${path}`);
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
    if (!expected.has(path) && !isAdapterSource(path)) rmSync(join(root, path), { force: true });
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
