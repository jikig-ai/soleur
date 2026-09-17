import { Glob } from "bun";
import { parse as parseYaml } from "yaml";
import { resolve, basename, dirname } from "path";
import { readFileSync } from "fs";

const PLUGIN_ROOT = resolve(import.meta.dir, "..");

// Agents recurse into subdirectories (loader behavior)
export function discoverAgents(): string[] {
  return Array.from(new Glob("agents/**/*.md").scanSync(PLUGIN_ROOT)).filter(
    (f) => !basename(f).startsWith("README") && !f.includes("/references/"),
  );
}

// Commands are flat under commands/
export function discoverCommands(): string[] {
  return Array.from(new Glob("commands/*.md").scanSync(PLUGIN_ROOT));
}

// A manifest may spell one directory several ways ("./skills", "skills",
// "skills/"). Two DECLARATIONS of one directory are not two roots, so they must
// compare equal or clause (a) below reports a directory colliding with itself.
export function normalizeSkillRoot(root: string): string {
  return root.replace(/^\.\//, "").replace(/\/+$/, "");
}

// Skills are one level only (loader does NOT recurse). `root` is plugin-relative.
export function discoverSkillsIn(root: string): string[] {
  const clean = normalizeSkillRoot(root);
  return Array.from(new Glob(`${clean}/*/SKILL.md`).scanSync(PLUGIN_ROOT));
}

export function discoverSkills(): string[] {
  return discoverSkillsIn("skills");
}

// Claude Code hides a skill from the `/` menu when `user-invocable` is false,
// while leaving it invocable by the model. Absent key means true (documented
// default), so only an explicit `false` suppresses the menu row.
export function isUserInvocable(relativePath: string): boolean {
  return parseComponent(relativePath).frontmatter["user-invocable"] !== false;
}

export interface SkillEntry {
  name: string;
  userInvocable: boolean;
}

export interface SkillRootInput {
  root: string;
  skills: SkillEntry[];
}

export interface CollisionReport {
  // clause (a): one skill name contributed by more than one distinct root
  duplicateSkillNames: string[];
  // clause (b): a user-invocable skill sharing a name with a command stem
  commandCollisions: string[];
}

// Pure. Both collision classes that put two rows under one `/` name.
export function collidingNames(input: {
  commandNames: string[];
  skillRoots: SkillRootInput[];
}): CollisionReport {
  // Roots are keyed by their NORMALIZED path. There is deliberately no
  // `if (seen.has(key)) continue` here: it would be dead code. Duplicate
  // spellings of one directory collapse anyway, because clause (a) accumulates
  // each name into a Set of normalized roots (so three spellings of "skills"
  // yield one member) and clause (b) dedupes its result through a Set. A review
  // measured that deleting such a guard left the suite byte-identical green, and
  // a fixture comment claimed it was load-bearing when it was not.
  const roots: SkillRootInput[] = input.skillRoots.map((r) => ({
    ...r,
    root: normalizeSkillRoot(r.root),
  }));

  const nameToRoots = new Map<string, Set<string>>();
  for (const r of roots) {
    for (const s of r.skills) {
      const at = nameToRoots.get(s.name) ?? new Set<string>();
      at.add(r.root);
      nameToRoots.set(s.name, at);
    }
  }
  const duplicateSkillNames = [...nameToRoots.entries()]
    .filter(([, at]) => at.size > 1)
    .map(([name]) => name)
    .sort();

  // A non-user-invocable skill renders no `/` row, so it cannot duplicate the
  // command's row. That exemption is precisely what this guard protects.
  const commands = new Set(input.commandNames);
  const commandCollisions = [
    ...new Set(
      roots.flatMap((r) =>
        r.skills
          .filter((s) => s.userInvocable && commands.has(s.name))
          .map((s) => s.name),
      ),
    ),
  ].sort();

  return { duplicateSkillNames, commandCollisions };
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

// Applying an acknowledgement list to a collision report. Extracted so the
// FILTER is testable, not just the set it reads: a review neutered the inline
// filter to `() => false` — making clause (a) incapable of reporting anything,
// for any manifest, forever — and every suite stayed green, because the only
// assertion inspected `ACKED_CROSS_ROOT_DUPES`'s membership rather than what the
// filter did with it.
export function unackedDuplicates(
  duplicateSkillNames: string[],
  acked: ReadonlySet<string>,
): string[] {
  return duplicateSkillNames.filter((n) => !acked.has(n));
}
