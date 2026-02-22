import { readdirSync, statSync } from "node:fs";
import { join, resolve } from "node:path";

function countMdFilesRecursive(dir) {
  let count = 0;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      count += countMdFilesRecursive(join(dir, entry.name));
    } else if (entry.name.endsWith(".md")) {
      count++;
    }
  }
  return count;
}

export default function () {
  const agentsDir = resolve("plugins/soleur/agents");
  const skillsDir = resolve("plugins/soleur/skills");
  const commandsDir = resolve("plugins/soleur/commands/soleur");

  const agents = countMdFilesRecursive(agentsDir);

  // Departments: count non-empty top-level directories under agents/
  const departments = readdirSync(agentsDir, { withFileTypes: true })
    .filter(
      (e) => e.isDirectory() && countMdFilesRecursive(join(agentsDir, e.name)) > 0
    ).length;

  // Skills: count directories that contain SKILL.md (flat, no recursion)
  let skills = 0;
  for (const entry of readdirSync(skillsDir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      try {
        statSync(join(skillsDir, entry.name, "SKILL.md"));
        skills++;
      } catch {
        // No SKILL.md in this directory
      }
    }
  }

  // Commands: count .md files in commands/soleur/
  const commands = readdirSync(commandsDir).filter((f) =>
    f.endsWith(".md")
  ).length;

  return { agents, skills, commands, departments };
}
