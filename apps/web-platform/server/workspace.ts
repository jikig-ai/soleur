import {
  existsSync,
  mkdirSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from "fs";
import { join, resolve } from "path";
import { execFileSync } from "child_process";
import { createChildLogger } from "./logger";
import { generateInstallationToken, randomCredentialPath } from "./github-app";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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
  if (!UUID_RE.test(userId)) {
    throw new Error(`Invalid userId format: ${userId}`);
  }
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

/**
 * Provisions a workspace by cloning an existing GitHub repository.
 *
 * Uses a temporary credential helper to authenticate the clone via
 * GitHub App installation token. After cloning, overlays the Soleur
 * plugin symlink, creates .claude/settings.json, and scaffolds
 * knowledge-base/ subdirectories if missing.
 *
 * @param userId         User ID (used for workspace path and credential helper naming)
 * @param repoUrl        HTTPS URL of the repo to clone
 * @param installationId GitHub App installation ID for token generation
 * @param userName       Git user.name for commits
 * @param userEmail      Git user.email for commits
 * @returns The absolute path to the provisioned workspace.
 */
export async function provisionWorkspaceWithRepo(
  userId: string,
  repoUrl: string,
  installationId: number,
  userName?: string,
  userEmail?: string,
): Promise<string> {
  if (!UUID_RE.test(userId)) {
    throw new Error(`Invalid userId format: ${userId}`);
  }

  const workspacePath = join(getWorkspacesRoot(), userId);

  // 1. Generate installation token for clone authentication
  let token: string;
  try {
    token = await generateInstallationToken(installationId);
  } catch (err) {
    throw new Error(`Token generation failed: ${(err as Error).message}`);
  }

  // 2. Write temporary credential helper (unpredictable path, outside sandbox)
  const helperPath = randomCredentialPath();
  try {
    writeFileSync(
      helperPath,
      `#!/bin/sh\necho "username=x-access-token"\necho "password=${token}"`,
      { mode: 0o700 },
    );
  } catch (err) {
    throw new Error(`Credential helper write failed: ${(err as Error).message}`);
  }

  try {
    // 3. Remove existing workspace if present (fresh clone)
    removeWorkspaceDir(workspacePath);

    // 4. Clone the repository (shallow for speed)
    try {
      execFileSync(
        "git",
        [
          "-c", `credential.helper=!${helperPath}`,
          "clone",
          "--depth", "1",
          repoUrl,
          workspacePath,
        ],
        { stdio: "pipe", timeout: 120_000 },
      );
    } catch (err) {
      const rawStderr = (err as { stderr?: Buffer })?.stderr?.toString() ?? "";
      // Strip internal paths to avoid leaking server filesystem layout
      const stderr = rawStderr.replace(/\/[^\s:]+/g, "<path>");
      throw new Error(`Git clone failed: ${stderr || (err as Error).message}`);
    }

    log.info({ userId, repoUrl }, "Repository cloned successfully");
  } finally {
    // 5. Clean up credential helper immediately
    try {
      unlinkSync(helperPath);
    } catch {
      // Best-effort cleanup
    }
  }

  // 6. Set git identity per workspace
  if (userName) {
    try {
      execFileSync("git", ["config", "user.name", userName], {
        cwd: workspacePath,
        stdio: "pipe",
      });
    } catch (err) {
      log.warn({ err, userId }, "Failed to set git user.name");
    }
  }
  if (userEmail) {
    try {
      execFileSync("git", ["config", "user.email", userEmail], {
        cwd: workspacePath,
        stdio: "pipe",
      });
    } catch (err) {
      log.warn({ err, userId }, "Failed to set git user.email");
    }
  }

  // 7. Overlay Soleur plugin symlink
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

  // 8. Create .claude directory and settings
  const claudeDir = join(workspacePath, ".claude");
  ensureDir(claudeDir);
  writeFileSync(
    join(claudeDir, "settings.json"),
    JSON.stringify(DEFAULT_SETTINGS, null, 2) + "\n",
  );

  // 9. Scaffold knowledge-base/ subdirectories if they don't exist in the clone
  const kbRoot = join(workspacePath, "knowledge-base");
  ensureDir(kbRoot);
  const projectDir = join(kbRoot, "project");
  ensureDir(projectDir);
  for (const sub of KNOWLEDGE_BASE_DIRS) {
    ensureDir(join(projectDir, sub));
  }

  return workspacePath;
}

/**
 * Deletes a user's workspace directory.
 *
 * Used during account deletion (GDPR Art. 17) to remove all local files.
 * Uses execFileSync to avoid shell injection via userId.
 */
export async function deleteWorkspace(userId: string): Promise<void> {
  if (!UUID_RE.test(userId)) {
    throw new Error(`Invalid userId format: ${userId}`);
  }
  const workspacePath = join(getWorkspacesRoot(), userId);

  if (existsSync(workspacePath)) {
    removeWorkspaceDir(workspacePath);
    log.info({ userId }, "Workspace deleted");
  }
}

/**
 * Removes a workspace directory, handling permission-denied errors from
 * root-owned files (created by bubblewrap sandbox UID remapping).
 *
 * Phase 1: Direct rm -rf (fast path for user-owned files).
 * Phase 2: chmod to fix restrictive permission bits, then find -delete
 *          which continues past individual permission errors.
 *
 * Throws with manual cleanup instructions if the directory cannot be
 * fully removed (e.g., root-owned files that require sudo).
 */
export function removeWorkspaceDir(workspacePath: string): void {
  const root = resolve(getWorkspacesRoot());
  const resolved = resolve(workspacePath);
  if (resolved === root || !resolved.startsWith(root + "/")) {
    throw new Error("Refusing to remove path outside workspace root");
  }

  if (!existsSync(workspacePath)) return;

  // Phase 1: Direct removal (works when all files owned by current user)
  try {
    execFileSync("rm", ["-rf", workspacePath], { stdio: "pipe" });
    return;
  } catch {
    log.warn({ workspacePath }, "Direct rm -rf failed, attempting partial cleanup");
  }

  // Phase 2: Fix permission bits on user-owned files, then delete individually.
  // chmod fixes restrictive modes (git pack 444, dirs 555) on files WE own.
  // find -delete continues past root-owned files instead of aborting.
  try {
    execFileSync("chmod", ["-R", "u+rwX", workspacePath], { stdio: "pipe" });
  } catch {
    // chmod may fail on root-owned files -- continue to find -delete
  }

  try {
    execFileSync("find", [workspacePath, "-mindepth", "1", "-delete"], {
      stdio: "pipe",
    });
    execFileSync("rmdir", [workspacePath], { stdio: "pipe" });
  } catch (err) {
    const stderr = (err as { stderr?: Buffer })?.stderr?.toString() ?? "";
    log.error({ workspacePath, stderr }, "Workspace cleanup failed");
    throw new Error(
      "Workspace cleanup failed. Some files may be owned by root. " +
        "Manual cleanup required: sudo rm -rf <workspace-path>",
    );
  }
}

function ensureDir(dirPath: string): void {
  if (!existsSync(dirPath)) {
    mkdirSync(dirPath, { recursive: true });
  }
}
