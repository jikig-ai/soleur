import { describe, test, expect } from "bun:test";
import { readFileSync, existsSync } from "fs";
import { resolve } from "path";
import { $ } from "bun";
import {
  EXPECTED_SOLEUR_AGENT_COUNT,
  AGENTS_MANIFEST_PATH,
  agentIdToCompatFilename,
  agentIdToGrokSubagentType,
  buildAgentsManifest,
} from "../lib/agent-registry";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const MANIFEST_ABS = resolve(REPO_ROOT, AGENTS_MANIFEST_PATH);

function grokOnPath(): boolean {
  try {
    const result = Bun.spawnSync(["which", "grok"]);
    return result.exitCode === 0;
  } catch {
    return false;
  }
}

function countSoleurProjectAgents(inspectOutput: string): number {
  const lines = inspectOutput.split("\n");
  let inAgents = false;
  let count = 0;
  for (const line of lines) {
    if (/^\s+Agents \(\d+\)/.test(line)) {
      inAgents = true;
      continue;
    }
    if (inAgents && /^\s+Plugins \(\d+\)/.test(line)) {
      break;
    }
    // Compat stubs register under hyphen form (Grok spawn key = filename stem).
    // Accept colon form too for older stubs during transition.
    if (inAgents && /soleur[-:][^\s]+\s+project/.test(line)) {
      count++;
    }
  }
  return count;
}

describe("grok-agent-discoverability", () => {
  test("manifest exists and matches registry count", () => {
    expect(existsSync(MANIFEST_ABS)).toBe(true);
    const manifest = JSON.parse(readFileSync(MANIFEST_ABS, "utf-8"));
    expect(manifest.count).toBe(EXPECTED_SOLEUR_AGENT_COUNT);
    expect(manifest.agents.length).toBe(EXPECTED_SOLEUR_AGENT_COUNT);
  });

  test("buildAgentsManifest matches committed manifest", () => {
    const onDisk = JSON.parse(readFileSync(MANIFEST_ABS, "utf-8"));
    const fresh = buildAgentsManifest();
    expect(fresh.count).toBe(onDisk.count);
    expect(fresh.agents.map((a) => a.id)).toEqual(
      onDisk.agents.map((a: { id: string }) => a.id),
    );
  });

  // ADR-226 amendment 2026-09-24 (#8317): agent descriptions name siblings by canonical
  // registry id; the stub generator renders those ids as Grok spawn keys. The manifest keeps
  // the canonical form. Both halves are asserted, so neither a stub that leaks the colon form
  // nor a generator that also rewrote the manifest passes.
  test("stub descriptions render registry agent ids as Grok spawn keys; the manifest keeps them canonical", () => {
    type Entry = { id: string; description: string };
    const agents: Entry[] = JSON.parse(readFileSync(MANIFEST_ABS, "utf-8")).agents;
    const ids = agents.map((a) => a.id);
    const idPattern = /soleur:[a-z0-9-]+(?::[a-z0-9-]+)+/g;
    const leaked: string[] = [];
    let rendered = 0;
    for (const a of agents) {
      const stub = readFileSync(resolve(REPO_ROOT, ".grok/agents", agentIdToCompatFilename(a.id)), "utf-8");
      const stubDescription = stub.split("\n").find((l) => l.startsWith("description: ")) ?? "";
      for (const m of stubDescription.match(idPattern) ?? []) {
        if (ids.includes(m)) leaked.push(`${a.id}: ${m}`);
      }
      for (const m of a.description.match(idPattern) ?? []) {
        if (!ids.includes(m)) continue;
        expect(stubDescription).toContain(agentIdToGrokSubagentType(m));
        rendered++;
      }
    }
    expect(leaked).toEqual([]);
    // Measured 2026-09-24: 50 agents name at least one sibling in their description.
    expect(rendered).toBeGreaterThanOrEqual(50);
  });

  test("grok inspect lists soleur project agents when grok is available", async () => {
    if (!grokOnPath()) {
      console.log("SKIP: grok not on PATH — local-only discoverability gate");
      return;
    }

    const result = await $`grok inspect`.cwd(REPO_ROOT).quiet().nothrow();
    expect(result.exitCode).toBe(0);

    const output = result.stdout.toString();
    const count = countSoleurProjectAgents(output);
    expect(count).toBeGreaterThanOrEqual(EXPECTED_SOLEUR_AGENT_COUNT);

    // Hyphen form is the Grok spawn key; must appear in inspect Agents list.
    expect(output).toMatch(/soleur-engineering-review-security-sentinel/);
  }, 30_000);
});