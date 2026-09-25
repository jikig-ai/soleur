import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import {
  resolveActiveWorkspaceKbRoot,
  resolveActiveWorkspaceRepoMeta,
} from "@/server/workspace-resolver";
import { renameUserIdToHash } from "@/server/userid-pseudonymize";
import { githubApiGet, GitHubApiError } from "@/server/github-api";
import { kbGithubUrlPath } from "@/server/kb-github-path";
import { mirrorWarnWithDebounce, reportSilentFallback } from "@/server/observability";
import {
  C4_DIAGRAMS_DIR,
  C4_SOURCE_EXT,
  C4_MODEL_JSON,
  MAX_C4_BYTES,
} from "@/lib/c4-constants";
import {
  c4ModelCounts,
  MODEL_LEVEL_LINE,
  type Diagnostic,
} from "@/lib/c4-model-shape";
import logger from "@/server/logger";

export const runtime = "nodejs";

type ContentsEntry = { name: string; path: string; sha: string; type: string };
type GitBlob = { content: string; encoding: string; size?: number };

/** A GitHub blob whose decoded body exceeds `MAX_C4_BYTES`. Distinct from a
 * GitHub-read failure so the caller can map it to a 413 (model) or skip it
 * (best-effort source) rather than a 503. */
class BlobTooLargeError extends Error {}

/** Longest `dir` accepted. Real KB folders are a few segments deep. */
const MAX_DIR_LENGTH = 256;
/** Characters that re-enter URL syntax: `%` (a pre-encoded `%2e%2e` is
 *  resolved as `..` by the URL parser), `\\`, `?` and `#`. Defence in depth:
 *  the per-segment encoding in `kbGithubUrlPath` already neutralises each,
 *  so this only refuses early (at the cost of folder names containing `%`). */
