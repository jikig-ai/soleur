import { describe, it, expect, vi, beforeEach } from "vitest";

// Owner-scoped C4 project endpoint (GET /api/kb/c4/project).
//
// As of F-D (#5221 read-slice fix), this route reads the `.c4` sources and the
// layouted `model.likec4.json` from the GitHub SOURCE OF TRUTH — NOT the
// possibly-permanently-stale on-disk workspace clone. So the suite mocks
// `githubApiGet` (Contents listing for per-file shas → Git Blobs API for
// bodies) instead of standing up a real tmpfs. Auth, the workspace resolver,
// and the repo-meta resolver are mocked; the symlink/O_NOFOLLOW surface is gone
// (no filesystem read), so the prior tmpfs symlink test was removed with the
// on-disk read blocks.
const mocks = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockResolveKbRoot: vi.fn(),
  mockResolveRepoMeta: vi.fn(),
  mockGithubApiGet: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockLoggerError: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mocks.mockGetUser },
  })),
  createServiceClient: vi.fn(() => ({})),
}));

vi.mock("@/server/workspace-resolver", () => ({
  resolveActiveWorkspaceKbRoot: mocks.mockResolveKbRoot,
  resolveActiveWorkspaceRepoMeta: mocks.mockResolveRepoMeta,
}));

vi.mock("@/server/github-api", () => ({
  githubApiGet: mocks.mockGithubApiGet,
  GitHubApiError: class GitHubApiError extends Error {
    statusCode: number;
    constructor(msg: string, statusCode: number) {
      super(msg);
      this.statusCode = statusCode;
    }
  },
}));

vi.mock("@/server/observability", async () => {
  const actual = await vi.importActual<typeof import("@/server/observability")>(
    "@/server/observability",
  );
  return { ...actual, reportSilentFallback: mocks.mockReportSilentFallback };
});

vi.mock("@/server/logger", () => ({
  default: {
    info: vi.fn(),
    error: mocks.mockLoggerError,
    warn: vi.fn(),
    debug: vi.fn(),
  },
}));

vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));

import { GET } from "@/app/api/kb/c4/project/route";
import { GitHubApiError } from "@/server/github-api";
import { C4_DIAGRAMS_DIR } from "@/lib/c4-constants";

const OWNER = "jikig-ai";
const REPO = "soleur";

/**
 * Wire the `githubApiGet` mock to serve a diagrams dir:
 *   - a Contents-dir listing (one call) returning per-file blob shas (NO
 *     `content` field — bodies must come from the Blobs API);
 *   - a Git Blobs response per sha (base64 body), proving the route round-trips
 *     bodies via `GET /git/blobs/{sha}`, not the >1 MB-truncating Contents API.
 */
function setupGitHub(
  files: Record<string, string>,
  opts: { listingError?: unknown; blobErrors?: Record<string, unknown> } = {},
) {
  const entries = Object.keys(files).map((name) => ({
    name,
    path: `knowledge-base/${C4_DIAGRAMS_DIR}/${name}`,
    sha: `sha-${name}`,
    type: "file",
  }));
  mocks.mockGithubApiGet.mockImplementation(async (_inst: number, p: string) => {
    if (p.includes("/contents/")) {
      if (opts.listingError) throw opts.listingError;
      return entries;
    }
    const m = p.match(/\/git\/blobs\/(.+)$/);
    if (m) {
      const sha = m[1];
      const name = Object.keys(files).find((n) => `sha-${n}` === sha);
      if (!name) throw new GitHubApiError("blob not found", 404);
      if (opts.blobErrors && name in opts.blobErrors) throw opts.blobErrors[name];
      return {
        content: Buffer.from(files[name], "utf8").toString("base64"),
        encoding: "base64",
        size: Buffer.byteLength(files[name], "utf8"),
      };
    }
    throw new Error(`unexpected github path: ${p}`);
  });
}

async function callGET(dir?: string) {
  const url = dir
    ? `http://localhost:3000/api/kb/c4/project?dir=${encodeURIComponent(dir)}`
    : "http://localhost:3000/api/kb/c4/project";
  return GET(new Request(url));
}

