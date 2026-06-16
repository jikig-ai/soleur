// RED/GREEN — unconditional pre-sandbox workspace-dir guarantee
// (feat-one-shot-warm-reprovision-ensure-dir-presandbox).
//
// The bwrap sandbox binds cwd=workspacePath at query() construction and
// REQUIRES the dir to exist; after a host/sandbox reclaim it can be gone.
// The PR #5367 mkdir lives INSIDE realGraftRepoClone, reached only past
// ensureWorkspaceRepoCloned's `:85` (not-connected) / `:89` (.git-present)
// early-returns — so a reclaimed NOT-CONNECTED workspace skips the mkdir
// entirely and the sandbox is built against a non-existent CWD (the
// reported "the configured CWD /workspaces/<uuid> doesn't exist" symptom).
//
// This file asserts the INVARIANT (dir exists at the path the sandbox
// binds, at sandbox-construction time) against a real reclaimed tmpdir —
// NOT a mocked-call-ordering proxy (which is GREEN on main for connected
// users). RED on main: the not-connected workspace never gets an mkdir
// before buildAgentQueryOptions.
//
// Harness mirrors cc-dispatcher-real-factory.test.ts. The one deliberate
// difference: `@/server/ensure-workspace-repo` is mocked via importActual so
// the REAL `ensureWorkspaceDirExists` helper runs (the actual mkdir under
// test) while only the clone (`ensureWorkspaceRepoCloned`) is stubbed.

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { existsSync } from "node:fs";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.NEXT_PUBLIC_APP_URL ??= "https://app.soleur.ai";

const {
  mockLogInfo,
  mockQuery,
  mockGetUserApiKey,
  mockGetUserServiceTokens,
  mockPatchWorkspacePermissions,
  mockReportSilentFallback,
  mockSendToClient,
  mockBuildAgentEnv,
  mockBuildAgentSandboxConfig,
  mockSupabaseFrom,
  mockResolveInstallationId,
  mockGenerateInstallationToken,
  mockResolveBashAutonomous,
  mockResolveAutonomousAck,
  mockResolveIsWorkspaceOwner,
  mockWriteAskpassScriptTo,
  mockCleanupAskpassScript,
  mockResolveActiveWorkspacePath,
  mockGetCurrentRepoUrl,
  mockGetInstallationAccount,
  mockFindRepoOwnerInstallationForUser,
  mockEnsureWorkspaceRepoCloned,
} = vi.hoisted(() => ({
  mockLogInfo: vi.fn(),
  mockQuery: vi.fn(),
  mockGetUserApiKey: vi.fn(),
  mockGetUserServiceTokens: vi.fn(),
  mockPatchWorkspacePermissions: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockSendToClient: vi.fn(),
  mockBuildAgentEnv: vi.fn(),
  mockBuildAgentSandboxConfig: vi.fn(),
  mockSupabaseFrom: vi.fn(),
  mockResolveInstallationId: vi.fn(),
  mockGenerateInstallationToken: vi.fn(),
  mockResolveBashAutonomous: vi.fn(),
  mockResolveAutonomousAck: vi.fn(),
  mockResolveIsWorkspaceOwner: vi.fn(),
  mockWriteAskpassScriptTo: vi.fn(),
  mockCleanupAskpassScript: vi.fn(),
  mockResolveActiveWorkspacePath: vi.fn(),
  mockGetCurrentRepoUrl: vi.fn(),
  mockGetInstallationAccount: vi.fn(),
  mockFindRepoOwnerInstallationForUser: vi.fn(),
  mockEnsureWorkspaceRepoCloned: vi.fn(async () => undefined),
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
  getSessionMessages: vi.fn().mockResolvedValue([]),
  tool: vi.fn(),
  createSdkMcpServer: vi.fn(),
}));

vi.mock("@/server/agent-runner", () => ({
  getUserApiKey: mockGetUserApiKey,
  getUserServiceTokens: mockGetUserServiceTokens,
  patchWorkspacePermissions: mockPatchWorkspacePermissions,
}));

vi.mock("@/server/agent-runner-sandbox-config", () => ({
  buildAgentSandboxConfig: mockBuildAgentSandboxConfig,
}));

vi.mock("@/server/agent-env", () => ({
  buildAgentEnv: mockBuildAgentEnv,
}));

vi.mock("@/server/sandbox-hook", () => ({
  createSandboxHook: vi.fn(() => async () => ({})),
}));

vi.mock("@/server/resolve-installation-id", () => ({
  resolveInstallationId: mockResolveInstallationId,
}));

