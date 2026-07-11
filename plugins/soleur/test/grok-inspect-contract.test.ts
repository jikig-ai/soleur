import { describe, test, expect } from "bun:test";
import { readFileSync } from "fs";
import { resolve } from "path";
import { $ } from "bun";
import {
  parseGrokInspectOutput,
  validateGrokInspectParsed,
  validateStaticArtifacts,
  countSoleurSkillsOnDisk,
  MIN_SOLEUR_PLUGIN_SKILL_COUNT,
  REPO_ROOT,
} from "../lib/grok-inspect-contract";
import { EXPECTED_SOLEUR_AGENT_COUNT } from "../lib/agent-registry";

const FIXTURE = readFileSync(
  resolve(import.meta.dir, "fixtures/grok-inspect/minimal-contract.txt"),
  "utf-8",
);

function grokOnPath(): boolean {
  try {
    return Bun.spawnSync(["which", "grok"]).exitCode === 0;
  } catch {
    return false;
  }
}

describe("grok-inspect-contract parser", () => {
  test("parses minimal fixture for soleur plugin + sample agent rows", () => {
    const parsed = parseGrokInspectOutput(FIXTURE);
    expect(parsed.soleurPluginListed).toBe(true);
    expect(parsed.soleurPluginSkillCount).toBe(94);
    expect(parsed.soleurProjectAgentCount).toBe(2);
    // Threshold validation runs against live inspect + static artifacts, not this snippet.
    expect(validateGrokInspectParsed({
      ...parsed,
      soleurProjectAgentCount: EXPECTED_SOLEUR_AGENT_COUNT,
    })).toEqual([]);
  });

  test("flags missing soleur plugin", () => {
    const parsed = parseGrokInspectOutput("  Plugins (1)\n  └ other (user) 1 skills\n");
    expect(parsed.soleurPluginListed).toBe(false);
    expect(validateGrokInspectParsed(parsed).length).toBeGreaterThan(0);
  });
});

describe("grok-inspect-contract static artifacts", () => {
  test("manifest, stubs, skills, and config meet thresholds", () => {
    expect(validateStaticArtifacts()).toEqual([]);
    expect(countSoleurSkillsOnDisk()).toBeGreaterThanOrEqual(MIN_SOLEUR_PLUGIN_SKILL_COUNT);
  });

  test("sync-grok-agent-compat --check passes", async () => {
    const result = await $`bun run scripts/sync-grok-agent-compat.ts --check`
      .cwd(resolve(REPO_ROOT, "plugins/soleur"))
      .quiet()
      .nothrow();
    expect(result.exitCode).toBe(0);
  });
});

describe("grok-inspect-contract live inspect", () => {
  test("grok inspect satisfies contract when grok is on PATH", async () => {
    if (!grokOnPath()) {
      console.log("SKIP: grok not on PATH — live inspect gate deferred to grok-fidelity CI job");
      return;
    }

    const result = await $`grok inspect`.cwd(REPO_ROOT).quiet().nothrow();
    expect(result.exitCode).toBe(0);

    const parsed = parseGrokInspectOutput(result.stdout.toString());
    const violations = validateGrokInspectParsed(parsed);
    expect(violations).toEqual([]);
    expect(parsed.soleurProjectAgentCount).toBeGreaterThanOrEqual(EXPECTED_SOLEUR_AGENT_COUNT);
    expect(parsed.soleurPluginSkillCount).toBeGreaterThanOrEqual(MIN_SOLEUR_PLUGIN_SKILL_COUNT);
  }, 60_000);
});