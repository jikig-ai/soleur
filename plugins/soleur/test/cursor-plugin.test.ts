import { describe, expect, test } from "bun:test";
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "fs";
import { join, resolve } from "path";
import { tmpdir } from "os";

const pluginRoot = resolve(import.meta.dir, "..");
const repoRoot = resolve(pluginRoot, "../..");
const readJson = (path: string) => JSON.parse(readFileSync(path, "utf8"));

describe("Cursor CLI plugin package", () => {
  test("manifest points at the generated tree and an empty hooks file", () => {
    const manifest = readJson(join(pluginRoot, ".cursor-plugin/plugin.json"));
    expect(manifest.skills).toBe("./cursor/skills");
    expect(manifest.agents).toBe("./cursor/agents");
    expect(manifest.commands).toBe("./cursor/commands");
    expect(manifest.hooks).toBe("./cursor/hooks-empty.json");
    expect(manifest.mcpServers).toBeUndefined();
    expect(readJson(join(pluginRoot, "cursor/hooks-empty.json"))).toEqual({ hooks: {} });
    expect(readFileSync(join(pluginRoot, "hooks/hooks.json"), "utf8")).not.toBe(
      readFileSync(join(pluginRoot, "cursor/hooks-empty.json"), "utf8"),
    );
    const instructions = readFileSync(join(pluginRoot, "cursor/INSTRUCTIONS.md"), "utf8");
    expect(instructions).toContain("registers no hook events");
    expect(instructions).toContain("does not classify the session as `cursor`");
    expect(instructions).toContain("`.claude/settings.json` is unmeasured");
    expect(instructions).not.toContain("## Tools");
    expect(instructions).toContain("If a canonical file tells you to call those tools, stop.");
    expect(instructions).toContain(
      "When `/go` or a stub names a skill, Read `plugins/soleur/skills/<name>/SKILL.md` and follow that file.",
    );
    expect(instructions).not.toContain("Do not follow a line that names");
  });

  test("go.md cursor spellings stay inside the three harness-forms regions", () => {
    const text = readFileSync(join(pluginRoot, "commands/go.md"), "utf8");
    const regions = [...text.matchAll(/<!-- harness-forms:start -->([\s\S]*?)<!-- harness-forms:end -->/g)].map((m) => m[1] ?? "");
    expect(regions).toHaveLength(3);
    const joined = regions.join("\n");
    for (const phrase of [
      "/go",
      "/sync",
      "/soleur-plan",
      "/soleur-help",
      "/soleur-review",
      "/plan",
      "/help",
      "/review",
      "/shell",
      "does not run hooks",
      "does not classify the session as cursor",
      "Skill tool",
      "Task tool",
      "run_subagent",
      "AwaitShell",
    ]) {
      expect(joined).toContain(phrase);
    }
    expect(text).toContain("If harness is unknown and Skill/slash tools are unavailable, STOP");
    expect(text).not.toContain("cursor --plugin-dir");
    expect(text).toContain("On Grok Build only. Map `soleur:<skill>`");
    expect(text).toContain("**Cursor CLI:** Read `plugins/soleur/skills/<name>/SKILL.md`");
    expect(text).toContain("Every other skill uses the prefixed form, including");
    expect(text).toContain("The unknown-harness stop below is a different case.");
  });

  test("help.md cursor column names the prefixed skills and the built-ins not to type", () => {
    const help = readFileSync(join(pluginRoot, "commands/help.md"), "utf8");
    const grok = help.slice(help.indexOf("### Grok Build"), help.indexOf("### Cursor CLI"));
    expect(grok).toContain("/help                 This help listing");
    expect(grok).not.toContain("/soleur-help");
    const cursorStart = help.indexOf("### Cursor CLI");
    const fence = help.indexOf("```text", cursorStart);
    const fenceEnd = help.indexOf("```", fence + 7);
    const cursor = help.slice(fence, fenceEnd);
    expect(cursor).toContain("/go");
    expect(cursor).toContain("/sync");
    expect(cursor).toContain("/soleur-help");
    expect(cursor).toContain("/soleur-plan");
    expect(cursor).toContain("/soleur-review");
    expect(cursor).toContain("Do not type Cursor's built-ins /plan, /help, /review, or /shell for Soleur.");
    expect(cursor).not.toMatch(/^ {2}\/plan /m);
    expect(cursor).not.toMatch(/^ {2}\/help /m);
    expect(cursor).not.toMatch(/^ {2}\/review /m);
    expect(cursor).not.toMatch(/^ {2}\/shell /m);
    expect(cursor).toContain("does not classify the session as cursor");
  });

  test("commands directory keeps the default command scan from registering bare names", () => {
    const names = readdirSync(join(pluginRoot, "cursor/commands"));
    expect(names).toContain(".gitkeep");
    const forbidden = names.filter((name) => /\.(md|mdc|markdown|txt)$/.test(name));
    expect(forbidden).toEqual([]);
  });

  test("repo marketplace lists this plugin and is not a cursor.com submission", () => {
    const marketplace = readJson(join(repoRoot, ".cursor-plugin/marketplace.json"));
    expect(marketplace.name).toBe("soleur");
    expect(marketplace.owner.name).toBe("jikig-ai");
    expect(marketplace.plugins).toEqual([{ name: "soleur", source: "plugins/soleur" }]);
  });

  test("setup prints the limit and refuses to run when agent is missing", () => {
    const script = readFileSync(join(repoRoot, "scripts/setup-cursor.sh"), "utf8");
    for (const banned of ["readlink -f", "timeout", "sed -i", "date -d", "marketplace add", "plugins/local"]) {
      expect(script).not.toContain(banned);
    }

    const empty = mkdtempSync(join(tmpdir(), "soleur-cursor-nopath-"));
    try {
      for (const tool of ["bash", "dirname"]) symlinkSync(`/usr/bin/${tool}`, join(empty, tool));
      const missing = Bun.spawnSync(["bash", join(repoRoot, "scripts/setup-cursor.sh")], {
        env: { ...process.env, PATH: empty },
      });
      expect(missing.exitCode).not.toBe(0);
      expect(missing.stdout.toString()).toContain("agent is not on PATH");
      expect(missing.stdout.toString()).not.toContain("agent --plugin-dir");
    } finally {
      rmSync(empty, { recursive: true, force: true });
    }

    const bin = mkdtempSync(join(tmpdir(), "soleur-cursor-path-"));
    try {
      const marker = join(bin, "agent-ran");
      writeFileSync(join(bin, "agent"), `#!/bin/sh\ntouch '${marker}'\nexit 99\n`, { mode: 0o755 });
      const present = Bun.spawnSync(["bash", join(repoRoot, "scripts/setup-cursor.sh")], {
        env: { ...process.env, PATH: `${bin}:/usr/bin:/bin` },
      });
      expect(existsSync(marker)).toBe(false);
      expect(present.exitCode).toBe(0);
      const stdout = present.stdout.toString();
      expect(stdout).toContain(`agent --plugin-dir ${pluginRoot}`);
      expect(stdout).toContain("does not classify the session as cursor");
      expect(stdout).toContain("does not run hooks");
      expect(stdout).not.toContain("marketplace");
    } finally {
      rmSync(bin, { recursive: true, force: true });
    }
  });
});