vi.mock("@/server/github-app", () => ({
  generateInstallationToken: mockGenerateInstallationToken,
  getInstallationAccount: mockGetInstallationAccount,
  findRepoOwnerInstallationForUser: mockFindRepoOwnerInstallationForUser,
}));

vi.mock("@/server/git-auth", () => ({
  writeAskpassScriptTo: mockWriteAskpassScriptTo,
  cleanupAskpassScript: mockCleanupAskpassScript,
}));

vi.mock("@/server/resolve-bash-autonomous", () => ({
  resolveBashAutonomous: mockResolveBashAutonomous,
}));

vi.mock("@/server/resolve-autonomous-ack", () => ({
  resolveAutonomousAck: mockResolveAutonomousAck,
}));
vi.mock("@/server/resolve-workspace-owner", () => ({
  resolveIsWorkspaceOwner: mockResolveIsWorkspaceOwner,
}));

vi.mock("@/server/workspace-resolver", async () => {
  const actual = await vi.importActual<typeof import("@/server/workspace-resolver")>(
    "@/server/workspace-resolver",
  );
  return {
    ...actual,
    resolveActiveWorkspacePath: mockResolveActiveWorkspacePath,
    // ADR-044 PR-1: factory resolves this directly before the Promise.all.
    resolveActiveWorkspace: async (userId: string) => ({
      ok: true as const,
      workspaceId: userId,
    }),
  };
});

vi.mock("@/server/current-repo-url", () => ({
  getCurrentRepoUrl: mockGetCurrentRepoUrl,
  // #5394 — gate reads repo readiness; default ready so dispatch is not blocked.
  getCurrentRepoStatus: vi.fn(async () => ({
    repoStatus: "ready",
    repoError: null,
  })),
}));

// DELIBERATE: keep the REAL `ensureWorkspaceDirExists` (the mkdir under test)
// and stub ONLY the clone. importActual is the difference vs.
// cc-dispatcher-real-factory.test.ts's wholesale mock.
vi.mock("@/server/ensure-workspace-repo", async () => {
  const actual = await vi.importActual<typeof import("@/server/ensure-workspace-repo")>(
    "@/server/ensure-workspace-repo",
  );
  return { ...actual, ensureWorkspaceRepoCloned: mockEnsureWorkspaceRepoCloned };
});

vi.mock("@/server/permission-callback", () => ({
  createCanUseTool: vi.fn(() => async () => ({ behavior: "allow" })),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
  mirrorWithDebounce: mockReportSilentFallback,
  __resetMirrorDebounceForTests: vi.fn(),
  MIRROR_DEBOUNCE_MS: 5 * 60 * 1000,
}));

vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(() => ({ from: mockSupabaseFrom })),
}));

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ from: mockSupabaseFrom })),
  mintFounderJwt: vi.fn(),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));

vi.mock("@/server/byok-lease", async () => {
  const actual = await vi.importActual<typeof import("@/server/byok-lease")>(
    "@/server/byok-lease",
  );
  return {
    ...actual,
    runWithByokLease: vi.fn(
      async <T>(
        args: { workspaceContextUserId: string; keyOwnerUserId: string },
        body: (lease: {
          workspaceContextUserId: string;
          keyOwnerUserId: string;
          getRestApiKey: () => string | Promise<string>;
          getAgentCredential: () => Promise<{ value: string; scheme: "api_key" | "oauth_token" }>;
        }) => Promise<T>,
      ) =>
        body({
          workspaceContextUserId: args.workspaceContextUserId,
          keyOwnerUserId: args.keyOwnerUserId,
          getRestApiKey: () => mockGetUserApiKey(),
          getAgentCredential: async () => ({
            value: await mockGetUserApiKey(),
            scheme: "api_key" as const,
          }),
        }),
    ),
  };
});

vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));

vi.mock("@/server/ws-handler", () => ({
  sendToClient: mockSendToClient,
}));

