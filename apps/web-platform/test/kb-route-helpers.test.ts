import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const {
  mockGetUser,
  mockServiceFrom,
  mockResolveKbRoot,
  mockResolveRepoMeta,
  mockGitWithAuth,
  mockIsPathInWorkspace,
  mockLstat,
  mockValidateOrigin,
  mockRejectCsrf,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  // The service-role client is created via createServiceClient() and handed
  // to the (mocked) resolvers — its `.from` is never reached in these tests,
  // but a stub keeps the createServiceClient() call non-throwing.
  mockServiceFrom: vi.fn(),
  // ADR-044 (#4956): the helper now composes the two membership-scoped
  // service-role resolvers instead of a tenant `users` read. Mock both.
  mockResolveKbRoot: vi.fn(),
  mockResolveRepoMeta: vi.fn(),
  mockGitWithAuth: vi.fn(),
  mockIsPathInWorkspace: vi.fn(),
  mockLstat: vi.fn(),
  mockValidateOrigin: vi.fn(),
  mockRejectCsrf: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
  })),
  createServiceClient: vi.fn(() => ({
    from: mockServiceFrom,
  })),
}));

// #4956 ADR-044 — the helper resolves the active workspace's kbRoot + repo
// metadata via these two membership-scoped resolvers (service-role, read from
// the `workspaces` source of truth via the membership-checked installation
// RPC), replacing the legacy tenant `users` read. The pre-resolved active id
// is threaded from kbRoot → repoMeta so both key to ONE membership-resolved id.
vi.mock("@/server/workspace-resolver", () => ({
  resolveActiveWorkspaceKbRoot: mockResolveKbRoot,
  resolveActiveWorkspaceRepoMeta: mockResolveRepoMeta,
}));

const { mockReportSilentFallback, mockWarnSilentFallback } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockWarnSilentFallback: vi.fn(),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: mockWarnSilentFallback,
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: mockValidateOrigin,
  rejectCsrf: mockRejectCsrf,
}));

vi.mock("@/server/git-auth", () => ({
  gitWithInstallationAuth: mockGitWithAuth,
}));

vi.mock("@/server/sandbox", () => ({
  isPathInWorkspace: mockIsPathInWorkspace,
}));

vi.mock("node:fs", () => ({
  promises: { lstat: mockLstat },
}));

// ---------------------------------------------------------------------------
// Import helpers AFTER mocks
// ---------------------------------------------------------------------------

import {
  authenticateAndResolveKbPath,
  syncWorkspace,
} from "@/server/kb-route-helpers";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const TEST_USER_ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const TEST_INSTALLATION_ID = 12345;
const TEST_WORKSPACE_PATH = "/workspaces/test-user";
const TEST_REPO_URL = "https://github.com/test-owner/test-repo";

function createRequest(): Request {
  return new Request("http://localhost:3000/api/kb/file/overview/test.pdf", {
    method: "DELETE",
    headers: { Origin: "https://app.soleur.ai" },
  });
}

function createParams(pathSegments: string[]): Promise<{ path: string[] }> {
  return Promise.resolve({ path: pathSegments });
}

function setupAuthenticatedUser() {
  mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
}

// Wire both resolvers to the solo-owner happy path (activeWorkspaceId === userId,
// kbRoot/repo identical to the legacy read). `activeWorkspaceId` overrides the
// solo default so the member-vs-solo id-threading test can assert it propagates.
function setupResolvers(activeWorkspaceId: string = TEST_USER_ID) {
  mockResolveKbRoot.mockResolvedValue({
    ok: true,
    activeWorkspaceId,
    workspacePath: TEST_WORKSPACE_PATH,
    kbRoot: `${TEST_WORKSPACE_PATH}/knowledge-base`,
    repoStatus: "ready",
  });
  mockResolveRepoMeta.mockResolvedValue({
    ok: true,
    repoUrl: TEST_REPO_URL,
    githubInstallationId: TEST_INSTALLATION_ID,
  });
}

function setupHappyPath() {
  mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
  setupAuthenticatedUser();
  setupResolvers();
  mockIsPathInWorkspace.mockReturnValue(true);
  mockLstat.mockResolvedValue({
    isSymbolicLink: () => false,
    isFile: () => true,
    isDirectory: () => false,
  });
}

const fakeLogger = {
  info: vi.fn(),
  warn: vi.fn(),
  error: vi.fn(),
  // pino Logger signature has many methods; tests only require these.
} as unknown as import("pino").Logger;

// ---------------------------------------------------------------------------
// Tests — authenticateAndResolveKbPath
// ---------------------------------------------------------------------------

