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

describe("Devin plugin package", () => {
  test("shares metadata and MCP servers with the canonical plugin", () => {
    const canonical = readJson(join(pluginRoot, ".claude-plugin/plugin.json"));
    const devin = readJson(join(pluginRoot, ".devin-plugin/plugin.json"));
    expect(devin.name).toBe(canonical.name);
    expect(devin.version).toBeUndefined();
    for (const server of Object.keys(canonical.mcpServers)) {
      expect(devin.mcpServers[server].url).toBe(canonical.mcpServers[server].url);
      expect(devin.mcpServers[server].transport).toBe("http");
    }
    expect(devin.skills).toEqual(["./skills", "./devin/skills"]);
    for (const path of devin.skills) expect(existsSync(resolve(pluginRoot, path))).toBe(true);
  });

  test("entry-point wrapper links stay inside the installed package and resolve", () => {
    for (const name of ["go", "help", "sync"]) {
      const directory = join(pluginRoot, "devin/skills", name);
      const source = readFileSync(join(directory, "SKILL.md"), "utf8");
      const targets = Array.from(source.matchAll(/\]\(([^)]+)\)/g), (match) => resolve(directory, match[1]));
      expect(targets).toEqual([join(pluginRoot, "devin/INSTRUCTIONS.md"), join(pluginRoot, "commands", name + ".md")]);
      for (const target of targets) expect(existsSync(target)).toBe(true);
    }
  });

  test("every go route uses the Devin adapter", () => {
    const environment = { DEVIN: "1" };
    for (const [label, skill] of Object.entries(GO_SKILL_ROUTES)) {
      const result = dispatchGoRoute(label, "test request", environment);
      expect(result.kind).toBe("skill");
      if (result.kind === "skill") expect(result.invocation.command).toBe(`/soleur:${skill} test request`);
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
      delete process.env.CODEX_THREAD_ID;
      process.env.DEVIN = "1";
      for (const agent of discoverAgentEntries()) {
        const result = spawnAgent(agent.id, "test request");
        expect(result.tool).toBe("run_subagent");
        expect(result.prompt).toContain(join(pluginRoot, agent.path));
      }
      expect(() => spawnAgent("missing-agent", "test")).toThrow("Unknown or ambiguous");
    } finally {
      for (const key of Object.keys(process.env)) if (!(key in saved)) delete process.env[key];
      Object.assign(process.env, saved);
    }
  });

  test("session context works from an installed path containing spaces", () => {
    const temporary = mkdtempSync(join(tmpdir(), "soleur devin "));
    try {
      const installed = join(temporary, "installed plugin");
      cpSync(join(pluginRoot, "devin"), join(installed, "devin"), { recursive: true });
      mkdirSync(join(installed, "hooks"));
      cpSync(join(pluginRoot, "hooks/devin-session-start.sh"), join(installed, "hooks/devin-session-start.sh"));
      const result = Bun.spawnSync(["bash", join(installed, "hooks/devin-session-start.sh")], {
        cwd: temporary,
        env: { ...process.env, DEVIN: "1" },
        stdin: Buffer.from("{}"),
      });
      expect(result.exitCode).toBe(0);
      const context = JSON.parse(result.stdout.toString()).hookSpecificOutput;
      expect(context.hookEventName).toBe("SessionStart");
      expect(context.additionalContext).toContain(installed);
      expect(context.additionalContext).toContain("/soleur:go");
      expect(context.additionalContext).toContain("run_subagent");
    } finally {
      rmSync(temporary, { recursive: true, force: true });
    }
  });

  test("shared bootstrap stays silent outside Devin", () => {
    const environment = { ...process.env };
    delete environment.DEVIN;
    delete environment.DEVIN_HOME;
    delete environment.DEVIN_PROJECT_DIR;
    delete environment.DEVIN_PLUGIN_ROOT;
    const result = Bun.spawnSync(["bash", join(pluginRoot, "hooks/devin-session-start.sh")], { env: environment });
    expect(result.exitCode).toBe(0);
    expect(result.stdout.toString()).toBe("");
  });
});
