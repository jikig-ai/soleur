import { describe, expect, test } from "bun:test";
import { mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "fs";
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
    } finally {
      rmSync(empty, { recursive: true, force: true });
    }

    const bin = mkdtempSync(join(tmpdir(), "soleur-cursor-path-"));
    try {
      writeFileSync(join(bin, "agent"), "#!/bin/sh\nexit 0\n", { mode: 0o755 });
      const present = Bun.spawnSync(["bash", join(repoRoot, "scripts/setup-cursor.sh")], {
        env: { ...process.env, PATH: `${bin}:/usr/bin:/bin` },
      });
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