describe("authenticateAndResolveKbPath", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test("returns CSRF response when origin invalid", async () => {
    mockValidateOrigin.mockReturnValue({ valid: false, origin: "https://evil.com" });
    const csrfResponse = new Response(JSON.stringify({ error: "Forbidden" }), {
      status: 403,
    });
    mockRejectCsrf.mockReturnValue(csrfResponse);

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response).toBe(csrfResponse);
      expect(mockRejectCsrf).toHaveBeenCalledWith("api/kb/file", "https://evil.com");
    }
    // CSRF rejected before any credential resolution.
    expect(mockResolveKbRoot).not.toHaveBeenCalled();
  });

  test("returns 401 when unauthenticated", async () => {
    mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
    mockGetUser.mockResolvedValue({ data: { user: null } });

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.status).toBe(401);
    }
    expect(mockResolveKbRoot).not.toHaveBeenCalled();
  });

  test("returns 503 'Workspace not ready' when kbRoot resolver reports 503", async () => {
    setupHappyPath();
    mockResolveKbRoot.mockResolvedValue({ ok: false, status: 503 });

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.status).toBe(503);
      const body = await result.response.json();
      expect(body.error).toMatch(/workspace not ready/i);
    }
    // No repo-meta resolution once the kbRoot gate fails.
    expect(mockResolveRepoMeta).not.toHaveBeenCalled();
  });

  test("returns 'No repository connected' when kbRoot resolver reports 404 (not connected)", async () => {
    setupHappyPath();
    mockResolveKbRoot.mockResolvedValue({ ok: false, status: 404 });

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.status).toBe(404);
      const body = await result.response.json();
      expect(body.error).toMatch(/no repository connected/i);
    }
    expect(mockResolveRepoMeta).not.toHaveBeenCalled();
  });

  test("returns 'No repository connected' when repoMeta resolver reports 404 (no repo_url)", async () => {
    setupHappyPath();
    mockResolveRepoMeta.mockResolvedValue({ ok: false, status: 404 });

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.status).toBe(404);
      const body = await result.response.json();
      expect(body.error).toMatch(/no repository connected/i);
    }
  });

  test("returns 'No repository connected' when repoMeta resolver reports 400 (no installation)", async () => {
    setupHappyPath();
    mockResolveRepoMeta.mockResolvedValue({ ok: false, status: 400 });

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.status).toBe(400);
      const body = await result.response.json();
      expect(body.error).toMatch(/no repository connected/i);
    }
  });

  test("returns 503 'Workspace not ready' when repoMeta resolver reports 503", async () => {
    setupHappyPath();
    mockResolveRepoMeta.mockResolvedValue({ ok: false, status: 503 });

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.status).toBe(503);
      const body = await result.response.json();
      expect(body.error).toMatch(/workspace not ready/i);
    }
  });

  test("returns 400 for empty path", async () => {
    setupHappyPath();

    const result = await authenticateAndResolveKbPath(createRequest(), createParams([]));
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.status).toBe(400);
      const body = await result.response.json();
      expect(body.error).toMatch(/file path required/i);
    }
  });

  test("returns 400 for null byte in path", async () => {
    setupHappyPath();

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test\0evil.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.status).toBe(400);
      const body = await result.response.json();
      expect(body.error).toMatch(/null byte/i);
    }
  });

  test("returns 400 for .md extension when blockMarkdown: true", async () => {
    setupHappyPath();

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "readme.md"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.status).toBe(400);
      const body = await result.response.json();
      expect(body.error).toMatch(/markdown/i);
    }
  });

  test("returns 400 for path traversal outside workspace", async () => {
    setupHappyPath();
    mockIsPathInWorkspace.mockReturnValue(false);

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["..", "..", "etc", "passwd.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.status).toBe(400);
      const body = await result.response.json();
      expect(body.error).toMatch(/invalid path/i);
    }
  });

  test("returns 403 when target is a symlink", async () => {
    setupHappyPath();
    mockLstat.mockResolvedValue({
      isSymbolicLink: () => true,
      isFile: () => false,
      isDirectory: () => false,
    });

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "link.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.response.status).toBe(403);
  });

  test("proceeds OK when lstat returns ENOENT (file not on disk)", async () => {
    setupHappyPath();
    const enoent = new Error("ENOENT") as NodeJS.ErrnoException;
    enoent.code = "ENOENT";
    mockLstat.mockRejectedValue(enoent);

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "remote-only.pdf"]),
    );
    expect(result.ok).toBe(true);
  });

  test("returns 403 when lstat fails with non-ENOENT error", async () => {
    setupHappyPath();
    const permErr = new Error("EACCES") as NodeJS.ErrnoException;
    permErr.code = "EACCES";
    mockLstat.mockRejectedValue(permErr);

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "locked.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.response.status).toBe(403);
  });

  test("happy path returns populated context sourced from the resolvers", async () => {
    setupHappyPath();

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test.pdf"]),
    );
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.ctx).toMatchObject({
        user: { id: TEST_USER_ID },
        userData: {
          workspace_path: TEST_WORKSPACE_PATH,
          repo_url: TEST_REPO_URL,
          github_installation_id: TEST_INSTALLATION_ID,
        },
        owner: "test-owner",
        repo: "test-repo",
        relativePath: "overview/test.pdf",
        filePath: "knowledge-base/overview/test.pdf",
        ext: ".pdf",
      });
      expect(result.ctx.kbRoot).toContain("knowledge-base");
      expect(result.ctx.fullPath).toContain("overview/test.pdf");
    }
    // The credential read goes through the service-role resolvers, not a
    // tenant `users` read.
    expect(mockResolveKbRoot).toHaveBeenCalledWith(TEST_USER_ID, expect.anything());
  });

  test("threads the resolved active workspace id from kbRoot into repoMeta (member-vs-solo)", async () => {
    // An invited member operating on a shared workspace: the kbRoot resolver
    // returns an activeWorkspaceId distinct from the caller's user id; the
    // repoMeta resolver MUST be called with that same pre-resolved id so the
    // kbRoot, repo, and credential all key to ONE membership-resolved workspace
    // (no second independent resolution → no stale-claim divergence). This is
    // the #4543 write-route fix.
    setupHappyPath();
    const SHARED_WORKSPACE_ID = "11111111-2222-3333-4444-555555555555";
    setupResolvers(SHARED_WORKSPACE_ID);

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test.pdf"]),
    );
    expect(result.ok).toBe(true);
    expect(mockResolveRepoMeta).toHaveBeenCalledWith(
      TEST_USER_ID,
      expect.anything(),
      SHARED_WORKSPACE_ID,
    );
  });

  test("blockMarkdown: false allows .md paths through", async () => {
    setupHappyPath();

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "readme.md"]),
      { endpoint: "api/kb/file", blockMarkdown: false },
    );
    expect(result.ok).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Tests — syncWorkspace
