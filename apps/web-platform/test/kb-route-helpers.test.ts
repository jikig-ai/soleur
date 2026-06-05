import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const {
  mockGetUser,
  mockFrom,
  mockServiceFrom,
  mockGetFreshTenantClient,
  mockGitWithAuth,
  mockIsPathInWorkspace,
  mockLstat,
  mockValidateOrigin,
  mockRejectCsrf,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
  // Distinct service-role `.from` so the mint-failure fallback tests can
  // prove the SERVICE-ROLE client (not the tenant client) produced the
  // resolved workspace — wiring both clients to the same `mockFrom` would
  // let a fallback assertion pass vacuously (deepen-plan P1).
  mockServiceFrom: vi.fn(),
  mockGetFreshTenantClient: vi.fn(),
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
  // Service-role client → distinct `mockServiceFrom` (see hoisted note).
  createServiceClient: vi.fn(() => ({
    from: mockServiceFrom,
  })),
}));

// PR-C §2.8 (#3244): kb-route-helpers imports `getFreshTenantClient` from
// `@/lib/supabase/tenant`. Default impl resolves to the tenant `mockFrom`
// (the same per-table setup `setupUserData` drives); individual tests
// override with `mockGetFreshTenantClient.mockRejectedValueOnce(...)` to
// simulate a tenant-mint failure. The mock RuntimeAuthError mirrors the
// real two-arg `(cause, message)` signature + public `cause` field so the
// fallback's `instanceof` check and any cause-discrimination work in tests.
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: mockGetFreshTenantClient,
  RuntimeAuthError: class RuntimeAuthError extends Error {
    public readonly cause: "jwt_mint" | "rotation" | "denied_jti";
    constructor(
      cause: "jwt_mint" | "rotation" | "denied_jti",
      message: string,
    ) {
      super(message);
      this.name = "RuntimeAuthError";
      this.cause = cause;
    }
  },
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
import { RuntimeAuthError } from "@/lib/supabase/tenant";

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

function setupUserData(overrides: Record<string, unknown> = {}) {
  const mockSingle = vi.fn().mockResolvedValue({
    data: {
      workspace_path: TEST_WORKSPACE_PATH,
      workspace_status: "ready",
      repo_url: TEST_REPO_URL,
      github_installation_id: TEST_INSTALLATION_ID,
      ...overrides,
    },
    error: null,
  });
  const mockEq = vi.fn(() => ({ single: mockSingle }));
  const mockSelect = vi.fn(() => ({ eq: mockEq }));
  mockFrom.mockImplementation((table: string) => {
    if (table === "users") return { select: mockSelect };
    return {};
  });
  // Default: the tenant mint succeeds and the tenant client reads via mockFrom.
  mockGetFreshTenantClient.mockResolvedValue({ from: mockFrom });
}

// Wire the SERVICE-ROLE client's `.from` (distinct from the tenant `mockFrom`)
// to a `users` row. Used by the tenant-mint-failure fallback tests so the
// assertion proves the service-role read — not the tenant read — produced the
// result. Returns nothing when called for a table other than "users".
function setupServiceUserData(overrides: Record<string, unknown> = {}) {
  const mockSingle = vi.fn().mockResolvedValue({
    data: {
      workspace_path: TEST_WORKSPACE_PATH,
      workspace_status: "ready",
      repo_url: TEST_REPO_URL,
      github_installation_id: TEST_INSTALLATION_ID,
      ...overrides,
    },
    error: null,
  });
  const mockEq = vi.fn(() => ({ single: mockSingle }));
  const mockSelect = vi.fn(() => ({ eq: mockEq }));
  mockServiceFrom.mockImplementation((table: string) => {
    if (table === "users") return { select: mockSelect };
    return {};
  });
}

