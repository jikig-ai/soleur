import { NextResponse } from "next/server";
import path from "path";
import { promises as fs } from "node:fs";
import { createClient } from "@/lib/supabase/server";
import {
  getFreshTenantClient,
  RuntimeAuthError,
} from "@/lib/supabase/tenant";
import {
  reportSilentFallback,
  warnSilentFallback,
} from "@/server/observability";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { isPathInWorkspace } from "@/server/sandbox";
import {
  ERROR_CLASS_NON_FAST_FORWARD,
  ERROR_CLASS_SYNC_FAILED,
  type KbSyncErrorClass,
} from "@/server/session-sync";
import type { Logger } from "pino";

// git-auth is lazily loaded inside syncWorkspace so that routes which only
// need authenticateAndResolveKbPath / resolveUserKbRoot don't drag
// github-app + its logger child into their test-mock surface. The
// file-route already mocks github-app; share/upload do not need to.

export type KbRouteContext = {
  user: { id: string };
  userData: {
    workspace_path: string;
    repo_url: string;
    github_installation_id: number;
  };
  owner: string;
  repo: string;
  relativePath: string; // e.g. "domain/file.pdf"
  filePath: string; // e.g. "knowledge-base/domain/file.pdf"
  kbRoot: string; // absolute path to workspace/knowledge-base
  fullPath: string; // kbRoot + relativePath
  ext: string; // ".pdf" (lowercased)
};

export type KbRouteOptions = {
  endpoint: string;
  blockMarkdown: boolean;
};

/**
 * Authenticate, validate the KB path, and resolve repo metadata.
 * Returns either a typed context object or a Response error to return.
 *
 * Shared across PATCH and DELETE handlers on /api/kb/file/[...path].
 * `.md` files are rejected when `blockMarkdown: true` (default).
 */
export async function authenticateAndResolveKbPath(
  request: Request,
  params: Promise<{ path: string[] }>,
  opts: KbRouteOptions = {
    endpoint: "api/kb/file",
    blockMarkdown: true,
  },
): Promise<
  | { ok: true; ctx: KbRouteContext }
  | { ok: false; response: Response }
> {
  // CSRF
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) {
    return { ok: false, response: rejectCsrf(opts.endpoint, origin) };
  }

  // Auth
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return err(401, "Unauthorized");

  // PR-C §2.8 (#3244): tenant-scoped workspace read. RLS on `users`
  // enforces `auth.uid() = id`. The `.single()` SELECT IS the auth
  // probe (the route flow reads only the caller's own row before any
  // cross-row work).
  let tenant;
  try {
    tenant = await getFreshTenantClient(user.id);
  } catch (mintErr) {
    if (mintErr instanceof RuntimeAuthError) {
      reportSilentFallback(mintErr, {
        feature: "kb-route-helpers",
        op: "authenticateAndResolveKbPath.tenant-mint",
        extra: { userId: user.id },
      });
      return err(503, "Workspace not ready");
    }
    throw mintErr;
  }
  const { data: userData } = await tenant
    .from("users")
    .select(
      "workspace_path, workspace_status, repo_url, github_installation_id",
    )
    .eq("id", user.id)
    .single();

  if (!userData?.workspace_path || userData.workspace_status !== "ready") {
    return err(503, "Workspace not ready");
  }
  // Fallback to workspace-sibling installation only when the user has a
  // repo but no installation ID (#4543). Skip the fallback when repo_url
  // is also null ("no repository connected" — nothing to resolve for).
  let installationId = userData.github_installation_id;
  if (!installationId && userData.repo_url) {
    const { resolveInstallationId } = await import(
      "@/server/resolve-installation-id"
    );
    installationId = await resolveInstallationId(user.id);
  }
  if (!userData.repo_url || !installationId) {
    return err(400, "No repository connected");
  }
  userData.github_installation_id = installationId;

  // Path
  const { path: pathSegments } = await params;
  const relativePath = pathSegments.join("/");
  if (!relativePath) return err(400, "File path required");
  if (relativePath.includes("\0")) {
    return err(400, "Invalid path: null byte detected");
  }

  const ext = path.extname(relativePath).toLowerCase();
  if (opts.blockMarkdown && ext === ".md") {
    return err(
      400,
      "Markdown files cannot be modified through this endpoint",
    );
  }

  const kbRoot = path.join(userData.workspace_path, "knowledge-base");
  const fullPath = path.join(kbRoot, relativePath);
  if (!isPathInWorkspace(fullPath, kbRoot)) return err(400, "Invalid path");

  // Symlink check (tolerate ENOENT — file may not exist on disk yet)
  try {
    const stat = await fs.lstat(fullPath);
    if (stat.isSymbolicLink()) return err(403, "Access denied");
  } catch (e) {
    const code = (e as NodeJS.ErrnoException).code;
    if (code !== "ENOENT") return err(403, "Access denied");
  }

  // Parse owner/repo
  const repoUrlParts = userData.repo_url.replace(/\.git$/, "").split("/");
  const repo = repoUrlParts.pop();
  const owner = repoUrlParts.pop();
  if (!owner || !repo) return err(500, "Invalid repository URL");

  const filePath = `knowledge-base/${relativePath}`;

  return {
    ok: true,
    ctx: {
      user: { id: user.id },
      userData: {
        workspace_path: userData.workspace_path,
        repo_url: userData.repo_url,
        github_installation_id: userData.github_installation_id,
      },
      owner,
      repo,
      relativePath,
      filePath,
      kbRoot,
      fullPath,
      ext,
    },
  };

  function err(status: number, message: string) {
    return {
      ok: false as const,
      response: NextResponse.json({ error: message }, { status }),
    };
  }
}

