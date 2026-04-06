// ---------------------------------------------------------------------------
// Session sync: pull before session, push after session
//
// Keeps the user's workspace in sync with their connected GitHub repo.
// All operations are best-effort — failures are logged but never block
// the agent session.
// ---------------------------------------------------------------------------

import { execFileSync } from "child_process";
import { unlinkSync, writeFileSync } from "fs";
import { createServiceClient } from "@/lib/supabase/server";
import type { SupabaseClient } from "@supabase/supabase-js";
import { generateInstallationToken, randomCredentialPath } from "./github-app";
import { createChildLogger } from "./logger";

const log = createChildLogger("session-sync");

let _supabase: SupabaseClient | null = null;

function getSupabase(): SupabaseClient | null {
  if (_supabase) return _supabase;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) {
    log.warn("Supabase env vars not set — session sync disabled");
    return null;
  }
  _supabase = createServiceClient();
  return _supabase;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function hasRemote(workspacePath: string): boolean {
  try {
    const result = execFileSync("git", ["remote", "-v"], {
      cwd: workspacePath,
      stdio: "pipe",
    });
    return result.toString().trim().length > 0;
  } catch {
    return false;
  }
}

function hasLocalCommits(workspacePath: string): boolean {
  try {
    // Check if there are commits ahead of the remote tracking branch
    const result = execFileSync(
      "git",
      ["rev-list", "--count", "@{u}..HEAD"],
      { cwd: workspacePath, stdio: "pipe" },
    );
    return parseInt(result.toString().trim(), 10) > 0;
  } catch {
    // No upstream tracking branch — if we have any commits at all, attempt push.
    // This handles the case where auto-commit created local commits but no
    // upstream tracking branch is set (first push after clone).
    try {
      const result = execFileSync(
        "git",
        ["rev-list", "--count", "HEAD"],
        { cwd: workspacePath, stdio: "pipe" },
      );
      return parseInt(result.toString().trim(), 10) > 0;
    } catch {
      return false;
    }
  }
}

function writeCredentialHelper(token: string): string {
  const helperPath = randomCredentialPath();
  writeFileSync(
    helperPath,
    `#!/bin/sh\necho "username=x-access-token"\necho "password=${token}"`,
    { mode: 0o700 },
  );
  return helperPath;
}

function cleanupCredentialHelper(helperPath: string): void {
  try {
    unlinkSync(helperPath);
  } catch {
    // Best-effort cleanup
  }
}

async function getInstallationId(userId: string): Promise<number | null> {
  const supabase = getSupabase();
  if (!supabase) return null;

  const { data, error } = await supabase
    .from("users")
    .select("github_installation_id")
    .eq("id", userId)
    .single();

  if (error || !data?.github_installation_id) {
    return null;
  }

  return data.github_installation_id;
}

async function updateLastSynced(userId: string): Promise<void> {
  const supabase = getSupabase();
  if (!supabase) return;

  const { error } = await supabase
    .from("users")
    .update({ repo_last_synced_at: new Date().toISOString() })
    .eq("id", userId);

  if (error) {
    log.warn({ err: error, userId }, "Failed to update repo_last_synced_at");
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Pull latest changes from remote before an agent session.
 * Best-effort: failures are logged but never throw.
 */
export async function syncPull(
  userId: string,
  workspacePath: string,
): Promise<void> {
  if (!hasRemote(workspacePath)) {
    return; // Empty workspace, no remote
  }

  let helperPath: string | null = null;

  try {
    const installationId = await getInstallationId(userId);
    if (!installationId) {
      log.warn({ userId }, "No installation ID found for sync pull");
      return;
    }

    const token = await generateInstallationToken(installationId);
    helperPath = writeCredentialHelper(token);

    // Auto-commit any uncommitted changes before pulling to avoid conflicts
    try {
      const status = execFileSync("git", ["status", "--porcelain"], {
        cwd: workspacePath,
        stdio: "pipe",
      });
      if (status.toString().trim().length > 0) {
        execFileSync("git", ["add", "-A"], {
          cwd: workspacePath,
          stdio: "pipe",
        });
        execFileSync(
          "git",
          ["commit", "-m", "Auto-commit before sync pull"],
          { cwd: workspacePath, stdio: "pipe" },
        );
      }
    } catch (err) {
      log.warn({ err, userId }, "Auto-commit before pull failed");
    }

    // Use merge (not rebase) — shallow clones lack sufficient history for rebase
    execFileSync(
      "git",
      [
        "-c", `credential.helper=!${helperPath}`,
        "pull",
        "--no-rebase",
        "--autostash",
      ],
      { cwd: workspacePath, stdio: "pipe", timeout: 60_000 },
    );

    await updateLastSynced(userId);
    log.info({ userId }, "Sync pull completed");
  } catch (err) {
    log.warn({ err, userId }, "Sync pull failed — continuing with local state");
  } finally {
    if (helperPath) cleanupCredentialHelper(helperPath);
  }
}

/**
 * Push local changes to remote after an agent session.
 * Best-effort: failures are logged but never throw.
 */
export async function syncPush(
  userId: string,
  workspacePath: string,
): Promise<void> {
  if (!hasRemote(workspacePath)) {
    return; // Empty workspace, no remote
  }

  let helperPath: string | null = null;

  try {
    // Auto-commit any uncommitted changes before pushing
    try {
      const status = execFileSync("git", ["status", "--porcelain"], {
        cwd: workspacePath,
        stdio: "pipe",
      });
      if (status.toString().trim().length > 0) {
        execFileSync("git", ["add", "-A"], {
          cwd: workspacePath,
          stdio: "pipe",
        });
        execFileSync(
          "git",
          ["commit", "-m", "Auto-commit after session"],
          { cwd: workspacePath, stdio: "pipe" },
        );
      }
    } catch (err) {
      log.warn({ err, userId }, "Auto-commit before push failed");
    }

    if (!hasLocalCommits(workspacePath)) {
      log.debug({ userId }, "No local commits to push");
      return;
    }

    const installationId = await getInstallationId(userId);
    if (!installationId) {
      log.warn({ userId }, "No installation ID found for sync push");
      return;
    }

    const token = await generateInstallationToken(installationId);
    helperPath = writeCredentialHelper(token);

    execFileSync(
      "git",
      [
        "-c", `credential.helper=!${helperPath}`,
        "push",
      ],
      { cwd: workspacePath, stdio: "pipe", timeout: 60_000 },
    );

    await updateLastSynced(userId);
    log.info({ userId }, "Sync push completed");
  } catch (err) {
    log.warn({ err, userId }, "Sync push failed — next session will retry");
  } finally {
    if (helperPath) cleanupCredentialHelper(helperPath);
  }
}
