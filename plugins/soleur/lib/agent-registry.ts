/**
 * Agent registry — canonical qualified IDs for Soleur agents across harnesses.
 *
 * Claude discovers nested `agents/**` recursively; Grok requires flat project
 * compat stubs (see scripts/sync-grok-agent-compat.ts).
 */

import { Glob } from "bun";
import { parse as parseYaml } from "yaml";
import { resolve, basename } from "path";
import { readFileSync } from "fs";

export const PLUGIN_ROOT = resolve(import.meta.dir, "..");

/** Load-bearing agent count for Grok inspect / Phase F CI contract tests. */
export const EXPECTED_SOLEUR_AGENT_COUNT = 67;

/** Relative path from repo root to the committed agents manifest. */
export const AGENTS_MANIFEST_PATH = "plugins/soleur/.claude-plugin/agents.manifest.json";

export interface AgentEntry {
  id: string;
  path: string;
  name: string;
  description: string;
  model: string;
}

export interface AgentsManifest {
  schemaVersion: 1;
  plugin: "soleur";
  count: number;
  agents: AgentEntry[];
}

/** Discover agent markdown paths (excludes README* and references/). */
export function discoverAgentPaths(): string[] {
  return Array.from(new Glob("agents/**/*.md").scanSync(PLUGIN_ROOT)).filter(
    (f) => !basename(f).startsWith("README") && !f.includes("/references/"),
  );
}

/** `agents/engineering/review/security-sentinel.md` → `soleur:engineering:review:security-sentinel` */
export function pathToAgentId(relativePath: string): string {
  const normalized = relativePath.replace(/^agents\//, "").replace(/\.md$/, "");
  return `soleur:${normalized.split("/").join(":")}`;
}

function parseFrontmatter(relativePath: string): Record<string, unknown> {
  const raw = readFileSync(resolve(PLUGIN_ROOT, relativePath), "utf-8");
  const match = raw.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
  if (!match) return {};
  return (parseYaml(match[1]) ?? {}) as Record<string, unknown>;
}

function frontmatterString(fm: Record<string, unknown>, key: string): string {
  const val = fm[key];
  return typeof val === "string" ? val : "";
}

/** Full registry entries for manifest generation and harness ID resolution. */
export function discoverAgentEntries(): AgentEntry[] {
  return discoverAgentPaths()
    .map((path) => {
      const fm = parseFrontmatter(path);
      const name = frontmatterString(fm, "name") || basename(path, ".md");
      return {
        id: pathToAgentId(path),
        path,
        name,
        description: frontmatterString(fm, "description"),
        model: frontmatterString(fm, "model") || "inherit",
      };
    })
    .sort((a, b) => a.id.localeCompare(b.id));
}

/** Build the committed manifest payload (deterministic sort, no timestamps). */
export function buildAgentsManifest(): AgentsManifest {
  const agents = discoverAgentEntries();
  return {
    schemaVersion: 1,
    plugin: "soleur",
    count: agents.length,
    agents,
  };
}

/** Filename for a Grok project compat stub under `.grok/agents/`. */
export function agentIdToCompatFilename(id: string): string {
  return `${agentIdToGrokSubagentType(id)}.md`;
}

/**
 * Grok `spawn_subagent` type key for a Soleur agent.
 *
 * Project compat stubs live at `.grok/agents/<id-with-colons-as-hyphens>.md`.
 * Grok Build (≤0.2.102) validates `subagent_type` against the **filename stem**,
 * not the frontmatter `name:` field. Colon-form IDs (e.g. `soleur:product:cpo`)
 * appear in available-type lists when frontmatter uses colons, but spawn then
 * fails with "Unknown subagent type". Hyphen form matches the file stem and
 * spawns successfully.
 *
 * Canonical Claude / registry IDs remain colon-qualified (`soleur:…`).
 * Call this only when targeting Grok's spawn surface.
 */
export function agentIdToGrokSubagentType(id: string): string {
  return id.replace(/:/g, "-");
}

/** Body for a thin Grok compat stub that defers to the canonical agent source. */
export function buildCompatStubBody(relativeAgentPath: string): string {
  return (
    `Read and follow the instructions in \${GROK_PLUGIN_ROOT}/${relativeAgentPath}.`
  );
}