type ResolveUserKbRootExtras = "repo_url" | "github_installation_id";

export type ResolveUserKbRootResult<E extends ResolveUserKbRootExtras = never> =
  | {
      ok: true;
      workspacePath: string;
      kbRoot: string;
      extras: { [K in E]: K extends "repo_url" ? string : number };
    }
  | { ok: false; response: Response };

/**
 * Resolve the authenticated user's KB root and workspace status. Returns
 * either { ok: true, kbRoot, workspacePath } or an { ok: false, response }
 * holding the appropriate NextResponse to return from the route handler.
 *
 * Routes that need GitHub repo metadata (upload) can pass `extras: ["repo_url",
 * "github_installation_id"]` to receive those fields plus a 400 "No repository
 * connected" error if either is unset — this mirrors the inline block the
 * upload route used to carry.
 *
 * Note: the file-route helper (`authenticateAndResolveKbPath`) already does
 * auth + CSRF + path-segment validation in one pass for PATCH/DELETE on URL-
 * segment endpoints. `resolveUserKbRoot` is the simpler building block for
 * endpoints where the relative path comes from the request body (upload,
 * share). Both helpers live in this file intentionally: they are the two
 * "workspace entry points" for KB endpoints.
 */
export async function resolveUserKbRoot<
  E extends ResolveUserKbRootExtras = never,
>(
  userId: string,
  opts?: { extras?: readonly E[] },
): Promise<ResolveUserKbRootResult<E>> {
  const selectCols =
    opts?.extras && opts.extras.length > 0
      ? `workspace_path, workspace_status, ${opts.extras.join(", ")}`
      : "workspace_path, workspace_status";

  // PR-C §2.8 (#3244): tenant-scoped. Single-row SELECT IS the auth
  // probe. RuntimeAuthError → same "Workspace not ready" response so
  // callers don't have to discriminate.
  let tenant;
  try {
    tenant = await getFreshTenantClient(userId);
  } catch (mintErr) {
    if (mintErr instanceof RuntimeAuthError) {
      reportSilentFallback(mintErr, {
        feature: "kb-route-helpers",
        op: "resolveUserKbRoot.tenant-mint",
        extra: { userId },
      });
      return {
        ok: false,
        response: NextResponse.json(
          { error: "Workspace not ready" },
          { status: 503 },
        ),
      };
    }
    throw mintErr;
  }
  const { data: userData } = await tenant
    .from("users")
    .select(selectCols)
    .eq("id", userId)
    .single<Record<string, unknown>>();

  if (
    !userData?.workspace_path ||
    userData.workspace_status !== "ready"
  ) {
    return {
      ok: false,
      response: NextResponse.json(
        { error: "Workspace not ready" },
        { status: 503 },
      ),
    };
  }

  if (opts?.extras) {
    for (const k of opts.extras) {
      if (userData[k] === null || userData[k] === undefined) {
        return {
          ok: false,
          response: NextResponse.json(
            { error: "No repository connected" },
            { status: 400 },
          ),
        };
      }
    }
  }

  const workspacePath = userData.workspace_path as string;
  const kbRoot = path.join(workspacePath, "knowledge-base");
  const extras = {} as { [K in E]: K extends "repo_url" ? string : number };
  if (opts?.extras) {
    for (const k of opts.extras) {
      (extras as Record<string, unknown>)[k] = userData[k];
    }
  }
  return { ok: true, workspacePath, kbRoot, extras };
}

