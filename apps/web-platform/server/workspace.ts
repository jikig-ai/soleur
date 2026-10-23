import {
  existsSync,
  lstatSync,
  mkdirSync,
  readdirSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from "fs";
import { basename, join, resolve } from "path";
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
import { hashUserId, reportSilentFallback } from "./observability";
import { seedWorktreeConfig } from "./worktree-config-seed";
import { atomicGitConfig } from "./git-config-atomic";
import {
  workspaceReapRoots,
  type ReapRootLabel,
} from "./workspace-resolver";

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
  // Lowercase AFTER the case-insensitive shape check: the filesystem is case-sensitive, and
  // delete reaps the lowercase path, so every entry point must build the same one.
  const workspacePath = join(getWorkspacesRoot(), workspaceId.toLowerCase());

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
  } catch (err) {
    log.warn({ err, workspaceId }, "Git init failed");
  }

  // Heal worktree git config HOST-SIDE (#4826): remove any extensions.worktreeConfig
  // that would force in-sandbox git to read the masked/unreadable .git/config.worktree
  // and fatal. Deliberately OUTSIDE the init/commit try so it runs whenever `git init`
  // produced a `.git/` even if `git add`/`git commit` failed (e.g. no git identity on a
  // runner). Best-effort + no-op on a healthy/absent-`.git` workspace.
  seedWorktreeConfig(workspacePath);

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

  const workspacePath = join(getWorkspacesRoot(), workspaceId.toLowerCase());

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

  // 6. Set git identity per workspace. Route the raw `git config` writes through
  //    the lock-free atomic writer (#6191, ADR-099 §Known latent surfaces): atomic
  //    by rename(2), so a stale/masked `.git/config.lock` cannot EEXIST the seed.
  //    Still best-effort — the outer try/catch → log.warn keeps a seed failure from
  //    ever stranding provisioning (atomicGitConfig itself never throws).
  if (userName) {
    try {
      atomicGitConfig(workspacePath, ["config", "user.name", userName]);
    } catch (err) {
      log.warn({ err, workspaceId }, "Failed to set git user.name");
    }
  }
  if (userEmail) {
    try {
      atomicGitConfig(workspacePath, ["config", "user.email", userEmail]);
    } catch (err) {
      log.warn({ err, workspaceId }, "Failed to set git user.email");
    }
  }

  // 6.5. Heal worktree git config HOST-SIDE (#4826): a fresh clone has no
  // extensions.worktreeConfig, so this is a no-op here — but keeps the provision and
  // session-boot paths symmetric with ensureWorkspaceRepoCloned.
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

/** Which leg of the reap failed. `resolver` = the root list itself could not be built. */
export type ReapFailureRoot = ReapRootLabel | "resolver";
/**
 * Why. `moved-aside`: the tree was only RENAMED to `<id>.orphaned-<ts>` (still on
 * disk, nothing under WORKTREE_ROOT ever sweeps it). `survived`: the path is still
 * there after the removal. `recreated`: it was gone, then reappeared (a straggling
 * writer). `error`: a removal/stat call threw.
 */
export type ReapFailureKind = "moved-aside" | "survived" | "recreated" | "error";
export interface ReapFailure {
  root: ReapFailureRoot;
  kind: ReapFailureKind;
  code?: string;
  /** For `root: "resolver"`: which tenant root could not be resolved. */
  label?: ReapRootLabel;
}

/**
 * Thrown by {@link deleteWorkspace} after EVERY root was attempted. Carries
 * path-free, id-free summaries only (root LABEL, kind, errno code): the raw
 * errors from rm/unlink/lstat embed `<root>/<uuid>`, and this object is handed
 * to Sentry by callers.
 */
export class WorkspaceReapError extends AggregateError {
  readonly failures: ReadonlyArray<ReapFailure>;
  constructor(failures: ReapFailure[], errors: Error[], total: number) {
    super(
      errors,
      `deleteWorkspace: ${failures.length} of ${total} reap targets could not be reaped`,
    );
    this.name = "WorkspaceReapError";
    this.failures = failures;
  }
}

/** Pause before the final re-verification, so a straggling writer's file is caught. */
export const REAP_RECHECK_DELAY_MS = 250;

