import { NextResponse } from "next/server";
import path from "path";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import {
  resolveActiveWorkspaceKbRoot,
  resolveActiveWorkspaceRepoMeta,
} from "@/server/workspace-resolver";
import { isPathInWorkspace } from "@/server/sandbox";
import { renameUserIdToHash } from "@/server/userid-pseudonymize";
import { githubApiGet, GitHubApiError } from "@/server/github-api";
import { reportSilentFallback } from "@/server/observability";
import {
  C4_DIAGRAMS_DIR,
  C4_SOURCE_EXT,
  C4_MODEL_JSON,
  MAX_C4_BYTES,
} from "@/lib/c4-constants";
import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";

export const runtime = "nodejs";

type ContentsEntry = { name: string; path: string; sha: string; type: string };
type GitBlob = { content: string; encoding: string; size?: number };

function isGitHub404(err: unknown): boolean {
  return err instanceof GitHubApiError && err.statusCode === 404;
}

/** Fetch a file body from the Git Blobs API and base64-decode it.
 *
 * The Contents API omits the base64 `content` field for files > 1 MB, and
 * `model.likec4.json` is capped at 4 MB (`MAX_C4_BYTES`) — so a 1–4 MB model
 * read via Contents `content` would decode to empty and serve a broken dump
 * WITHOUT tripping the 413 (silent corruption, B2). The Blobs API carries
 * base64 bodies up to 100 MB. base64-decode shape mirrors
 * `server/inngest/functions/cron-ruleset-bypass-audit.ts:100-120`. */
async function fetchBlobUtf8(
  installationId: number,
  owner: string,
  repo: string,
  sha: string,
): Promise<string> {
  const blob = await githubApiGet<GitBlob>(
    installationId,
    `/repos/${owner}/${repo}/git/blobs/${sha}`,
  );
  // `Buffer.from(_, "base64")` tolerates the GitHub-wrapped newlines in the
  // base64 payload.
  return Buffer.from(blob.content ?? "", "base64").toString("utf8");
}

/**
 * GET /api/kb/c4/project?dir=<kb-relative dir>
 *
 * Returns a LikeC4 project for client-side rendering: the precomputed, layouted
 * model (`model.likec4.json`) plus the raw `.c4` sources for the editor.
 *
 * F-D (#5221 read-slice): the bodies are read from the GitHub SOURCE OF TRUTH —
 * NOT the on-disk workspace clone. The clone is updated only by a best-effort
 * `git pull --ff-only` whose self-heal ABORTS when the clone holds un-pushed
 * `session-sync` commits (`workspace-sync.ts:198-218`); a diverged clone stays
 * permanently stale, so reading it served pre-edit content on every refresh
 * after a Save (the reported bug). GitHub holds the committed truth — the `.c4`
 * AND the re-rendered `model.likec4.json` are both committed by `writeC4Diagram`
 * before it returns 200 — so reading GitHub makes a refresh reflect the edit.
 * The on-disk clone-staleness root cause is workspace-wide and tracked in #5221.
 *
 * Snapshot consistency: a single Contents-dir listing returns every file's blob
 * `sha` atomically; the bodies are then fetched by (content-addressed) sha, so
 * the `.c4` source and the `model.likec4.json` dump are a consistent snapshot —
 * never two independently-racing reads a concurrent Save could split.
 */