// ---------------------------------------------------------------------------

describe("syncWorkspace", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGitWithAuth.mockResolvedValue(Buffer.from(""));
  });

  test("returns ok:true when git pull succeeds; delegates auth to gitWithInstallationAuth", async () => {
    const result = await syncWorkspace(
      TEST_INSTALLATION_ID,
      TEST_WORKSPACE_PATH,
      fakeLogger,
      { userId: TEST_USER_ID, op: "delete" },
    );
    expect(result.ok).toBe(true);

    expect(mockGitWithAuth).toHaveBeenCalledTimes(1);
    const [args, installationId, opts] = mockGitWithAuth.mock.calls[0];
    expect(args).toEqual(["pull", "--ff-only"]);
    expect(installationId).toBe(TEST_INSTALLATION_ID);
    expect(opts).toMatchObject({
      cwd: TEST_WORKSPACE_PATH,
      timeout: 30_000,
    });
  });

  test("returns ok:false when git pull fails", async () => {
    const pullErr = new Error("merge conflict");
    mockGitWithAuth.mockRejectedValue(pullErr);

    const result = await syncWorkspace(
      TEST_INSTALLATION_ID,
      TEST_WORKSPACE_PATH,
      fakeLogger,
      { userId: TEST_USER_ID, op: "rename" },
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toBe(pullErr);
  });

  test("logger.error is called with op tag on failure", async () => {
    mockGitWithAuth.mockRejectedValue(new Error("boom"));
    const errSpy = vi.fn();
    const logger = {
      info: vi.fn(),
      warn: vi.fn(),
      error: errSpy,
    } as unknown as import("pino").Logger;

    await syncWorkspace(TEST_INSTALLATION_ID, TEST_WORKSPACE_PATH, logger, {
      userId: TEST_USER_ID,
      op: "upload",
    });

    expect(errSpy).toHaveBeenCalledWith(
      expect.objectContaining({ userId: TEST_USER_ID, op: "upload" }),
      expect.stringContaining("upload"),
    );
  });

  // #4224 Phase 3 — Sentry-mirror sweep (cq-silent-fallback-must-mirror-to-sentry).
  // This is the NON-self-healable (`sync_failed`) path: a clean auth/host error
  // matches none of the ff-only/dirty-tree signatures, so it does NOT self-heal
  // and DOES page (log.error → pino-mirror + reportSilentFallback). The
  // self-healable `non_fast_forward` class is de-noised separately (see the
  // de-noise tests below).
  test("on a NON-self-healable (sync_failed) git pull failure, mirrors to Sentry via reportSilentFallback with feature:kb-route-helpers and op:workspace-sync-${op}", async () => {
    const pullErr = new Error(
      "fatal: unable to access 'https://github.com/o/r': Could not resolve host",
    );
    mockGitWithAuth.mockRejectedValue(pullErr);
    mockReportSilentFallback.mockClear();

    await syncWorkspace(TEST_INSTALLATION_ID, TEST_WORKSPACE_PATH, fakeLogger, {
      userId: TEST_USER_ID,
      op: "delete",
    });

    // The error-level pino line still fires for a genuine sync failure.
    expect(fakeLogger.error).toHaveBeenCalled();
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      pullErr,
      expect.objectContaining({
        feature: "kb-route-helpers",
        op: "workspace-sync-delete",
        message: expect.stringMatching(/workspace sync failed/i),
        // workspacePath intentionally NOT in extras — it embeds raw userId
        // (workspacePath = `<root>/<userId>`), which bypasses the
        // hashExtraUserId top-level rename (Recital 26).
        extra: expect.objectContaining({
          userId: TEST_USER_ID,
        }),
      }),
    );
  });

  // -------------------------------------------------------------------------
  // Fix B (this plan) — classify git failure + gated self-heal.
  // The non-fast-forward stderr signature was captured from the installed git
  // (2.53.0): `fatal: Not possible to fast-forward, aborting.`
  // -------------------------------------------------------------------------

  // A helper that builds a per-argv mock so the pull rejects but the
  // self-heal git ops (fetch / rev-list / reset) can be scripted.
  function scriptGit(handlers: {
    pull?: () => Promise<unknown> | never;
    fetch?: () => Promise<unknown>;
    revList?: () => Promise<unknown>;
    reset?: () => Promise<unknown>;
    symbolicRef?: () => Promise<unknown>;
    // `git rev-parse --abbrev-ref HEAD` — which branch HEAD is on. Drives the
    // recover-vs-protect decision on a diverged clone (default branch →
    // branch-aside + reset; feature branch → abort; "HEAD" → detached abort).
    // Defaults to the resolved default branch ("main\n") so a diverged
    // default-branch clone recovers unless a test scripts otherwise. MUST be
    // set explicitly in feature-branch / detached tests so they pass because
    // the branch was detected, not via a fall-through (Kieran P1-3).
    revParse?: () => Promise<unknown>;
    // `git branch <recovery> HEAD` — the branch-aside that preserves un-pushed
    // commits before the reset.
    branch?: () => Promise<unknown>;
  }) {
    mockGitWithAuth.mockImplementation((args: string[]) => {
      const verb = args[0];
      if (verb === "pull") {
        return handlers.pull
          ? handlers.pull()
          : Promise.resolve(Buffer.from(""));
      }
      if (verb === "symbolic-ref") {
        return handlers.symbolicRef
          ? handlers.symbolicRef()
          : Promise.resolve(Buffer.from("origin/main\n"));
      }
      if (verb === "rev-parse") {
        return handlers.revParse
          ? handlers.revParse()
          : Promise.resolve(Buffer.from("main\n"));
      }
      if (verb === "fetch") {
        return handlers.fetch
          ? handlers.fetch()
          : Promise.resolve(Buffer.from(""));
      }
      if (verb === "rev-list") {
        return handlers.revList
          ? handlers.revList()
          : Promise.resolve(Buffer.from("0\n"));
      }
      if (verb === "branch") {
        return handlers.branch
          ? handlers.branch()
          : Promise.resolve(Buffer.from(""));
      }
      if (verb === "reset") {
        return handlers.reset
          ? handlers.reset()
          : Promise.resolve(Buffer.from(""));
      }
      return Promise.resolve(Buffer.from(""));
    });
  }

  const NON_FF_STDERR =
    "fatal: Not possible to fast-forward, aborting.";

  // #4886-follow-up incident: the KB MIRROR clone had an uncommitted local edit
  // to `.claude/settings.json`, so `pull --ff-only` aborted on every push and the
  // reconcile froze (no row written). git 2.53.0 stderr for that abort:
  const DIRTY_TREE_STDERR =
    "error: Your local changes to the following files would be overwritten by merge:\n" +
    "\t.claude/settings.json\n" +
    "Please commit your changes or stash them before you merge.\nAborting";

  test("classifies a non-fast-forward stderr as non_fast_forward", async () => {
    // Diverged with ZERO local commits → safe self-heal path resets and recovers.
    scriptGit({
      pull: () => Promise.reject(new Error(NON_FF_STDERR)),
      revList: () => Promise.resolve(Buffer.from("0\n")),
    });

    const result = await syncWorkspace(
      TEST_INSTALLATION_ID,
      TEST_WORKSPACE_PATH,
      fakeLogger,
      { userId: TEST_USER_ID, op: "push" },
    );

    // Recovered → ok:true. The classification is asserted via the self-heal
    // path being taken (a sync_failed would never fetch/reset).
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.recovered).toBe(true);
  });

  test("#4886-followup: dirty-working-tree abort self-heals (reset --hard) → {ok:true, recovered:true}", async () => {
    // The KB-mirror clone had an uncommitted `.claude/settings.json` edit; the
    // dirty-tree abort must route to the SAME gated self-heal as non_fast_forward
    // (reset --hard discards the spurious edit; the un-pushed-commit gate protects
    // real session work). Before this fix it classified as sync_failed → froze.
    scriptGit({
      pull: () => Promise.reject(new Error(DIRTY_TREE_STDERR)),
      symbolicRef: () => Promise.resolve(Buffer.from("origin/main\n")),
      revList: () => Promise.resolve(Buffer.from("0\n")),
    });

    const result = await syncWorkspace(
      TEST_INSTALLATION_ID,
      TEST_WORKSPACE_PATH,
      fakeLogger,
      { userId: TEST_USER_ID, op: "push" },
    );

    expect(result.ok).toBe(true);
    if (result.ok) expect(result.recovered).toBe(true);
    const calls = mockGitWithAuth.mock.calls.map((c: unknown[]) => c[0] as string[]);
    expect(calls).toContainEqual(["reset", "--hard", "origin/main"]);
  });

  // De-noise (Sentry 9ccf1d86…): a self-HEALED ff-only abort must NOT emit an
  // error-level mirror. Before this fix, syncWorkspace called
  // `log.error({ err })` (pino-mirrored to Sentry as feature:"pino-mirror",
  // level error) + `reportSilentFallback` UNCONDITIONALLY before the self-heal,
  // so a benign, recovered dirty-tree abort paged the operator on every push.
  test("de-noise: dirty-tree abort that self-heals emits NO error mirror (no log.error, no reportSilentFallback), only an info breadcrumb + self-heal-reset warn", async () => {
    scriptGit({
      pull: () => Promise.reject(new Error(DIRTY_TREE_STDERR)),
      symbolicRef: () => Promise.resolve(Buffer.from("origin/main\n")),
      revList: () => Promise.resolve(Buffer.from("0\n")),
    });

    const result = await syncWorkspace(
      TEST_INSTALLATION_ID,
      TEST_WORKSPACE_PATH,
      fakeLogger,
      { userId: TEST_USER_ID, op: "push" },
    );

    expect(result.ok).toBe(true);
    if (result.ok) expect(result.recovered).toBe(true);
    // No error-level pino line (the pino-mirror Sentry capture path) on a
    // recovered self-heal.
    expect(fakeLogger.error).not.toHaveBeenCalled();
    // No reportSilentFallback at all on the recovered path: neither the removed
    // pre-self-heal mirror nor any self-heal abort/failure mirror.
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
    // The breadcrumb is recorded at info (Better Stack drain, below the WARN+
    // Sentry-mirror threshold).
    expect(fakeLogger.info).toHaveBeenCalledWith(
      expect.objectContaining({ userId: TEST_USER_ID, op: "push" }),
      expect.stringMatching(/ff-only pull blocked/i),
    );
    // The breadcrumb MUST carry no `err` key — that absence is the load-bearing
    // reason it does not pino-mirror to Sentry (logger.ts captures only when an
    // `err` is present at error/fatal). A future edit that re-adds `{ err }`
    // here would quietly re-introduce the capture this fix removed.
    const infoCtx = (fakeLogger.info as unknown as ReturnType<typeof vi.fn>).mock
      .calls[0][0];
    expect(infoCtx).not.toHaveProperty("err");
    // Recovery stays observable via the warning-level self-heal-reset mirror.
    expect(mockWarnSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "self-heal-reset" }),
    );
  });

  test("de-noise: diverged (non-FF) abort that self-heals also emits NO error mirror, only an info breadcrumb + self-heal-reset warn", async () => {
    scriptGit({
      pull: () => Promise.reject(new Error(NON_FF_STDERR)),
      symbolicRef: () => Promise.resolve(Buffer.from("origin/main\n")),
      revList: () => Promise.resolve(Buffer.from("0\n")),
    });

    const result = await syncWorkspace(
      TEST_INSTALLATION_ID,
      TEST_WORKSPACE_PATH,
      fakeLogger,
      { userId: TEST_USER_ID, op: "push" },
    );

    expect(result.ok).toBe(true);
    // Symmetric with the dirty-tree sibling: pin the FULL contract so this test
    // distinguishes "correctly de-noised" from "went dark" (no observability at
    // all). recovered:true proves the self-heal path was actually taken.
    if (result.ok) expect(result.recovered).toBe(true);
    expect(fakeLogger.error).not.toHaveBeenCalled();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
    expect(fakeLogger.info).toHaveBeenCalledWith(
      expect.objectContaining({ userId: TEST_USER_ID, op: "push" }),
      expect.stringMatching(/ff-only pull blocked/i),
    );
    expect(mockWarnSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "self-heal-reset" }),
    );
  });

  test("#4886-followup: dirty-tree + un-pushed commits on a FEATURE branch → NO reset (gate protects work), {ok:false}", async () => {
    // HEAD on a non-default named branch = genuine agent work targeting a PR.
    // The branch-aside recovery applies ONLY to default-branch divergence; a
    // feature branch must keep aborting to protect un-pushed work.
    scriptGit({
      pull: () => Promise.reject(new Error(DIRTY_TREE_STDERR)),
      symbolicRef: () => Promise.resolve(Buffer.from("origin/main\n")),
      revParse: () => Promise.resolve(Buffer.from("feat-session-work\n")),
      revList: () => Promise.resolve(Buffer.from("2\n")),
    });

    const result = await syncWorkspace(
      TEST_INSTALLATION_ID,
      TEST_WORKSPACE_PATH,
      fakeLogger,
      { userId: TEST_USER_ID, op: "push" },
    );

    expect(result.ok).toBe(false);
    const calls = mockGitWithAuth.mock.calls.map((c: unknown[]) => c[0] as string[]);
    expect(calls.some((a) => a[0] === "reset")).toBe(false);
    // No branch-aside either — a feature branch is protected, not recovered.
    expect(calls.some((a) => a[0] === "branch")).toBe(false);
  });

  test("classifies an auth/IO error as sync_failed (no self-heal attempted)", async () => {
    const authErr = new Error("fatal: Authentication failed for repo");
    mockGitWithAuth.mockRejectedValue(authErr);

    const result = await syncWorkspace(
      TEST_INSTALLATION_ID,
      TEST_WORKSPACE_PATH,
      fakeLogger,
      { userId: TEST_USER_ID, op: "manual" },
    );

    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.errorClass).toBe("sync_failed");
    // Only the pull was attempted — no fetch/rev-list/reset.
    const verbs = mockGitWithAuth.mock.calls.map((c: unknown[]) => (c[0] as string[])[0]);
    expect(verbs).toEqual(["pull"]);
  });

  test("self-heal: non-FF + ZERO local commits → fetch + reset to resolved default branch, returns {ok:true, recovered:true}", async () => {
    scriptGit({
      pull: () => Promise.reject(new Error(NON_FF_STDERR)),
      symbolicRef: () => Promise.resolve(Buffer.from("origin/main\n")),
      revList: () => Promise.resolve(Buffer.from("0\n")),
    });

    const result = await syncWorkspace(
      TEST_INSTALLATION_ID,
      TEST_WORKSPACE_PATH,
      fakeLogger,
      { userId: TEST_USER_ID, op: "push" },
    );

    expect(result.ok).toBe(true);
    if (result.ok) expect(result.recovered).toBe(true);

    const calls = mockGitWithAuth.mock.calls.map((c: unknown[]) => c[0] as string[]);
    // fetch origin <default> and reset --hard origin/<default> must be present,
    // resolved (not literal "main" passed by us — derived from symbolic-ref).
    expect(calls).toContainEqual(["fetch", "origin", "main"]);
    expect(calls).toContainEqual(["reset", "--hard", "origin/main"]);
    // rev-list guard ran before reset.
    const verbs = calls.map((a) => a[0]);
    expect(verbs.indexOf("rev-list")).toBeLessThan(verbs.indexOf("reset"));
  });

  test("self-heal AC3: non-FF + NON-ZERO local commits on a FEATURE branch → NO reset/branch, returns {ok:false, errorClass:non_fast_forward}", async () => {
    // revParse returns a feature branch EXPLICITLY so the abort is reached
    // because a non-default branch was detected, not via an empty-string
    // fall-through (Kieran P1-3).
    scriptGit({
      pull: () => Promise.reject(new Error(NON_FF_STDERR)),
      symbolicRef: () => Promise.resolve(Buffer.from("origin/main\n")),
      revParse: () => Promise.resolve(Buffer.from("feat-something\n")),
      revList: () => Promise.resolve(Buffer.from("3\n")), // un-pushed agent work
    });

    const result = await syncWorkspace(
      TEST_INSTALLATION_ID,
      TEST_WORKSPACE_PATH,
      fakeLogger,
      { userId: TEST_USER_ID, op: "push" },
    );

    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.errorClass).toBe("non_fast_forward");

    const verbs = mockGitWithAuth.mock.calls.map(
      (c: unknown[]) => (c[0] as string[])[0],
    );
    expect(verbs).not.toContain("reset");
    expect(verbs).not.toContain("branch");
    // Dirty-abort is observable + fail_loud.
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "self-heal-aborted-dirty" }),
    );
  });

  // ---------------------------------------------------------------------------
  // Diverged-clone-with-un-pushed-commits recovery (THIS plan). A clone on the
  // DEFAULT branch with un-pushable auto-sync orphan commits is recovered by
  // branching the commits aside (preserve) then resetting to origin — the
  // permanent dead-end behind the prod Sentry `self-heal-aborted-dirty` cluster.
  // ---------------------------------------------------------------------------

  test("AC1/AC2 recovery: non-FF + un-pushed commits on the DEFAULT branch → branch-aside BEFORE reset, returns {ok:true, recovered:true}", async () => {
    scriptGit({
      pull: () => Promise.reject(new Error(NON_FF_STDERR)),
      // resolved default branch (symbolic-ref → origin/main → "main")
      symbolicRef: () => Promise.resolve(Buffer.from("origin/main\n")),
      // HEAD is ON the default branch — compared against the RESOLVED default,
      // not a hardcoded literal, so the test passes for the right reason.
      revParse: () => Promise.resolve(Buffer.from("main\n")),
      revList: () => Promise.resolve(Buffer.from("2\n")), // un-pushable orphans
      branch: () => Promise.resolve(Buffer.from("")),
      reset: () => Promise.resolve(Buffer.from("")),
    });

    const result = await syncWorkspace(
      TEST_INSTALLATION_ID,
      TEST_WORKSPACE_PATH,
      fakeLogger,
      { userId: TEST_USER_ID, op: "push" },
    );

    // AC1 — recovered, not aborted.
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.recovered).toBe(true);

    const calls = mockGitWithAuth.mock.calls.map(
      (c: unknown[]) => c[0] as string[],
    );
    // The branch-aside targets HEAD and resets to the RESOLVED default.
    const branchCall = calls.find((a) => a[0] === "branch");
    expect(branchCall).toBeDefined();
    // `git branch <recovery> HEAD` — preserves the un-pushed commits on a ref.
    expect(branchCall?.[2]).toBe("HEAD");
    expect(branchCall?.[1]).toMatch(/^soleur\/recovered-kb-sync-\d+$/);
    expect(calls).toContainEqual(["reset", "--hard", "origin/main"]);

    // AC2 — non-destructive ordering: branch-aside is issued BEFORE the reset
    // so the commit objects live on a named ref before the default ref moves.
    const verbs = calls.map((a) => a[0]);
    expect(verbs.indexOf("branch")).toBeGreaterThan(-1);
    expect(verbs.indexOf("branch")).toBeLessThan(verbs.indexOf("reset"));

    // Recovery is observable as a distinct WARN op (queryable recovery rate,
    // does not page) and NOT bucketed into the abort/phantom-reset slugs.
    expect(mockWarnSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "self-heal-recovered-diverged" }),
    );
    // It is a recovery, not a failure — no error-level mirror.
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  test("AC4 detached HEAD: rev-parse → literal \"HEAD\" + un-pushed commits → abort with DISTINCT op, no branch/reset", async () => {
    scriptGit({
      pull: () => Promise.reject(new Error(NON_FF_STDERR)),
      symbolicRef: () => Promise.resolve(Buffer.from("origin/main\n")),
      // `git rev-parse --abbrev-ref HEAD` emits the literal "HEAD" when detached.
      revParse: () => Promise.resolve(Buffer.from("HEAD\n")),
      revList: () => Promise.resolve(Buffer.from("1\n")),
    });

    const result = await syncWorkspace(
      TEST_INSTALLATION_ID,
      TEST_WORKSPACE_PATH,
      fakeLogger,
      { userId: TEST_USER_ID, op: "push" },
    );

    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.errorClass).toBe("non_fast_forward");

    const verbs = mockGitWithAuth.mock.calls.map(
      (c: unknown[]) => (c[0] as string[])[0],
    );
    expect(verbs).not.toContain("branch");
    expect(verbs).not.toContain("reset");
    // Distinct, queryable slug — never silently bucketed into aborted-dirty.
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "self-heal-aborted-detached-head" }),
    );
    expect(mockReportSilentFallback).not.toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "self-heal-aborted-dirty" }),
    );
  });

  test("AC5a observability: recovery payload carries pseudonymized userId and NO raw workspacePath", async () => {
    scriptGit({
      pull: () => Promise.reject(new Error(NON_FF_STDERR)),
      symbolicRef: () => Promise.resolve(Buffer.from("origin/main\n")),
      revParse: () => Promise.resolve(Buffer.from("main\n")),
      revList: () => Promise.resolve(Buffer.from("2\n")),
    });
    await syncWorkspace(TEST_INSTALLATION_ID, TEST_WORKSPACE_PATH, fakeLogger, {
      userId: TEST_USER_ID,
      op: "push",
    });
    expect(mockWarnSilentFallback.mock.calls.length).toBeGreaterThan(0);
    for (const call of mockWarnSilentFallback.mock.calls) {
      const opts = call[1] as { extra?: Record<string, unknown> };
      expect(opts.extra).not.toHaveProperty("workspacePath");
      expect(opts.extra?.userId).toBe(TEST_USER_ID);
    }
  });

  test("AC5b observability: detached-abort payload carries pseudonymized userId and NO raw workspacePath", async () => {
    scriptGit({
      pull: () => Promise.reject(new Error(NON_FF_STDERR)),
      symbolicRef: () => Promise.resolve(Buffer.from("origin/main\n")),
      revParse: () => Promise.resolve(Buffer.from("HEAD\n")),
      revList: () => Promise.resolve(Buffer.from("1\n")),
    });
    await syncWorkspace(TEST_INSTALLATION_ID, TEST_WORKSPACE_PATH, fakeLogger, {
      userId: TEST_USER_ID,
      op: "push",
    });
    expect(mockReportSilentFallback.mock.calls.length).toBeGreaterThan(0);
    for (const call of mockReportSilentFallback.mock.calls) {
      const opts = call[1] as { extra?: Record<string, unknown> };
      expect(opts.extra).not.toHaveProperty("workspacePath");
      expect(opts.extra?.userId).toBe(TEST_USER_ID);
    }
  });

  test("AC6 phantom path unchanged: ZERO local commits → self-heal-reset, issues NO branch", async () => {
    scriptGit({
      pull: () => Promise.reject(new Error(NON_FF_STDERR)),
      symbolicRef: () => Promise.resolve(Buffer.from("origin/main\n")),
      revList: () => Promise.resolve(Buffer.from("0\n")),
    });

    const result = await syncWorkspace(
      TEST_INSTALLATION_ID,
      TEST_WORKSPACE_PATH,
      fakeLogger,
      { userId: TEST_USER_ID, op: "push" },
    );

    expect(result.ok).toBe(true);
    if (result.ok) expect(result.recovered).toBe(true);

    const verbs = mockGitWithAuth.mock.calls.map(
      (c: unknown[]) => (c[0] as string[])[0],
    );
    // The new branch-aside is gated on localCommits > 0 — a phantom (zero
    // commit) reset must NOT create a recovery branch.
    expect(verbs).not.toContain("branch");
    // It stays the phantom-reset slug, NOT the diverged-recovery one.
    expect(mockWarnSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "self-heal-reset" }),
    );
    expect(mockWarnSilentFallback).not.toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "self-heal-recovered-diverged" }),
    );
  });

  test("recovery is keyed on the RESOLVED default branch, not a hardcoded \"main\" (default = trunk)", async () => {
    // The HEAD comparison must use the symbolic-ref-resolved default, so a
    // repo whose default is `trunk` recovers and resets to origin/trunk. A
    // buggy `headRef === "main"` impl would abort here instead of recovering.
    scriptGit({
      pull: () => Promise.reject(new Error(NON_FF_STDERR)),
      symbolicRef: () => Promise.resolve(Buffer.from("origin/trunk\n")),
      revParse: () => Promise.resolve(Buffer.from("trunk\n")),
      revList: () => Promise.resolve(Buffer.from("1\n")),
    });

    const result = await syncWorkspace(
      TEST_INSTALLATION_ID,
      TEST_WORKSPACE_PATH,
      fakeLogger,
      { userId: TEST_USER_ID, op: "push" },
    );

    expect(result.ok).toBe(true);
    if (result.ok) expect(result.recovered).toBe(true);
    const calls = mockGitWithAuth.mock.calls.map(
      (c: unknown[]) => c[0] as string[],
    );
    expect(calls.some((a) => a[0] === "branch")).toBe(true);
    expect(calls).toContainEqual(["reset", "--hard", "origin/trunk"]);
    expect(mockWarnSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "self-heal-recovered-diverged" }),
    );
  });

  test("un-countable rev-list (NaN) → fail safe: abort, NO branch/reset", async () => {
    // A malformed rev-list count must NOT branch-aside or reset — the
    // recovery is gated on a COUNTABLE divergence (`!Number.isNaN`). Empty
    // output → parseInt(...) === NaN → abort, preserve work.
    scriptGit({
      pull: () => Promise.reject(new Error(NON_FF_STDERR)),
      symbolicRef: () => Promise.resolve(Buffer.from("origin/main\n")),
      revParse: () => Promise.resolve(Buffer.from("main\n")),
      revList: () => Promise.resolve(Buffer.from("")), // unparseable → NaN
    });

    const result = await syncWorkspace(
      TEST_INSTALLATION_ID,
      TEST_WORKSPACE_PATH,
      fakeLogger,
      { userId: TEST_USER_ID, op: "push" },
    );

    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.errorClass).toBe("non_fast_forward");
    const verbs = mockGitWithAuth.mock.calls.map(
      (c: unknown[]) => (c[0] as string[])[0],
    );
    expect(verbs).not.toContain("branch");
    expect(verbs).not.toContain("reset");
  });

  test("self-heal failure: non-FF + reset rejects → fail_loud + {ok:false}", async () => {
    const resetErr = new Error("fatal: reset failed");
    scriptGit({
      pull: () => Promise.reject(new Error(NON_FF_STDERR)),
      symbolicRef: () => Promise.resolve(Buffer.from("origin/main\n")),
      revList: () => Promise.resolve(Buffer.from("0\n")),
      reset: () => Promise.reject(resetErr),
    });

    const result = await syncWorkspace(
      TEST_INSTALLATION_ID,
      TEST_WORKSPACE_PATH,
      fakeLogger,
      { userId: TEST_USER_ID, op: "push" },
    );

    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.errorClass).toBe("non_fast_forward");
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      resetErr,
      expect.objectContaining({ op: "self-heal-failed" }),
    );
  });

  test("self-heal success is observable (op:self-heal-reset mirror)", async () => {
    scriptGit({
      pull: () => Promise.reject(new Error(NON_FF_STDERR)),
      revList: () => Promise.resolve(Buffer.from("0\n")),
    });

    await syncWorkspace(TEST_INSTALLATION_ID, TEST_WORKSPACE_PATH, fakeLogger, {
      userId: TEST_USER_ID,
      op: "push",
    });

    expect(mockWarnSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "self-heal-reset" }),
    );
  });

  test("clean pull → ok:true, no reset, no recovered flag", async () => {
    mockGitWithAuth.mockResolvedValue(Buffer.from(""));

    const result = await syncWorkspace(
      TEST_INSTALLATION_ID,
      TEST_WORKSPACE_PATH,
      fakeLogger,
      { userId: TEST_USER_ID, op: "manual" },
    );

    expect(result.ok).toBe(true);
    if (result.ok) expect(result.recovered).toBeUndefined();
    const verbs = mockGitWithAuth.mock.calls.map(
      (c: unknown[]) => (c[0] as string[])[0],
    );
    expect(verbs).toEqual(["pull"]);
  });
});
