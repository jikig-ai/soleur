import { NextResponse } from "next/server";
import path from "path";
import { promises as fs } from "node:fs";
import { createClient } from "@/lib/supabase/server";
import {
  getFreshTenantClient,
  RuntimeAuthError,
} from "@/lib/supabase/tenant";
import { reportSilentFallback } from "@/server/observability";
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

  // PR-C §2.8 (#3244): tenant-scoped workspace read. RLS on `users`
  // enforces `auth.uid() = id`. The `.single()` SELECT IS the auth
  // probe (the route flow reads only the caller's own row before any
  // cross-row work).
  //
  // Tenant-ONLY mint handling (reverted #4919's per-cause service-role fallback).
  // PR #4919 fell back to a SERVICE-ROLE read on the availability causes
  // (`jwt_mint`/`rotation`); PIR #4913 proved that mint failure was a
  // MISDIAGNOSIS — the tenant-JWT mint works in prod (the dead "Generate link"
  // button was the missing-`workspace_id` NOT-NULL insert bug, fixed in #4922).
  // So the service-role escape hatch was dead code that re-widened the read
  // credential; this revert restores the tenant-only boundary:
  //   - `jwt_mint` | `rotation` (availability failures) → 503 "Workspace not
  //     ready" (the surface retries; the genuine prod path never trips this).
  //   - `denied_jti` (deliberate revocation) and any future cause → FAIL CLOSED
  //     with 403, honoring the deny-list on these mutation routes.
  // `reportSilentFallback` still fires for EVERY cause BEFORE the branch, so a
  // chronic mint failure (ceiling trip / GoTrue outage) AND a revocation-hit
  // both stay Sentry-visible (cq-silent-fallback-must-mirror-to-sentry) and the
  // #4920 `kb_tenant_mint_silent_fallback` alert keeps its signal. The path MUST
  // RETURN a Response (never throw): both route handlers call this helper
  // OUTSIDE their try block, so a thrown RuntimeAuthError would escape to
  // Next.js → an uncontrolled 500.
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
      if (mintErr.cause === "jwt_mint" || mintErr.cause === "rotation") {
        // Availability failure — no service-role fallback; surface 503.
        return err(503, "Workspace not ready");
      }
      // `denied_jti` (revocation) or any future cause — honor the deny-list.
      return err(403, "Access denied");
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