vi.mock("@/server/logger", () => ({
  default: { info: mockLogInfo, error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({
    info: mockLogInfo,
    warn: vi.fn(),
    error: vi.fn(),
  }),
}));

vi.mock("@/server/notifications", () => ({ notifyOfflineUser: vi.fn() }));

import { realSdkQueryFactory } from "@/server/cc-dispatcher";

function makeFakeQuery() {
  return {
    async *[Symbol.asyncIterator]() {},
    close: vi.fn().mockResolvedValue(undefined),
    interrupt: vi.fn().mockResolvedValue(undefined),
    setPermissionMode: vi.fn().mockResolvedValue(undefined),
    setModel: vi.fn().mockResolvedValue(undefined),
    supportedCommands: vi.fn().mockResolvedValue([]),
    supportedModels: vi.fn().mockResolvedValue([]),
    mcpServerStatus: vi.fn().mockResolvedValue([]),
    next: vi.fn(),
    return: vi.fn(),
    throw: vi.fn(),
    // biome-ignore lint/suspicious/noExplicitAny: SDK Query stub
  } as any;
}

function makeArgs(overrides: Partial<Parameters<typeof realSdkQueryFactory>[0]> = {}) {
  // biome-ignore lint/suspicious/noExplicitAny: minimal AsyncIterable stub
  const promptStream = {
    async *[Symbol.asyncIterator]() {},
  } as any;
  return {
    prompt: promptStream,
    systemPrompt: "system",
    pluginPath: "/ignored",
    cwd: "/ignored",
    userId: "user-1",
    conversationId: "conv-1",
    ...overrides,
  };
}

// Tracks tmpdirs created per test so afterEach can clean up.
const createdDirs: string[] = [];

/** A real tmpdir then `rm -rf`'d — models a reclaimed workspace path. */
async function reclaimedWorkspacePath(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "cc-presandbox-"));
  createdDirs.push(dir);
  await rm(dir, { recursive: true, force: true });
  expect(existsSync(dir)).toBe(false);
  return dir;
}

