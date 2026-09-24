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
import { reportSilentFallback, warnSilentFallback } from "@/server/observability";
import { renderC4Model, type RenderFailure } from "@/server/c4-render";
import {
  stageCommittedC4Sources,
  listCommittedDiagrams,
  statusOf,
  DIAGRAMS_UNREADABLE_DETAIL,
  RATE_LIMITED_DETAIL,
  FORBIDDEN_DETAIL,
  type RefusalClass,
  type StageResult,
} from "@/server/c4-stage-sources";
import { sanitizeForLog } from "@/lib/log-sanitize";
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
        // #8623: the render input is THIS commit's diagrams subtree, fetched
        // from GitHub — never the (tenant-writable) workspace.
        commitSha: result?.commit?.sha,
        content,
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
  /** The commit GitHub returned for the `.c4` write. */
  commitSha: string | undefined;
  /** The bytes just committed — staged without re-downloading them. */
  content: string;
};

type RerenderOutcome = {
  rerendered: boolean;
  /** A concise, user-facing reason on failure (the UI shows
   *  `Saved — ${diagnostic}`). Absent only when a newer source change
   *  supersedes this render (see rerenderAndCommit): nothing on the page
   *  refreshes on its own, so the banner names the supersede instead. */
  diagnostic?: string;
};

// User-facing copy (CPO-approved, plan 2026-09-24 "Behaviour changes a tenant
// can see", adjusted at review). Plain text — the UI renders it after
// "Saved — ", so quotes, not backticks.
export const RETRY_DIAGNOSTIC = "diagram not updated for this save. Save again to retry.";
export const RATE_LIMITED_DIAGNOSTIC =
  "diagram not updated: GitHub's rate limit for this repository was reached. Save again in a few minutes.";
export const FORBIDDEN_DIAGNOSTIC =
  "diagram not updated: GitHub denied access to the diagrams folder. Check that the Soleur GitHub app still has access to this repository.";
export const UNREADABLE_DIAGNOSTIC =
  "diagram not updated: the diagrams folder could not be read from GitHub. " +
  "If a parent folder is a symbolic link, replace it with a real folder in your GitHub repository.";
export const FOLDER_DIAGNOSTIC =
  "diagram not updated: the diagrams folder, or a folder above it, is a symbolic link or a submodule. " +
  "Replace it with a real folder in your GitHub repository to turn automatic updates back on.";
export const TOO_LARGE_DIAGNOSTIC =
  "diagram not updated: the diagrams folder has more than 50 diagram files or more than 4 MB of diagram source, " +
  "which is too much to update automatically. Combine or remove some diagram files to turn automatic updates back on.";
export const MODEL_TOO_LARGE_DIAGNOSTIC =
  "diagram not updated: the rendered diagram is larger than 4 MB, which is too large to save. Simplify the diagram to turn automatic updates back on.";
export const INTERNAL_DIAGNOSTIC =
  "diagram not updated: the diagram could not be rendered this time. Save again to retry; if it keeps happening, contact support.";
export const REFUSAL_NOUN: Record<"likec4-config" | "symlink" | "gitlink", string> = {
  "likec4-config": "a likec4 config file",
  symlink: "a symbolic link",
  gitlink: "a submodule",
};
const MAX_DIAGNOSTIC_PATH = 60;

/**
 * The offender path is chosen by whoever pushed to the tenant repo, and it
 * reaches the Concierge's context through `rerenderDiagnostic`. Reduce it to
 * `[A-Za-z0-9._/-]` (which also removes C0/DEL/U+2028/U+2029/bidi controls and
 * quotes) and cap it, keeping the END (the file name identifies the file).
 */
export function sanitizeDiagnosticPath(p: string): string {
  const clean = p.replace(/[^A-Za-z0-9._/-]/g, "_");
  return clean.length <= MAX_DIAGNOSTIC_PATH ? clean : `...${clean.slice(-(MAX_DIAGNOSTIC_PATH - 3))}`;
}

/** The user-facing reason a refused tree was not rendered. */
export function unsafeSourceDiagnostic(
  refusalClass: RefusalClass,
  path: string | undefined,
  more: number,
): string {
  if (refusalClass === "diagrams-folder") return FOLDER_DIAGNOSTIC;
  if (refusalClass === "too-large" || !path) return TOO_LARGE_DIAGNOSTIC;
  const text =
    `diagram not updated: "${sanitizeDiagnosticPath(path)}" (${REFUSAL_NOUN[refusalClass]}) ` +
    "isn't supported in the diagrams folder. Remove it from your GitHub repository to turn " +
    "automatic updates back on.";
  return more > 0 ? `${text} (and ${more} more)` : text;
}

