// ---------------------------------------------------------------------------
// Session sync: pull before session, push after session
//
// Keeps the user's workspace in sync with their connected GitHub repo.
// All operations are best-effort — failures are logged but never block
// the agent session.
// ---------------------------------------------------------------------------

import { execFileSync } from "child_process";
import { readdirSync } from "fs";
import { join } from "path";
import { createServiceClient } from "@/lib/supabase/service";
import type { SupabaseClient } from "@supabase/supabase-js";
import { gitWithInstallationAuth } from "./git-auth";
import { createChildLogger } from "./logger";

const log = createChildLogger("session-sync");

// Path-allowlist for the auto-commit sweep. Only paths under
// `knowledge-base/` are eligible for automatic staging during syncPull/syncPush.
// Everything else (`.claude/`, `.github/`, `apps/`, root config files, ...)
// is left dirty in the working tree so it never lands in PRs the loop did
// not explicitly author. See #2905 for the failure modes this prevents.
const ALLOWED_AUTOCOMMIT_PATHS = [/^knowledge-base\//];

// Auto-commit headlines used by syncPull / syncPush. Exported as named
// constants so .github/scripts/check-auto-commit-density.sh can stay in
// sync (the regex there must reference these exact strings).
export const AUTO_COMMIT_MSG_PULL = "Auto-commit before sync pull";
export const AUTO_COMMIT_MSG_PUSH = "Auto-commit after session";

/**
 * Parse `git status --porcelain=v1 -z` output and return the subset of
 * paths matching ALLOWED_AUTOCOMMIT_PATHS.
 *
 * The `-z` flag emits NUL-separated entries with no C-quoting, so paths
 * containing tabs, newlines, quotes, or non-ASCII characters round-trip
 * cleanly to `git add --`. For renames (R) and copies (C), git emits the
 * destination path first, then the source path as a separate NUL entry —
 * this parser skips the source.
 */
export function getAllowlistedChanges(workspacePath: string): string[] {
  let output: string;
  try {
    output = execFileSync("git", ["status", "--porcelain=v1", "-z"], {
      cwd: workspacePath,
      stdio: "pipe",
    }).toString();
  } catch {
    return [];
  }

  const paths: string[] = [];
  const tokens = output.split("\0");
  for (let i = 0; i < tokens.length; i++) {
    const entry = tokens[i];
    if (entry.length < 4) continue; // status (2 chars) + space + path
    const status = entry.slice(0, 2);
    const path = entry.slice(3);
    if (ALLOWED_AUTOCOMMIT_PATHS.some((re) => re.test(path))) {
      paths.push(path);
    }
    // R (rename) and C (copy) are followed by an extra NUL-separated
    // entry containing the SOURCE path — skip it.
    if (status[0] === "R" || status[0] === "C") {
      i++;
    }
  }
  return paths;
}

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

/**
 * Recursively count .md files in a directory.
 * Returns 0 if the directory does not exist.
 */
export function countMdFiles(dirPath: string): number {
  let count = 0;
  try {
    const entries = readdirSync(dirPath, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = join(dirPath, entry.name);
      if (entry.isDirectory()) {
        count = count + countMdFiles(fullPath);
      } else if (entry.isFile() && entry.name.endsWith(".md")) {
        count = count + 1;
      }
    }
  } catch {
    // Directory does not exist or is not readable
  }
  return count;
}

/**
 * Record the current KB file count in the user's kb_sync_history JSONB array.
 * Trims to the last 14 entries. Best-effort — failures are logged, never thrown.
 */
async function recordKbSyncHistory(
  userId: string,
  workspacePath: string,
): Promise<void> {
  const supabase = getSupabase();
  if (!supabase) return;

  const kbPath = join(workspacePath, "knowledge-base");
  const fileCount = countMdFiles(kbPath);

  const { data: user, error: fetchError } = await supabase
    .from("users")
    .select("kb_sync_history")
    .eq("id", userId)
    .single();

  if (fetchError || !user) {
    log.warn({ err: fetchError, userId }, "Failed to fetch kb_sync_history");
    return;
  }

  const history = Array.isArray(user.kb_sync_history)
    ? (user.kb_sync_history as Array<{ date: string; count: number }>)
    : [];

  const today = new Date().toISOString().slice(0, 10);
  const updated = [...history, { date: today, count: fileCount }].slice(-14);

  const { error: updateError } = await supabase
    .from("users")
    .update({ kb_sync_history: updated })
    .eq("id", userId);

  if (updateError) {
    log.warn({ err: updateError, userId }, "Failed to update kb_sync_history");
  } else {
    log.debug({ userId, fileCount }, "Recorded KB sync history");
  }
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

  try {
    const installationId = await getInstallationId(userId);
    if (!installationId) {
      log.warn({ userId }, "No installation ID found for sync pull");
      return;
    }

    // Auto-commit any uncommitted changes before pulling to avoid conflicts.
    // Path-scoped to ALLOWED_AUTOCOMMIT_PATHS — see #2905.
    try {
      const allowed = getAllowlistedChanges(workspacePath);
      if (allowed.length === 0) {
        log.info(
          { userId },
          "No allowlisted changes to commit — skipping auto-commit",
        );
      } else {
        execFileSync("git", ["add", "--", ...allowed], {
          cwd: workspacePath,
          stdio: "pipe",
        });
        execFileSync(
          "git",
          ["commit", "-m", AUTO_COMMIT_MSG_PULL],
          { cwd: workspacePath, stdio: "pipe" },
        );
      }
    } catch (err) {
      log.warn({ err, userId }, "Auto-commit before pull failed");
    }

    // Use merge (not rebase) — shallow clones lack sufficient history for rebase
    await gitWithInstallationAuth(
      ["pull", "--no-rebase", "--autostash"],
      installationId,
      { cwd: workspacePath, timeout: 60_000 },
    );

    await updateLastSynced(userId);
    log.info({ userId }, "Sync pull completed");
  } catch (err) {
    log.warn({ err, userId }, "Sync pull failed — continuing with local state");
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

  try {
    // Auto-commit any uncommitted changes before pushing.
    // Path-scoped to ALLOWED_AUTOCOMMIT_PATHS — see #2905.
    try {
      const allowed = getAllowlistedChanges(workspacePath);
      if (allowed.length === 0) {
        log.info(
          { userId },
          "No allowlisted changes to commit — skipping auto-commit",
        );
      } else {
        execFileSync("git", ["add", "--", ...allowed], {
          cwd: workspacePath,
          stdio: "pipe",
        });
        execFileSync(
          "git",
          ["commit", "-m", AUTO_COMMIT_MSG_PUSH],
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

    await gitWithInstallationAuth(
      ["push"],
      installationId,
      { cwd: workspacePath, timeout: 60_000 },
    );

    // Best-effort: record KB file count for analytics sparklines
    try {
      await recordKbSyncHistory(userId, workspacePath);
    } catch (err) {
      log.warn({ err, userId }, "KB sync history recording failed");
    }

    await updateLastSynced(userId);
    log.info({ userId }, "Sync push completed");
  } catch (err) {
    log.warn({ err, userId }, "Sync push failed — next session will retry");
  }
}