/**
 * Deletes a workspace's directories (Art. 17 erasure of the local working tree).
 *
 * Reaps `<root>/<workspaceId>` under every root from {@link workspaceReapRoots}:
 * `WORKSPACES_ROOT` FIRST, then `WORKTREE_ROOT` (raw and flag-independent, so the
 * live clone with the git-data split on AND a tree left behind after a rollback are
 * both erased, #8211). Roots resolve per root: a bad or unresolvable root is
 * recorded as a `resolver` failure and never skips the other. Each root's
 * `<id>.orphaned-<ms timestamp>` siblings (left by a PROVISION-time move-aside,
 * which ignores the outcome; nothing sweeps a `WORKTREE_ROOT` orphan) are reaped
 * too, matched strictly on the exact validated id. Every target is attempted;
 * failures are thrown together as one {@link WorkspaceReapError} after the loop.
 *
 * "Erased" is decided by the tree being GONE, not by the original path being
 * absent: a move-aside (`removeWorkspaceDir` phase 3) counts as a FAILURE, the
 * path is re-checked after a short delay, and a symlink at the path is unlinked,
 * never followed. Uses execFileSync to avoid shell injection via the workspace
 * identifier; the id is lowercased before any path is built (the UUID check is
 * case-insensitive, the filesystem is not).
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
  const id = workspaceId.toLowerCase();
  const idHash = hashUserId(id);

  const failures: ReapFailure[] = [];
  const errors: Error[] = [];
  const fail = (
    root: ReapFailureRoot,
    kind: ReapFailureKind,
    err?: unknown,
    label?: ReapRootLabel,
  ) => {
    const code =
      err && typeof (err as NodeJS.ErrnoException).code === "string"
        ? (err as NodeJS.ErrnoException).code
        : undefined;
    failures.push({ root, kind, ...(code ? { code } : {}), ...(label ? { label } : {}) });
    // Path-free summary: the raw error's message embeds `<root>/<uuid>`, so the raw error
    // is never logged or forwarded.
    const summary = Object.assign(
      new Error(
        `reap ${label ?? root} ${kind}${code ? ` (${code})` : err instanceof Error ? ` (${err.name})` : ""}`,
      ),
      code ? { code } : {},
    );
    errors.push(summary);
    log.error({ workspaceIdHash: idHash, root, label, kind, code }, "Workspace root reap failed");
  };

  // Roots resolve PER ROOT (see workspaceReapRoots): WORKSPACES_ROOT comes first and a
  // fault on one root is recorded without skipping the other. Nothing is resolved against
  // the cwd: a relative root is a fault, not a path.
  let roots: { label: ReapRootLabel; root: string }[] = [];
  let resolverFaults = 0;
  try {
    const resolved = workspaceReapRoots();
    roots = resolved.roots;
    for (const f of resolved.faults) {
      resolverFaults += 1;
      fail("resolver", "error", f.err, f.label);
    }
  } catch (err) {
    resolverFaults += 1;
    fail("resolver", "error", err);
  }

  // Each unit is one path to erase: the tree itself, plus any `<id>.orphaned-<ts>` sibling a
  // PROVISION-time move-aside left behind (that caller ignores the outcome, and nothing sweeps
  // a WORKTREE_ROOT orphan). Orphans are listed BEFORE the tree is touched, so the orphan this
  // very call may create stays a reported failure rather than being retried silently.
  const units: { label: ReapRootLabel; root: string; path: string }[] = [];
  for (const { label, root } of roots) {
    try {
      for (const name of readdirSync(root)) {
        if (isOrphanOf(id, name)) units.push({ label, root, path: join(root, name) });
      }
    } catch (err) {
      if ((err as NodeJS.ErrnoException)?.code !== "ENOENT") fail(label, "error", err);
    }
    units.push({ label, root, path: join(root, id) });
  }

  const removed: typeof units = [];
  for (const t of units) {
    try {
      const existed = lstatOrNull(t.path) !== null;
      const outcome = removeWorkspaceDir(t.path, [t.root]);
      if (outcome === "moved-aside") {
        fail(t.label, "moved-aside");
      } else if (lstatOrNull(t.path)) {
        // Verify, don't assume: lstat (never follows a link) must now report ENOENT.
        fail(t.label, "survived");
      } else if (existed) {
        removed.push(t);
        log.info({ workspaceIdHash: idHash, root: t.label }, "Workspace deleted");
      }
    } catch (err) {
      fail(t.label, "error", err);
    }
  }

  if (removed.length > 0) {
    await new Promise<void>((r) => setTimeout(r, REAP_RECHECK_DELAY_MS));
    for (const t of removed) {
      try {
        if (lstatOrNull(t.path)) fail(t.label, "recreated");
      } catch (err) {
        fail(t.label, "error", err);
      }
    }
  }

  if (failures.length > 0) {
    throw new WorkspaceReapError(failures, errors, units.length + resolverFaults);
  }
}

/**
 * Strictly `<id>.orphaned-<digits>`: the exact (already validated, lowercased) id, the
 * literal `.orphaned-`, and a millisecond timestamp (`Date.now()`) and nothing else. Never
 * a broader glob: another tenant's orphan, `<id>x`, or a doubly-orphaned name must not match.
 */
