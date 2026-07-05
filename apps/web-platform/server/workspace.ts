import {
  existsSync,
  lstatSync,
  mkdirSync,
  symlinkSync,
  writeFileSync,
} from "fs";
import { join, resolve } from "path";
import { execFileSync } from "child_process";
import { createChildLogger } from "./logger";
import {
  gitWithInstallationAuth,
  classifyGitError,
  sanitizeGitStderr,
  GitOperationError,
} from "./git-auth";
import { generateInstallationToken, checkRepoAccess } from "./github-app";
import { getPluginPath } from "./plugin-path";
import { reportSilentFallback } from "./observability";

// Minimal structural type for the Storage remove path — avoids dragging the
// full SupabaseClient generic into this FS/git-focused module.
interface StorageRemoveClient {
  storage: {
    from: (bucket: string) => {
      remove: (paths: string[]) => Promise<{ error: unknown }>;
    };
  };
}

/**
 * Purge a workspace's logo Storage object (#4916). Called from the SOLE-OWNED
 * workspace teardown in account-delete (where `workspaceId === userId` per the
 * N2 invariant) — NOT on shared-workspace member removal, which would delete a
 * shared asset. Uses the Storage API `.remove()` (the sanctioned path —
 * Supabase's `protect_delete` trigger blocks direct SQL DELETE on
 * storage.objects). Best-effort: a remove failure is reported, never thrown,
 * so it cannot abort the Art. 17 cascade. Retention = workspace lifetime.
 */
export async function purgeWorkspaceLogoObjects(
  workspaceId: string,
  service: StorageRemoveClient,
): Promise<void> {
  const { error } = await service.storage
    .from("workspace-logos")
    .remove([`${workspaceId}/logo.webp`]);
  if (error) {
    reportSilentFallback(error, {
      feature: "workspace-logo",
      op: "purge-on-account-delete",
      extra: { workspaceId },
    });
  }
}

const GITHUB_URL_RE =
  /^https:\/\/github\.com\/([a-zA-Z0-9._-]+)\/([a-zA-Z0-9._-]+?)(?:\.git)?\/?$/;