describe("realSdkQueryFactory — unconditional pre-sandbox workspace-dir guarantee", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetUserApiKey.mockResolvedValue("sk-test");
    mockGetUserServiceTokens.mockResolvedValue({});
    mockBuildAgentEnv.mockReturnValue({ ANTHROPIC_API_KEY: "sk-test" });
    mockBuildAgentSandboxConfig.mockReturnValue({
      enabled: true,
      failIfUnavailable: true,
      autoAllowBashIfSandboxed: true,
      allowUnsandboxedCommands: false,
      enableWeakerNestedSandbox: true,
      network: { allowedDomains: [], allowManagedDomainsOnly: true },
      filesystem: { allowWrite: [], denyRead: ["/workspaces", "/proc"] },
    });
    // Capture dir-existence AT the instant the sandbox is constructed (the SDK
    // query() call binds the bwrap cwd). This is the invariant, not a proxy.
    mockQuery.mockImplementation(() => makeFakeQuery());
    // Not-connected by default — the genuinely-RED-on-main fixture: the clone
    // (and its PR #5367 mkdir) is skipped entirely via ensure-workspace-repo:85.
    mockResolveInstallationId.mockResolvedValue(null);
    mockGetCurrentRepoUrl.mockResolvedValue(null);
    mockGenerateInstallationToken.mockResolvedValue("ghs_default_test_token");
    mockResolveBashAutonomous.mockResolvedValue(false);
    mockResolveAutonomousAck.mockResolvedValue(null);
    mockResolveIsWorkspaceOwner.mockResolvedValue(false);
    mockGetInstallationAccount.mockResolvedValue({ login: "owner", id: 1, type: "Organization" });
    mockFindRepoOwnerInstallationForUser.mockResolvedValue({ installationId: null, outcome: "not-member" });
    mockWriteAskpassScriptTo.mockReturnValue("/ignored/.askpass.sh");
    mockSupabaseFrom.mockImplementation(() => ({
      select: () => ({ eq: () => ({ single: () => ({ data: null, error: null }) }) }),
      insert: () => ({ error: null }),
      update: () => ({ eq: () => ({ error: null }) }),
    }));
  });

  afterEach(async () => {
    for (const dir of createdDirs.splice(0)) {
      await rm(dir, { recursive: true, force: true }).catch(() => {});
    }
  });

  // T1 (RED-first): not-connected + reclaimed dir → dir exists at bound cwd.
  it("T1: not-connected reclaimed workspace → dir exists at the bound cwd when the sandbox is constructed", async () => {
    const ws = await reclaimedWorkspacePath();
    mockResolveActiveWorkspacePath.mockResolvedValue(ws);

    let dirExistedAtSandboxBuild: boolean | undefined;
    mockQuery.mockImplementation((arg: { options: { cwd: string } }) => {
      dirExistedAtSandboxBuild = existsSync(arg.options.cwd);
      return makeFakeQuery();
    });

    await realSdkQueryFactory(makeArgs());

    // Sanity: the sandbox bound the factory's own resolved path (not args.cwd).
    expect(mockQuery.mock.calls[0][0].options.cwd).toBe(ws);
    // The invariant. RED on main (no mkdir runs for a not-connected reclaim).
    expect(dirExistedAtSandboxBuild, "not-connected reclaim").toBe(true);
  });

  // T2 (AC2): .git-present-but-root-reclaimed also skips ensureWorkspaceRepoCloned's
  // mkdir (via :89). The unconditional mkdir still ensures the dir. Modeled here
  // as the connected path with the clone stubbed to a no-op (so no clone mkdir
  // runs) — the dir must still exist at sandbox-build time.
  it("T2: clone-skipped (stubbed no-op) reclaimed workspace → dir still ensured before sandbox build", async () => {
    const ws = await reclaimedWorkspacePath();
    mockResolveActiveWorkspacePath.mockResolvedValue(ws);
    mockResolveInstallationId.mockResolvedValue(987654);
    mockGetCurrentRepoUrl.mockResolvedValue("https://github.com/acme/repo");
    mockGetInstallationAccount.mockResolvedValue({ login: "acme", id: 987654, type: "Organization" });
    // clone is a no-op (mockEnsureWorkspaceRepoCloned) → no clone-mkdir runs.

    let dirExistedAtSandboxBuild: boolean | undefined;
    mockQuery.mockImplementation((arg: { options: { cwd: string } }) => {
      dirExistedAtSandboxBuild = existsSync(arg.options.cwd);
      return makeFakeQuery();
    });

    await realSdkQueryFactory(makeArgs());

    expect(dirExistedAtSandboxBuild, "clone-skipped reclaim").toBe(true);
  });

  // AC4: the pre-sandbox mkdir creates ONLY the root dir, never `.git`.
  it("AC4: pre-sandbox mkdir creates the root but NOT a .git (clone .git-absent no-op guard unperturbed)", async () => {
    const ws = await reclaimedWorkspacePath();
    mockResolveActiveWorkspacePath.mockResolvedValue(ws);

    let rootExistedAtSandboxBuild: boolean | undefined;
    let gitExistedAtSandboxBuild: boolean | undefined;
    mockQuery.mockImplementation((arg: { options: { cwd: string } }) => {
      rootExistedAtSandboxBuild = existsSync(arg.options.cwd);
      gitExistedAtSandboxBuild = existsSync(join(arg.options.cwd, ".git"));
      return makeFakeQuery();
    });

    await realSdkQueryFactory(makeArgs());

    // Positive half makes this RED-on-main (the root would NOT exist without the
    // fix); negative half pins that the mkdir creates only the root, never .git
    // (so the clone's .git-absent no-op guard + "failed" honest-message path
    // stay unperturbed). Asserting only the negative was vacuous (GREEN on main).
    expect(rootExistedAtSandboxBuild, "root dir ensured").toBe(true);
    expect(gitExistedAtSandboxBuild, ".git NOT created by the mkdir").toBe(false);
  });

  // T4 / AC6: mkdir fails → reportSilentFallback fires AND the factory rejects
  // (surfaces the retryable/honest envelope) rather than building a doomed
  // sandbox. Forced by resolving workspacePath UNDER a regular file, so a
  // recursive mkdir fails with ENOTDIR.
  it("AC6: mkdir failure mirrors to Sentry and rejects — does NOT build a sandbox against a missing CWD", async () => {
    const fileAsParent = await mkdtemp(join(tmpdir(), "cc-presandbox-file-"));
    createdDirs.push(fileAsParent);
    const filePath = join(fileAsParent, "not-a-dir");
    await writeFile(filePath, "x");
    // mkdir(recursive) under a regular file → ENOTDIR.
    const ws = join(filePath, "workspace");
    mockResolveActiveWorkspacePath.mockResolvedValue(ws);

    await expect(realSdkQueryFactory(makeArgs())).rejects.toThrow();

    // Doomed sandbox was NOT constructed.
    expect(mockQuery).not.toHaveBeenCalled();
    // AC7 shape: cc-dispatcher feature + stable op + hashed userId.
    const calls = mockReportSilentFallback.mock.calls.filter(
      ([, opts]) => opts?.op === "ensure-workspace-dir-presandbox",
    );
    expect(calls).toHaveLength(1);
    expect(calls[0][1]).toMatchObject({
      feature: "cc-dispatcher",
      op: "ensure-workspace-dir-presandbox",
      extra: { userId: "user-1" },
    });
  });
});
