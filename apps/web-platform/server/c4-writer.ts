// Server-only: the single write path for canonical LikeC4 diagram sources.
// Both the UI editor (PUT /api/kb/c4/[...path]) and the Concierge MCP tool
// (edit_c4_diagram) funnel through here, so the diagrams-dir scope guard
// (`isC4DiagramPath`) is enforced in exactly one place. The Concierge's generic
// Edit/Write tools stay hard-blocked (cc-dispatcher CC_PATH_DISALLOWED_TOOLS);
// this is its ONLY sanctioned write capability.
import "server-only";
import {
  githubApiGet,
  githubApiPost,
  GitHubApiError,
} from "@/server/github-api";
// Import from the leaf workspace-sync module (NOT kb-route-helpers) so this
// file — bundled into the WS/custom server via the Concierge edit_c4_diagram
// tool — does not pull kb-route-helpers' `@/lib/supabase/server` (next/headers)
// into the server bundle, which crashes the custom server at startup.
import { syncWorkspace } from "@/server/workspace-sync";
import { isC4DiagramPath } from "@/lib/c4-constants";
import { renameUserIdToHash } from "@/server/userid-pseudonymize";
import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";

const MAX_C4_WRITE_BYTES = 256 * 1024;

export type WriteC4Input = {
  userId: string;
  installationId: number;
  owner: string;
  repo: string;
  workspacePath: string;
  /** KB-relative path, forward-slashed, e.g. "engineering/architecture/diagrams/model.c4". */
  relativePath: string;
  content: string;
};

export type WriteC4Result =
  | { ok: true; commitSha: string | null }
  | { ok: false; status: number; error: string; code?: string };

/**
 * Commit `content` to a canonical diagram source via the GitHub Contents API,
 * then pull the workspace so the on-disk clone (read by the compute route)
 * matches. Rejects any path outside the diagrams dir.
 */
export async function writeC4Diagram(
  input: WriteC4Input,
): Promise<WriteC4Result> {
  const { userId, installationId, owner, repo, workspacePath, relativePath, content } =
    input;

  // --- Scope guard (security-critical) ------------------------------------
  if (!isC4DiagramPath(relativePath)) {
    return {
      ok: false,
      status: 400,
      error: "Path is not a writable diagram source",
      code: "OUT_OF_SCOPE",
    };
  }
  if (typeof content !== "string" || content.length === 0) {
    return { ok: false, status: 400, error: "Content required" };
  }
  if (Buffer.byteLength(content, "utf8") > MAX_C4_WRITE_BYTES) {
    return { ok: false, status: 413, error: "Diagram source too large" };
  }

  const filePath = `knowledge-base/${relativePath}`;
  const fileName = relativePath.split("/").pop() ?? relativePath;
  // Pseudonymise userId at the source per #3698 — log `userIdHash`, never the
  // raw id. Computed off the logger line so the source carries no raw token.
  const userLog = renameUserIdToHash({ userId });

  try {
    // Resolve current blob sha (update) — absent means create.
    let sha: string | undefined;
    try {
      const existing = await githubApiGet<{ sha: string; type: string }>(
        installationId,
        `/repos/${owner}/${repo}/contents/${filePath}`,
      );
      sha = Array.isArray(existing) ? undefined : existing.sha;
    } catch (err) {
      if (!(err instanceof GitHubApiError) || err.statusCode !== 404) throw err;
    }

    const result = await githubApiPost<{ commit: { sha: string } }>(
      installationId,
      `/repos/${owner}/${repo}/contents/${filePath}`,
      {
        message: `Update ${fileName} via Soleur diagram editor`,
        content: Buffer.from(content, "utf8").toString("base64"),
        ...(sha ? { sha } : {}),
      },
      "PUT",
    );

    const sync = await syncWorkspace(installationId, workspacePath, logger, {
      userId,
      op: "manual",
    });
    if (!sync.ok) {
      Sentry.captureException(sync.error);
      return {
        ok: false,
        status: 500,
        error: "Committed to GitHub but workspace sync failed. Try refreshing.",
        code: "SYNC_FAILED",
      };
    }

    logger.info(
      { event: "c4_write", ...userLog, path: filePath },
      "kb/c4: diagram source written",
    );
    return { ok: true, commitSha: result?.commit?.sha ?? null };
  } catch (error) {
    Sentry.captureException(error);
    if (error instanceof GitHubApiError) {
      if (error.statusCode === 409) {
        return {
          ok: false,
          status: 409,
          error: "File changed since last read. Refresh and retry.",
          code: "SHA_MISMATCH",
        };
      }
      logger.error(
        { err: error, ...userLog, path: filePath },
        "kb/c4: GitHub API error",
      );
      return { ok: false, status: 502, error: error.message, code: "GITHUB_API_ERROR" };
    }
    logger.error({ err: error, ...userLog }, "kb/c4: unexpected write error");
    return { ok: false, status: 500, error: "Internal server error" };
  }
}
