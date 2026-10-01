/**
 * Grok inspect contract — parse `grok inspect` output and validate Soleur fidelity thresholds.
 *
 * Phase F (#6325): CI contract test for plugin/skills/agents discoverability.
 * Static artifact checks complement live `grok inspect` when the CLI is on PATH.
 */

import { Glob } from "bun";
import { readFileSync, existsSync, readdirSync, lstatSync, realpathSync, mkdirSync, writeFileSync } from "fs";
import { resolve } from "path";
import { homedir } from "os";
import {
  EXPECTED_SOLEUR_AGENT_COUNT,
  AGENTS_MANIFEST_PATH,
  PLUGIN_ROOT,
} from "./agent-registry";

export const REPO_ROOT = resolve(PLUGIN_ROOT, "../..");
export const GROK_CONFIG_PATH = resolve(REPO_ROOT, ".grok/config.toml");
export const GROK_COMMANDS_DIR = resolve(REPO_ROOT, ".grok/commands");

/**
 * Soleur entry commands that Claude Code serves from `plugins/soleur/commands/`
 * and Grok serves from `.grok/commands/` (ADR-224). Membership is exact — a
 * name added here without a shim, or a shim added without this name, is drift.
 */
export const GROK_ENTRY_COMMANDS = ["go", "help", "sync"] as const;
export type GrokEntryCommand = (typeof GROK_ENTRY_COMMANDS)[number];

/** Floor for soleur plugin skills in `grok inspect` Plugins section. */
export const MIN_SOLEUR_PLUGIN_SKILL_COUNT = 90;

/**
 * Grok skips project `.grok/commands/` (and project skills) in untrusted
 * folders. CI checkouts are untrusted, so live `grok inspect --json` will not
 * see the entry-command shims unless the repo root is in
 * `~/.grok/trusted_folders.toml` (hooks.md — the same store `/hooks-trust`
 * writes). Idempotent: an existing table for `repoRoot` is left untouched.
 */
export function ensureGrokFolderTrusted(repoRoot: string, grokHome = resolve(homedir(), ".grok")): string {
  mkdirSync(grokHome, { recursive: true });
  const file = resolve(grokHome, "trusted_folders.toml");
  const key = `[folders."${repoRoot}"]`;
  let existing = "";
  try {
    existing = readFileSync(file, "utf-8");
  } catch {
    existing = "";
  }
  if (existing.includes(key)) {
    return file;
  }
  const prefix = existing.length === 0 || existing.endsWith("\n") ? "" : "\n";
  const block = `${prefix}${key}\ntrusted = true\ndecided_at = ${Math.floor(Date.now() / 1000)}\n`;
  writeFileSync(file, `${existing}${block}`, { mode: 0o600 });
  return file;
}

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

    // Grok project agents register under filename stem (colons→hyphens).
    // Accept colon form only as a transition / pre-rename fixture shape.
    if (inAgents && /soleur[-:][^\s]+\s+project/.test(line)) {
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

/**
 * Grok 1.0.40 validates a plugin `commands/` directory but does not register
 * those files as slash commands (`grok inspect --json` plugin.provides has no
 * `commands` key). `skills/{go,help,sync}` stay `user-invocable: false` so
 * Claude Code's `/` menu is not duplicated. The Grok slash rows are therefore
 * `.grok/commands/<name>.md` symlinks onto the canonical command files.
 *
 * Flipping the plugin skill to `user-invocable: true` would make `/go` appear
 * on Grok and would re-duplicate Claude Code — this check requires the shim
 * path, not merely a user-invocable skill named `go`.
 */
export function validateGrokEntryCommandShims(): string[] {
  const violations: string[] = [];
  const expected = new Set(GROK_ENTRY_COMMANDS.map((n) => `${n}.md`));
  let listed: string[] = [];
  try {
    listed = readdirSync(GROK_COMMANDS_DIR).filter((f) => f.endsWith(".md"));
  } catch {
    violations.push(".grok/commands/ is missing");
    return violations;
  }

  const extra = listed.filter((f) => !expected.has(f)).sort();
  if (extra.length) {
    violations.push(`.grok/commands/ has unexpected files: ${extra.join(", ")}`);
  }

  for (const name of GROK_ENTRY_COMMANDS) {
    const shim = resolve(GROK_COMMANDS_DIR, `${name}.md`);
    const canonical = resolve(PLUGIN_ROOT, "commands", `${name}.md`);
    if (!existsSync(shim)) {
      violations.push(`.grok/commands/${name}.md is missing`);
      continue;
    }
    let isLink = false;
    try {
      isLink = lstatSync(shim).isSymbolicLink();
    } catch {
      violations.push(`.grok/commands/${name}.md is unreadable`);
      continue;
    }
    if (!isLink) {
      violations.push(`.grok/commands/${name}.md is not a symlink (copy would drift from commands/${name}.md)`);
      continue;
    }
    if (!existsSync(canonical)) {
      violations.push(`plugins/soleur/commands/${name}.md is missing`);
      continue;
    }
    const shimReal = realpathSync(shim);
    const canonicalReal = realpathSync(canonical);
    if (shimReal !== canonicalReal) {
      violations.push(
        `.grok/commands/${name}.md resolves to ${shimReal}, expected ${canonicalReal}`,
      );
    }
  }
  return violations;
}

export interface GrokInspectJsonSkill {
  name?: string;
  userInvocable?: boolean;
  source?: { type?: string; path?: string };
  collidesWith?: string;
  invocableAs?: string;
}

export interface GrokInspectJson {
  skills?: GrokInspectJsonSkill[];
}

/** True when a JSON skill row is the Grok slash-command shim for `name`. */
export function isGrokEntryCommandShimRow(
  skill: GrokInspectJsonSkill,
  name: GrokEntryCommand,
): boolean {
  if (skill.name !== name) return false;
  if (skill.userInvocable !== true) return false;
  const path = skill.source?.path ?? "";
  return path.includes(`/.grok/commands/${name}.md`);
}

/** Return violations for missing Grok slash rows in `grok inspect --json`. */
export function validateGrokInspectJsonEntryCommands(json: GrokInspectJson): string[] {
  const skills = json.skills ?? [];
  const violations: string[] = [];
  for (const name of GROK_ENTRY_COMMANDS) {
    const hit = skills.find((s) => isGrokEntryCommandShimRow(s, name));
    if (!hit) {
      violations.push(
        `grok inspect --json has no user-invocable .grok/commands/${name}.md row (plugin commands/ is not a slash surface; skills/${name} is hidden)`,
      );
    }
  }
  const go = skills.find((s) => isGrokEntryCommandShimRow(s, "go"));
  if (go?.collidesWith) {
    violations.push(
      `go shim collides with /${go.collidesWith} → ${go.invocableAs ?? "qualified"}; /go must stay the bare slash`,
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

  violations.push(...validateGrokEntryCommandShims());

  return violations;
}