import { NextResponse } from "next/server";
import path from "node:path";
import { promises as fs, constants as fsConstants } from "node:fs";
import { createServiceClient } from "@/lib/supabase/server";
import { workspacePathForWorkspaceId } from "@/server/workspace-resolver";
import { isPathInWorkspace } from "@/server/sandbox";
import {
  shareEndpointThrottle,
  extractClientIpFromHeaders,
  logRateLimitRejection,
} from "@/server/rate-limiter";
import { C4_MODEL_JSON, MAX_C4_BYTES } from "@/lib/c4-constants";
import logger from "@/server/logger";
import { reportSilentFallback } from "@/server/observability";

export const runtime = "nodejs";

// Every 4xx/5xx emits Cache-Control: no-store so a shared cache (Cloudflare,
// corporate proxy) cannot pin an error state past its natural lifetime —
// especially the revoked-share 410. Matches app/api/shared/[token]/route.ts.
function jsonNoStore(body: unknown, status: number): Response {
  return NextResponse.json(body, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

// Only the columns the C4 boundary needs. Unlike the markdown route we do NOT
// read content_sha256: the markdown hash gate covers the .md bytes, while the
// committed model.likec4.json is a separate file whose freshness is independent
// (parity with the authenticated viewer, which does not hash-gate the model).
type ShareRow = {
  document_path: string;
  revoked: boolean;
  // ADR-044: KB root is keyed off the share's workspace_id, never the caller's
  // session — this endpoint is anonymous, there is no caller workspace.
  workspace_id: string;
};

/**
 * GET /api/shared/[token]/c4
 *
 * Public, token-scoped LikeC4 data endpoint. Resolves the KB root from the
 * SHARE ROW's `workspace_id` (no Supabase auth) and serves the precomputed,
 * layouted model (`model.likec4.json`) for the shared document's OWN diagram
 * directory. Gated only by a valid, non-revoked share token + rate limit.
 *
 * Data-minimization: returns `{ dir, dump, viewIds }` and OMITS the raw `.c4`
 * `sources` (those are consumed only by the owner Code-tab editor, which the
 * public share never renders). This removes a source-text exposure class.
 *
 * The `dir` is derived server-side from `dirname(document_path)` — a
 * client-supplied `?dir` is ignored. This binds a token to its document's
 * diagram project and blocks pivoting to other workspace dirs.
 */
export async function GET(
  request: Request,
  { params }: { params: Promise<{ token: string }> },
) {
  const { token } = await params;

  const clientIp = extractClientIpFromHeaders(request.headers);
  if (!shareEndpointThrottle.isAllowed(clientIp)) {
    logRateLimitRejection("share-endpoint", clientIp);
    return jsonNoStore({ error: "Too many requests" }, 429);
  }

  const serviceClient = createServiceClient();
  const { data: shareLink, error: fetchError } = await serviceClient
    .from("kb_share_links")
    .select("document_path, revoked, workspace_id")
    .eq("token", token)
    .single<ShareRow>();

  if (fetchError || !shareLink) {
    return jsonNoStore({ error: "Not found" }, 404);
  }
  if (shareLink.revoked) {
    return jsonNoStore(
      { error: "This link has been disabled", code: "revoked" },
      410,
    );
  }

  const kbRoot = path.join(
    workspacePathForWorkspaceId(shareLink.workspace_id),
    "knowledge-base",
  );

  // Derive the C4 dir from the shared document's own directory — NEVER from the
  // query string. document_path is server-controlled (validated at share-create),
  // but the explicit \0/.. reject + isPathInWorkspace below are defense-in-depth,
  // mirroring app/api/kb/c4/project/route.ts:55-62.
  const dir = path.dirname(shareLink.document_path);
  if (dir.includes("\0") || dir.includes("..")) {
    return jsonNoStore({ error: "Invalid dir" }, 400);
  }
  const dirAbs = path.join(kbRoot, dir);
  if (!isPathInWorkspace(dirAbs, kbRoot)) {
    return jsonNoStore({ error: "Invalid dir" }, 400);
  }

  try {
    const jsonAbs = path.join(dirAbs, C4_MODEL_JSON);
    if (!isPathInWorkspace(jsonAbs, kbRoot)) {
      return jsonNoStore({ error: "Invalid dir" }, 400);
    }
    let dump: unknown;
    // Open once and read from the same descriptor — checking via lstat then
    // re-reading by path is a TOCTOU race. O_NOFOLLOW rejects a symlinked final
    // component atomically; fstat on the open fd reads the same inode we read
    // from. (CodeQL js/file-system-race — mirrors the authenticated route.)
    let handle: fs.FileHandle | undefined;
    try {
      handle = await fs.open(
        jsonAbs,
        fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW,
      );
      const stat = await handle.stat();
      if (stat.size > MAX_C4_BYTES) {
        return jsonNoStore({ error: "Diagram model too large" }, 413);
      }
      dump = JSON.parse(await handle.readFile("utf8"));
    } catch (e) {
      const code = (e as NodeJS.ErrnoException).code;
      if (code === "ENOENT") {
        logger.info(
          { event: "shared_c4_not_built", token, dir },
          "shared-c4: diagram model not built",
        );
        return jsonNoStore(
          {
            error:
              "Diagram model not built. Run `/soleur:architecture render` to generate it.",
            code: "MODEL_NOT_BUILT",
          },
          404,
        );
      }
      // O_NOFOLLOW on a symlink → ELOOP; treat as a rejected unsafe/oversized model.
      if (code === "ELOOP") {
        return jsonNoStore({ error: "Diagram model too large" }, 413);
      }
      throw e;
    } finally {
      await handle?.close();
    }

    const viewIds = Object.keys(
      (dump as { views?: Record<string, unknown> }).views ?? {},
    );

    logger.info(
      { event: "shared_c4_served", token, dir, viewCount: viewIds.length },
      "shared-c4: document diagram served",
    );

    return NextResponse.json(
      { dir, dump, viewIds },
      { status: 200, headers: { "Cache-Control": "private, no-cache" } },
    );
  } catch (error) {
    reportSilentFallback(error, {
      feature: "shared-c4",
      op: "serve",
      extra: { token },
    });
    return jsonNoStore({ error: "Failed to load diagram" }, 500);
  }
}