export async function GET(request: Request) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // ADR-044 (#4543): the KB (and its C4 diagrams) live on the ACTIVE workspace,
  // not the caller's own `users` row — an invited member viewing a shared
  // workspace has an empty solo row. Resolve the active workspace once (kbRoot +
  // readiness gate), then resolve its repo coordinates for the SAME id.
  const serviceClient = createServiceClient();
  const access = await resolveActiveWorkspaceKbRoot(user.id, serviceClient);
  if (!access.ok) {
    return access.status === 404
      ? NextResponse.json({ error: "Workspace not found" }, { status: 404 })
      : NextResponse.json({ error: "Workspace not ready" }, { status: 503 });
  }
  const { kbRoot, activeWorkspaceId } = access;

  const requestedDir =
    new URL(request.url).searchParams.get("dir") || C4_DIAGRAMS_DIR;
  // Validate the `dir` STRING before it ever becomes a GitHub path: reject NUL /
  // `..` traversal and anything resolving outside the workspace KB root.
  if (requestedDir.includes("\0") || requestedDir.includes("..")) {
    return NextResponse.json({ error: "Invalid dir" }, { status: 400 });
  }
  const dirAbs = path.join(kbRoot, requestedDir);
  if (!isPathInWorkspace(dirAbs, kbRoot)) {
    return NextResponse.json({ error: "Invalid dir" }, { status: 400 });
  }

  // Resolve the ACTIVE workspace's repo coordinates (NOT the caller's own row —
  // reusing the membership-scoped resolver already wired in sync/upload). Pass
  // the pre-resolved active id so kbRoot + repo key to ONE membership decision.
  const repoMeta = await resolveActiveWorkspaceRepoMeta(
    user.id,
    serviceClient,
    activeWorkspaceId,
  );
  if (!repoMeta.ok) {
    return repoMeta.status === 404
      ? NextResponse.json({ error: "Workspace not found" }, { status: 404 })
      : NextResponse.json({ error: "Workspace not ready" }, { status: 503 });
  }
  // Parse owner/repo from repo_url (copy upload/route.ts:198-201).
  const repoUrlParts = repoMeta.repoUrl.replace(/\.git$/, "").split("/");
  const repo = repoUrlParts.pop();
  const owner = repoUrlParts.pop();
  if (!owner || !repo) {
    return NextResponse.json({ error: "Invalid repository URL" }, { status: 500 });
  }

  const installationId = repoMeta.githubInstallationId;
  const githubDir = `knowledge-base/${requestedDir}`;

  try {
    // 1. List the diagrams dir (one call) for per-file blob shas. A 404 here
    //    means the diagram was never built → MODEL_NOT_BUILT (run render).
    let entries: ContentsEntry[];
    try {
      const listing = await githubApiGet<ContentsEntry[] | ContentsEntry>(
        installationId,
        `/repos/${owner}/${repo}/contents/${githubDir}`,
      );
      entries = Array.isArray(listing) ? listing : [listing];
    } catch (err) {
      if (isGitHub404(err)) return modelNotBuilt();
      throw err;
    }

    // 2. Layouted model (required). Absent in the listing → MODEL_NOT_BUILT.
    const modelEntry = entries.find(
      (e) => e.name === C4_MODEL_JSON && e.type === "file",
    );
    if (!modelEntry) return modelNotBuilt();

    let modelText: string;
    try {
      modelText = await fetchBlobUtf8(installationId, owner, repo, modelEntry.sha);
    } catch (err) {
      if (isGitHub404(err)) return modelNotBuilt();
      throw err;
    }
    if (Buffer.byteLength(modelText, "utf8") > MAX_C4_BYTES) {
      reportSilentFallback(new Error("model.likec4.json exceeds MAX_C4_BYTES"), {
        feature: "c4-project-read",
        op: "github-read-oversize",
        extra: { ...renameUserIdToHash({ userId: user.id }), dir: requestedDir },
      });
      return NextResponse.json(
        { error: "Diagram model too large" },
        { status: 413 },
      );
    }
    const dump: unknown = JSON.parse(modelText);
    const viewIds = Object.keys(
      (dump as { views?: Record<string, unknown> }).views ?? {},
    );

    // 3. Raw `.c4` editor sources PLUS the directory index README (exact
    //    `README.md` match — NOT a blanket `.md` — so the `c4-model.md`
    //    view-embed page never leaks in as a browsable "source"). Best-effort:
    //    a single source body failing must not fail the whole render.
    const sources: Record<string, string> = {};
    const sourceEntries = entries
      .filter(
        (e) =>
          e.type === "file" &&
          (e.name.endsWith(C4_SOURCE_EXT) || e.name === "README.md"),
      )
      .sort((a, b) => a.name.localeCompare(b.name));
    for (const entry of sourceEntries) {
      try {
        const body = await fetchBlobUtf8(installationId, owner, repo, entry.sha);
        // Mirror the model cap on sources defensively; skip an oversized source
        // (sources are optional) rather than 413-ing the whole request.
        if (Buffer.byteLength(body, "utf8") > MAX_C4_BYTES) continue;
        sources[entry.name] = body;
      } catch {
        // sources are optional for rendering
      }
    }

    return NextResponse.json(
      { dir: requestedDir, sources, dump, viewIds, diagnostics: [] },
      { status: 200, headers: { "Cache-Control": "private, no-cache" } },
    );
  } catch (error) {
    // A GitHub-read failure (network/auth/rate-limit/blobs error) is reported
    // (mirrored to Sentry) and returns a distinct 503 — NEVER a silent stale
    // serve. The clone is a cache that can diverge; a cache lag must not present
    // as data loss (#4976 insight, applied to the read path).
    reportSilentFallback(error, {
      feature: "c4-project-read",
      op: "github-read-failed",
      extra: { ...renameUserIdToHash({ userId: user.id }), dir: requestedDir },
    });
    Sentry.captureException(error);
    logger.error(
      { err: error, ...renameUserIdToHash({ userId: user.id }), dir: requestedDir },
      "kb/c4/project: GitHub read failed",
    );
    return NextResponse.json(
      { error: "Couldn't load the latest diagram — try again." },
      { status: 503 },
    );
  }
}

function modelNotBuilt() {
  return NextResponse.json(
    {
      error:
        "Diagram model not built. Run `/soleur:architecture render` to generate it.",
      code: "MODEL_NOT_BUILT",
    },
    { status: 404 },
  );
}
