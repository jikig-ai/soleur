import { existsSync, mkdirSync, symlinkSync, writeFileSync } from "fs";
import { join } from "path";
import { execFileSync } from "child_process";
import { createChildLogger } from "./logger";

const log = createChildLogger("workspace");

function getWorkspacesRoot(): string {
  return process.env.WORKSPACES_ROOT || "/workspaces";
}

function getPluginPath(): string {
  return process.env.SOLEUR_PLUGIN_PATH || "/app/shared/plugins/soleur";
}

const KNOWLEDGE_BASE_DIRS = [
  "brainstorms",
  "specs",
  "plans",
  "learnings",
] as const;

const DEFAULT_SETTINGS = {
  permissions: {
    allow: [] as string[],
  },
  sandbox: {
    enabled: true,
  },
};

/**
 * Provisions a workspace directory for a new user.
 *
 * Creates the directory structure, symlinks the Soleur plugin,
 * initializes a git repo, and writes default Claude settings.
 *
 * @returns The absolute path to the provisioned workspace.
 */
export async function provisionWorkspace(userId: string): Promise<string> {
  const workspacePath = join(getWorkspacesRoot(), userId);

  // 1. Create workspace root (skip if exists)
  ensureDir(workspacePath);

  // 2. Create knowledge-base subdirectories
  const kbRoot = join(workspacePath, "knowledge-base");
  ensureDir(kbRoot);
  const projectDir = join(kbRoot, "project");
  ensureDir(projectDir);
  for (const sub of KNOWLEDGE_BASE_DIRS) {
    ensureDir(join(projectDir, sub));
  }

  // 3. Create .claude directory and settings
  const claudeDir = join(workspacePath, ".claude");
  ensureDir(claudeDir);
  writeFileSync(
    join(claudeDir, "settings.json"),
    JSON.stringify(DEFAULT_SETTINGS, null, 2) + "\n",
  );

  // 4. Symlink plugins/soleur -> shared plugin path
  const pluginsDir = join(workspacePath, "plugins");
  ensureDir(pluginsDir);
  const symlinkTarget = join(pluginsDir, "soleur");
  if (!existsSync(symlinkTarget)) {
    try {
      symlinkSync(getPluginPath(), symlinkTarget);
    } catch (err) {
      log.warn({ err, userId }, "Failed to symlink plugin");
    }
  }

  // 5. Initialize git repo (execFileSync avoids shell injection)
  try {
    execFileSync("git", ["init"], { cwd: workspacePath, stdio: "pipe" });
    execFileSync("git", ["add", "."], { cwd: workspacePath, stdio: "pipe" });
    execFileSync("git", ["commit", "-m", "Initial workspace"], {
      cwd: workspacePath,
      stdio: "pipe",
    });
  } catch (err) {
    log.warn({ err, userId }, "Git init failed");
  }

  return workspacePath;
}

function ensureDir(dirPath: string): void {
  if (!existsSync(dirPath)) {
    mkdirSync(dirPath, { recursive: true });
  }
}
