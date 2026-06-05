import { NextResponse } from "next/server";
import path from "path";
import { promises as fs } from "node:fs";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import {
  resolveActiveWorkspaceKbRoot,
  resolveActiveWorkspaceRepoMeta,
} from "@/server/workspace-resolver";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { isPathInWorkspace } from "@/server/sandbox";
// `syncWorkspace` (the git-pull reconcile + gated self-heal) was extracted to
// `@/server/workspace-sync` so surfaces that must stay out of the App-Router
// `next/headers` graph (c4-writer → cc-dispatcher WS bundle) can import it
// without dragging this file's `@/lib/supabase/server` import. Re-exported here
// so existing kb-route-helpers callers are unaffected.
export {
  syncWorkspace,
  type SyncWorkspaceResult,
} from "@/server/workspace-sync";

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

  // ADR-044 resolver consolidation (#4543, #4956). Resolve the active
  // workspace's kbRoot + repo metadata via the two membership-scoped
  // service-role resolvers instead of the legacy tenant `users` read:
  //   - resolveActiveWorkspaceKbRoot → workspacePath + readiness/connectivity
  //     gate, reading the SOURCE OF TRUTH (`workspaces.repo_status` +
  //     the active workspace owner's readiness) — the SAME active workspace the
  //     UI file tree renders from;
  //   - resolveActiveWorkspaceRepoMeta → repo_url + GitHub installation id via
  //     the membership-checked `resolve_workspace_installation_id` SECURITY
  //     DEFINER RPC (the credential is REVOKED from a direct tenant SELECT).
  // This FIXES the #4543 dual-ownership trap on the write routes: the legacy
  // resolver read the CALLER's own `users.{workspace_path,repo_url,installation}`
  // row, which is the empty solo row for an invited member operating on a shared
  // workspace → spurious "Workspace not ready" / "No repository connected". The
  // active-id resolution fails CLOSED to the SOLO workspace (never a sibling),
  // so it is also the IDOR guard. The resolvers return typed Responses and mirror
  // every query error to Sentry, so a credential-read failure stays observable
  // (cq-silent-fallback-must-mirror-to-sentry) — no bare 404/503.
  //
  // Status→message parity (#4956 AC10): the legacy helper returned
  // 503 "Workspace not ready" and 400 "No repository connected"; the resolvers
  // use 404 for not-connected. Clients render `body.error` (not the numeric
  // code), so map to the legacy MESSAGE strings — 503 → "Workspace not ready",
  // 404/400 → "No repository connected".
  const serviceClient = createServiceClient();
  const access = await resolveActiveWorkspaceKbRoot(user.id, serviceClient);
  if (!access.ok) {
    return err(
      access.status,
      access.status === 503 ? "Workspace not ready" : "No repository connected",
    );
  }
  // Pass the already-resolved active id so kbRoot, repo metadata, and the
  // credential all key to ONE membership-resolved id (no divergence under a
  // stale-claim self-heal; no redundant resolution) — mirrors kb/upload.
  const repoMeta = await resolveActiveWorkspaceRepoMeta(
    user.id,
    serviceClient,
    access.activeWorkspaceId,
  );
  if (!repoMeta.ok) {
    return err(
      repoMeta.status,
      repoMeta.status === 503 ? "Workspace not ready" : "No repository connected",
    );
  }
  const userData = {
    workspace_path: access.workspacePath,
    repo_url: repoMeta.repoUrl,
    github_installation_id: repoMeta.githubInstallationId,
  };

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
