import { Glob } from "bun";
import { parse as parseYaml } from "yaml";
import { resolve, basename, dirname } from "path";
import { readFileSync } from "fs";

const PLUGIN_ROOT = resolve(import.meta.dir, "..");

// Agents recurse into subdirectories (loader behavior)
export function discoverAgents(): string[] {
  return Array.from(new Glob("agents/**/*.md").scanSync(PLUGIN_ROOT)).filter(
    (f) => !basename(f).startsWith("README"),
  );
}

// Commands are flat under commands/soleur/
export function discoverCommands(): string[] {
  return Array.from(new Glob("commands/soleur/*.md").scanSync(PLUGIN_ROOT));
}

// Skills are one level only (loader does NOT recurse)
export function discoverSkills(): string[] {
  return Array.from(new Glob("skills/*/SKILL.md").scanSync(PLUGIN_ROOT));
}

interface ParsedComponent {
  frontmatter: Record<string, unknown>;
  body: string;
}

export function parseComponent(relativePath: string): ParsedComponent {
  const raw = readFileSync(resolve(PLUGIN_ROOT, relativePath), "utf-8");
  const match = raw.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);

  if (!match) {
    return { frontmatter: {}, body: raw };
  }

  return {
    frontmatter: parseYaml(match[1]) ?? {},
    body: match[2],
  };
}

// kebab-case name: agents/commands use basename, skills use directory name
export function getComponentName(
  relativePath: string,
  type: "agent" | "command" | "skill",
): string {
  if (type === "skill") return basename(dirname(relativePath));
  return basename(relativePath, ".md");
}

export { PLUGIN_ROOT };
