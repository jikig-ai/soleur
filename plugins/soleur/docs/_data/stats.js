import { readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));

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
  const agentsDir = join(__dirname, "..", "..", "agents");
  const skillsDir = join(__dirname, "..", "..", "skills");
  const commandsDir = join(__dirname, "..", "..", "commands");

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

  // Commands: count .md files in commands/
  const commands = readdirSync(commandsDir).filter((f) =>
    f.endsWith(".md")
  ).length;

  return { agents, skills, commands, departments };
}
