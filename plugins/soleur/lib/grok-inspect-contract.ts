/**
 * Grok inspect contract — parse `grok inspect` output and validate Soleur fidelity thresholds.
 *
 * Phase F (#6325): CI contract test for plugin/skills/agents discoverability.
 * Static artifact checks complement live `grok inspect` when the CLI is on PATH.
 */

import { Glob } from "bun";
import { readFileSync, existsSync, readdirSync } from "fs";
import { resolve } from "path";
import {
  EXPECTED_SOLEUR_AGENT_COUNT,
  AGENTS_MANIFEST_PATH,
  PLUGIN_ROOT,
} from "./agent-registry";

export const REPO_ROOT = resolve(PLUGIN_ROOT, "../..");
export const GROK_CONFIG_PATH = resolve(REPO_ROOT, ".grok/config.toml");

/** Floor for soleur plugin skills in `grok inspect` Plugins section. */
export const MIN_SOLEUR_PLUGIN_SKILL_COUNT = 90;

export interface GrokInspectParsed {
  soleurPluginListed: boolean;
  soleurPluginSkillCount: number;
  soleurProjectAgentCount: number;
  totalSkillsListed: number;
}

/** Count soleur SKILL.md files on disk (canonical source). */
export function countSoleurSkillsOnDisk(): number {
  return Array.from(new Glob("skills/**/SKILL.md").scanSync(PLUGIN_ROOT)).length;
}

/** Count committed Grok compat stubs under `.grok/agents/`. */
export function countGrokAgentStubs(): number {
  const dir = resolve(REPO_ROOT, ".grok/agents");
  try {
    return readdirSync(dir).filter((f) => f.endsWith(".md")).length;
  } catch {
    return 0;
  }
}

/** Parse `grok inspect` stdout for Soleur plugin + project agent rows. */
export function parseGrokInspectOutput(output: string): GrokInspectParsed {
  const lines = output.split("\n");
  let soleurPluginListed = false;
  let soleurPluginSkillCount = 0;
  let soleurProjectAgentCount = 0;
  let totalSkillsListed = 0;
  let inAgents = false;

  for (const line of lines) {
    const skillsHeader = line.match(/^\s+Skills \((\d+)\)/);
    if (skillsHeader) {
      totalSkillsListed = Number(skillsHeader[1]);
      inAgents = false;
      continue;
    }

    if (/^\s+Agents \(\d+\)/.test(line)) {
      inAgents = true;
      continue;
    }

    if (inAgents && /^\s+Plugins \(\d+\)/.test(line)) {
      inAgents = false;
      continue;
    }

    if (inAgents && /soleur:[^\s]+\s+project/.test(line)) {
      soleurProjectAgentCount++;
      continue;
    }

    const pluginLine = line.match(/^\s+└ soleur \(project[^)]*\)\s+(\d+) skills/);
    if (pluginLine) {
      soleurPluginListed = true;
      soleurPluginSkillCount = Number(pluginLine[1]);
    }
  }

  return {
    soleurPluginListed,
    soleurPluginSkillCount,
    soleurProjectAgentCount,
    totalSkillsListed,
  };
}

export interface StaticArtifactContract {
  manifestCount: number;
  stubCount: number;
  skillCount: number;
  grokConfigHasSoleur: boolean;
}

export function readStaticArtifactContract(): StaticArtifactContract {
  const manifestPath = resolve(REPO_ROOT, AGENTS_MANIFEST_PATH);
  let manifestCount = 0;
  if (existsSync(manifestPath)) {
    const manifest = JSON.parse(readFileSync(manifestPath, "utf-8")) as { count?: number };
    manifestCount = manifest.count ?? 0;
  }

  let grokConfigHasSoleur = false;
  if (existsSync(GROK_CONFIG_PATH)) {
    const cfg = readFileSync(GROK_CONFIG_PATH, "utf-8");
    grokConfigHasSoleur =
      /enabled\s*=\s*\[[^\]]*["']soleur["']/.test(cfg) ||
      /paths\s*=\s*\[[^\]]*plugins\/soleur/.test(cfg);
  }

  return {
    manifestCount,
    stubCount: countGrokAgentStubs(),
    skillCount: countSoleurSkillsOnDisk(),
    grokConfigHasSoleur,
  };
}

/** Return human-readable violation messages (empty = pass). */
export function validateGrokInspectParsed(parsed: GrokInspectParsed): string[] {
  const violations: string[] = [];
  if (!parsed.soleurPluginListed) {
    violations.push("soleur plugin missing from Plugins section");
  }
  if (parsed.soleurPluginSkillCount < MIN_SOLEUR_PLUGIN_SKILL_COUNT) {
    violations.push(
      `soleur plugin skill count ${parsed.soleurPluginSkillCount} < floor ${MIN_SOLEUR_PLUGIN_SKILL_COUNT}`,
    );
  }
  if (parsed.soleurProjectAgentCount < EXPECTED_SOLEUR_AGENT_COUNT) {
    violations.push(
      `soleur project agents ${parsed.soleurProjectAgentCount} < expected ${EXPECTED_SOLEUR_AGENT_COUNT}`,
    );
  }
  return violations;
}

/** Validate committed artifacts without invoking grok CLI. */
export function validateStaticArtifacts(): string[] {
  const violations: string[] = [];
  const artifacts = readStaticArtifactContract();

  if (!artifacts.grokConfigHasSoleur) {
    violations.push(".grok/config.toml does not enable soleur plugin");
  }
  if (artifacts.manifestCount !== EXPECTED_SOLEUR_AGENT_COUNT) {
    violations.push(
      `agents.manifest.json count ${artifacts.manifestCount} !== ${EXPECTED_SOLEUR_AGENT_COUNT}`,
    );
  }
  if (artifacts.stubCount !== EXPECTED_SOLEUR_AGENT_COUNT) {
    violations.push(
      `.grok/agents stub count ${artifacts.stubCount} !== ${EXPECTED_SOLEUR_AGENT_COUNT}`,
    );
  }
  if (artifacts.skillCount < MIN_SOLEUR_PLUGIN_SKILL_COUNT) {
    violations.push(
      `on-disk soleur skills ${artifacts.skillCount} < floor ${MIN_SOLEUR_PLUGIN_SKILL_COUNT}`,
    );
  }

  return violations;
}