beforeEach(() => {
  vi.clearAllMocks();
  mocks.mockGetUser.mockResolvedValue({ data: { user: { id: "user-1" } } });
  mocks.mockResolveKbRoot.mockResolvedValue({
    ok: true,
    activeWorkspaceId: "ws-1",
    workspacePath: "/workspaces/ws-1",
    kbRoot: "/workspaces/ws-1/knowledge-base",
    repoStatus: "connected",
  });
  mocks.mockResolveRepoMeta.mockResolvedValue({
    ok: true,
    repoUrl: `https://github.com/${OWNER}/${REPO}`,
    githubInstallationId: 42,
  });
});

describe("GET /api/kb/c4/project — GitHub source-of-truth read (F-D)", () => {
  it("AC1: serves the POST-edit .c4 source AND post-edit dump from GitHub, regardless of clone state", async () => {
    setupGitHub({
      "model.c4": 'model {\n  founder = actor "Founder TEST"\n}',
      "model.likec4.json": JSON.stringify({ views: { index: { id: "index" } } }),
    });
    const res = await callGET();
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.sources["model.c4"]).toContain("Founder TEST");
    expect(body.dump).toEqual({ views: { index: { id: "index" } } });
    expect(body.viewIds).toEqual(["index"]);
  });

  it("AC2: a 1–4 MB model.likec4.json round-trips fully via the Blobs API", async () => {
    // ~1.5 MB of JSON — above the Contents API's 1 MB `content` cutoff, below
    // the 4 MB MAX_C4_BYTES cap. `setupGitHub` serves bodies ONLY from
    // `/git/blobs/{sha}` (the listing entries carry no `content` field), so a
    // full 12000-view round-trip is reachable only through the Blobs path — an
    // implementation that read the Contents `content` field instead would see
    // `undefined` and fail this assertion.
    const bigViews: Record<string, unknown> = {};
    for (let i = 0; i < 12000; i++) bigViews[`view-${i}`] = { id: `view-${i}`, blob: "x".repeat(100) };
    const bigDump = JSON.stringify({ views: bigViews });
    expect(Buffer.byteLength(bigDump)).toBeGreaterThan(1024 * 1024);
    expect(Buffer.byteLength(bigDump)).toBeLessThan(4 * 1024 * 1024);
    setupGitHub({ "model.c4": "model {}", "model.likec4.json": bigDump });
    const res = await callGET();
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(Object.keys(body.dump.views)).toHaveLength(12000);
  });

  it("AC1b: sources filter — includes README.md + .c4, excludes c4-model.md", async () => {
    setupGitHub({
      "model.likec4.json": JSON.stringify({ views: { index: {} } }),
      "spec.c4": "specification {}",
      "model.c4": "model {}",
      "views.c4": "views {}",
      "README.md": "# Diagrams\n\nFile taxonomy.",
      "c4-model.md": "```likec4-view\nindex\n```",
    });
    const res = await callGET();
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(Object.keys(body.sources).sort()).toEqual([
      "README.md",
      "model.c4",
      "spec.c4",
      "views.c4",
    ]);
    expect(body.sources["README.md"]).toContain("File taxonomy.");
    expect("c4-model.md" in body.sources).toBe(false);
  });

  it("AC3: a dir with `..` → 400 and triggers ZERO GitHub fetch", async () => {
    setupGitHub({ "model.likec4.json": JSON.stringify({ views: {} }) });
    const res = await callGET("../../etc");
    expect(res.status).toBe(400);
    expect(mocks.mockGithubApiGet).not.toHaveBeenCalled();
  });

  it("AC4: resolves repo coordinates for the ACTIVE (shared) workspace, not the caller's own row", async () => {
    // Invited member: kbRoot resolves the SHARED workspace id; repo-meta MUST be
    // resolved for that same active id and read the SHARED repo.
    mocks.mockResolveKbRoot.mockResolvedValue({
      ok: true,
      activeWorkspaceId: "shared-ws-id",
      workspacePath: "/workspaces/shared-ws-id",
      kbRoot: "/workspaces/shared-ws-id/knowledge-base",
      repoStatus: "connected",
    });
    mocks.mockResolveRepoMeta.mockResolvedValue({
      ok: true,
      repoUrl: "https://github.com/shared-org/shared-repo",
      githubInstallationId: 99,
    });
    setupGitHub({
      "model.c4": "model {}",
      "model.likec4.json": JSON.stringify({ views: {} }),
    });
    const res = await callGET();
    expect(res.status).toBe(200);
    // Repo-meta resolved with the active (shared) workspace id, not "user-1".
    expect(mocks.mockResolveRepoMeta).toHaveBeenCalledWith(
      "user-1",
      expect.anything(),
      "shared-ws-id",
    );
    // GitHub reads target the SHARED repo.
    const paths = mocks.mockGithubApiGet.mock.calls.map((c) => c[1] as string);
    expect(paths.every((p) => p.includes("/repos/shared-org/shared-repo/"))).toBe(true);
  });

  it("AC5: a GitHub-read failure → 503, reportSilentFallback, and NO partial/stale body", async () => {
    // Non-vacuous negative: the dir LISTING succeeds (so the route HAS the model
    // entry + sha in hand) but the model BLOB read fails. A route that served a
    // partial dump or fell back to anything would leak a body here — assert it
    // returns a clean 503 with neither `dump` nor `sources`.
    setupGitHub(
      { "model.c4": "model {}", "model.likec4.json": JSON.stringify({ views: {} }) },
      { blobErrors: { "model.likec4.json": new GitHubApiError("rate limited", 429) } },
    );
    const res = await callGET();
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.dump).toBeUndefined();
    expect(body.sources).toBeUndefined();
    expect(body.error).toContain("try again");
    expect(mocks.mockReportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        feature: "c4-project-read",
        op: "github-read-failed",
      }),
    );
  });

  it("AC5b: a dir-LISTING failure also → 503 (not a stale serve)", async () => {
    setupGitHub(
      { "model.likec4.json": JSON.stringify({ views: {} }) },
      { listingError: new GitHubApiError("rate limited", 429) },
    );
    const res = await callGET();
    expect(res.status).toBe(503);
    expect(mocks.mockReportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "github-read-failed" }),
    );
  });

  it("AC6: a GitHub 404 on model.likec4.json → MODEL_NOT_BUILT 404 (not 503)", async () => {
    // Listing succeeds but the model dump is absent (never rendered).
    setupGitHub({ "model.c4": "model {}" });
    const res = await callGET();
    expect(res.status).toBe(404);
    const body = await res.json();
    expect(body.code).toBe("MODEL_NOT_BUILT");
  });

  it("AC7: an oversized (>4 MB) model.likec4.json from GitHub → 413 + oversize op", async () => {
    const huge = "x".repeat(4 * 1024 * 1024 + 10);
    setupGitHub({ "model.c4": "model {}", "model.likec4.json": huge });
    const res = await callGET();
    expect(res.status).toBe(413);
    const body = await res.json();
    expect(body.error).toContain("too large");
    // The oversize path mirrors a DISTINCT op so a corrupt/oversized model is
    // not conflated with a transient github-read-failed in the Sentry filter.
    expect(mocks.mockReportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        feature: "c4-project-read",
        op: "github-read-oversize",
      }),
    );
  });

  it("AC8: the op slug is pinned in the route source so the Sentry filter can match it", async () => {
    const fs = await import("node:fs");
    const url = await import("node:url");
    const pathMod = await import("node:path");
    const here = pathMod.dirname(url.fileURLToPath(import.meta.url));
    const src = fs.readFileSync(
      pathMod.join(here, "../app/api/kb/c4/project/route.ts"),
      "utf8",
    );
    expect(src).toContain('feature: "c4-project-read"');
    expect(src).toContain('op: "github-read-failed"');
  });
});
