// Server-only: the single write path for canonical LikeC4 diagram sources.
// Both the UI editor (PUT /api/kb/c4/[...path]) and the Concierge MCP tool
// (edit_c4_diagram) funnel through here, so the diagrams-dir scope guard
// (`isC4DiagramPath`) is enforced in exactly one place. The Concierge's generic
// Edit/Write tools stay hard-blocked (cc-dispatcher CC_PATH_DISALLOWED_TOOLS);
// this is its ONLY sanctioned write capability.
//
// NOTE: no `import "server-only"` here (unlike most server/ modules). The
// Concierge edit_c4_diagram tool bundles this file into the WS/custom server
// via esbuild, which — unlike Next's bundler — cannot resolve the `server-only`
// guard package and crashes the server at startup. This module is server-only
// by construction (GitHub API + git), and its only importers are server code
// (the PUT route + the MCP tool), so dropping the build-time guard is safe.
// Mirrors the earlier c4-compute.ts removal for the same vitest/esbuild reason.
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
import {
  isC4DiagramPath,
  C4_DIAGRAMS_DIR,
  C4_MODEL_JSON,
  C4_SOURCE_EXT,
} from "@/lib/c4-constants";
import { renameUserIdToHash } from "@/server/userid-pseudonymize";
import { reportSilentFallback } from "@/server/observability";
import { renderC4Model } from "@/server/c4-render";
import { sanitizeForLog } from "@/lib/log-sanitize";
import { open } from "node:fs/promises";
import { constants as fsConstants } from "node:fs";
import { join } from "node:path";
import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";

const MAX_C4_WRITE_BYTES = 256 * 1024;
// The layouted model JSON can be far larger than the 256 KB source cap — mirror
// the GET /project route's bound so a pathological re-render can't commit an
// unbounded blob.
const MAX_C4_MODEL_BYTES = 4 * 1024 * 1024;

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
  | {
      ok: true;
      commitSha: string | null;
      rerendered: boolean;
      // Present only on a re-render FAILURE (`rerendered:false`): a concise,
      // sanitized, user-facing reason the diagram didn't update (e.g. an
      // unresolved-reference hint). Absent on success and on `.md` saves.
      rerenderDiagnostic?: string;
    }
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

    // Layer 2 (#4964): after a `.c4` source change, regenerate the precomputed
    // model.likec4.json out-of-process so the rendered diagram actually updates.
    // `.md` view-embed saves don't change layout, so the diagram is already
    // current → rerendered:true with no work. The re-render is best-effort and
    // failure-isolated: the `.c4` commit above is the load-bearing success and
    // is NEVER rolled back. On any re-render/commit/sync failure we report and
    // return rerendered:false, degrading to the Layer-1 honest-stale banner.
    let rerendered = true;
    let rerenderDiagnostic: string | undefined;
    if (relativePath.endsWith(C4_SOURCE_EXT)) {
      const r = await rerenderAndCommit({
        installationId,
        owner,
        repo,
        workspacePath,
        userId,
        relativePath,
      });
      rerendered = r.rerendered;
      rerenderDiagnostic = r.diagnostic;
    }
    return {
      ok: true,
      commitSha: result?.commit?.sha ?? null,
      rerendered,
      ...(rerenderDiagnostic ? { rerenderDiagnostic } : {}),
    };
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

type RerenderInput = {
  installationId: number;
  owner: string;
  repo: string;
  workspacePath: string;
  userId: string;
  relativePath: string;
};

type RerenderOutcome = {
  rerendered: boolean;
  /** A concise, user-facing reason on failure (e.g. an unresolved-reference
   *  hint). Only set when the failure is the user's source (empty/invalid
   *  render); absent for internal failures (oversized model, resync, etc.). */
  diagnostic?: string;
};

/**
 * Turn a render-failure `detail` (the captured `likec4` stderr) into a concise,
 * sanitized, user-facing diagnostic. Prefers the first `Could not resolve …`
 * line — the actionable cause, usually a `spec.c4` that defines the element
 * kinds/tags is missing — over the raw multi-line dump.
 */
function buildRerenderDiagnostic(detail: string | undefined): string {
  const raw = detail ?? "";
  const match = raw.match(/Could not resolve reference to \w+ named '[^']+'/);
  if (match) {
    return sanitizeForLog(
      `Re-render failed: ${match[0]} (is spec.c4 present?)`,
      200,
    );
  }
  return sanitizeForLog(
    "Re-render failed: the diagram model is empty or invalid.",
    200,
  );
}

