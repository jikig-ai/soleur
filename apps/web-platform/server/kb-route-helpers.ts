import { NextResponse } from "next/server";
import path from "path";
import { promises as fs } from "node:fs";
import { createClient, createServiceClient } from "@/lib/supabase/server";
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
  // PER-CAUSE tenant-mint fallback (#4914), diverging from `resolveUserKbRoot`'s
  // all-causes fallback because this helper serves the file PATCH/DELETE
  // *mutation* routes (not the read/share path):
  //   - `jwt_mint` | `rotation` (availability failures — signing/RPC failure, or
  //     the 60/hr per-founder mint ceiling tripped): fall back to a SERVICE-ROLE
  //     read of the caller's OWN row, exactly as `resolveUserKbRoot` does. The
  //     read stays hard-scoped `.eq("id", user.id)` (server-derived session
  //     user, never request-controlled), so the fallback restores availability
  //     without weakening cross-tenant isolation — the mutation then proceeds.
  //   - `denied_jti` (the cached JWT's jti landed in `public.denied_jti` — a
  //     DELIBERATE revocation) and any future un-named cause: FAIL CLOSED with a
  //     403. Unlike the share path (whose privileged `createShare` write was
  //     already service-role, so the deny-list never gated it), here the
  //     downstream GitHub mutation IS gated on this helper resolving — a
  //     service-role fallback would defeat the revocation's intent. We branch on
  //     the POSITIVE allow-list of availability causes so an unknown 4th cause
  //     fails closed (the safe default on a mutation route), not open.
  // `reportSilentFallback` fires for EVERY cause (incl. `denied_jti`) BEFORE the
  // branch, so a chronic mint failure AND a revocation-hit both stay Sentry-
  // visible (cq-silent-fallback-must-mirror-to-sentry). The fail-closed path
  // MUST RETURN a Response (never throw): both route handlers call this helper
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
        // Availability failure — restore availability via a self-row read.
        tenant = createServiceClient();
      } else {
        // `denied_jti` (revocation) or any future cause — honor the deny-list.
        return err(403, "Access denied");
      }
    } else {
      throw mintErr;
    }
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

  // PR-C §2.8 (#3244): tenant-scoped read is the PRIMARY path. Single-row
  // SELECT IS the auth probe.
  //
  // Regression fix (PR #3854 dead-ended the "Generate link" button): when the
  // tenant JWT mint fails, fall back to a SERVICE-ROLE read of the user's OWN
  // row instead of returning 503. A 503 here resets the share popover to idle
  // — the silent dead-end the user reported.
  //
  // Ceiling that keeps the fallback safe for ALL three `RuntimeAuthError`
  // causes (`jwt_mint` | `rotation` | `denied_jti`): the fallback read is
  // scoped to `.eq("id", userId)` where `userId` is the already-authenticated
  // session user, so even a deny-listed / revoked tenant token can only ever
  // read its OWN workspace row — never another tenant's. The privileged share
  // *write* (`createShare`) on this path was never tenant-scoped (it uses the
  // service-role client at `route.ts`), so the deny-list never gated a
  // privileged action here in the first place; `denied_jti` only blocked this
  // self-read. We still emit `reportSilentFallback` so a chronically-failing
  // mint (ceiling trip / GoTrue outage) stays visible to the operator in
  // Sentry even though users now recover. The fallback applies the same
  // `workspace_status === "ready"` + `extras` validation below, so a
  // genuinely-not-ready workspace still gets the 503.
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
      tenant = createServiceClient();
    } else {
      throw mintErr;
    }
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