/**
 * Result shape returned by {@link syncWorkspace}.
 *
 * - `{ ok: true }` — clean `pull --ff-only`.
 * - `{ ok: true, recovered: true }` — a diverged clone with ZERO un-pushed
 *   local commits was self-healed via `reset --hard origin/<default>`.
 * - `{ ok: false, error, errorClass }` — sync failed and could not be
 *   recovered. `errorClass` is derived from the git stderr/exit signature
 *   (never hard-coded by callers) so the `kb_sync_history` row and the
 *   `KbSyncStatus` desync state classify correctly (#non_fast_forward was
 *   previously unreachable — syncWorkspace is its first producer).
 */
export type SyncWorkspaceResult =
  | { ok: true; recovered?: boolean }
  | { ok: false; error: unknown; errorClass: KbSyncErrorClass };

/**
 * Classify a failed-git error into a {@link KbSyncErrorClass}.
 *
 * The non-fast-forward signature in `git pull --ff-only` stderr is
 * `Not possible to fast-forward` (verified against installed git 2.53.0:
 * `fatal: Not possible to fast-forward, aborting.`). Match on the stable
 * substring so a wording drift in the surrounding hint text (e.g. the
 * "Diverging branches can't be fast-forwarded" advice) does not break it.
 * Everything else (auth, IO, network, timeout) is `sync_failed`.
 */
function classifyGitSyncError(err: unknown): KbSyncErrorClass {
  const text =
    err instanceof Error
      ? `${err.message}\n${(err as { stderr?: string }).stderr ?? ""}`
      : String(err);
  if (text.includes("Not possible to fast-forward")) {
    return ERROR_CLASS_NON_FAST_FORWARD;
  }
  return ERROR_CLASS_SYNC_FAILED;
}

/**
 * Resolve the workspace clone's default branch as `<short>` (e.g. `main`)
 * via `git symbolic-ref --short refs/remotes/origin/HEAD`. Robust across
 * repos that do not use `main` (AC-B5 — never assume `main`). Falls back to
 * `main` only if the symbolic ref is missing (detached `origin/HEAD`); the
 * caller logs the fallback path.
 */
