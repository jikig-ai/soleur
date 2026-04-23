import { NextResponse } from "next/server";
import path from "path";
import { promises as fs } from "node:fs";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { isPathInWorkspace } from "@/server/sandbox";
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

  // Workspace
  const serviceClient = createServiceClient();
  const { data: userData } = await serviceClient
    .from("users")
    .select(
      "workspace_path, workspace_status, repo_url, github_installation_id",
    )
    .eq("id", user.id)
    .single();

  if (!userData?.workspace_path || userData.workspace_status !== "ready") {
    return err(503, "Workspace not ready");
  }
  if (!userData.repo_url || !userData.github_installation_id) {
    return err(400, "No repository connected");
  }

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
  serviceClient: ReturnType<typeof createServiceClient>,
  userId: string,
  opts?: { extras?: readonly E[] },
): Promise<ResolveUserKbRootResult<E>> {
  const selectCols =
    opts?.extras && opts.extras.length > 0
      ? `workspace_path, workspace_status, ${opts.extras.join(", ")}`
      : "workspace_path, workspace_status";

  const { data: userData } = await serviceClient
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
 * Pull the workspace to sync local files with the remote repo after a
 * successful GitHub mutation. Uses an installation-scoped credential helper.
 *
 * Returns { ok: true } on success, { ok: false, error } on failure.
 * Callers decide which 500 response shape to return (different handlers
 * include different metadata — commitSha, oldPath/newPath, etc.).
 */
export async function syncWorkspace(
  installationId: number,
  workspacePath: string,
  log: Logger,
  context: { userId: string; op: "delete" | "rename" | "upload" },
): Promise<{ ok: true } | { ok: false; error: unknown }> {
  const { gitWithInstallationAuth } = await import("@/server/git-auth");
  try {
    await gitWithInstallationAuth(
      ["pull", "--ff-only"],
      installationId,
      { cwd: workspacePath, timeout: 30_000 },
    );
    return { ok: true };
  } catch (syncError) {
    log.error(
      { err: syncError, userId: context.userId, op: context.op },
      `kb/${context.op}: workspace sync failed`,
    );
    return { ok: false, error: syncError };
  }
}
