/**
 * Branch push handler for platform MCP tools (#1929).
 *
 * Pushes commits from the agent workspace to a feature branch.
 * Uses the credential helper pattern from workspace.ts for auth.
 *
 * Safety guards:
 * - Protected branch rejection (main, master, stored default)
 * - Force-push blocking
 * - Credential helper cleanup in finally block
 * - Git author set to Soleur Agent identity
 */

import { execFileSync } from "child_process";
import { writeFileSync, unlinkSync } from "fs";

import { generateInstallationToken, randomCredentialPath } from "./github-app";
import { createChildLogger } from "./logger";

const log = createChildLogger("push-branch");

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

export const PROTECTED_BRANCHES = ["main", "master"] as const;
const AGENT_AUTHOR_NAME = "Soleur Agent";
const AGENT_AUTHOR_EMAIL = "agent@soleur.ai";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface PushBranchOptions {
  installationId: number;
  owner: string;
  repo: string;
  workspacePath: string;
  branch: string;
  force: boolean;
  defaultBranch?: string;
}

export interface PushResult {
  branch: string;
  pushed: boolean;
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/**
 * Validate that a branch name is not protected.
 * Throws if the branch matches main, master, or the stored default branch.
 */
export function validateBranchName(
  branch: string,
  defaultBranch?: string,
): void {
  const protectedSet = new Set<string>([...PROTECTED_BRANCHES]);
  if (defaultBranch) protectedSet.add(defaultBranch);

  if (protectedSet.has(branch)) {
    throw new Error(
      `Push to protected branch '${branch}' is not allowed from cloud agents. ` +
      "Push to a feature branch instead.",
    );
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Push the current workspace HEAD to a feature branch on the remote.
 *
 * The gating (review gate) is handled by canUseTool — this function
 * only executes after the founder has approved.
 */
export async function pushBranch(options: PushBranchOptions): Promise<PushResult> {
  const { installationId, owner, repo, workspacePath, branch, force, defaultBranch } = options;

  // 1. Reject force-push unconditionally
  if (force) {
    throw new Error(
      "Force-push is not allowed from cloud agents. " +
      "Use a regular push or create a new branch.",
    );
  }

  // 2. Validate branch name
  validateBranchName(branch, defaultBranch);

  // 3. Set git author to Soleur Agent identity
  try {
    execFileSync("git", ["config", "user.name", AGENT_AUTHOR_NAME], {
      cwd: workspacePath,
      stdio: "pipe",
    });
    execFileSync("git", ["config", "user.email", AGENT_AUTHOR_EMAIL], {
      cwd: workspacePath,
      stdio: "pipe",
    });
  } catch (err) {
    log.warn({ err }, "Failed to set git author — push may use existing config");
  }

  // 4. Generate token and create credential helper
  const token = await generateInstallationToken(installationId);
  const helperPath = randomCredentialPath();

  try {
    writeFileSync(
      helperPath,
      `#!/bin/sh\necho 'username=x-access-token'\necho 'password=${token}'`,
      { mode: 0o700 },
    );

    // 5. Push to remote
    const repoUrl = `https://github.com/${owner}/${repo}.git`;
    execFileSync(
      "git",
      [
        "-c", `credential.helper=!${helperPath}`,
        "push",
        repoUrl,
        `HEAD:refs/heads/${branch}`,
      ],
      {
        cwd: workspacePath,
        stdio: "pipe",
        timeout: 120_000,
      },
    );

    log.info({ branch, owner, repo }, "Branch pushed successfully");

    return { branch, pushed: true };
  } catch (err) {
    const rawStderr = (err as { stderr?: Buffer })?.stderr?.toString() ?? "";
    // Strip internal paths to avoid leaking server filesystem layout
    const stderr = rawStderr.replace(/\/[^\s:]+/g, "<path>");
    throw new Error(`Git push failed: ${stderr || (err as Error).message}`);
  } finally {
    // 6. Clean up credential helper immediately
    try {
      unlinkSync(helperPath);
    } catch {
      // Best-effort cleanup
    }
  }
}