async function resolveDefaultBranch(
  gitWithInstallationAuth: (
    args: string[],
    installationId: number,
    opts: { cwd: string; timeout: number },
  ) => Promise<Buffer | string>,
  installationId: number,
  workspacePath: string,
): Promise<string> {
  try {
    const out = await gitWithInstallationAuth(
      ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"],
      installationId,
      { cwd: workspacePath, timeout: 30_000 },
    );
    const ref = out.toString().trim(); // e.g. "origin/main"
    const branch = ref.replace(/^origin\//, "");
    return branch || "main";
  } catch {
    return "main";
  }
}

/**
 * Pull the workspace to sync local files with the remote repo after a
 * successful GitHub mutation. Uses an installation-scoped credential helper.
 *
 * On a `non_fast_forward` (diverged clone) the function attempts a GATED,
 * OBSERVABLE self-heal: it resets to `origin/<default>` ONLY when the clone
 * holds ZERO un-pushed local commits (`git rev-list --count @{u}..HEAD == 0`).
 * A non-zero count means real, un-pushed agent-session work
 * (`session-sync.ts` auto-commits `knowledge-base/**` into the SAME clone) —
 * the reset is ABORTED and the failure surfaces, never destroying that work
 * (AC-B6). The guard mirrors the existing `hasLocalCommits` probe in
 * `session-sync.ts:200-208`.
 *
 * Returns a {@link SyncWorkspaceResult}. Callers decide which 5xx response
 * shape to return (different handlers include different metadata).
 */
export async function syncWorkspace(
  installationId: number,
  workspacePath: string,
  log: Logger,
  context: {
    userId: string;
    op: "delete" | "rename" | "upload" | "push" | "manual";
  },
): Promise<SyncWorkspaceResult> {
  const { gitWithInstallationAuth } = await import("@/server/git-auth");
  try {
    await gitWithInstallationAuth(
      ["pull", "--ff-only"],
      installationId,
      { cwd: workspacePath, timeout: 30_000 },
    );
    return { ok: true };
  } catch (syncError) {
    const errorClass = classifyGitSyncError(syncError);
    log.error(
      { err: syncError, userId: context.userId, op: context.op, errorClass },
      `kb/${context.op}: workspace sync failed`,
    );
    reportSilentFallback(syncError, {
      feature: "kb-route-helpers",
      op: `workspace-sync-${context.op}`,
      // workspacePath omitted — the path embeds raw userId
      // (workspacePath = `<root>/<userId>`) and bypasses the
      // hashExtraUserId top-level rename (Recital 26).
      extra: { userId: context.userId },
      message: `kb/${context.op}: workspace sync failed`,
    });

    // Gated, observable self-heal for a diverged clone (non-fast-forward).
    if (errorClass === ERROR_CLASS_NON_FAST_FORWARD) {
      return await selfHealNonFastForward(
        gitWithInstallationAuth,
        installationId,
        workspacePath,
        log,
        context,
      );
    }

    return { ok: false, error: syncError, errorClass };
  }
}

/**
 * Gated self-heal for a `non_fast_forward` clone. Fetches the default branch,
 * checks for un-pushed local commits, and ONLY resets when there are none.
 *
 * Observability (AC-B4):
 * - success → `warnSilentFallback` op:self-heal-reset (worth observing, not
 *   paging) + `{ ok: true, recovered: true }` so the caller writes a
 *   `recovered` kb_sync_history row.
 * - un-pushed local commits present → `reportSilentFallback` (fail_loud)
 *   op:self-heal-aborted-dirty + `{ ok: false }`; the reset is NOT run.
 * - fetch/reset error → `reportSilentFallback` (fail_loud) op:self-heal-failed
 *   + `{ ok: false }`.
 *
 * All git ops use the same installation-auth/cwd/timeout envelope as the pull.
 * Payloads OMIT workspacePath (raw userId) per the Recital 26 omission above.
 */
async function selfHealNonFastForward(
  gitWithInstallationAuth: (
    args: string[],
    installationId: number,
    opts: { cwd: string; timeout: number },
  ) => Promise<Buffer | string>,
  installationId: number,
  workspacePath: string,
  log: Logger,
  context: { userId: string; op: string },
): Promise<SyncWorkspaceResult> {
  const gitOpts = { cwd: workspacePath, timeout: 30_000 };
  try {
    const defaultBranch = await resolveDefaultBranch(
      gitWithInstallationAuth,
      installationId,
      workspacePath,
    );

    await gitWithInstallationAuth(
      ["fetch", "origin", defaultBranch],
      installationId,
      gitOpts,
    );

    // Local-commit guard (AC-B6) — mirrors session-sync.ts:200-208.
    const revListOut = await gitWithInstallationAuth(
      ["rev-list", "--count", "@{u}..HEAD"],
      installationId,
      gitOpts,
    );
    const localCommits = parseInt(revListOut.toString().trim(), 10);

    if (Number.isNaN(localCommits) || localCommits > 0) {
      // Real, un-pushed agent-session work — do NOT destroy it.
      log.error(
        { userId: context.userId, op: context.op, localCommits },
        `kb/${context.op}: self-heal aborted — diverged clone holds un-pushed local commits`,
      );
      reportSilentFallback(
        new Error("self-heal aborted: un-pushed local commits present"),
        {
          feature: "kb-route-helpers",
          op: "self-heal-aborted-dirty",
          extra: { userId: context.userId },
          message: `kb/${context.op}: self-heal aborted (un-pushed local commits)`,
        },
      );
      return {
        ok: false,
        error: new Error("non-fast-forward with un-pushed local commits"),
        errorClass: ERROR_CLASS_NON_FAST_FORWARD,
      };
    }

    // Phantom divergence (upstream force-push / corrupted ref). Safe to reset.
    await gitWithInstallationAuth(
      ["reset", "--hard", `origin/${defaultBranch}`],
      installationId,
      gitOpts,
    );

    log.warn(
      { userId: context.userId, op: context.op, defaultBranch },
      `kb/${context.op}: self-heal reset clone to origin/${defaultBranch}`,
    );
    warnSilentFallback(
      new Error("workspace self-healed via reset --hard"),
      {
        feature: "kb-route-helpers",
        op: "self-heal-reset",
        extra: { userId: context.userId },
        message: `kb/${context.op}: workspace clone self-healed (reset to origin/${defaultBranch})`,
      },
    );
    return { ok: true, recovered: true };
  } catch (healError) {
    log.error(
      { err: healError, userId: context.userId, op: context.op },
      `kb/${context.op}: self-heal failed`,
    );
    reportSilentFallback(healError, {
      feature: "kb-route-helpers",
      op: "self-heal-failed",
      extra: { userId: context.userId },
      message: `kb/${context.op}: self-heal failed`,
    });
    return {
      ok: false,
      error: healError,
      errorClass: ERROR_CLASS_NON_FAST_FORWARD,
    };
  }
}
