import { describe, expect, test } from "bun:test";
import { readdirSync, readFileSync } from "fs";
import { join, resolve } from "path";

const pluginRoot = resolve(import.meta.dir, "..");

function componentDir(value: unknown): string {
  if (typeof value !== "string" || !value.startsWith("./")) {
    throw new Error(`manifest component path is not a plugin-relative string: ${String(value)}`);
  }
  return join(pluginRoot, value.slice(2));
}

describe("Cursor loader proof", () => {
  test("the manifest's own directories register go and sync once", () => {
    const manifest = JSON.parse(readFileSync(join(pluginRoot, ".cursor-plugin/plugin.json"), "utf8")) as {
      skills?: unknown;
      commands?: unknown;
      hooks?: unknown;
    };
    expect(manifest.skills).toBe("./cursor/skills");
    expect(manifest.commands).toBe("./cursor/commands");
    expect(manifest.hooks).toBe("./cursor/hooks-empty.json");

    const skills = readdirSync(componentDir(manifest.skills));
    expect(skills).toContain("go");
    expect(skills).toContain("sync");
    expect(skills).toContain("soleur-help");
    expect(skills).toContain("soleur-plan");
    expect(skills).toContain("soleur-review");
    expect(skills).not.toContain("help");
    expect(skills).not.toContain("plan");
    expect(skills).not.toContain("review");
    expect(skills).not.toContain("soleur-go");
    expect(skills).not.toContain("soleur-sync");
    expect(skills.length).toBeGreaterThan(100);

    const commands = readdirSync(componentDir(manifest.commands));
    expect(commands).toContain(".gitkeep");
    expect(commands.filter((name) => /\.(md|mdc|markdown|txt)$/.test(name))).toEqual([]);
  });
});
