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
  mockMirrorWarnWithDebounce: vi.fn(),
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
  // `mirrorWarnWithDebounce` MUST be an explicit spy: the real one keeps a
  // module-level debounce map (it would dedupe across tests), and the
  // `@sentry/nextjs` mock below has no `captureMessage`.
  return {
    ...actual,
    reportSilentFallback: mocks.mockReportSilentFallback,
    mirrorWarnWithDebounce: mocks.mockMirrorWarnWithDebounce,
  };
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
import { canonicalizeC4Model } from "@/lib/c4-canonical.mjs";

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
  opts: {
    listingError?: unknown;
    blobErrors?: Record<string, unknown>;
    dir?: string;
    /** The listing's own path prefix, when it should differ from the request
     *  dir (GitHub reports its canonical path, not the caller's spelling). */
    listingDir?: string;
  } = {},
) {
  const entries = Object.keys(files).map((name) => ({
    name,
    path: `knowledge-base/${opts.listingDir ?? opts.dir ?? C4_DIAGRAMS_DIR}/${name}`,
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

  it("AC7b: a committed model that is not valid JSON (e.g. left-over merge markers) → handled 502 + parse op", async () => {
    // #8542 made the artifact line-mergeable, so a hand-botched merge can now
    // commit conflict markers into it. The viewer must degrade to a handled
    // error with its own Sentry op, never an unhandled crash.
    const botched = '{\n"views": {\n<<<<<<< ours\n"a": {}\n=======\n"b": {}\n>>>>>>> theirs\n}\n}\n';
    setupGitHub({ "model.c4": "model {}", "model.likec4.json": botched });
    const res = await callGET();
    expect(res.status).toBe(502);
    const body = await res.json();
    expect(body.error).toContain("corrupt");
    expect(mocks.mockReportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "c4-project-read", op: "model-parse-failed" }),
    );
    // The reported error must not carry the SyntaxError's quote of the model text.
    const call = mocks.mockReportSilentFallback.mock.calls.find(
      (c: unknown[]) => (c[1] as { op?: string })?.op === "model-parse-failed",
    )!;
    expect((call[0] as Error).message).toBe("model.likec4.json parse failed");
    expect(JSON.stringify(call)).not.toContain("<<<<<<<");
  });

  it("AC7c: the canonical line-per-value format (#8542) is served like the one-line form", async () => {
    const dump = { views: { index: { id: "index", hash: "" } }, elements: { a: { id: "a" } } };
    const canonical = canonicalizeC4Model(JSON.stringify(dump));
    setupGitHub({ "model.c4": "model {}", "model.likec4.json": canonical });
    const res = await callGET();
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.dump).toEqual(dump);
    expect(body.viewIds).toEqual(["index"]);
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

// #8740: a committed model with elements but no views (written before the
// server re-render pinned wasm layout, or by a plugin writer — #8861) renders
// as "View `index` not found in the model." with nothing saying why. The route
// explains it through the existing diagnostics channel.
describe("GET /api/kb/c4/project — zero-view model diagnostic (#8740)", () => {
  const CANONICAL_COPY =
    "This diagram has no views to draw because its saved layout is incomplete. This is not caused by your diagram source. To fix it, ask the Concierge to re-render this diagram, then reload the page.";
  const OTHER_DIR_COPY =
    "This diagram has no views to draw because its saved layout is incomplete. This is not caused by your diagram source. To fix it, re-run the diagram export for this folder in your repository, then reload the page.";
  const CANONICAL_MODEL_PATH = `knowledge-base/${C4_DIAGRAMS_DIR}/model.likec4.json`;

  function zeroViewModel() {
    return JSON.stringify({ elements: { a: { id: "a" }, b: { id: "b" } }, views: {} });
  }

  // The real client always sends `?dir=` (useC4Project), so T1 runs both with
  // the explicit canonical dir and with the route's default.
  it.each([["explicit dir", C4_DIAGRAMS_DIR], ["default dir", undefined]])(
    "T1 (%s): elements + empty views → one model-level diagnostic and one debounced warn",
    async (_label, dir) => {
    setupGitHub({ "model.c4": "model {}", "model.likec4.json": zeroViewModel() });
    const res = await callGET(dir);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.viewIds).toEqual([]);
    expect(body.diagnostics).toEqual([
      { message: CANONICAL_COPY, line: 0, sourceFsPath: "model.likec4.json" },
    ]);
    expect(mocks.mockMirrorWarnWithDebounce).toHaveBeenCalledTimes(1);
    const [err, ctx, key, errorClass] = mocks.mockMirrorWarnWithDebounce.mock.calls[0];
    expect(err).toBeNull();
    expect(ctx).toEqual(
      expect.objectContaining({
        feature: "c4-project-read",
        op: "zero-view-model",
        message: "c4 project read: committed model has elements but no views",
      }),
    );
    expect(ctx).not.toHaveProperty("tags");
    expect(ctx.extra).toEqual(
      expect.objectContaining({
        dir: C4_DIAGRAMS_DIR,
        modelPath: CANONICAL_MODEL_PATH,
        elementCount: 2,
        userIdHash: expect.any(String),
      }),
    );
    expect(ctx.extra).not.toHaveProperty("userId");
    expect(key).toBe(`ws-1:${CANONICAL_MODEL_PATH}`);
    expect(errorClass).toBe("c4-project-read:zero-view-model");
    // The zero-view state is a warning, never a paged failure.
    expect(mocks.mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("T2: a model with a view → no diagnostic, no warn", async () => {
    setupGitHub({
      "model.likec4.json": JSON.stringify({
        elements: { a: { id: "a" } },
        views: { index: { id: "index" } },
      }),
    });
    const res = await callGET();
    const body = await res.json();
    expect(body.diagnostics).toEqual([]);
    expect(mocks.mockMirrorWarnWithDebounce).not.toHaveBeenCalled();
  });

  it("T3: an empty model (no elements, no views) → no false diagnostic", async () => {
    setupGitHub({ "model.likec4.json": JSON.stringify({ elements: {}, views: {} }) });
    const res = await callGET();
    const body = await res.json();
    expect(body.diagnostics).toEqual([]);
    expect(mocks.mockMirrorWarnWithDebounce).not.toHaveBeenCalled();
  });

  it.each([
    ["absent views", { elements: { a: { id: "a" } } }, true],
    // A non-empty ARRAY of views is still no views: only a plain object counts.
    ["array views", { elements: { a: { id: "a" } }, views: ["index"] }, true],
    ["array elements", { elements: ["x"], views: {} }, false],
    ["string elements", { elements: "xy", views: {} }, false],
  ])("T4: %s → diagnostic=%s", async (_label, model, expectDiag) => {
    setupGitHub({ "model.likec4.json": JSON.stringify(model) });
    const res = await callGET();
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.diagnostics).toHaveLength(expectDiag ? 1 : 0);
    expect(mocks.mockMirrorWarnWithDebounce).toHaveBeenCalledTimes(expectDiag ? 1 : 0);
  });

  // The Concierge can write only DIRECTLY under the canonical folder
  // (isC4DiagramPath), so near misses on either side get the export copy.
  it.each(["product/diagrams", `${C4_DIAGRAMS_DIR}/sub`, `x/${C4_DIAGRAMS_DIR}`])(
    "T5: %s is outside the Concierge-writable folder → the export copy, which does not name the Concierge",
    async (dir) => {
      setupGitHub({ "model.likec4.json": zeroViewModel() }, { dir });
      const res = await callGET(dir);
      expect(res.status).toBe(200);
      const body = await res.json();
      expect(body.diagnostics).toEqual([
        { message: OTHER_DIR_COPY, line: 0, sourceFsPath: "model.likec4.json" },
      ]);
      expect(body.diagnostics[0].message).not.toContain("Concierge");
    },
  );

  it("T5b: a model whose JSON is `null` → 200, no diagnostic, no misattributed read failure", async () => {
    setupGitHub({ "model.likec4.json": "null" });
    const res = await callGET();
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.viewIds).toEqual([]);
    expect(body.diagnostics).toEqual([]);
    expect(mocks.mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it.each([
    "%2e%2e/x",
    "./x",
    "a//b",
    "a/",
    "a%2Fb",
    "..",
    "a/../b",
    "a/./b",
    "x\u0001y",
    "x\u0000y",
    "x\u007fy",
    "x\u2028y",
    "x\u2029y",
    "a?ref=main",
    "a#b",
    "a\\b",
    "/abs",
    "a".repeat(257),
  ])("T6: dir %j → 400 with zero GitHub calls", async (dir) => {
    setupGitHub({ "model.likec4.json": zeroViewModel() });
    const res = await callGET(dir);
    expect(res.status).toBe(400);
    expect(mocks.mockGithubApiGet).not.toHaveBeenCalled();
  });

  it.each([C4_DIAGRAMS_DIR, "product/v1.2_diagrams", "Architecture Docs/diagrams", "équipe/diagrammes"])(
    "T6b: dir %j passes validation (spaces and non-ASCII names keep working)",
    async (dir) => {
      setupGitHub({ "model.likec4.json": JSON.stringify({ views: { index: {} } }) }, { dir });
      expect((await callGET(dir)).status).toBe(200);
    },
  );

  it("T6c: each dir segment is percent-encoded into the GitHub path, separators kept", async () => {
    const dir = "Architecture Docs/équipe";
    setupGitHub({ "model.likec4.json": JSON.stringify({ views: { index: {} } }) }, { dir });
    await callGET(dir);
    const listing = mocks.mockGithubApiGet.mock.calls
      .map((c) => c[1] as string)
      .find((p) => p.includes("/contents/"));
    expect(listing).toBe(
      `/repos/${OWNER}/${REPO}/contents/knowledge-base/Architecture%20Docs/%C3%A9quipe`,
    );
  });

  it("T7: the debounce key is the listing's canonical path, not the raw request dir", async () => {
    // GitHub reports its own spelling of the path; the key must use it, so
    // the fixture's listing path deliberately differs from the request dir.
    setupGitHub(
      { "model.likec4.json": zeroViewModel() },
      { dir: "Product/Diagrams", listingDir: "product/diagrams" },
    );
    await callGET("Product/Diagrams");
    const keys = mocks.mockMirrorWarnWithDebounce.mock.calls.map((c) => c[2]);
    expect(keys).toEqual(["ws-1:knowledge-base/product/diagrams/model.likec4.json"]);
  });

  it("T8: the zero-view op slug occurs exactly once in the route source", async () => {
    const fs = await import("node:fs");
    const url = await import("node:url");
    const pathMod = await import("node:path");
    const here = pathMod.dirname(url.fileURLToPath(import.meta.url));
    const src = fs.readFileSync(
      pathMod.join(here, "../app/api/kb/c4/project/route.ts"),
      "utf8",
    );
    expect(src.split('op: "zero-view-model"').length - 1).toBe(1);
  });
});