/**
 * Regenerate `model.likec4.json` via the out-of-process `likec4` CLI, commit it
 * through the same GitHub Contents API path, and re-sync the clone so the
 * committed JSON survives the next reconcile/GC and the GET /project route reads
 * the fresh `dump`. Returns `{ rerendered:true }` only on full success; any
 * failure is reported (mirrored to Sentry) and returns `{ rerendered:false }`
 * (with a user-facing `diagnostic` when the cause is the user's source) — the
 * caller has already committed the `.c4` source, so a re-render failure never
 * fails the save, and an empty/invalid render NEVER commits over the good model
 * (renderC4Model validated to a temp file and left the real JSON untouched).
 */
async function rerenderAndCommit(
  input: RerenderInput,
): Promise<RerenderOutcome> {
  const { installationId, owner, repo, workspacePath, userId, relativePath } =
    input;
  const jsonRelPath = `${C4_DIAGRAMS_DIR}/${C4_MODEL_JSON}`;
  const jsonFilePath = `knowledge-base/${jsonRelPath}`;
  try {
    const render = await renderC4Model(workspacePath);
    if (!render.ok) {
      reportSilentFallback(new Error(render.detail ?? render.reason), {
        feature: "c4-rerender",
        op: "render",
        // Only `relativePath` (charset-constrained KB path) goes in `extra` —
        // the userIdHash + feature/op tags already locate the tenant, and the
        // absolute workspacePath is internal-topology noise in telemetry.
        extra: { userId, relativePath, reason: render.reason },
        message: "c4 re-render failed — source committed, diagram stale",
      });
      // Surface a user-facing diagnostic ONLY when the user's source is the
      // cause (empty_model). For our own io_error / timeout / non_zero_exit /
      // spawn_error, stay silent (honest stale banner) — don't blame the source.
      return {
        rerendered: false,
        ...(render.reason === "empty_model"
          ? { diagnostic: buildRerenderDiagnostic(render.detail) }
          : {}),
      };
    }

    // Read the regenerated JSON off the diagrams dir (renderC4Model validated
    // the temp export and copied it onto this real path) and commit it via the
    // same Contents API path. The path is constant-derived (no user input), but
    // open with O_NOFOLLOW + an fd-stat size cap to match the GET /project
    // route's TOCTOU/symlink hardening (CodeQL js/file-system-race) — the
    // copyFile target could be a planted symlink at this path.
    const jsonAbsPath = join(
      workspacePath,
      "knowledge-base",
      C4_DIAGRAMS_DIR,
      C4_MODEL_JSON,
    );
    let json: string;
    const handle = await open(
      jsonAbsPath,
      fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW,
    );
    try {
      const stat = await handle.stat();
      if (stat.size > MAX_C4_MODEL_BYTES) {
        reportSilentFallback(new Error(`model.likec4.json ${stat.size}B exceeds cap`), {
          feature: "c4-rerender",
          op: "commit-json",
          extra: { userId, relativePath, size: stat.size },
          message: "c4 re-render: regenerated model too large to commit",
        });
        return { rerendered: false };
      }
      json = await handle.readFile("utf8");
    } finally {
      await handle.close();
    }

    let jsonSha: string | undefined;
    try {
      const existing = await githubApiGet<{ sha: string; type: string }>(
        installationId,
        `/repos/${owner}/${repo}/contents/${jsonFilePath}`,
      );
      jsonSha = Array.isArray(existing) ? undefined : existing.sha;
    } catch (err) {
      if (!(err instanceof GitHubApiError) || err.statusCode !== 404) throw err;
    }

    await githubApiPost(
      installationId,
      `/repos/${owner}/${repo}/contents/${jsonFilePath}`,
      {
        message: `Re-render ${C4_MODEL_JSON} via Soleur diagram editor`,
        content: Buffer.from(json, "utf8").toString("base64"),
        ...(jsonSha ? { sha: jsonSha } : {}),
      },
      "PUT",
    );

    const resync = await syncWorkspace(installationId, workspacePath, logger, {
      userId,
      op: "manual",
    });
    if (!resync.ok) {
      reportSilentFallback(resync.error, {
        feature: "c4-rerender",
        op: "resync",
        extra: { userId, relativePath },
        message: "c4 re-render: JSON committed but re-sync failed",
      });
      return { rerendered: false };
    }

    logger.info(
      { event: "c4_rerender", path: jsonFilePath, durationMs: render.durationMs },
      "kb/c4: diagram re-rendered",
    );
    return { rerendered: true };
  } catch (err) {
    reportSilentFallback(err, {
      feature: "c4-rerender",
      op: "commit-json",
      extra: { userId, relativePath },
      message: "c4 re-render: regenerate/commit failed — source committed, diagram stale",
    });
    return { rerendered: false };
  }
}
