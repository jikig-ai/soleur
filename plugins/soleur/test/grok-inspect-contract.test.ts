import { describe, test, expect } from "bun:test";
import { mkdtempSync, readFileSync, rmSync } from "fs";
import { join, resolve } from "path";
import { tmpdir } from "os";
import { $ } from "bun";
import {
  parseGrokInspectOutput,
  validateGrokInspectParsed,
  validateStaticArtifacts,
  validateGrokEntryCommandShims,
  validateGrokInspectJsonEntryCommands,
  ensureGrokFolderTrusted,
  countSoleurSkillsOnDisk,
  MIN_SOLEUR_PLUGIN_SKILL_COUNT,
  GROK_ENTRY_COMMANDS,
  REPO_ROOT,
  type GrokInspectJson,
} from "../lib/grok-inspect-contract";
import { EXPECTED_SOLEUR_AGENT_COUNT } from "../lib/agent-registry";

const FIXTURE = readFileSync(
  resolve(import.meta.dir, "fixtures/grok-inspect/minimal-contract.txt"),
  "utf-8",
);

const ENTRY_COMMANDS_JSON = JSON.parse(
  readFileSync(resolve(import.meta.dir, "fixtures/grok-inspect/entry-commands.json"), "utf-8"),
) as GrokInspectJson;

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

  // Exact membership, not a floor: shrinking this set without deleting the
  // matching shim (or adding a shim without this name) is the drift this pin
  // exists to make visible. Same shape as ACKED_CROSS_ROOT_DUPES.
  test("Grok entry-command shims are exactly go, help, and sync", () => {
    expect([...GROK_ENTRY_COMMANDS]).toEqual(["go", "help", "sync"]);
    expect(validateGrokEntryCommandShims()).toEqual([]);
  });

  test("sync-grok-agent-compat --check passes", async () => {
    const result = await $`bun run scripts/sync-grok-agent-compat.ts --check`
      .cwd(resolve(REPO_ROOT, "plugins/soleur"))
      .quiet()
      .nothrow();
    expect(result.exitCode).toBe(0);
  });
});

describe("grok-inspect-contract JSON entry commands", () => {
  test("synthesized fixture with .grok/commands shims passes", () => {
    expect(validateGrokInspectJsonEntryCommands(ENTRY_COMMANDS_JSON)).toEqual([]);
  });

  test("a user-invocable plugin skill named go does not satisfy the Grok slash row", () => {
    const json: GrokInspectJson = {
      skills: [
        {
          name: "go",
          userInvocable: true,
          source: {
            type: "plugin",
            path: "/repo/.grok/plugins/soleur/skills/go/SKILL.md",
          },
        },
        {
          name: "help",
          userInvocable: true,
          source: { type: "project", path: "/repo/.grok/commands/help.md" },
        },
        {
          name: "sync",
          userInvocable: true,
          source: { type: "project", path: "/repo/.grok/commands/sync.md" },
        },
      ],
    };
    const violations = validateGrokInspectJsonEntryCommands(json);
    expect(violations.some((v) => v.includes("commands/go.md"))).toBe(true);
  });

  test("hidden plugin skill plus missing shim is the pre-fix Grok state", () => {
    const json: GrokInspectJson = {
      skills: [
        {
          name: "go",
          userInvocable: false,
          source: {
            type: "plugin",
            path: "/repo/.grok/plugins/soleur/skills/go/SKILL.md",
          },
        },
      ],
    };
    const violations = validateGrokInspectJsonEntryCommands(json);
    expect(violations.length).toBe(GROK_ENTRY_COMMANDS.length);
    expect(violations.some((v) => v.includes("commands/go.md"))).toBe(true);
  });

  test("a colliding /go row fails even when the shim path is present", () => {
    const json: GrokInspectJson = {
      skills: ENTRY_COMMANDS_JSON.skills?.map((s) =>
        s.name === "go" && s.userInvocable
          ? { ...s, collidesWith: "go", invocableAs: "local:go" }
          : s,
      ),
    };
    const violations = validateGrokInspectJsonEntryCommands(json);
    expect(violations.some((v) => v.includes("/go must stay the bare slash"))).toBe(true);
  });
});

describe("ensureGrokFolderTrusted", () => {
  test("writes a trusted_folders.toml table and is idempotent", () => {
    const home = mkdtempSync(join(tmpdir(), "grok-trust-"));
    try {
      const file = ensureGrokFolderTrusted("/ci/checkout", home);
      const first = readFileSync(file, "utf-8");
      expect(first).toContain('[folders."/ci/checkout"]');
      expect(first).toContain("trusted = true");
      ensureGrokFolderTrusted("/ci/checkout", home);
      expect(readFileSync(file, "utf-8")).toBe(first);
    } finally {
      rmSync(home, { recursive: true, force: true });
    }
  });
});

describe("grok-inspect-contract live inspect", () => {
  test("grok inspect satisfies contract when grok is on PATH", async () => {
    if (!grokOnPath()) {
      console.log("SKIP: grok not on PATH — live inspect gate deferred to grok-fidelity CI job");
      return;
    }

    ensureGrokFolderTrusted(REPO_ROOT);
    const result = await $`grok inspect`.cwd(REPO_ROOT).quiet().nothrow();
    expect(result.exitCode).toBe(0);

    const parsed = parseGrokInspectOutput(result.stdout.toString());
    const violations = validateGrokInspectParsed(parsed);
    expect(violations).toEqual([]);
    expect(parsed.soleurProjectAgentCount).toBeGreaterThanOrEqual(EXPECTED_SOLEUR_AGENT_COUNT);
    expect(parsed.soleurPluginSkillCount).toBeGreaterThanOrEqual(MIN_SOLEUR_PLUGIN_SKILL_COUNT);
  }, 60_000);

  test("grok inspect --json exposes user-invocable /go from .grok/commands", async () => {
    if (!grokOnPath()) {
      console.log("SKIP: grok not on PATH — live inspect gate deferred to grok-fidelity CI job");
      return;
    }

    ensureGrokFolderTrusted(REPO_ROOT);
    const result = await $`grok inspect --json`.cwd(REPO_ROOT).quiet().nothrow();
    expect(result.exitCode).toBe(0);
    const json = JSON.parse(result.stdout.toString()) as GrokInspectJson;
    expect(validateGrokInspectJsonEntryCommands(json)).toEqual([]);
  }, 60_000);
});