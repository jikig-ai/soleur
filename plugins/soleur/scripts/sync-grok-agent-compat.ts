#!/usr/bin/env bun
/**
 * Generate Grok agent compat artifacts from the canonical agent registry.
 *
 * Writes:
 *   - plugins/soleur/.claude-plugin/agents.manifest.json
 *   - <repo-root>/.grok/agents/<qualified-id-dashes>.md (thin project-agent stubs)
 *
 * Usage:
 *   bun run scripts/sync-grok-agent-compat.ts          # write artifacts
 *   bun run scripts/sync-grok-agent-compat.ts --check  # exit 1 on drift
 *   bun run scripts/sync-grok-agent-compat.ts --verbose
 */

import { mkdirSync, readFileSync, writeFileSync, readdirSync, rmSync } from "fs";
import { resolve, join } from "path";
import {
  buildAgentsManifest,
  discoverAgentEntries,
  agentIdToCompatFilename,
  agentIdToGrokSubagentType,
  buildCompatStubBody,
  PLUGIN_ROOT,
} from "../lib/agent-registry";

const REPO_ROOT = resolve(PLUGIN_ROOT, "../..");
const MANIFEST_PATH = resolve(PLUGIN_ROOT, ".claude-plugin/agents.manifest.json");
const GROK_AGENTS_DIR = resolve(REPO_ROOT, ".grok/agents");

const args = new Set(process.argv.slice(2));
const checkOnly = args.has("--check");
const verbose = args.has("--verbose");

function log(msg: string): void {
  if (verbose) console.log(msg);
}

function manifestJson(manifest: ReturnType<typeof buildAgentsManifest>): string {
  return `${JSON.stringify(manifest, null, 2)}\n`;
}

/** Claude Code aliases. Grok's catalog does not resolve them (ADR-110 decision 4). */
const CLAUDE_MODEL_ALIASES = new Set(["haiku", "sonnet", "opus", "fable"]);

/** Omit the line for a Claude alias so the Grok stub inherits the session model. */
function grokStubModelLine(model: string): string | null {
  if (CLAUDE_MODEL_ALIASES.has(model)) return null;
  return `model: ${model}`;
}

/** YAML-safe quoted scalar for frontmatter fields that may contain `:`, `§`, etc. */
function yamlQuote(value: string): string {
  const escaped = value.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  return `"${escaped}"`;
}

/**
 * Render registry agent ids in a stub description as Grok spawn keys (ADR-226 amendment
 * 2026-09-24, #8317). Agent descriptions name siblings by canonical registry id, and a stub is
 * adapter output, so the harness form is the adapter's to render: Grok spawns by filename stem.
 * Keyed on the registry's own id set, never on the text's shape, so a skill id (`soleur:plan`,
 * which Grok resolves through the skill preamble) is never rendered as a nonexistent agent stem.
 * `agents.manifest.json` keeps the canonical ids.
 */
function renderAgentIdsForGrok(text: string, agentIds: ReadonlySet<string>): string {
  return text.replace(/soleur:[a-z0-9-]+(?::[a-z0-9-]+)+/g, (id) =>
    agentIds.has(id) ? agentIdToGrokSubagentType(id) : id,
  );
}

function compatStubMarkdown(
  entry: ReturnType<typeof discoverAgentEntries>[number],
  agentIds: ReadonlySet<string>,
): string {
  const description = renderAgentIdsForGrok(entry.description || entry.name, agentIds);
  // Frontmatter name MUST match the Grok spawn key (filename stem = colons→hyphens).
  // Using colon-form here lists `soleur:product:cpo` in available types while
  // spawn only accepts `soleur-product-cpo` (Grok ≤0.2.102 filename-stem match).
  const grokName = agentIdToGrokSubagentType(entry.id);
  const lines = [
    "---",
    `name: ${grokName}`,
    `description: ${yamlQuote(description)}`,
  ];
  const modelLine = grokStubModelLine(entry.model);
  if (modelLine !== null) lines.push(modelLine);
  lines.push("---", "", buildCompatStubBody(entry.path), "");
  return lines.join("\n");
}

function expectedCompatFiles(): Map<string, string> {
  const files = new Map<string, string>();
  const entries = discoverAgentEntries();
  const agentIds = new Set(entries.map((e) => e.id));
  for (const entry of entries) {
    files.set(agentIdToCompatFilename(entry.id), compatStubMarkdown(entry, agentIds));
  }
  return files;
}

function readText(path: string): string {
  return readFileSync(path, "utf-8");
}

function checkDrift(): boolean {
  let drift = false;
  const manifest = buildAgentsManifest();
  const expectedManifest = manifestJson(manifest);

  try {
    if (readText(MANIFEST_PATH) !== expectedManifest) {
      console.error(`DRIFT: ${MANIFEST_PATH}`);
      drift = true;
    }
  } catch {
    console.error(`MISSING: ${MANIFEST_PATH}`);
    drift = true;
  }

  const expected = expectedCompatFiles();
  let onDisk: string[] = [];
  try {
    onDisk = readdirSync(GROK_AGENTS_DIR).filter((f) => f.endsWith(".md"));
  } catch {
    console.error(`MISSING: ${GROK_AGENTS_DIR}`);
    drift = true;
  }

  const expectedNames = new Set(expected.keys());
  const onDiskSet = new Set(onDisk);

  for (const name of expectedNames) {
    if (!onDiskSet.has(name)) {
      console.error(`MISSING compat stub: .grok/agents/${name}`);
      drift = true;
      continue;
    }
    const path = join(GROK_AGENTS_DIR, name);
    if (readText(path) !== expected.get(name)) {
      console.error(`DRIFT compat stub: .grok/agents/${name}`);
      drift = true;
    }
  }

  for (const name of onDisk) {
    if (!expectedNames.has(name)) {
      console.error(`EXTRA compat stub: .grok/agents/${name}`);
      drift = true;
    }
  }

  return drift;
}

function writeArtifacts(): void {
  const manifest = buildAgentsManifest();
  mkdirSync(resolve(PLUGIN_ROOT, ".claude-plugin"), { recursive: true });
  mkdirSync(GROK_AGENTS_DIR, { recursive: true });

  writeFileSync(MANIFEST_PATH, manifestJson(manifest));
  log(`Wrote ${MANIFEST_PATH} (${manifest.count} agents)`);

  const expected = expectedCompatFiles();
  const keep = new Set(expected.keys());

  for (const [filename, content] of expected) {
    writeFileSync(join(GROK_AGENTS_DIR, filename), content);
    log(`Wrote .grok/agents/${filename}`);
  }

  for (const existing of readdirSync(GROK_AGENTS_DIR)) {
    if (existing.endsWith(".md") && !keep.has(existing)) {
      rmSync(join(GROK_AGENTS_DIR, existing));
      log(`Removed stale .grok/agents/${existing}`);
    }
  }
}

if (checkOnly) {
  process.exit(checkDrift() ? 1 : 0);
}

writeArtifacts();
if (checkDrift()) {
  console.error("sync-grok-agent-compat: write completed but drift check failed");
  process.exit(1);
}

console.log(
  `sync-grok-agent-compat: ${discoverAgentEntries().length} agents → manifest + .grok/agents/`,
);