function isOrphanOf(id: string, name: string): boolean {
  const prefix = `${id}.orphaned-`;
  return name.startsWith(prefix) && /^\d{10,16}$/.test(name.slice(prefix.length));
}

function lstatOrNull(path: string): ReturnType<typeof lstatSync> | null {
  try {
    return lstatSync(path);
  } catch (err) {
    if ((err as NodeJS.ErrnoException)?.code === "ENOENT") return null;
    throw err;
  }
}

/**
 * Log fields for a workspace path: the leaf is a workspace UUID (= a user id for
 * solo workspaces), and these logs reach Sentry through the pino mirror, so the
 * raw path never travels, only the hashed leaf.
 */
function pathFields(workspacePath: string): { workspaceIdHash: string } {
  return { workspaceIdHash: hashUserId(basename(workspacePath)) };
}

/** What {@link removeWorkspaceDir} did to the path. */
export type RemoveOutcome = "removed" | "unlinked" | "absent" | "moved-aside";

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
 *
 * `allowedRoots` is the set of roots the path must be a strict child of; it
 * DEFAULTS to the single workspaces root, so existing callers keep the exact
 * guard. A `/` root never matches. A symlink at the path is unlinked, never
 * followed.
 *
 * Returns what happened. `"moved-aside"` means the tree was only RENAMED to
 * `<path>.orphaned-<ts>` (undeletable files remain on disk): the path is free for
 * re-provisioning, which is all the provision caller needs and why it ignores the
 * return, but it is NOT an erasure, so `deleteWorkspace` treats it as a failure.
 */
export function removeWorkspaceDir(
  workspacePath: string,
  allowedRoots: string[] = [getWorkspacesRoot()],
): RemoveOutcome {
  const resolved = resolve(workspacePath);
  const allowed = allowedRoots.some((r) => {
    // A "/" root can never match: resolve("/") + "/" is "//", which no resolved path starts with.
    const root = resolve(r);
    return resolved !== root && resolved.startsWith(root + "/");
  });
  if (!allowed) {
    throw new Error("Refusing to remove path outside workspace root");
  }

  // lstat (not existsSync): existsSync follows links, so a dangling link looks
  // absent, and a link to a directory would be treated as the directory itself.
  if (lstatOrNull(workspacePath)?.isSymbolicLink()) {
    unlinkSync(workspacePath);
    return "unlinked";
  }

  if (!existsSync(workspacePath)) return "absent";

  // Phase 1: Direct removal (works when all files owned by current user)
  try {
    execFileSync("rm", ["-rf", workspacePath], { stdio: "pipe" });
    return "removed";
  } catch {
    log.warn({ ...pathFields(workspacePath) }, "Direct rm -rf failed, attempting partial cleanup");
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
    return "removed"; // fully cleaned
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
      { ...pathFields(workspacePath), orphanedAt: orphanedPath.slice(workspacePath.length) },
      "Workspace contained undeletable files; moved aside for background cleanup",
    );
    return "moved-aside";
  } catch (err) {
    log.error(
      { ...pathFields(workspacePath), errCode: (err as NodeJS.ErrnoException)?.code },
      "Workspace cleanup failed: cannot move aside",
    );
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
  } else {
    // Diagnostic breadcrumb (C3 / ADR-093): the workspace already has a
    // plugins/soleur entry, so the symlink is skipped. If it is a REAL directory
    // (not our symlink), the connected repo ships its OWN committed plugin copy —
    // the previously-SILENT shadow condition behind the #4826 delivery wedge. This
    // is diagnostic-only, NOT an alert: both SDK factories load getPluginPath()
    // (the deployed root), so the committed copy is inert for the SDK — the fix
    // this ADR records already neutralizes it. Emitting the field makes the
    // collision path observable (it was blind during the 5-round saga).
    try {
      if (lstatSync(symlinkTarget).isDirectory()) {
        log.warn(
          { workspacePath, connectedRepoShipsPlugin: true },
          "connected repo ships plugins/soleur/ — deployed plugin is authoritative via SDK load (getPluginPath()); workspace copy is inert for the SDK (ADR-093)",
        );
      }
    } catch {
      // lstat race (entry removed between existsSync and lstat) — non-critical diagnostic; ignore.
    }
  }
}