function setupHappyPath() {
  mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
  setupAuthenticatedUser();
  setupUserData();
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
  });

  test("returns 503 when workspace is not ready", async () => {
    setupHappyPath();
    setupUserData({ workspace_status: "provisioning" });

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.response.status).toBe(503);
  });

  test("returns 400 when no repo connected", async () => {
    setupHappyPath();
    setupUserData({ repo_url: null });

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.response.status).toBe(400);
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

  test("happy path returns populated context", async () => {
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
    // Recovery stays observable via the warning-level self-heal-reset mirror.
    expect(mockWarnSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "self-heal-reset" }),
    );
  });

  test("de-noise: diverged (non-FF) abort that self-heals also emits NO error mirror", async () => {
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
    expect(fakeLogger.error).not.toHaveBeenCalled();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  test("#4886-followup: dirty-tree + un-pushed commits → NO reset (gate protects work), {ok:false}", async () => {
    scriptGit({
      pull: () => Promise.reject(new Error(DIRTY_TREE_STDERR)),
      symbolicRef: () => Promise.resolve(Buffer.from("origin/main\n")),
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

  test("self-heal AC-B6: non-FF + NON-ZERO local commits → NO reset, returns {ok:false, errorClass:non_fast_forward}", async () => {
    scriptGit({
      pull: () => Promise.reject(new Error(NON_FF_STDERR)),
      symbolicRef: () => Promise.resolve(Buffer.from("origin/main\n")),
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
    // Dirty-abort is observable + fail_loud.
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "self-heal-aborted-dirty" }),
    );
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

// ---------------------------------------------------------------------------
// Tests — authenticateAndResolveKbPath — tenant-mint failure (REVERTED)
//
// PR #4919 added a per-cause service-role fallback (availability causes
// jwt_mint/rotation fell back to a service-role read; denied_jti failed closed).
// PIR #4913 proved the mint failure was a misdiagnosis, so #4919's fallback is
// the same dead-code class as #4913's. This revert restores the pre-#4919
// behavior on the file mutation routes: availability causes → 503 (workspace
// not resolvable right now), revocation/unknown → 403 (fail closed). The emit
// is PRESERVED for EVERY cause so the #4920 alert keeps its signal, and the
// service-role client is never reached. The distinct mockServiceFrom keeps each
// `not called` assertion non-vacuous.
// ---------------------------------------------------------------------------

describe("authenticateAndResolveKbPath — tenant-mint failure (reverted)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Happy-path wiring for CSRF / auth / path / lstat; the per-test mint
    // override forces the RuntimeAuthError branch. A ready service-role row is
    // wired but MUST NOT be read after the revert (keeps negatives non-vacuous).
    setupHappyPath();
    setupServiceUserData();
  });

  // Availability causes (jwt_mint / rotation) → 503, NO service-role fallback.
  test.each(["jwt_mint", "rotation"] as const)(
    "availability cause %s → 503 Workspace not ready, NO service-role fallback",
    async (cause) => {
      mockGetFreshTenantClient.mockRejectedValueOnce(
        new RuntimeAuthError(cause, `mint failed: ${cause}`),
      );

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
      // The service-role escape hatch is gone — neither client is reached.
      expect(mockServiceFrom).not.toHaveBeenCalled();
      expect(mockFrom).not.toHaveBeenCalled();
    },
  );

  // Revocation (denied_jti) and any unknown cause → fail CLOSED with 403.
  test("denied_jti → fail closed with 403, NO read of any kind", async () => {
    mockGetFreshTenantClient.mockRejectedValueOnce(
      new RuntimeAuthError("denied_jti", "jti on deny-list"),
    );

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test.pdf"]),
    );

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.status).toBe(403);
      const body = await result.response.json();
      expect(body.error).toMatch(/access denied/i);
    }
    expect(mockServiceFrom).not.toHaveBeenCalled();
    expect(mockFrom).not.toHaveBeenCalled();
  });

  // Load-bearing: both route handlers call this helper OUTSIDE their try block,
  // so the mint-failure path must RESOLVE to a Response, never reject (a thrown
  // RuntimeAuthError would escape to Next.js → uncontrolled 500).
  test("mint-failure path RESOLVES to a Response, never rejects", async () => {
    mockGetFreshTenantClient.mockRejectedValueOnce(
      new RuntimeAuthError("denied_jti", "jti on deny-list"),
    );

    await expect(
      authenticateAndResolveKbPath(
        createRequest(),
        createParams(["overview", "test.pdf"]),
      ),
    ).resolves.toMatchObject({ ok: false });
  });

  // reportSilentFallback fires exactly once for EVERY cause, including
  // denied_jti (the revocation hit must stay Sentry-visible BEFORE the 403
  // early-return) — this is the #4920 alert's signal, preserved across the revert.
  test.each(["jwt_mint", "rotation", "denied_jti"] as const)(
    "%s emits exactly one reportSilentFallback with op:authenticateAndResolveKbPath.tenant-mint",
    async (cause) => {
      const mintErr = new RuntimeAuthError(cause, `mint failure: ${cause}`);
      mockGetFreshTenantClient.mockRejectedValueOnce(mintErr);

      await authenticateAndResolveKbPath(
        createRequest(),
        createParams(["overview", "test.pdf"]),
      );

      expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
      expect(mockReportSilentFallback).toHaveBeenCalledWith(
        mintErr,
        expect.objectContaining({
          feature: "kb-route-helpers",
          op: "authenticateAndResolveKbPath.tenant-mint",
          extra: expect.objectContaining({ userId: TEST_USER_ID }),
        }),
      );
    },
  );

  // A non-RuntimeAuthError mint failure is re-thrown unchanged.
  test("a non-RuntimeAuthError from the mint is re-thrown (not swallowed)", async () => {
    mockGetFreshTenantClient.mockRejectedValueOnce(new Error("unexpected boom"));

    await expect(
      authenticateAndResolveKbPath(
        createRequest(),
        createParams(["overview", "test.pdf"]),
      ),
    ).rejects.toThrow("unexpected boom");
    expect(mockServiceFrom).not.toHaveBeenCalled();
  });

  // Regression guard — happy path (mint succeeds): tenant read, no fallback.
  test("happy path (mint succeeds) reads via the TENANT client, no fallback", async () => {
    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test.pdf"]),
    );

    expect(result.ok).toBe(true);
    expect(mockFrom).toHaveBeenCalledWith("users");
    expect(mockServiceFrom).not.toHaveBeenCalled();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });
});