function parseGithubRepoUrl(
  repoUrl: string,
): { owner: string; repo: string } | null {
  const match = repoUrl.match(GITHUB_URL_RE);
  if (!match) return null;
  return { owner: match[1], repo: match[2] };
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const log = createChildLogger("workspace");

function getWorkspacesRoot(): string {
  return process.env.WORKSPACES_ROOT || "/workspaces";
}

const KNOWLEDGE_BASE_PROJECT_DIRS = [
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
 * Pre-seed the git config that in-sandbox worktree creation needs, HOST-SIDE at
 * provision time — BEFORE the agent sandbox bind-mounts /dev/null over
 * `.git/config.lock`.
 *
 * The Claude Agent SDK's bubblewrap masks the literal path `.git/config.lock`
 * with a read-only /dev/null bind mount (an in-sandbox, per-session guard against
 * git-config RCE via `core.hooksPath`/`core.sshCommand`; confirmed single-path via
 * `findmnt` = `tmpfs[/null]`). Inside the sandbox, any `git config` WRITE to the
 * shared config fails EEXIST against that masked lock. `worktree-manager.sh`'s
 * `ensure_bare_config` normally performs FOUR shared-config mutations before
 * `git worktree add` (set `core.repositoryformatversion=1`, set
 * `extensions.worktreeConfig=true`, unset `core.bare`, unset `core.worktree`); if
 * any needs a real write against the masked lock, worktree creation wedges (#4826).
 *
 * Performing that exact transformation here — on the host, before the mask exists —
 * makes the in-sandbox `ensure_bare_config` a ZERO-WRITE no-op: `atomic_git_config`
 * takes its read-first idempotent fast path for the two SETs (a read never takes the
 * lock) and skips both UNSETs because the keys are already absent. `git worktree add`
 * then reads `extensions.worktreeConfig` (a read) and writes only per-worktree config
 * (`config.worktree`, unmasked) — it never touches the masked `.git/config.lock`.
 *
 * Best-effort: a failure degrades to the in-sandbox write path (no worse than today),
 * so we log and continue rather than fail provisioning. Idempotent + safe to re-run.
 * Root cause + evidence: ADR-081 (corrected); this is the durable fix for #4826.
 */
export function seedWorktreeConfig(workspacePath: string): void {
  // Mirror ensure_bare_config's shared-config transformation exactly.
  // SETs: log on failure (these gate in-sandbox success). repositoryformatversion=1
  // MUST precede the extensions.* write for git to honor the extension namespace.
  for (const [key, value] of [
    ["core.repositoryformatversion", "1"],
    ["extensions.worktreeConfig", "true"],
  ] as const) {
    try {
      execFileSync("git", ["config", key, value], {
        cwd: workspacePath,
        stdio: "pipe",
      });
    } catch (err) {
      log.warn({ err, workspacePath, key }, "Failed to pre-seed worktree git config");
    }
  }
  // UNSETs: core.bare / core.worktree belong in per-worktree config, not shared
  // (a normal clone/init carries `core.bare=false`). --unset on an already-absent
  // key exits non-zero; that is expected, so these are silent best-effort — a
  // present key that fails to unset just falls back to the in-sandbox path.
  for (const key of ["core.bare", "core.worktree"] as const) {
    try {
      execFileSync("git", ["config", "--unset", key], {
        cwd: workspacePath,
        stdio: "pipe",
      });
    } catch {
      // absent key (or already-unset) — nothing to do.
    }
  }
}

/**
 * Provisions a workspace directory.
 *
 * Creates the directory structure, symlinks the Soleur plugin,
 * initializes a git repo, and writes default Claude settings.
 *
 * @param workspaceId The UUID of the workspace (`workspaces.id`). Solo signup
 *   passes `user.id` directly because migration 053 §1.1.7 N2 invariant
 *   guarantees `workspaces.id === user.id` for backfilled and trigger-created
 *   solo workspaces. Team-invite callers (Phase 5) resolve to the target
 *   workspace_id via `resolveWorkspacePathForUser` before calling this.
 * @returns The absolute path to the provisioned workspace.
 */
export async function provisionWorkspace(workspaceId: string): Promise<string> {
  if (!UUID_RE.test(workspaceId)) {
    throw new Error(`Invalid workspaceId format: ${workspaceId}`);
  }
  const workspacePath = join(getWorkspacesRoot(), workspaceId);

  // 1. Create workspace root (skip if exists)
  ensureDir(workspacePath);

  // 2-4. Scaffold KB dirs, .claude/, plugin symlink (single entry point
  // — the `provisionWorkspaceWithRepo` path reuses the same helper).
  // `provisionWorkspace` is the default ("Start Fresh") path and always
  // writes the welcome sentinel; the repo-cloning path only writes it
  // when explicitly opted in.
  scaffoldWorkspaceDefaults(workspacePath, { suppressWelcomeHook: true });

  // 5. Initialize git repo (execFileSync avoids shell injection)
  try {
    execFileSync("git", ["init"], { cwd: workspacePath, stdio: "pipe" });
    execFileSync("git", ["add", "."], { cwd: workspacePath, stdio: "pipe" });
    execFileSync("git", ["commit", "-m", "Initial workspace"], {
      cwd: workspacePath,
      stdio: "pipe",
    });
    // Pre-seed worktree-config prerequisites HOST-SIDE, before the sandbox masks
    // .git/config.lock, so in-sandbox worktree creation is a zero-write no-op (#4826).
    seedWorktreeConfig(workspacePath);
  } catch (err) {
    log.warn({ err, workspaceId }, "Git init failed");
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
 * @param workspaceId    Workspace UUID (`workspaces.id`); for solo signup
 *                       this equals `user.id` per migration 053 N2 invariant.
 * @param repoUrl        HTTPS URL of the repo to clone
 * @param installationId GitHub App installation ID for token generation
 * @param userName       Git user.name for commits
 * @param userEmail      Git user.email for commits
 * @returns The absolute path to the provisioned workspace.
 */
export async function provisionWorkspaceWithRepo(
  workspaceId: string,
  repoUrl: string,
  installationId: number,
  userName?: string,
  userEmail?: string,
  options?: { suppressWelcomeHook?: boolean },
): Promise<string> {
  if (!UUID_RE.test(workspaceId)) {
    throw new Error(`Invalid workspaceId format: ${workspaceId}`);
  }

  const workspacePath = join(getWorkspacesRoot(), workspaceId);

  // 1. Pre-fetch the installation token so token-generation failures surface
  //    with a distinct "Token generation failed: …" message. The result is
  //    cached in memory by `generateInstallationToken` (5-min safety margin),
  //    so the redundant call inside `gitWithInstallationAuth` is free.
  try {
    await generateInstallationToken(installationId);
  } catch (err) {
    throw new Error(`Token generation failed: ${(err as Error).message}`);
  }

  // 2. Run preflight repo-access check in parallel with workspace cleanup.
  //    Preflight distinguishes "repo is gone / app has no access" from
  //    "git.github.com hiccup" — a degraded GitHub API does NOT block the
  //    clone. Parallelizing with `removeWorkspaceDir` (disk I/O) removes
  //    the ~150-400ms preflight from the happy-path critical path.
  const parsed = parseGithubRepoUrl(repoUrl);
  const [access] = await Promise.all([
    parsed
      ? checkRepoAccess(installationId, parsed.owner, parsed.repo)
      : Promise.resolve("degraded" as const),
    Promise.resolve().then(() => removeWorkspaceDir(workspacePath)),
  ]);

  if (access === "not_found") {
    throw new GitOperationError(
      "REPO_NOT_FOUND",
      "",
      "Repository not found or no longer accessible. Reinstall the Soleur GitHub App or choose a different repository.",
    );
  }
  if (access === "access_revoked") {
    throw new GitOperationError(
      "REPO_ACCESS_REVOKED",
      "",
      "The Soleur GitHub App no longer has access to this repository. Reinstall the app, then try again.",
    );
  }

  // 3. Clone the repository (shallow for speed). `gitWithInstallationAuth`
  //    uses GIT_ASKPASS + GIT_TERMINAL_PROMPT=0 so the token never appears
  //    in argv and any auth failure produces deterministic stderr instead
  //    of the silent "could not read Username" fall-through.
  try {
    await gitWithInstallationAuth(
      ["clone", "--depth", "1", repoUrl, workspacePath],
      installationId,
      { timeout: 120_000 },
    );
    log.info({ workspaceId, repoUrl }, "Repository cloned successfully");
  } catch (err) {
    const rawStderr = (err as { stderr?: Buffer })?.stderr?.toString() ?? "";
    const stderr = sanitizeGitStderr(rawStderr);
    const errorCode = classifyGitError(rawStderr);
    throw new GitOperationError(
      errorCode,
      stderr,
      `Git clone failed: ${stderr || (err as Error).message}`,
    );
  }

  // 6. Set git identity per workspace
  if (userName) {
    try {
      execFileSync("git", ["config", "user.name", userName], {
        cwd: workspacePath,
        stdio: "pipe",
      });
    } catch (err) {
      log.warn({ err, workspaceId }, "Failed to set git user.name");
    }
  }
  if (userEmail) {
    try {
      execFileSync("git", ["config", "user.email", userEmail], {
        cwd: workspacePath,
        stdio: "pipe",
      });
    } catch (err) {
      log.warn({ err, workspaceId }, "Failed to set git user.email");
    }
  }

  // 6.5. Pre-seed worktree-config prerequisites HOST-SIDE, before the agent
  // sandbox bind-mounts /dev/null over .git/config.lock, so the in-sandbox
  // worktree creation path is a zero-write no-op and never wedges (#4826).
  seedWorktreeConfig(workspacePath);

  // 7-9. Overlay plugin symlink, .claude/settings.json, and KB scaffolding
  // via the shared helper. Missing entries are created; existing directories
  // are preserved (e.g., when the clone already provides knowledge-base/).
  // Non-directory entries (files, symlinks) at expected-directory paths
  // throw — see `ensureDir` for the symlink-traversal rationale (#2333).
  scaffoldWorkspaceDefaults(workspacePath, {
    suppressWelcomeHook: options?.suppressWelcomeHook,
  });

  return workspacePath;
}

/**
 * Deletes a workspace directory.
 *
 * Used during account deletion (GDPR Art. 17) to remove all local files.
 * Uses execFileSync to avoid shell injection via the workspace identifier.
 *
 * @param workspaceId Workspace UUID. For solo account deletion this equals
 *   `user.id` per the N2 invariant; the caller (account-delete.ts) passes
 *   the userId directly because the user is by definition the sole member
 *   of their own backfilled workspace. Cross-workspace cleanup (member
 *   removal, Phase 5.5) does NOT call this path — it only revokes the
 *   membership row.
 */
export async function deleteWorkspace(workspaceId: string): Promise<void> {
  if (!UUID_RE.test(workspaceId)) {
    throw new Error(`Invalid workspaceId format: ${workspaceId}`);
  }
  const workspacePath = join(getWorkspacesRoot(), workspaceId);

  if (existsSync(workspacePath)) {
    removeWorkspaceDir(workspacePath);
    log.info({ workspaceId }, "Workspace deleted");
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
  } catch {
    // find -delete continues past individual errors; ignore aggregate exit code
  }

  // Check if workspace dir is now empty
  try {
    execFileSync("rmdir", [workspacePath], { stdio: "pipe" });
    return; // fully cleaned
  } catch {
    // Directory not empty -- root-owned files remain
  }

  // Phase 3: Move aside so provisioning can proceed.
  // mv (rename) operates on the parent directory's inode, not the contents,
  // so it succeeds even when the directory contains root-owned files.
  const orphanedPath = workspacePath + `.orphaned-${Date.now()}`;
  try {
    execFileSync("mv", [workspacePath, orphanedPath], { stdio: "pipe" });
    log.warn(
      { workspacePath, orphanedPath },
      "Workspace contained undeletable files; moved aside for background cleanup",
    );
    return;
  } catch (err) {
    log.error({ workspacePath, err }, "Workspace cleanup failed: cannot move aside");
    throw new Error(
      "Workspace cleanup failed \u2014 please try again or contact support",
    );
  }
}

/**
 * Create `dirPath` if missing; throw if an existing entry at the path is not
 * a directory (file, symlink, FIFO, etc.).
 *
 * TOCTOU-safe: uses a single `lstatSync` call to authoritatively classify the
 * entry without following symlinks, so we never "check then open" with two
 * syscalls (CWE-367). Rejects symlinks unconditionally — knowledge-base
 * scaffolding paths must never be symlinks in the first place (#2333).
 */
function ensureDir(dirPath: string): void {
  try {
    const st = lstatSync(dirPath);
    if (!st.isDirectory()) {
      throw new Error(`Refusing to scaffold over non-directory: ${dirPath}`);
    }
    return;
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code !== "ENOENT") throw err;
  }
  mkdirSync(dirPath, { recursive: true });
}

/**
 * Idempotent scaffolding for a workspace directory: creates the
 * knowledge-base/ layout, writes `.claude/settings.json`, overlays the
 * Soleur plugin symlink, and (optionally) suppresses the welcome hook.
 *
 * Called from both `provisionWorkspace` ("Start Fresh") and
 * `provisionWorkspaceWithRepo` (git clone) so the two paths produce
 * identical workspaces. Any non-directory entry at an expected-directory
 * path (symlink, file) causes `ensureDir` to throw — see #2333.
 *
 * @param workspacePath   Absolute path to an already-existing workspace root.
 * @param options.suppressWelcomeHook  When true, writes
 *   `.claude/soleur-welcomed.local` so the guided onboarding flow does not
 *   re-trigger. `provisionWorkspace` passes true; the repo-cloning path
 *   passes the user's explicit choice.
 */
export function scaffoldWorkspaceDefaults(
  workspacePath: string,
  options: { suppressWelcomeHook?: boolean } = {},
): void {
  // Knowledge-base layout
  const kbRoot = join(workspacePath, "knowledge-base");
  ensureDir(kbRoot);
  ensureDir(join(kbRoot, "overview"));
  const projectDir = join(kbRoot, "project");
  ensureDir(projectDir);
  for (const sub of KNOWLEDGE_BASE_PROJECT_DIRS) {
    ensureDir(join(projectDir, sub));
  }

  // .claude/settings.json — canUseTool-routed permissions (see #725).
  const claudeDir = join(workspacePath, ".claude");
  ensureDir(claudeDir);
  writeFileSync(
    join(claudeDir, "settings.json"),
    JSON.stringify(DEFAULT_SETTINGS, null, 2) + "\n",
  );

  if (options.suppressWelcomeHook) {
    writeFileSync(join(claudeDir, "soleur-welcomed.local"), "");
  }

  // Soleur plugin symlink — best effort (warn-only on failure so a broken
  // symlink doesn't block workspace creation).
  const pluginsDir = join(workspacePath, "plugins");
  ensureDir(pluginsDir);
  const symlinkTarget = join(pluginsDir, "soleur");
  if (!existsSync(symlinkTarget)) {
    try {
      symlinkSync(getPluginPath(), symlinkTarget);
    } catch (err) {
      log.warn({ err, workspacePath }, "Failed to symlink plugin");
    }
  }
}