/**
 * Turn a render failure into the user-facing diagnostic. Every failure gets
 * one (a failed render never implies a later automatic refresh): the likec4
 * `Could not resolve …` line for `empty_model` (the user's source is broken),
 * class-specific copy for staging refusals and fetch failures, and a neutral
 * retry line for our own internal failures.
 */
function buildRerenderDiagnostic(render: RenderFailure): string {
  if (render.reason === "unsafe_source") {
    return unsafeSourceDiagnostic(render.refusalClass, render.path, render.more);
  }
  if (render.phase === "stage") {
    if (render.detail === DIAGRAMS_UNREADABLE_DETAIL) return UNREADABLE_DIAGNOSTIC;
    if (render.detail === RATE_LIMITED_DETAIL) return RATE_LIMITED_DIAGNOSTIC;
    if (render.detail === FORBIDDEN_DETAIL) return FORBIDDEN_DIAGNOSTIC;
    return RETRY_DIAGNOSTIC;
  }
  if (render.reason !== "empty_model") return INTERNAL_DIAGNOSTIC;
  const raw = render.detail ?? "";
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

const HEAD_RELIST_TIMEOUT_MS = 5_000;

/**
 * Regenerate `model.likec4.json` from the committed diagrams sources of
 * `commitSha` (staged from GitHub into a private dir — #8623), commit it
 * through the same GitHub Contents API path, and re-sync the clone so the GET
 * /project route reads the fresh `dump`. Returns `{ rerendered:true }` only on
 * full success; any failure is reported and returns `{ rerendered:false }`
 * with a user-facing `diagnostic` — the caller has already committed the
 * `.c4` source, so a re-render failure never fails the save, and an
 * empty/invalid render NEVER commits over the good model.
 *
 * Concurrent saves: before the model PUT, HEAD's diagrams listing is re-read
 * and its SOURCE SET (path + blob sha pairs) must equal the one rendered —
 * otherwise a newer source change is on HEAD and this render is superseded
 * (no commit; a newer save through the editor or Concierge renders its own).
 * When HEAD's tree is itself refused, no later save can render it, so that
 * case returns the refusal diagnostic instead of a silent supersede. A newer
 * source change pushed from outside Soleur is still a silent supersede: the
 * diagram catches up on the next save.
 * The PUT then carries HEAD's model sha from that same listing, so a model
 * committed in between fails the PUT (409/422) and the check runs once more.
 * Comparing sources rather than model bytes is what stops an older render
 * landing after an undo: the undo restores the old MODEL bytes, never the old
 * source set. A source change pushed from outside Soleur in the milliseconds
 * between the re-read and the PUT is not caught; the next save re-renders.
 */
async function rerenderAndCommit(
  input: RerenderInput,
): Promise<RerenderOutcome> {
  const { installationId, owner, repo, workspacePath, userId, relativePath, commitSha, content } =
    input;
  const jsonRelPath = `${C4_DIAGRAMS_DIR}/${C4_MODEL_JSON}`;
  const jsonFilePath = `knowledge-base/${jsonRelPath}`;
  if (!commitSha) {
    reportSilentFallback(new Error("no commit sha"), {
      feature: "c4-rerender",
      op: "render",
      extra: { userId, relativePath, reason: "io_error" },
      tags: { reason: "io_error", phase: "stage" },
      message: "c4 re-render failed — source committed, diagram stale",
    });
    return { rerendered: false, diagnostic: RETRY_DIAGNOSTIC };
  }
  try {
    let staged: StageResult | undefined;
    const render = await renderC4Model(async (destDir, signal) => {
      staged = await stageCommittedC4Sources({
        installationId,
        owner,
        repo,
        commitSha,
        destDir,
        signal,
        known: [Buffer.from(content, "utf8")],
      });
      return staged;
    });
    if (!render.ok) {
      if (render.reason === "unsafe_source") {
        // A recurring, tenant-caused condition (e.g. an imported repo with a
        // legitimate likec4.config.json): warning level, not an error per
        // save. The offender path is tenant-chosen: in neither tags nor extra.
        warnSilentFallback(new Error(`c4 re-render refused: ${render.refusalClass}`), {
          feature: "c4-rerender",
          op: "render",
          extra: { userId, relativePath, reason: render.reason, refusalClass: render.refusalClass },
          tags: { reason: render.reason, refusalClass: render.refusalClass, phase: "stage" },
          message: "c4 re-render refused the committed diagrams tree — source committed, diagram stale",
        });
      } else {
        // err = null: a real Error is captured first by the pino mirror and
        // Sentry drops the tagged capture (#8629). A fixed message per reason
        // keeps grouping stable; `detail_class` opens one issue per failure
        // class. A slot wait is load, not a defect: warning level.
        const report = render.detailClass === "slot-wait" ? warnSilentFallback : reportSilentFallback;
        report(null, {
          feature: "c4-rerender",
          op: "render",
          // Only `relativePath` (charset-constrained KB path) goes in `extra` —
          // the userIdHash + feature/op tags already locate the tenant, and the
          // absolute workspacePath is internal-topology noise in telemetry.
          extra: { userId, relativePath, reason: render.reason, detail: render.detail },
          tags: {
            reason: render.reason,
            phase: render.phase,
            detail_class: render.detailClass ?? "other",
          },
          message: `c4 re-render failed: ${render.reason}`,
        });
      }
      return { rerendered: false, diagnostic: buildRerenderDiagnostic(render) };
    }
    if (!staged?.ok) {
      // Cannot happen (a successful render implies a successful stage); if a
      // refactor ever breaks that, never commit without a verified source set.
      reportSilentFallback(new Error("render ok without a staged source set"), {
        feature: "c4-rerender",
        op: "commit-json",
        extra: { userId, relativePath },
        tags: { phase: "commit" },
        message: "c4 re-render: no staged source set — model not committed",
      });
      return { rerendered: false, diagnostic: INTERNAL_DIAGNOSTIC };
    }
    const renderedSourceKey = staged.sourceKey;

    // renderC4Model returned the validated bytes in-process (#4976) — commit
    // them directly via the same Contents API path. Cap on the exact bytes we
    // are about to commit.
    const json = render.json;
    const size = Buffer.byteLength(json, "utf8");
    if (size > MAX_C4_MODEL_BYTES) {
      reportSilentFallback(new Error(`model.likec4.json ${size}B exceeds cap`), {
        feature: "c4-rerender",
        op: "commit-json",
        extra: { userId, relativePath, size },
        tags: { phase: "commit" },
        message: "c4 re-render: regenerated model too large to commit",
      });
      return { rerendered: false, diagnostic: MODEL_TOO_LARGE_DIAGNOSTIC };
    }

    const superseded = (why: string) => {
      logger.warn(
        { event: "c4_rerender_superseded", path: jsonFilePath, why },
        "kb/c4: re-render superseded by a newer save",
      );
      return { rerendered: false };
    };
    let committed = false;
    for (let attempt = 0; attempt < 2 && !committed; attempt++) {
      const head = await listCommittedDiagrams({
        installationId,
        owner,
        repo,
        signal: AbortSignal.timeout(HEAD_RELIST_TIMEOUT_MS),
      });
      if (!head.ok) {
        // HEAD now carries something the render refuses: a newer source change
        // (not this render's) — superseded, not an incident. Unlike a plain
        // supersede, no later save will render it either (every save stages
        // HEAD's tree), so name the refused file rather than leave the
        // Concierge to promise the diagram "will update shortly".
        if (head.reason === "unsafe_source") {
          superseded("head-refused");
          return {
            rerendered: false,
            diagnostic: unsafeSourceDiagnostic(head.refusalClass, head.path, head.more),
          };
        }
        throw new Error(`HEAD re-list failed: ${head.reason}`);
      }
      if (head.sourceKey !== renderedSourceKey) return superseded("sources-changed");
      try {
        await githubApiPost(
          installationId,
          `/repos/${owner}/${repo}/contents/${jsonFilePath}`,
          {
            message: `Re-render ${C4_MODEL_JSON} via Soleur diagram editor`,
            content: Buffer.from(json, "utf8").toString("base64"),
            ...(head.modelSha ? { sha: head.modelSha } : {}),
          },
          "PUT",
        );
        committed = true;
      } catch (err) {
        const status = statusOf(err);
        // The model moved between the re-read and the PUT: re-check once. A
        // second conflict throws to the catch below — never loops.
        if ((status !== 409 && status !== 422) || attempt === 1) throw err;
      }
    }

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
      // The model IS committed on GitHub but not on this clone, so the page
      // keeps the old diagram until a re-save re-syncs it (#8695).
      return { rerendered: false, diagnostic: RETRY_DIAGNOSTIC };
    }

    logger.info(
      {
        event: "c4_rerender",
        path: jsonFilePath,
        durationMs: render.durationMs,
        queueWaitMs: render.queueWaitMs,
      },
      "kb/c4: diagram re-rendered",
    );
    return { rerendered: true };
  } catch (err) {
    reportSilentFallback(err, {
      feature: "c4-rerender",
      op: "commit-json",
      extra: { userId, relativePath },
      tags: { phase: "commit" },
      message: "c4 re-render: regenerate/commit failed — source committed, diagram stale",
    });
    return { rerendered: false, diagnostic: RETRY_DIAGNOSTIC };
  }
}
