import { existsSync } from "node:fs";
import { rm, rename } from "node:fs/promises";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { join } from "node:path";

import { gitWithInstallationAuth } from "@/server/git-auth";
import { normalizeRepoUrl } from "@/lib/repo-url";
import { reportSilentFallback } from "@/server/observability";
import { createChildLogger } from "@/server/logger";

const log = createChildLogger("ensure-workspace-repo");

// Test seams. The orchestration (`ensureWorkspaceRepoCloned`) is unit-tested by
// stubbing the git/fs mechanics so the decision logic + fail-soft posture are
// covered without touching real git. Production uses the real implementations.
type ExecFn = (
  file: string,
  args: string[],
  opts: { timeout?: number },
) => Promise<{ stdout: string | Buffer }>;
type GraftFn = (
  workspacePath: string,
  repoUrl: string,
  installationId: number,
) => Promise<void>;

let execFn: ExecFn = promisify(execFile) as unknown as ExecFn;
let graftFn: GraftFn = realGraftRepoClone;

/** @internal test seam */
export function __setExecForTests(fn: ExecFn): void {
  execFn = fn;
}
/** @internal test seam */
export function __setGraftForTests(fn: GraftFn): void {
  graftFn = fn;
}

export interface EnsureWorkspaceRepoArgs {
  userId: string;
  workspacePath: string;
  /** Per-user installation (resolveInstallationId, membership-checked). null = not connected. */
  installationId: number | null;
  /** Per-user connected repo (getCurrentRepoUrl, normalized). null/empty = not connected. */
  repoUrl: string | null;
}

/**
 * Session-start self-heal: ensure the user's connected repo is cloned into their
 * workspace. Generic per-user/per-repo — owner/repo + installation token are the
 * caller's membership-checked values; nothing is hardcoded.
 *
 * - Not connected (no installation / no repoUrl) → no-op (Start-Fresh workspaces
 *   correctly have no origin).
 * - Workspace already a clone of the connected repo → no-op (cheap disk + origin read).
 * - Connected but not cloned (no `.git`, or origin mismatch) → graft a fresh authed
 *   clone's `.git` onto the workspace dir and check out the default branch.
 * - Fail-soft: any failure mirrors to Sentry (`cq-silent-fallback-must-mirror-to-sentry`)
 *   and the function resolves — it NEVER throws into the conversation.
 *
 * The installation token rides the GIT_ASKPASS env inside `gitWithInstallationAuth`
 * (never embedded in a remote URL, never logged) — `hr-github-app-auth-not-pat`.
 */
export async function ensureWorkspaceRepoCloned(
  args: EnsureWorkspaceRepoArgs,
): Promise<void> {
  const { userId, workspacePath, installationId, repoUrl } = args;
  if (installationId === null || !repoUrl) return; // not connected → nothing to ensure

  try {
    if (existsSync(join(workspacePath, ".git"))) {
      let originUrl = "";
      try {
        const { stdout } = await execFn(
          "git",
          ["-C", workspacePath, "remote", "get-url", "origin"],
          { timeout: 10_000 },
        );
        originUrl = stdout.toString().trim();
      } catch {
        originUrl = ""; // no origin remote configured
      }
      if (normalizeRepoUrl(originUrl) === normalizeRepoUrl(repoUrl)) {
        return; // already the connected repo → no-op (idempotent)
      }
      // .git present but origin missing/mismatched → re-graft the connected repo.
      await graftFn(workspacePath, repoUrl, installationId);
      log.info({ userId, action: "repaired-origin" }, "ensure-workspace-repo: repaired");
      return;
    }
    // No `.git` at all → clone the connected repo into the existing workspace dir.
    await graftFn(workspacePath, repoUrl, installationId);
    log.info({ userId, action: "cloned" }, "ensure-workspace-repo: cloned connected repo");
  } catch (err) {
    // Fail-soft: surface to Sentry, never crash the conversation. Token never logged.
    reportSilentFallback(err, {
      feature: "ensure-workspace-repo",
      op: "clone",
      extra: { userId, hasInstallation: true },
      message: "ensure-workspace-repo failed; Concierge proceeds degraded (no clone)",
    });
  }
}

/**
 * Graft the connected repo onto an existing (possibly scaffold-populated) workspace
 * dir: clone shallowly into a temp subdir (same filesystem → rename is atomic),
 * move the `.git` onto the workspace, then `checkout -f <defaultBranch>` to
 * materialize tracked files over the scaffold. The token is supplied to the clone
 * via GIT_ASKPASS (env), never embedded in the remote URL.
 */
async function realGraftRepoClone(
  workspacePath: string,
  repoUrl: string,
  installationId: number,
): Promise<void> {
  const tmp = join(workspacePath, ".ensure-repo-tmp");
  await rm(tmp, { recursive: true, force: true });
  try {
    await gitWithInstallationAuth(
      ["clone", "--depth", "1", repoUrl, tmp],
      installationId,
      { timeout: 120_000 },
    );
    // Capture the default branch from the fresh clone before relocating .git.
    let defaultBranch = "main";
    try {
      const { stdout } = await execFn(
        "git",
        ["-C", tmp, "symbolic-ref", "--short", "HEAD"],
        { timeout: 10_000 },
      );
      const b = stdout.toString().trim();
      if (b) defaultBranch = b;
    } catch {
      /* keep "main" fallback */
    }
    await rm(join(workspacePath, ".git"), { recursive: true, force: true });
    await rename(join(tmp, ".git"), join(workspacePath, ".git")); // same fs
    await execFn(
      "git",
      ["-C", workspacePath, "checkout", "-f", defaultBranch],
      { timeout: 30_000 },
    );
  } finally {
    await rm(tmp, { recursive: true, force: true }).catch(() => {});
  }
}