const DIR_URL_META = /[%\\?#]/;

/** The `dir` query value as the GitHub path under `knowledge-base/`, or null
 *  when it is not a plain KB-relative folder. The shared per-segment guard
 *  (`kbGithubUrlPath`: dot/empty segments, control characters, per-segment
 *  encoding) plus a stricter refusal of URL-meta characters and a shorter
 *  length cap for a folder name. A blocklist rather than an allowlist so
 *  folders with spaces or non-ASCII names keep working. */
function toGithubDir(requestedDir: string): string | null {
  if (DIR_URL_META.test(requestedDir)) return null;
  return kbGithubUrlPath(requestedDir, MAX_DIR_LENGTH);
}

// #8740: a committed model with elements but no views renders as "View `index`
// not found in the model." with no explanation. Zero views means the layout
// step failed, never that the source caused it (ADR-050: a successful layout
// always emits `index`); the source itself is not validated here, so the copy
// claims only that. Inside the Concierge-writable folder a Concierge re-render
// (a `.c4` edit) fixes it; elsewhere the Concierge cannot write, so the copy
// points at the export. "re-render this diagram" is the phrase the Concierge
// prompt addendum keys on. "then reload the page" stays until #8739 reloads
// the workspace after a Concierge edit.
const ZERO_VIEW_PREFIX =
  "This diagram has no views to draw because its saved layout is incomplete. This is not caused by your diagram source. To fix it, ";
const ZERO_VIEW_DIAGNOSTIC =
  ZERO_VIEW_PREFIX + "ask the Concierge to re-render this diagram, then reload the page.";
const ZERO_VIEW_DIAGNOSTIC_OTHER_DIR =
  ZERO_VIEW_PREFIX + "re-run the diagram export for this folder in your repository, then reload the page.";

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
 * `server/inngest/functions/cron-ruleset-bypass-audit.ts:100-120`.
 *
 * Throws `BlobTooLargeError` when the body exceeds `MAX_C4_BYTES` — checked on
 * the API-reported `size` BEFORE decoding (so an oversized model never
 * allocates a multi-MB decode just to be rejected), then re-checked on the
 * decoded bytes defensively. */
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
  if (typeof blob.size === "number" && blob.size > MAX_C4_BYTES) {
    throw new BlobTooLargeError();
  }
  // `Buffer.from(_, "base64")` tolerates the GitHub-wrapped newlines in the
  // base64 payload.
  const text = Buffer.from(blob.content ?? "", "base64").toString("utf8");
  if (Buffer.byteLength(text, "utf8") > MAX_C4_BYTES) {
    throw new BlobTooLargeError();
  }
  return text;
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
 * Read-side snapshot consistency: a single Contents-dir listing returns every
 * file's blob `sha`, and the bodies are then fetched by (content-addressed)
 * sha, so this route never tears ACROSS its own fetches. Note this does NOT
 * pin a HEAD `sha`, and the writer commits the `.c4` and the re-rendered
 * `model.likec4.json` in TWO separate commits — so a read whose listing lands
 * between those commits can observe a new source with the prior dump. That skew
 * is transient (the next refresh after the re-render commit is consistent) and
 * is covered by the existing Layer-1 honest-stale banner (#4963/#4976).
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
  const { activeWorkspaceId } = access;

  const requestedDir =
    new URL(request.url).searchParams.get("dir") || C4_DIAGRAMS_DIR;
  // Validate the `dir` STRING before it becomes a GitHub API path. This route no
  // longer reads the on-disk clone, so we must NOT gate on clone filesystem
  // state (`isPathInWorkspace` against `kbRoot`) — a legitimately-shared dir can
  // be absent from a stale/empty local clone and would false-negative 400. A
  // pure-string guard is both sufficient and correct (see `toGithubDir`).
  const githubDir = toGithubDir(requestedDir);
  if (githubDir === null) {
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
  const userLog = renameUserIdToHash({ userId: user.id });

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
      if (err instanceof BlobTooLargeError) {
        reportSilentFallback(new Error("model.likec4.json exceeds MAX_C4_BYTES"), {
          feature: "c4-project-read",
          op: "github-read-oversize",
          extra: { ...userLog, dir: requestedDir },
        });
        return NextResponse.json(
          { error: "Diagram model too large" },
          { status: 413 },
        );
      }
      throw err;
    }

    let dump: unknown;
    try {
      dump = JSON.parse(modelText);
    } catch (err) {
      // The committed model is corrupt JSON — distinct from a GitHub-read
      // failure so the Sentry slug attributes the cause correctly.
      // Report a fixed Error, not `err`: V8's SyntaxError message quotes a slice
      // of the input, i.e. of the customer's model, and would ship it to Sentry.
      reportSilentFallback(new Error("model.likec4.json parse failed"), {
        feature: "c4-project-read",
        op: "model-parse-failed",
        extra: { ...userLog, dir: requestedDir, errName: err instanceof Error ? err.name : "unknown" },
      });
      return NextResponse.json(
        { error: "Diagram model is corrupt — re-render to regenerate it." },
        { status: 502 },
      );
    }
    const views =
      dump && typeof dump === "object"
        ? (dump as { views?: unknown }).views
        : undefined;
    const viewIds =
      views && typeof views === "object" && !Array.isArray(views)
        ? Object.keys(views)
        : [];

    // Count elements only when there are no views: the common, healthy model
    // skips the `Object.keys(elements)` pass.
    const elementCount = viewIds.length === 0 ? c4ModelCounts(dump).elements : 0;
    let diagnostics: Diagnostic[] = [];
    if (elementCount > 0) {
      diagnostics = [
        {
          message:
            requestedDir === C4_DIAGRAMS_DIR
              ? ZERO_VIEW_DIAGNOSTIC
              : ZERO_VIEW_DIAGNOSTIC_OTHER_DIR,
          line: MODEL_LEVEL_LINE,
          sourceFsPath: C4_MODEL_JSON,
        },
      ];
      // Debounced per workspace + model: every page load re-reads the model.
      // `err = null` keeps the tags (#8629). The key is GitHub's canonical
      // path, so `dir` spellings cannot fan out past the debounce.
      mirrorWarnWithDebounce(
        null,
        {
          feature: "c4-project-read",
          op: "zero-view-model",
          message: "c4 project read: committed model has elements but no views",
          extra: { ...userLog, dir: requestedDir, modelPath: modelEntry.path, elementCount },
        },
        `${activeWorkspaceId}:${modelEntry.path}`,
        "c4-project-read:zero-view-model",
      );
    }

    // 3. Raw `.c4` editor sources PLUS the directory index README (exact
    //    `README.md` match — NOT a blanket `.md` — so the `c4-model.md`
    //    view-embed page never leaks in as a browsable "source"). Best-effort
    //    AND concurrent: the source bodies are independent content-addressed
    //    reads, so fetch them in parallel; a single source failing must not
    //    fail the whole render.
    const sourceEntries = entries
      .filter(
        (e) =>
          e.type === "file" &&
          (e.name.endsWith(C4_SOURCE_EXT) || e.name === "README.md"),
      )
      .sort((a, b) => a.name.localeCompare(b.name));
    const fetched = await Promise.all(
      sourceEntries.map(async (entry) => {
        try {
          const body = await fetchBlobUtf8(installationId, owner, repo, entry.sha);
          return [entry.name, body] as const;
        } catch {
          // sources are optional for rendering; surface the omission (a
          // silently-missing source could present an incomplete editor) at
          // warn-level rather than paging on a best-effort miss.
          logger.warn(
            { ...userLog, dir: requestedDir, file: entry.name },
            "kb/c4/project: source body omitted (GitHub read failed)",
          );
          return null;
        }
      }),
    );
    const sources: Record<string, string> = {};
    for (const kv of fetched) if (kv) sources[kv[0]] = kv[1];

    return NextResponse.json(
      { dir: requestedDir, sources, dump, viewIds, diagnostics },
      { status: 200, headers: { "Cache-Control": "private, no-cache" } },
    );
  } catch (error) {
    // A GitHub-read failure (network/auth/rate-limit/blobs error) is reported
    // (mirrored to Sentry by reportSilentFallback) and returns a distinct 503 —
    // NEVER a silent stale serve. The clone is a cache that can diverge; a cache
    // lag must not present as data loss (#4976 insight, applied to the read
    // path).
    reportSilentFallback(error, {
      feature: "c4-project-read",
      op: "github-read-failed",
      extra: { ...userLog, dir: requestedDir },
    });
    logger.error(
      { err: error, ...userLog, dir: requestedDir },
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
