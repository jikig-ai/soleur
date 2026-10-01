import { describe, expect, test } from "bun:test";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from "fs";
import { join, resolve } from "path";
import { tmpdir } from "os";
import { discoverAgentEntries } from "../lib/agent-registry";
import { spawnAgent } from "../lib/harness";
import { dispatchGoRoute, GO_SKILL_ROUTES } from "../lib/go-routing";

const pluginRoot = resolve(import.meta.dir, "..");
const repoRoot = resolve(pluginRoot, "../..");
const readJson = (path: string) => JSON.parse(readFileSync(path, "utf8"));

describe("Codex plugin package", () => {
  test("shares metadata and MCP servers with the canonical plugin", () => {
    const canonical = readJson(join(pluginRoot, ".claude-plugin/plugin.json"));
    const codex = readJson(join(pluginRoot, ".codex-plugin/plugin.json"));
    expect(codex.name).toBe(canonical.name);
    expect(codex.mcpServers).toEqual(canonical.mcpServers);
    expect(codex.version).toBeUndefined();
    expect(codex.skills).toEqual(["./skills", "./codex/skills"]);
    for (const path of codex.skills) expect(existsSync(resolve(pluginRoot, path))).toBe(true);
  });

  test("marketplace points to the same distributable plugin subtree", () => {
    const marketplace = readJson(join(repoRoot, ".agents/plugins/marketplace.json"));
    expect(marketplace.name).toBe("soleur");
    expect(resolve(repoRoot, marketplace.plugins[0].source.path)).toBe(pluginRoot);
    expect(marketplace.plugins[0].policy.installation).toBe("AVAILABLE");
  });

  test("entry-point wrapper links stay inside the installed package and resolve", () => {
    for (const name of ["go", "help", "sync"]) {
      const directory = join(pluginRoot, "codex/skills", name);
      const source = readFileSync(join(directory, "SKILL.md"), "utf8");
      const targets = Array.from(source.matchAll(/\]\(([^)]+)\)/g), (match) => resolve(directory, match[1]));
      expect(targets).toEqual([join(pluginRoot, "codex/INSTRUCTIONS.md"), join(pluginRoot, "commands", name + ".md")]);
      for (const target of targets) expect(existsSync(target)).toBe(true);
    }
  });

  test("every go route uses the Codex adapter", () => {
    const environment = { CODEX_THREAD_ID: "test-thread" };
    for (const [label, skill] of Object.entries(GO_SKILL_ROUTES)) {
      const result = dispatchGoRoute(label, "test request", environment);
      expect(result.kind).toBe("skill");
      if (result.kind === "skill") expect(result.invocation.command).toBe("$soleur:" + skill);
    }
    const result = dispatchGoRoute("legal-threshold", "test request", environment);
    expect(result.kind).toBe("agent");
    if (result.kind === "agent") expect(result.spawn.agent).toBe("soleur:legal:clo");
  });

  test("all canonical agent IDs resolve without generated model pins", () => {
    const saved = { ...process.env };
    try {
      delete process.env.CLAUDECODE;
      for (const key of Object.keys(process.env)) if (key.startsWith("GROK_")) delete process.env[key];
      process.env.CODEX_THREAD_ID = "test-thread";
      for (const agent of discoverAgentEntries()) {
        const result = spawnAgent(agent.id, "test request");
        expect(result.tool).toBe("spawn_agent");
        expect(result.prompt).toContain(join(pluginRoot, agent.path));
      }
      expect(() => spawnAgent("missing-agent", "test")).toThrow("Unknown or ambiguous");
    } finally {
      for (const key of Object.keys(process.env)) if (!(key in saved)) delete process.env[key];
      Object.assign(process.env, saved);
    }
  });

  test("session context works from an installed path containing spaces", () => {
    const temporary = mkdtempSync(join(tmpdir(), "soleur codex "));
    try {
      const installed = join(temporary, "installed plugin");
      cpSync(join(pluginRoot, "codex"), join(installed, "codex"), { recursive: true });
      mkdirSync(join(installed, "hooks"));
      cpSync(join(pluginRoot, "hooks/codex-session-start.sh"), join(installed, "hooks/codex-session-start.sh"));
      const result = Bun.spawnSync(["bash", join(installed, "hooks/codex-session-start.sh")], {
        cwd: temporary,
        env: { ...process.env, CODEX_THREAD_ID: "test-thread" },
        stdin: Buffer.from("{}"),
      });
      expect(result.exitCode).toBe(0);
      const context = JSON.parse(result.stdout.toString()).hookSpecificOutput;
      expect(context.hookEventName).toBe("SessionStart");
      expect(context.additionalContext).toContain(installed);
      expect(context.additionalContext).toContain("$soleur:go");
      expect(context.additionalContext).toContain("spawn_agent");
    } finally {
      rmSync(temporary, { recursive: true, force: true });
    }
  });

  test("shared bootstrap stays silent outside Codex", () => {
    const environment = { ...process.env };
    delete environment.CODEX_THREAD_ID;
    delete environment.PLUGIN_ROOT;
    const result = Bun.spawnSync(["bash", join(pluginRoot, "hooks/codex-session-start.sh")], { env: environment });
    expect(result.exitCode).toBe(0);
    expect(result.stdout.toString()).toBe("");
  });
});
